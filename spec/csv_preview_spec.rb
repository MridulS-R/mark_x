require "spec_helper"
require "stringio"

RSpec.describe "CSV preview" do
  before do
    @stdout = StringIO.new
    allow($stdout).to receive(:write) { |*args| @stdout.write(*args) }
  end

  it "counts CSV rows in row mode with limit" do
    Dir.mktmpdir do |dir|
      folder = File.join(dir, "data")
      Dir.mkdir(folder)
      File.write(File.join(folder, "a.csv"), "name,team\nAlice,Search\nBob,UX\nCarol,Platform\n")
      File.write(File.join(folder, "note.txt"), "hello")
      args = ["ingest", "--folder", folder, "--csv-row-mode", "--csv-limit", "2", "--dry-run", "--json"]
      expect { MarkX::CLI.start(args) }.not_to raise_error
      json = JSON.parse(@stdout.string)
      # limit=2 rows from CSV + 1 non-CSV file
      expect(json["mode"]).to eq("folder")
      expect(json["files"]).to eq(3)
    end
  end

  it "filters CSV rows by key=value" do
    Dir.mktmpdir do |dir|
      folder = File.join(dir, "data")
      Dir.mkdir(folder)
      File.write(File.join(folder, "a.csv"), "name,team\nAlice,Search\nBob,UX\nCarol,Search\n")
      args = ["ingest", "--folder", folder, "--csv-row-mode", "--csv-where", "team=Search", "--dry-run", "--json"]
      expect { MarkX::CLI.start(args) }.not_to raise_error
      json = JSON.parse(@stdout.string)
      # two rows match
      expect(json["files"]).to eq(2)
    end
  end

  it "supports semicolon delimiter and counts rows" do
    Dir.mktmpdir do |dir|
      folder = File.join(dir, "data")
      Dir.mkdir(folder)
      File.write(File.join(folder, "b.csv"), "name;team\nAlice;Search\nBob;UX\n")
      args = ["ingest", "--folder", folder, "--csv-row-mode", "--csv-delimiter", ";", "--dry-run", "--json"]
      expect { MarkX::CLI.start(args) }.not_to raise_error
      json = JSON.parse(@stdout.string)
      expect(json["files"]).to eq(2)
    end
  end

  it ".csv.gz with semicolon delimiter counts rows" do
    require "zlib"
    Dir.mktmpdir do |dir|
      folder = File.join(dir, "data")
      Dir.mkdir(folder)
      gzpath = File.join(folder, "c.csv.gz")
      Zlib::GzipWriter.open(gzpath) { |gz| gz.write("name;team\nJane;Search\nPam;Platform\n") }
      args = ["ingest", "--folder", folder, "--csv-row-mode", "--csv-delimiter", ";", "--dry-run", "--json"]
      expect { MarkX::CLI.start(args) }.not_to raise_error
      json = JSON.parse(@stdout.string)
      expect(json["files"]).to eq(2)
    end
  end

  it "handles csv_headers=false for files without headers" do
    Dir.mktmpdir do |dir|
      folder = File.join(dir, "data")
      Dir.mkdir(folder)
      File.write(File.join(folder, "d.csv"), "Alice,Search\nBob,UX\n")
      args = ["ingest", "--folder", folder, "--csv-row-mode", "--csv-headers", "false", "--dry-run", "--json"]
      expect { MarkX::CLI.start(args) }.not_to raise_error
      json = JSON.parse(@stdout.string)
      expect(json["files"]).to eq(2)
    end
  end
end
