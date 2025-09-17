# frozen_string_literal: true

module MarkX
  class Reconstruct
    def initialize(db:)
      @db = db
    end

    def file_to_text(path)
      file = @db.files.where(path: path).first
      raise "File not indexed: #{path}" unless file
      chunks = @db.chunks.where(file_id: file[:id]).order(:position).all
      chunks.map { |c| c[:text] }.join("\n\n")
    end
  end
end

