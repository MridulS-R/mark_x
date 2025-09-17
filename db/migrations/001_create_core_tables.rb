Sequel.migration do
  change do
    create_table?(:files) do
      primary_key :id
      String :path, null: false, unique: true
      Integer :size, null: false
      Time :mtime, null: false
      String :content_hash, null: false, index: true
      String :format, null: false
      jsonb :metadata, default: Sequel.pg_jsonb({})
      Time :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      Time :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table?(:chunks) do
      primary_key :id
      foreign_key :file_id, :files, null: false, on_delete: :cascade
      Integer :position, null: false
      Integer :start_offset, null: false
      Integer :end_offset, null: false
      text :text, null: false
      Time :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      index [:file_id, :position], unique: true
    end

    create_table?(:embeddings) do
      primary_key :id
      foreign_key :chunk_id, :chunks, null: false, on_delete: :cascade
      # vector
      column :embedding, :vector, size: (ENV["EMBEDDINGS_DIM"]&.to_i || 3072), null: false
      Time :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      index :chunk_id, unique: true
    end

    create_table?(:queries) do
      primary_key :id
      text :query_text, null: false
      column :embedding, :vector, size: (ENV["EMBEDDINGS_DIM"]&.to_i || 3072)
      jsonb :filters, default: Sequel.pg_jsonb({})
      jsonb :results, default: Sequel.pg_jsonb([])
      Time :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table?(:chat_messages) do
      primary_key :id
      String :role, null: false # system|user|assistant
      text :content, null: false
      Integer :turn, null: false
      jsonb :context, default: Sequel.pg_jsonb([])
      Time :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    # Vector indexes (IVFFLAT by default)
    run "CREATE INDEX IF NOT EXISTS embeddings_embedding_idx ON embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)"
    run "CREATE INDEX IF NOT EXISTS queries_embedding_idx ON queries USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)"
  end
end

