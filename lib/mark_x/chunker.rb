# frozen_string_literal: true

module MarkX
  class Chunker
    def initialize(chunk_size:, overlap: 0)
      @size = chunk_size
      @overlap = overlap
    end

    def chunk(text)
      words = text.split(/\s+/)
      chunks = []
      pos = 0
      start_idx = 0
      while start_idx < words.length
        last_idx = [start_idx + @size, words.length].min
        chunk_words = words[start_idx...last_idx]
        chunk_text = chunk_words.join(" ")
        start_offset = pos
        end_offset = pos + chunk_text.length
        chunks << { position: chunks.length, start_offset:, end_offset:, text: chunk_text }
        break if last_idx >= words.length
        start_idx = last_idx - @overlap
        start_idx = 0 if start_idx.negative?
        pos = end_offset
      end
      chunks
    end
  end
end

