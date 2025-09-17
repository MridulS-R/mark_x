# frozen_string_literal: true

require "faraday"
require "multi_json"

module MarkX
  module ReRankers
    class Provider
      # Returns array of floats for snippets
      def score(query, snippets)
        raise NotImplementedError
      end
    end

    class Heuristic < Provider
      def score(query, snippets)
        q_tokens = query.downcase.scan(/\w+/).uniq
        snippets.map do |s|
          next 0.0 if q_tokens.empty?
          str = s.to_s.downcase
          hits = q_tokens.sum { |t| str.include?(t) ? 1 : 0 }
          (hits.to_f / q_tokens.size).clamp(0.0, 1.0)
        end
      end
    end

    class LLMScorer < Provider
      def initialize(llm: nil, config: nil)
        @llm = llm || (config && MarkX::LLM.build(config))
        @heuristic = Heuristic.new
      end

      def score(query, snippets)
        return @heuristic.score(query, snippets) unless @llm
        snippets.map do |s|
          begin
            @llm.score_snippet(query, s)
          rescue
            @heuristic.score(query, [s]).first
          end
        end
      end
    end

    class CrossEncoderHTTP < Provider
      def initialize(endpoint: ENV["RERANK_ENDPOINT"] || "http://localhost:8081/rerank", model: ENV["RERANK_MODEL"]) 
        @endpoint = endpoint
        @model = model
      end

      def score(query, snippets)
        conn = Faraday.new do |f|
          f.request :json
          f.response :json, content_type: /json/
          f.adapter Faraday.default_adapter
        end
        resp = conn.post(@endpoint) do |r|
          r.body = MultiJson.dump({ model: @model, query: query, inputs: snippets })
        end
        raise "Cross-encoder error: #{resp.status} #{resp.body}" unless resp.success?
        (resp.body["scores"] || resp.body).map(&:to_f)
      end
    end

    def self.build(name, config, endpoint: nil)
      case (name || "heuristic").downcase
      when "heuristic" then Heuristic.new
      when "llm" then LLMScorer.new(config: config)
      when "crossencoder", "cross-encoder", "http" then CrossEncoderHTTP.new(endpoint: endpoint)
      else Heuristic.new
      end
    end
  end
end

