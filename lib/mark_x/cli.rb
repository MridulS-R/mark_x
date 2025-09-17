# frozen_string_literal: true

require "thor"
require "digest"
require "csv"
require "json"
require "tty-spinner"
require "set"
require "ostruct"

module MarkX
  class CLI < Thor
    package_name "mark_x"

    class_option :project, type: :string, desc: "Project schema name (overrides .markx.yml)"

    desc "init", "Initialize per-project DB schema and migrations"
    def init
      config = Config.load
      config = Config.new(config.to_h.merge("project" => options[:project])) if options[:project]
      db = Database.new(config: config)
      db.migrate!
      Log.info "Initialized schema '#{db.schema}' on #{config["database_url"]}"
    end

    desc "ingest", "Ingest from a folder or a database source"
    method_option :folder, type: :string, desc: "Folder to ingest (.txt/.md/.markdown/.html etc.)"
    method_option :db_url, type: :string, desc: "Source DB URL (read-only)"
    method_option :db_alias, type: :string, default: "src", desc: "Source alias for namespacing paths"
    method_option :db_table, type: :string, desc: "Source table"
    method_option :db_id_column, type: :string, desc: "Row id column"
    method_option :db_text_column, type: :string, desc: "Text content column"
    method_option :db_where, type: :string, desc: "Optional WHERE clause"
    method_option :db_query, type: :string, desc: "Custom SQL returning id,text"
    method_option :db_format, type: :string, default: "text", desc: "text|markdown|html normalization"
    method_option :source, type: :string, desc: "Name(s) of configured source(s) in .markx.yml (comma-separated)"
    method_option :dry_run, type: :boolean, default: false, desc: "Preview items without writing to storage DB"
    method_option :json, type: :boolean, default: false, desc: "With --dry-run, output JSON summary"
    method_option :out, type: :string, desc: "With --dry-run, write preview output to a file"
    method_option :source_type, type: :string, enum: %w[folder db], desc: "Filter configured sources by type"
    # CSV-specific controls for folder ingestion
    method_option :csv_row_mode, type: :boolean, default: false, desc: "Treat each CSV row as a separate document"
    method_option :csv_delimiter, type: :string, default: ",", desc: "CSV delimiter (col_sep)"
    method_option :csv_headers, type: :string, default: "auto", desc: "CSV headers: true|false|auto"
    method_option :csv_where, type: :array, desc: "CSV row filters key=value (repeatable)"
    method_option :csv_limit, type: :numeric, desc: "Limit CSV rows ingested per file"
    def ingest
      config = Config.load
      config = Config.new(config.to_h.merge("project" => options[:project])) if options[:project]
      if options[:dry_run]
        if options[:folder]
          count = preview_folder(options[:folder], options)
          payload = { mode: "folder", folder: File.expand_path(options[:folder]), files: count }
          emit_preview(payload, json: options[:json], out: options[:out])
        elsif options[:db_url]
          count = preview_db_source(options)
          payload = { mode: "db", db_url: options[:db_url], rows: count }
          emit_preview(payload, json: options[:json], out: options[:out])
        else
          names = parse_source_names(options[:source])
          types = parse_source_types(options[:source_type])
          payload = preview_from_config_sources(config, names, types, as: (options[:json] ? :json : :text))
          emit_preview(payload, json: options[:json], out: options[:out])
        end
      else
        db = Database.new(config: config)
        db.migrate!
        embedder = Embeddings.build(config)
        chunker = Chunker.new(chunk_size: config["chunk_size"], overlap: config["chunk_overlap"])
        if options[:folder]
          ingest_folder(db, embedder, chunker, options[:folder], options)
        elsif options[:db_url]
          ingest_db_source(db, embedder, chunker, options)
        else
          ingest_from_config_sources(db, embedder, chunker, config, only_names: parse_source_names(options[:source]), only_types: parse_source_types(options[:source_type]))
        end
      end
    end

    desc "sync --folder PATH", "Re-index only changed files"
    method_option :folder, type: :string, required: true
    def sync
      config = Config.load
      config = Config.new(config.to_h.merge("project" => options[:project])) if options[:project]
      db = Database.new(config: config)
      db.migrate!
      embedder = Embeddings.build(config)
      chunker = Chunker.new(chunk_size: config["chunk_size"], overlap: config["chunk_overlap"])
      folder = File.expand_path(options[:folder])
      inputs = Dir.glob(File.join(folder, "**/*")).select { |p| File.file?(p) && Extractors.supported?(p) }

      updated = 0
      inputs.each do |path|
        rel_path = path
        stat = File.stat(path)
        content = Extractors.for(path).extract(path)
        hash = Digest::SHA256.hexdigest(content)
        file = db.files.where(path: rel_path).first
        if file.nil? || file[:content_hash] != hash
          # reingest via ingest logic for a single
          file_id = if file
            db.chunks.where(file_id: file[:id]).delete
            db.files.where(id: file[:id]).update(size: stat.size, mtime: stat.mtime, content_hash: hash, format: File.extname(path).downcase, updated_at: Time.now)
            file[:id]
          else
            db.files.insert(path: rel_path, size: stat.size, mtime: stat.mtime, content_hash: hash, format: File.extname(path).downcase, created_at: Time.now, updated_at: Time.now)
          end
          chunks = chunker.chunk(content)
          ids = chunks.map do |ch|
            db.chunks.insert(
              file_id: file_id,
              position: ch[:position],
              start_offset: ch[:start_offset],
              end_offset: ch[:end_offset],
              text: ch[:text],
              text_tsv: Sequel.lit("to_tsvector('english', ?)", ch[:text]),
              created_at: Time.now
            )
          end
          embeddings = embedder.embed_texts(chunks.map { |c| c[:text] })
          ids.zip(embeddings).each { |cid, vec| db.embeddings.insert(chunk_id: cid, embedding: Sequel.pg_vector(vec), created_at: Time.now) }
          updated += 1
        end
      end
      Log.info "Synced #{updated} files"
    end

    desc "prune --folder PATH", "Remove DB entries for deleted files"
    method_option :folder, type: :string, required: true
    def prune
      config = Config.load
      config = Config.new(config.to_h.merge("project" => options[:project])) if options[:project]
      db = Database.new(config: config)
      db.migrate!
      folder = File.expand_path(options[:folder])
      live_paths = Dir.glob(File.join(folder, "**/*")).select { |p| File.file?(p) }.to_set
      to_delete = db.files.all.select { |f| !live_paths.include?(f[:path]) }
      to_delete.each { |f| db.files.where(id: f[:id]).delete }
      Log.info "Pruned #{to_delete.size} files"
    end

    desc "search --query TEXT", "Query DB with semantic search"
    method_option :query, type: :string, required: true
    method_option :download, type: :string, desc: "Export results to .txt/.csv/.json"
    method_option :filter, type: :array, desc: "Filters like key=value"
    method_option :mode, type: :string, enum: %w[keyword vector hybrid], desc: "Search mode"
    method_option :hybrid, type: :boolean, default: false, desc: "Hybrid keyword + vector search (legacy toggle)"
    method_option :alpha, type: :numeric, default: 0.5, desc: "Vector weight in hybrid score (0..1)"
    method_option :rank, type: :string, enum: %w[rank rank_cd], default: 'rank', desc: "Full-text ranking function"
    method_option :re_rank, type: :boolean, default: false, desc: "Re-rank results"
    method_option :reranker, type: :string, desc: "Reranker provider: heuristic|llm|crossencoder"
    method_option :reranker_endpoint, type: :string, desc: "Reranker endpoint for cross-encoder HTTP"
    def search
      config = Config.load
      config = Config.new(config.to_h.merge("project" => options[:project])) if options[:project]
      db = Database.new(config: config)
      db.migrate!
      filters = {}
      (options[:filter] || []).each do |kv|
        k, v = kv.split("=", 2)
        filters[k] = v
      end
      search = Search.new(db: db, config: config)
      mode = options[:mode] || (options[:hybrid] ? 'hybrid' : nil)
      results = search.query(options[:query], filters: filters, hybrid: options[:hybrid], alpha: options[:alpha], mode: mode, rank_fn: options[:rank])
      if options[:re_rank] || config["re_rank"]
        results = search.rerank(results, options[:query], provider: (options[:reranker] || 'heuristic'), endpoint: options[:reranker_endpoint])
      end
      if options[:download]
        out = options[:download]
        case File.extname(out)
        when ".txt"
          list = results.is_a?(Sequel::Dataset) ? results.all : results
          File.open(out, "w") { |f| list.each { |r| sc = r[:re_rank_score] || r[:score] || r[:vec_score] || r[:ts_score] || 0; f.puts "#{sprintf('%.3f', sc)}\t#{r[:file_path]}\t#{r[:position]}\t#{r[:text]}" } }
        when ".csv"
          list = results.is_a?(Sequel::Dataset) ? results.all : results
          CSV.open(out, "w") { |csv| csv << %w[score path pos text]; list.each { |r| sc = r[:re_rank_score] || r[:score] || r[:vec_score] || r[:ts_score] || 0; csv << [sc, r[:file_path], r[:position], r[:text]] } }
        when ".json"
          list = results.is_a?(Sequel::Dataset) ? results.all : results
          File.write(out, JSON.pretty_generate(list))
        else
          raise "Unknown export format: #{out}"
        end
        Log.info "Exported to #{out}"
      else
        search.pretty_print(results)
      end
    end

    desc "reconstruct FILE --out FILE.txt", "Rebuild normalized file text"
    method_option :out, type: :string, required: true
    def reconstruct(file_path)
      config = Config.load
      config = Config.new(config.to_h.merge("project" => options[:project])) if options[:project]
      db = Database.new(config: config)
      db.migrate!
      rec = Reconstruct.new(db: db)
      text = rec.file_to_text(file_path)
      File.write(options[:out], text)
      Log.info "Wrote #{options[:out]}"
    end

    desc "extract --query TEXT --out results.json", "Structured extraction into JSON"
    method_option :query, type: :string, required: true
    method_option :out, type: :string, required: true
    def extract
      # Minimal: return top chunks as structure for now
      config = Config.load
      db = Database.new(config: config)
      db.migrate!
      search = Search.new(db: db, config: config)
      results = search.query(options[:query]).all
      payload = {
        query: options[:query],
        extracted: results.map { |r| { path: r[:file_path], position: r[:position], score: r[:score], text: r[:text] } }
      }
      File.write(options[:out], JSON.pretty_generate(payload))
      Log.info "Saved extraction to #{options[:out]}"
    end

    desc "chat", "Interactive chat mode with RAG"
    method_option :stream, type: :boolean, default: true, desc: "Stream assistant tokens"
    def chat
      config = Config.load
      db = Database.new(config: config)
      db.migrate!
      embedder = Embeddings.build(config)
      search = Search.new(db: db, config: config, embedder: embedder)
      llm = LLM.build(config)
      puts "Enter 'exit' to quit."
      turn = 1
      loop do
        print "you> "
        q = $stdin.gets&.strip
        break if q.nil? || q.downcase == "exit"
        results = search.query(q, top_k: config["top_k"], mode: 'hybrid', alpha: 0.6).all
        context = results.map { |r| r[:text] }[0, 4].join("\n\n")
        system_prompt = "You are a helpful assistant. Use the provided context to answer succinctly. If unknown, say you don't know."
        user_prompt = "Question:\n#{q}\n\nContext:\n#{context}"
        begin
          if options[:stream]
            print "assistant> "
            buffer = +""
            answer = llm.chat([
              { role: "system", content: system_prompt },
              { role: "user", content: user_prompt }
            ], stream: true) do |token|
              buffer << token
              print token
              $stdout.flush
            end
            puts
          else
            answer = llm.chat([
              { role: "system", content: system_prompt },
              { role: "user", content: user_prompt }
            ], stream: false)
            puts "assistant> #{answer}\n"
          end
        rescue => e
          Log.warn("LLM chat failed: #{e.message}. Falling back to context stub.")
          answer = "[Stubbed answer using #{results.size} retrieved chunks]\n\n" + context[0, 800]
          puts "assistant> #{answer}\n"
        end
        db.chat_messages.insert(role: "user", content: q, turn: turn, context: Sequel.pg_jsonb([]), created_at: Time.now)
        db.chat_messages.insert(role: "assistant", content: answer, turn: turn, context: Sequel.pg_jsonb(results.map { |r| { path: r[:file_path], pos: r[:position], score: r[:score] } }), created_at: Time.now)
        turn += 1
      end
    end

    desc "watch --folder PATH", "Watch folder and incrementally sync/prune"
    method_option :folder, type: :string, required: true
    method_option :interval, type: :numeric, default: 5.0, desc: "Polling interval seconds"
    def watch
      config = Config.load
      config = Config.new(config.to_h.merge("project" => options[:project])) if options[:project]
      db = Database.new(config: config)
      db.migrate!
      folder = File.expand_path(options[:folder])
      Log.info "Watching #{folder} (interval #{options[:interval]}s)"
      loop do
        invoke :sync, [], folder: folder, project: config["project"]
        invoke :prune, [], folder: folder, project: config["project"]
        sleep options[:interval]
      end
    end
    no_commands do
      def ingest_folder(db, embedder, chunker, folder, opts = nil)
        folder = File.expand_path(folder)
        inputs = Dir.glob(File.join(folder, "**/*")).select { |p| File.file?(p) && Extractors.supported?(p) }
        spinner = TTY::Spinner.new("[:spinner] Ingesting :count files", format: :bouncing, clear: true)
        spinner.update(count: inputs.size)
        spinner.auto_spin
        inputs.each_slice(20) do |batch|
          batch.each do |path|
            rel_path = path
            stat = File.stat(path)
            ext = File.extname(path).downcase
            if ext == ".csv" || path.downcase.end_with?(".csv.gz")
              csv_row_mode = opts && opts[:csv_row_mode]
              if csv_row_mode
                col_sep = (opts[:csv_delimiter] || ",")
                headers_opt = (opts[:csv_headers] || "auto")
                header_list, rows = Extractors::CSVFile.read_rows(path, col_sep: col_sep, headers: headers_opt.to_s == "auto" ? :auto : (headers_opt.to_s == "true"))
                # filter
                filters = parse_key_equals_array(opts[:csv_where])
                if filters && !filters.empty? && header_list
                  rows = rows.select { |r| filters.all? { |k, v| r[k]&.to_s == v } }
                end
                # limit
                if opts[:csv_limit]
                  rows = rows.first(opts[:csv_limit].to_i)
                end
                rows.each_with_index do |row, i|
                  row_text = Extractors::CSVFile.row_to_text(row, header_list)
                  content = row_text
                  vpath = "#{rel_path}#row=#{i+1}"
                  hash = Digest::SHA256.hexdigest(content)
                  file = db.files.where(path: vpath).first
                  if file && file[:content_hash] == hash
                    next
                  end
                  file_id = if file
                    db.chunks.where(file_id: file[:id]).delete
                    db.files.where(id: file[:id]).update(size: content.bytesize, mtime: stat.mtime, content_hash: hash, format: "csv-row", updated_at: Time.now)
                    file[:id]
                  else
                    db.files.insert(path: vpath, size: content.bytesize, mtime: stat.mtime, content_hash: hash, format: "csv-row", created_at: Time.now, updated_at: Time.now)
                  end
                  chunks = chunker.chunk(content)
                  ids = chunks.map do |ch|
                    db.chunks.insert(file_id: file_id, position: ch[:position], start_offset: ch[:start_offset], end_offset: ch[:end_offset], text: ch[:text], text_tsv: Sequel.lit("to_tsvector('english', ?)", ch[:text]), created_at: Time.now)
                  end
                  vectors = embedder.embed_texts(chunks.map { |c| c[:text] })
                  ids.zip(vectors).each { |cid, vec| db.embeddings.insert(chunk_id: cid, embedding: Sequel.pg_vector(vec), created_at: Time.now) }
                end
              else
                # Whole-file CSV as one document
                content = Extractors::CSVFile.extract(path)
                hash = Digest::SHA256.hexdigest(content)
                file = db.files.where(path: rel_path).first
                if file && file[:content_hash] == hash
                  next
                end
                file_id = if file
                  db.chunks.where(file_id: file[:id]).delete
                  db.files.where(id: file[:id]).update(size: stat.size, mtime: stat.mtime, content_hash: hash, format: File.extname(path).downcase, updated_at: Time.now)
                  file[:id]
                else
                  db.files.insert(path: rel_path, size: stat.size, mtime: stat.mtime, content_hash: hash, format: File.extname(path).downcase, created_at: Time.now, updated_at: Time.now)
                end
                chunks = chunker.chunk(content)
                chunk_ids = []
                chunks.each do |ch|
                  cid = db.chunks.insert(file_id: file_id, position: ch[:position], start_offset: ch[:start_offset], end_offset: ch[:end_offset], text: ch[:text], text_tsv: Sequel.lit("to_tsvector('english', ?)", ch[:text]), created_at: Time.now)
                  chunk_ids << cid
                end
                embeddings = embedder.embed_texts(chunks.map { |c| c[:text] })
                chunk_ids.zip(embeddings).each { |cid, vec| db.embeddings.insert(chunk_id: cid, embedding: Sequel.pg_vector(vec), created_at: Time.now) }
              end
            else
              content = Extractors.for(path).extract(path)
              hash = Digest::SHA256.hexdigest(content)
              file = db.files.where(path: rel_path).first
              if file && file[:content_hash] == hash
                next
              end
              if file
                db.chunks.where(file_id: file[:id]).delete
                db.files.where(id: file[:id]).update(size: stat.size, mtime: stat.mtime, content_hash: hash, format: File.extname(path).downcase, updated_at: Time.now)
                file_id = file[:id]
              else
                file_id = db.files.insert(path: rel_path, size: stat.size, mtime: stat.mtime, content_hash: hash, format: File.extname(path).downcase, created_at: Time.now, updated_at: Time.now)
              end
              chunks = chunker.chunk(content)
              chunk_ids = []
              chunks.each do |ch|
                cid = db.chunks.insert(file_id: file_id, position: ch[:position], start_offset: ch[:start_offset], end_offset: ch[:end_offset], text: ch[:text], text_tsv: Sequel.lit("to_tsvector('english', ?)", ch[:text]), created_at: Time.now)
                chunk_ids << cid
              end
              embeddings = embedder.embed_texts(chunks.map { |c| c[:text] })
              chunk_ids.zip(embeddings).each { |cid, vec| db.embeddings.insert(chunk_id: cid, embedding: Sequel.pg_vector(vec), created_at: Time.now) }
            end
          end
        end
        spinner.stop("Done")
        Log.info "Ingested #{inputs.size} files"
      end

      def ingest_db_source(db, embedder, chunker, options)
        source = Sources::DB.new(
          url: options[:db_url],
          table: options[:db_table],
          id_column: options[:db_id_column],
          text_column: options[:db_text_column],
          where: options[:db_where],
          query: options[:db_query]
        )
        count = 0
        source.each_row do |r|
          count += 1
          path = "db://#{options[:db_alias]}/#{options[:db_table] || 'query'}/#{r[:id]}"
          content = r[:text]
          norm = case (options[:db_format] || 'text')
                 when 'markdown', 'md' then Extractors::PlainOrMarkdown.extract_string(content)
                 when 'html', 'htm' then Extractors::HTML.extract_string(content)
                 else content.to_s
                 end
          hash = Digest::SHA256.hexdigest(norm)
          file = db.files.where(path: path).first
          if file && file[:content_hash] == hash
            next
          end
          file_id = if file
            db.chunks.where(file_id: file[:id]).delete
            db.files.where(id: file[:id]).update(size: norm.bytesize, mtime: Time.now, content_hash: hash, format: options[:db_format], updated_at: Time.now)
            file[:id]
          else
            db.files.insert(path: path, size: norm.bytesize, mtime: Time.now, content_hash: hash, format: options[:db_format], created_at: Time.now, updated_at: Time.now)
          end
          chunks = chunker.chunk(norm)
          ids = chunks.map do |ch|
            db.chunks.insert(file_id: file_id, position: ch[:position], start_offset: ch[:start_offset], end_offset: ch[:end_offset], text: ch[:text], text_tsv: Sequel.lit("to_tsvector('english', ?)", ch[:text]), created_at: Time.now)
          end
          vectors = embedder.embed_texts(chunks.map { |c| c[:text] })
          ids.zip(vectors).each { |cid, vec| db.embeddings.insert(chunk_id: cid, embedding: Sequel.pg_vector(vec), created_at: Time.now) }
        end
        Log.info "Ingested #{count} rows from source DB #{options[:db_alias]}"
      end

      def ingest_from_config_sources(db, embedder, chunker, config, only_names: nil, only_types: nil)
        sources = Array(config["sources"]) # [{name: 'docs', type: 'folder', path: ...}, {name: 'notes', type: 'db', url: ..., ...}]
        if sources.empty?
          raise Thor::Error, "No source provided. Use --folder, --db-url, or define 'sources:' in .markx.yml"
        end
        sources.each do |s|
          name = s["name"] || s[:name]
          if only_names && !only_names.empty?
            next unless only_names.map(&:to_s).include?(name.to_s)
          end
          type = (s["type"] || s[:type]).to_s
          if only_types && !only_types.empty?
            next unless only_types.include?(type)
          end
          case type
          when "folder"
            path = s["path"] || s[:path]
            csv_where = s["csv_where"] || s[:csv_where]
            csv_where = csv_where.map { |k, v| "#{k}=#{v}" } if csv_where.is_a?(Hash)
            fopts = {
              csv_row_mode: s["csv_row_mode"] || s[:csv_row_mode],
              csv_delimiter: s["csv_delimiter"] || s[:csv_delimiter],
              csv_headers: s["csv_headers"] || s[:csv_headers] || "auto",
              csv_where: csv_where,
              csv_limit: s["csv_limit"] || s[:csv_limit]
            }
            ingest_folder(db, embedder, chunker, path, fopts)
          when "db"
            opts = {
              db_url: s["url"] || s[:url],
              db_table: s["table"] || s[:table],
              db_id_column: s["id_column"] || s[:id_column],
              db_text_column: s["text_column"] || s[:text_column],
              db_where: s["where"] || s[:where],
              db_query: s["query"] || s[:query],
              db_alias: s["alias"] || s[:alias] || "src",
              db_format: s["format"] || s[:format] || "text"
            }
            ingest_db_source(db, embedder, chunker, opts)
          else
            Log.warn "Unknown source type: #{s.inspect} — skipping"
          end
        end
      end

      def preview_folder(folder, opts = nil)
        folder = File.expand_path(folder)
        csv_row_mode = opts && opts[:csv_row_mode]
        col_sep = opts && (opts[:csv_delimiter] || ",")
        headers_opt = opts && (opts[:csv_headers] || "auto")
        filters = parse_key_equals_array(opts && opts[:csv_where])
        limit = opts && opts[:csv_limit]
        total = 0
        Dir.glob(File.join(folder, "**/*")).each do |p|
          next unless File.file?(p) && Extractors.supported?(p)
          if csv_row_mode && (File.extname(p).downcase == ".csv" || p.downcase.end_with?(".csv.gz"))
            headers_flag = headers_opt.to_s == "auto" ? :auto : (headers_opt.to_s == "true")
            header_list, rows = MarkX::Extractors::CSVFile.read_rows(p, col_sep: col_sep, headers: headers_flag)
            if filters && !filters.empty? && header_list
              rows = rows.select { |r| filters.all? { |k, v| r[k]&.to_s == v } }
            end
            rows = rows.first(limit.to_i) if limit
            total += rows.size
          else
            total += 1
          end
        end
        total
      end

      def preview_db_source(options)
        source = Sources::DB.new(
          url: options[:db_url],
          table: options[:db_table],
          id_column: options[:db_id_column],
          text_column: options[:db_text_column],
          where: options[:db_where],
          query: options[:db_query]
        )
        count = 0
        source.each_row { |_r| count += 1 }
        count
      end

      def preview_from_config_sources(config, only_names, only_types, as: :text)
        sources = Array(config["sources"]) 
        raise Thor::Error, "No source provided. Use --folder, --db-url, or define 'sources:' in .markx.yml" if sources.empty?
        data = []
        sources.each do |s|
          name = s["name"] || s[:name]
          if only_names && !only_names.empty?
            next unless only_names.map(&:to_s).include?(name.to_s)
          end
          type = (s["type"] || s[:type]).to_s
          if only_types && !only_types.empty?
            next unless only_types.include?(type)
          end
          if type == "folder"
            path = s["path"] || s[:path]
            csv_where = s["csv_where"] || s[:csv_where]
            csv_where = csv_where.map { |k, v| "#{k}=#{v}" } if csv_where.is_a?(Hash)
            fopts = {
              csv_row_mode: s["csv_row_mode"] || s[:csv_row_mode],
              csv_delimiter: s["csv_delimiter"] || s[:csv_delimiter],
              csv_headers: s["csv_headers"] || s[:csv_headers] || "auto",
              csv_where: csv_where,
              csv_limit: s["csv_limit"] || s[:csv_limit]
            }
            count = preview_folder(path, fopts)
            if as == :json
              data << { name: name, type: type, folder: path, files: count }
            else
              puts "Source #{name || '(folder)'}: folder #{path} — files: #{count}"
            end
          elsif type == "db"
            opts = {
              db_url: (s["url"] || s[:url]),
              db_table: (s["table"] || s[:table]),
              db_id_column: (s["id_column"] || s[:id_column]),
              db_text_column: (s["text_column"] || s[:text_column]),
              db_where: (s["where"] || s[:where]),
              db_query: (s["query"] || s[:query])
            }
            rows = preview_db_source(opts)
            if as == :json
              data << { name: name, type: type, db_url: opts.db_url, rows: rows }
            else
              puts "Source #{name || '(db)'}: db #{opts.db_url} — rows: #{rows}"
            end
          else
            if as == :json
              data << { name: name, type: type, error: "unsupported" }
            else
              puts "Source #{name || '(unknown)'}: type=#{type} not supported"
            end
          end
        end
        { mode: "sources", sources: data }
      end

      def parse_source_names(value)
        return nil if value.nil?
        # Accept comma-separated string or already an array-like
        if value.is_a?(String)
          value.split(",").map { |s| s.strip }.reject(&:empty?)
        else
          Array(value).map(&:to_s)
        end
      end

      def parse_source_types(value)
        return nil if value.nil?
        arr = Array(value.is_a?(String) ? value.split(",") : value).map { |s| s.to_s.strip.downcase }.reject(&:empty?)
        arr & %w[folder db]
      end

      def parse_key_equals_array(arr)
        return nil if arr.nil?
        h = {}
        Array(arr).each do |kv|
          k, v = kv.to_s.split("=", 2)
          next if k.nil? || v.nil?
          h[k] = v
        end
        h
      end

      def emit_preview(payload, json:, out: nil)
        if json
          text = JSON.pretty_generate(payload || {})
        else
          if payload.nil?
            text = nil # preview_from_config_sources already printed lines
          else
            text = case payload[:mode] || payload["mode"]
                   when "folder"
                     p = payload[:folder] || payload["folder"]
                     c = payload[:files] || payload["files"]
                     "Would ingest #{c} files from folder: #{p}"
                   when "db"
                     u = payload[:db_url] || payload["db_url"]
                     r = payload[:rows] || payload["rows"]
                     "Would ingest approximately #{r} rows from DB: #{u}"
                   when "sources"
                     list = Array(payload[:sources])
                     lines = list.compact.map do |s|
                       if s[:type] == 'folder' || s['type'] == 'folder'
                         name = s[:name] || s['name'] || '(folder)'
                         path = s[:folder] || s['folder']
                         files = s[:files] || s['files']
                         "Source #{name}: folder #{path} — files: #{files}"
                       elsif s[:type] == 'db' || s['type'] == 'db'
                         name = s[:name] || s['name'] || '(db)'
                         url = s[:db_url] || s['db_url']
                         rows = s[:rows] || s['rows']
                         "Source #{name}: db #{url} — rows: #{rows}"
                       else
                         name = s[:name] || s['name'] || '(unknown)'
                         type = s[:type] || s['type']
                         "Source #{name}: type=#{type}"
                       end
                     end
                     lines.join("\n")
                   else
                     JSON.pretty_generate(payload)
                   end
          end
        end
        if out
          File.write(out, text || "")
          Log.info "Preview saved to #{out}"
        else
          puts text if text
        end
      end
    end
  end
end
