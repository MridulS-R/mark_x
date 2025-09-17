# frozen_string_literal: true

require "logger"
require "paint"

module MarkX
  class Log
    def self.logger
      @logger ||= begin
        l = Logger.new($stderr)
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

    def self.info(msg)
      logger.info(msg)
    end

    def self.debug(msg)
      logger.debug(msg)
    end

    def self.warn(msg)
      logger.warn(msg)
    end

    def self.error(msg)
      logger.error(msg)
    end
  end
end
