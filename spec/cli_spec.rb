require "spec_helper"

RSpec.describe "mark_x CLI" do
  it "has a version" do
    require "mark_x/version"
    expect(MarkX::VERSION).to match(/\d+\.\d+\.\d+/)
  end
end

