require "bundler/setup" rescue nil
require "tmpdir"
require "fileutils"
require "mark_x"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
