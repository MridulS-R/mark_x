# frozen_string_literal: true

require "yaml"
require "pathname"

module MarkX
  class Config
    DEFAULTS = {
      "database_url" => ENV["DATABASE_URL"] || "postgres://localhost/markx",
      "project"      => ENV["MARKX_PROJECT"] || File.basename(Dir.pwd).downcase.gsub(/[^a-z0-9_]+/, "_"),
      "embed_provider" => ENV["EMBEDDINGS_PROVIDER"] || "openai",
      "embed_model"    => ENV["EMBEDDINGS_MODEL"] || "text-embedding-3-large",
      "embed_dim"      => (ENV["EMBEDDINGS_DIM"]&.to_i || 3072),
      "chunk_size"     => 1000,
      "chunk_overlap"  => 150,
      "top_k"          => 8,
      "index_method"   => ENV["MARKX_INDEX_METHOD"] || "ivfflat",
      "re_rank"        => false
    }

    def self.load(cwd: Dir.pwd)
      files = [
        File.join(cwd, ".markx.yml"),
        File.join(Dir.home, ".markx.yml"),
      ]
      merged = DEFAULTS.dup
      files.each do |path|
        next unless File.exist?(path)
        begin
          conf = YAML.safe_load(File.read(path)) || {}
          merged.merge!(conf)
        rescue => e
          MarkX::Log.warn("Failed reading #{path}: #{e.message}")
        end
      end
      new(merged)
    end

    def initialize(hash)
      @data = hash
    end

    def [](key) = @data[key.to_s]
    def to_h = @data.dup
  end
end
