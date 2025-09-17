require "spec_helper"

RSpec.describe "DB preview" do
  before do
    begin
      require "sqlite3"
    rescue LoadError
      skip "sqlite3 not installed; skipping DB preview test"
    end
  end

  it "previews a sqlite source via --dry-run --json" do
    require "sequel"
    Dir.mktmpdir do |dir|
      db_path = File.join(dir, "src.sqlite3")
      db = Sequel.sqlite(db_path)
      db.create_table :notes do
        primary_key :id
        String :body
        TrueClass :published
      end
      db[:notes].insert(body: "hello world", published: true)
      db[:notes].insert(body: "draft note", published: false)
      db.disconnect

      url = "sqlite://#{db_path}"
      out_path = File.join(dir, "preview.json")
      expect {
        MarkX::CLI.start(["ingest", "--db-url", url, "--db-table", "notes", "--db-id-column", "id", "--db-text-column", "body", "--db-where", "published = 1", "--dry-run", "--json", "--out", out_path])
      }.not_to raise_error
      json = JSON.parse(File.read(out_path))
      expect(json["mode"]).to eq("db")
      expect(json["rows"]).to eq(1)
    end
  end
end

