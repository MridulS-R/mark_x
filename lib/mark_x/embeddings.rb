# frozen_string_literal: true

require "faraday"
require "multi_json"
require "zlib"

module MarkX
  module Embeddings
    class Provider
      def embed_texts(texts)
        raise NotImplementedError
      end
    end

    # Deterministic offline mock provider for testing
    class MockProvider < Provider
      def initialize(dim: (ENV["EMBEDDINGS_DIM"]&.to_i || 3072))
        @dim = dim
      end

      def embed_texts(texts)
        texts.map do |t|
          seed = Zlib.crc32(t.to_s)
          rng = Random.new(seed)
          Array.new(@dim) { (rng.rand * 2.0) - 1.0 }
        end
      end
    end

    class OpenAIProvider < Provider
      def initialize(model: ENV["EMBEDDINGS_MODEL"] || "text-embedding-3-large", api_key: ENV["OPENAI_API_KEY"])
        @model = model
        @api_key = api_key
      end

      def embed_texts(texts)
        raise "OPENAI_API_KEY missing" unless @api_key
        conn = Faraday.new(url: "https://api.openai.com") do |f|
          f.request :json
          f.response :json, content_type: /json/
          f.adapter Faraday.default_adapter
        end
        resp = conn.post("/v1/embeddings") do |r|
          r.headers["Authorization"] = "Bearer #{@api_key}"
          r.headers["Content-Type"] = "application/json"
          r.body = MultiJson.dump({ model: @model, input: texts })
        end
        raise "OpenAI error: #{resp.status} #{resp.body}" unless resp.success?
        resp.body.fetch("data").map { |d| d.fetch("embedding") }
      end
    end

    class LocalHTTPProvider < Provider
      def initialize(endpoint: ENV["EMBEDDINGS_ENDPOINT"] || "http://localhost:8080/embed", model: ENV["EMBEDDINGS_MODEL"])
        @endpoint = endpoint
        @model = model
      end

      def embed_texts(texts)
        conn = Faraday.new do |f|
          f.request :json
          f.response :json, content_type: /json/
          f.adapter Faraday.default_adapter
        end
        resp = conn.post(@endpoint) do |r|
          r.body = MultiJson.dump({ model: @model, input: texts })
        end
        raise "Local embed error: #{resp.status} #{resp.body}" unless resp.success?
        resp.body.fetch("data").map { |d| d.fetch("embedding") }
      end
    end

    class OllamaProvider < Provider
      def initialize(model: ENV["EMBEDDINGS_MODEL"] || "mxbai-embed-large", host: ENV["OLLAMA_HOST"] || "http://localhost:11434")
        @model = model
        @host = host
      end

      def embed_texts(texts)
        conn = Faraday.new(url: @host) do |f|
          f.request :json
          f.response :json, content_type: /json/
          f.adapter Faraday.default_adapter
        end
        embeddings = []
        texts.each do |t|
          resp = conn.post("/api/embeddings") do |r|
            r.body = MultiJson.dump({ model: @model, prompt: t })
          end
          raise "Ollama error: #{resp.status} #{resp.body}" unless resp.success?
          embeddings << resp.body.fetch("embedding")
        end
        embeddings
      end
    end

    def self.build(config)
      case (config["embed_provider"] || "openai").downcase
      when "openai" then OpenAIProvider.new(model: config["embed_model"])
      when "local"  then LocalHTTPProvider.new(model: config["embed_model"])
      when "ollama" then OllamaProvider.new(model: config["embed_model"])
      when "mock"   then MockProvider.new(dim: (config["embed_dim"] || 3072))
      else
        raise "Unknown embeddings provider: #{config["embed_provider"]}"
      end
    end
  end
end
