# frozen_string_literal: true

module MarkX
  module Models
    FileRow = Data.define(:id, :path, :size, :mtime, :content_hash, :format, :metadata, :created_at, :updated_at)
    ChunkRow = Data.define(:id, :file_id, :position, :start_offset, :end_offset, :text, :created_at)
    EmbeddingRow = Data.define(:id, :chunk_id, :embedding, :created_at)
    QueryRow = Data.define(:id, :query_text, :embedding, :filters, :results, :created_at)
    ChatMessageRow = Data.define(:id, :role, :content, :turn, :context, :created_at)
  end
end

