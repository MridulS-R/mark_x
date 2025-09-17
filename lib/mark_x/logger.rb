# frozen_string_literal: true

require "logger"
require "paint"

module MarkX
  class Log
    def self.logger
      @logger ||= begin
        l = Logger.new($stderr)
        l.level = (ENV["MARKX_LOG_LEVEL"] || "info").upcase.to_sym then nil rescue nil
        # Default INFO unless env provided
        l.level = case (ENV["MARKX_LOG_LEVEL"] || "info").downcase
                  when "debug" then Logger::DEBUG
                  when "warn"  then Logger::WARN
                  when "error" then Logger::ERROR
                  else Logger::INFO
                  end
        l.formatter = proc do |severity, datetime, _progname, msg|
          ts = datetime.strftime("%H:%M:%S")
          sev = case severity
                when "DEBUG" then Paint["DBG", :cyan]
                when "WARN"  then Paint["WRN", :yellow]
                when "ERROR" then Paint["ERR", :red]
                else Paint["INF", :green]
                end
          "[#{ts}] #{sev} #{msg}\n"
        end
        l
      end
    end

    def self.info(msg) = logger.info(msg)
    def self.debug(msg) = logger.debug(msg)
    def self.warn(msg) = logger.warn(msg)
    def self.error(msg) = logger.error(msg)
  end
end

