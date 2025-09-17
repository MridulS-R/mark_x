# frozen_string_literal: true

require "sequel"
require "pg"
require "pgvector"

module MarkX
  class Database
    attr_reader :db, :config

    def initialize(config: Config.load)
      @config = config
      @db = Sequel.connect(config["database_url"], keep_reference: false)
      ensure_pgvector!
    end

    def ensure_pgvector!
      db.run "CREATE EXTENSION IF NOT EXISTS vector" rescue nil
    end

    def schema
      @schema ||= config["project"].downcase.gsub(/[^a-z0-9_]/, "_")
    end

    def use_project_schema!
      db.run "CREATE SCHEMA IF NOT EXISTS \"#{schema}\"";
      db.run "SET search_path TO \"#{schema}\"";
    end

    def migrate!
      use_project_schema!
      Sequel.extension :migration
      migration_dir = File.expand_path("../../db/migrations", __dir__)
      Sequel::Migrator.run(db, migration_dir, table: :schema_migrations)
    end

    def files; db[:files]; end
    def chunks; db[:chunks]; end
    def embeddings; db[:embeddings]; end
    def queries; db[:queries]; end
    def chat_messages; db[:chat_messages]; end
  end
end
