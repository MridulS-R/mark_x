Sequel.migration do
  change do
    alter_table(:chunks) do
      add_column :text_tsv, :tsvector
    end
    run "CREATE INDEX IF NOT EXISTS chunks_text_tsv_idx ON chunks USING GIN (text_tsv)"
  end
end

