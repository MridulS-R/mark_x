# frozen_string_literal: true

begin
  require "dotenv/load"
rescue LoadError
  # dotenv is optional; skip if not available
end

module MarkX
end

require_relative "mark_x/version"
require_relative "mark_x/config"
require_relative "mark_x/logger"
require_relative "mark_x/database"
require_relative "mark_x/models"
require_relative "mark_x/extractors"
require_relative "mark_x/sources"
require_relative "mark_x/chunker"
require_relative "mark_x/embeddings"
require_relative "mark_x/llm"
require_relative "mark_x/rerankers"
require_relative "mark_x/search"
require_relative "mark_x/reconstruct"
require_relative "mark_x/cli"
