require "spec_helper"
require "stringio"

RSpec.describe MarkX::CLI do
  before do
    @stdout = StringIO.new
    allow($stdout).to receive(:write) { |*args| @stdout.write(*args) }
  end

  it "previews folder ingest without DB when --dry-run" do
    folder = File.expand_path("../../samples/docs", __FILE__)
    expect { MarkX::CLI.start(["ingest", "--folder", folder, "--dry-run"]) }.not_to raise_error
    out = @stdout.string
    expect(out).to match(/Would ingest \d+ files from folder/)
  end

  it "previews config sources by name" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".markx.yml"), <<~YML)
        sources:
          - name: docs
            type: folder
            path: #{File.expand_path("../../samples/docs", __FILE__)}
      YML
      Dir.chdir(dir) do
        expect { MarkX::CLI.start(["ingest", "--dry-run", "--source", "docs"]) }.not_to raise_error
        out = @stdout.string
        expect(out).to include("Source docs: folder")
      end
    end
  end

  it "previews multiple named sources and outputs JSON" do
    Dir.mktmpdir do |dir|
      docs_path = File.expand_path("../../samples/docs", __FILE__)
      FileUtils.mkdir_p(docs_path) unless Dir.exist?(docs_path)
      File.write(File.join(docs_path, "tmpfile.md"), "Hello world") unless File.exist?(File.join(docs_path, "tmpfile.md"))
      File.write(File.join(dir, ".markx.yml"), <<~YML)
        sources:
          - name: docs
            type: folder
            path: #{docs_path}
          - name: docs2
            type: folder
            path: #{docs_path}
      YML
      Dir.chdir(dir) do
        @stdout.truncate(0); @stdout.rewind
        expect { MarkX::CLI.start(["ingest", "--dry-run", "--source", "docs,docs2", "--json"]) }.not_to raise_error
        json = JSON.parse(@stdout.string)
        expect(json["mode"]).to eq("sources")
        expect(json["sources"]).to be_an(Array)
        names = json["sources"].map { |s| s["name"] }
        expect(names).to include("docs", "docs2")
      end
    end
  end
end
