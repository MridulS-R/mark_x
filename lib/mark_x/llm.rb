# frozen_string_literal: true

require "faraday"
require "multi_json"

module MarkX
  module LLM
    class Provider
      def chat(messages, stream: false)
        raise NotImplementedError
      end

      def score_snippet(query, snippet)
        # Optional: return float 0..1 of relevance
        # Default heuristic: normalized token overlap
        q_tokens = query.downcase.scan(/\w+/)
        s_tokens = snippet.downcase.scan(/\w+/)
        return 0.0 if q_tokens.empty? || s_tokens.empty?
        overlap = (q_tokens & s_tokens).size
        (overlap.to_f / q_tokens.uniq.size).clamp(0.0, 1.0)
      end
    end

    class OpenAIProvider < Provider
      def initialize(model: ENV["LLM_MODEL"] || "gpt-4o-mini", api_key: ENV["OPENAI_API_KEY"])
        @model = model
        @api_key = api_key
      end

      def chat(messages, stream: false, &block)
        raise "OPENAI_API_KEY missing" unless @api_key
        conn = Faraday.new(url: "https://api.openai.com") do |f|
          f.request :json
          f.response :json, content_type: /json/
          f.adapter Faraday.default_adapter
        end
        body = { model: @model, messages: messages, stream: !!stream }
        if stream && block_given?
          buffer = +""
          resp = conn.post("/v1/chat/completions") do |r|
            r.headers["Authorization"] = "Bearer #{@api_key}"
            r.headers["Content-Type"] = "application/json"
            r.options.on_data = Proc.new do |chunk, _overall_received_bytes|
              chunk.to_s.each_line do |line|
                next unless line.start_with?("data:")
                data = line.sub(/^data:\s*/, '').strip
                next if data == "[DONE]" || data.empty?
                begin
                  json = MultiJson.load(data)
                  delta = json.dig("choices", 0, "delta", "content")
                  if delta
                    buffer << delta
                    yield delta
                  end
                rescue
                  # ignore malformed line
                end
              end
            end
            r.body = MultiJson.dump(body)
          end
          raise "OpenAI chat error: #{resp.status}" unless resp.success?
          buffer
        else
          resp = conn.post("/v1/chat/completions") do |r|
            r.headers["Authorization"] = "Bearer #{@api_key}"
            r.body = MultiJson.dump(body)
          end
          raise "OpenAI chat error: #{resp.status} #{resp.body}" unless resp.success?
          resp.body.dig("choices", 0, "message", "content") || ""
        end
      end
    end

    class LocalHTTPProvider < Provider
      def initialize(endpoint: ENV["LLM_ENDPOINT"] || "http://localhost:8080/chat", model: ENV["LLM_MODEL"]) 
        @endpoint = endpoint
        @model = model
      end

      def chat(messages, stream: false, &block)
        conn = Faraday.new do |f|
          f.request :json
          f.response :json, content_type: /json/
          f.adapter Faraday.default_adapter
        end
        # Assume non-streaming simple JSON
        resp = conn.post(@endpoint) do |r|
          r.body = MultiJson.dump({ model: @model, messages: messages, stream: false })
        end
        raise "Local LLM error: #{resp.status} #{resp.body}" unless resp.success?
        resp.body["content"] || resp.body.dig("choices", 0, "message", "content") || ""
      end
    end

    class OllamaProvider < Provider
      def initialize(model: ENV["LLM_MODEL"] || "llama3.1:8b", host: ENV["OLLAMA_HOST"] || "http://localhost:11434")
        @model = model
        @host = host
      end

      def chat(messages, stream: false, &block)
        prompt = messages.map { |m| "#{m[:role]}: #{m[:content]}" }.join("\n\n")
        conn = Faraday.new(url: @host) do |f|
          f.request :json
          f.response :json, content_type: /json/
          f.adapter Faraday.default_adapter
        end
        if stream && block_given?
          buffer = +""
          resp = conn.post("/api/generate") do |r|
            r.options.on_data = Proc.new do |chunk, _|
              chunk.to_s.each_line do |line|
                begin
                  json = MultiJson.load(line)
                rescue
                  next
                end
                token = json["response"]
                if token
                  buffer << token
                  yield token
                end
              end
            end
            r.body = MultiJson.dump({ model: @model, prompt: prompt, stream: true })
          end
          raise "Ollama chat error: #{resp.status}" unless resp.success?
          buffer
        else
          resp = conn.post("/api/generate") do |r|
            r.body = MultiJson.dump({ model: @model, prompt: prompt, stream: false })
          end
          raise "Ollama chat error: #{resp.status} #{resp.body}" unless resp.success?
          resp.body["response"] || ""
        end
      end
    end

    def self.build(config)
      case (config["llm_provider"] || ENV["LLM_PROVIDER"] || "openai").downcase
      when "openai" then OpenAIProvider.new(model: config["llm_model"])
      when "local"  then LocalHTTPProvider.new(model: config["llm_model"])
      when "ollama" then OllamaProvider.new(model: config["llm_model"])
      else
        OpenAIProvider.new(model: config["llm_model"]) # default
      end
    end
  end
end
