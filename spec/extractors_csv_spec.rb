require "spec_helper"
require "tmpdir"

RSpec.describe MarkX::Extractors::CSVFile do
  it "parses a simple CSV file to text" do
    data = "name,age\nAlice,30\nBob,25\n"
    text = described_class.text_from_csv(data)
    expect(text).to include("Headers:")
    expect(text).to include("name: Alice")
    expect(text).to include("age: 30")
  end

  it "reads .csv.gz and returns normalized text" do
    require "zlib"
    Dir.mktmpdir do |dir|
      path = File.join(dir, "people.csv.gz")
      Zlib::GzipWriter.open(path) { |gz| gz.write("name,role\nJane,Engineer\n") }
      text = described_class.extract(path)
      expect(text).to include("Headers:")
      expect(text).to include("name: Jane")
      expect(text).to include("role: Engineer")
    end
  end
end
