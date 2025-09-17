# frozen_string_literal: true

require "tty-table"

module MarkX
  class Search
    def initialize(db:, config:, embedder: nil)
      @db = db
      @config = config
      @embedder = embedder || Embeddings.build(config)
    end

    def query(text, top_k: nil, filters: {}, hybrid: false, alpha: 0.5, mode: nil, rank_fn: 'rank')
      top_k ||= @config["top_k"] || 8
      qvec = @embedder.embed_texts([text]).first
      mode = (mode || (hybrid ? 'hybrid' : 'vector')).downcase
      rank_fn = %w[rank rank_cd].include?(rank_fn.to_s) ? rank_fn : 'rank'
      if mode == 'hybrid'
        alpha = [[alpha.to_f, 0.0].max, 1.0].min
        ds = @db.db[<<~SQL, Sequel.pg_vector(qvec), Sequel.pg_vector(qvec), text, Integer(top_k)]
          SELECT e.id AS embedding_id, c.id AS chunk_id, f.path AS file_path, c.position, c.text,
                 (1 - (e.embedding <=> $1)) AS vec_score,
                 ts_#{rank_fn}(c.text_tsv, plainto_tsquery('english', $3)) AS ts_score
          FROM embeddings e
          JOIN chunks c ON c.id = e.chunk_id
          JOIN files f ON f.id = c.file_id
          ORDER BY ((#{alpha}) * (1 - (e.embedding <=> $2)) + (#{1.0 - alpha}) * ts_#{rank_fn}(c.text_tsv, plainto_tsquery('english', $3))) DESC
          LIMIT $4
        SQL
      elsif mode == 'keyword'
        ds = @db.db[<<~SQL, text, Integer(top_k)]
          SELECT NULL::int AS embedding_id, c.id AS chunk_id, f.path AS file_path, c.position, c.text,
                 ts_#{rank_fn}(c.text_tsv, plainto_tsquery('english', $1)) AS ts_score
          FROM chunks c
          JOIN files f ON f.id = c.file_id
          WHERE c.text_tsv @@ plainto_tsquery('english', $1)
          ORDER BY ts_#{rank_fn}(c.text_tsv, plainto_tsquery('english', $1)) DESC
          LIMIT $2
        SQL
      else # vector
        ds = @db.db[<<~SQL, Sequel.pg_vector(qvec), Sequel.pg_vector(qvec), Integer(top_k)]
          SELECT e.id AS embedding_id, c.id AS chunk_id, f.path AS file_path, c.position, c.text,
                 1 - (e.embedding <=> $1) AS score
          FROM embeddings e
          JOIN chunks c ON c.id = e.chunk_id
          JOIN files f ON f.id = c.file_id
          ORDER BY e.embedding <=> $2
          LIMIT $3
        SQL
      end
      if filters["path_prefix"]
        ds = ds.where(Sequel.like(:file_path, "#{filters["path_prefix"]}%"))
      end
      ds
    end

    def rerank(results, query, provider: nil, endpoint: nil)
      rows = results.is_a?(Sequel::Dataset) ? results.all : Array(results)
      return rows if rows.empty?
      reranker = MarkX::ReRankers.build(provider, @config, endpoint: endpoint)
      scores = reranker.score(query, rows.map { |r| r[:text] })
      rows.each_with_index { |r, i| r[:re_rank_score] = scores[i].to_f }
      rows.sort_by { |r| -r[:re_rank_score] }
    end

    private

    def pretty_print(results)
      rows = []
      iterable = results.is_a?(Sequel::Dataset) ? results.each : results.each
      iterable.each do |r|
        score = r[:re_rank_score] || r[:score] || r[:vec_score] || r[:ts_score] || 0
        rows << [sprintf("%.3f", score), r[:file_path], r[:position], r[:text][0, 80]]
      end
      table = TTY::Table.new(["score", "path", "pos", "snippet"], rows)
      puts table.render(:ascii)
    end
  end
end
