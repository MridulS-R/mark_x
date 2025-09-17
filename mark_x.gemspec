Gem::Specification.new do |spec|
  spec.name          = "mark_x"
  spec.version       = "0.1.0"
  spec.authors       = ["Your Name"]
  spec.email         = ["you@example.com"]

  spec.summary       = "Semantic search + RAG CLI for local projects"
  spec.description   = "mark_x ingests markdown/text content, chunks, embeds with pluggable providers, and provides search/sync/chat over a PostgreSQL+pgvector index."
  spec.homepage      = "https://example.com/mark_x"
  spec.license       = "MIT"

  spec.required_ruby_version = Gem::Requirement.new(">= 3.0.0")

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["lib/**/*.rb", "exe/*", "README.md", "LICENSE", "db/migrations/*.rb", ".markx.example.yml", "Dockerfile", ".github/workflows/ci.yml"]
  end
  spec.bindir        = "exe"
  spec.executables   = ["mark_x"]
  spec.require_paths = ["lib"]

  # Runtime dependencies (kept lean; some are optional at runtime)
  spec.add_runtime_dependency "thor", "~> 1.2"
  spec.add_runtime_dependency "sequel", ">= 5.0"
  spec.add_runtime_dependency "pg", ">= 1.2"
  spec.add_runtime_dependency "pgvector", ">= 0.2.0"
  spec.add_runtime_dependency "tty-table", ">= 0.12"
  spec.add_runtime_dependency "tty-spinner", ">= 0.9"
  spec.add_runtime_dependency "paint", ">= 2.0"
  spec.add_runtime_dependency "faraday", ">= 2.9"
  spec.add_runtime_dependency "multi_json", ">= 1.15"
  spec.add_runtime_dependency "dotenv", ">= 2.8"
  spec.add_runtime_dependency "addressable", ">= 2.8"

  # Optional extractors
  spec.add_runtime_dependency "nokogiri", ">= 1.15"
  # PDF and DOCX gems are optional — loaded dynamically if present

  spec.metadata = {
    "source_code_uri" => "https://example.com/mark_x",
    "changelog_uri"   => "https://example.com/mark_x/CHANGELOG",
  }
end

