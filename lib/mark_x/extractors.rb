# frozen_string_literal: true

require "nokogiri"
require "csv"
require "zlib"

module MarkX
  module Extractors
    SUPPORTED = [".txt", ".md", ".markdown", ".pdf", ".docx", ".html", ".htm", ".csv", ".csv.gz"].freeze

    def self.supported?(path)
      ext = File.extname(path).downcase
      return true if SUPPORTED.include?(ext)
      return true if path.downcase.end_with?(".csv.gz")
      false
    end

    def self.for(path)
      ext = File.extname(path).downcase
      case ext
      when ".txt", ".md", ".markdown" then PlainOrMarkdown
      when ".html", ".htm" then HTML
      when ".csv" then CSVFile
      when ".gz"
        return CSVFile if path.downcase.end_with?(".csv.gz")
      when ".pdf" then PDF
      when ".docx" then DOCX
      else PlainOrMarkdown
      end
    end

    module PlainOrMarkdown
      module_function
      def extract(path)
        text = File.read(path)
        # naive markdown strip: remove code fences and some markup
        text = text.gsub(/```[\s\S]*?```/m, " ")
        text = text.gsub(/[\*_`#>\[\]!\(\)]/, " ")
        text = text.gsub(/[\r\t]/, " ").gsub(/ +/, " ")
        text.strip
      end
      def extract_string(text)
        text = text.to_s
        text = text.gsub(/```[\s\S]*?```/m, " ")
        text = text.gsub(/[\*_`#>\[\]!\(\)]/, " ")
        text = text.gsub(/[\r\t]/, " ").gsub(/ +/, " ")
        text.strip
      end
    end

    module HTML
      module_function
      def extract(path)
        html = File.read(path)
        Nokogiri::HTML(html).xpath("//text()")
          .map(&:text).join(" ").gsub(/\s+/, " ").strip
      end
      def extract_string(html)
        Nokogiri::HTML(html.to_s).xpath("//text()").map(&:text).join(" ").gsub(/\s+/, " ").strip
      end
    end

    module PDF
      module_function
      def extract(path)
        begin
          require "pdf/reader"
          reader = PDF::Reader.new(path)
          reader.pages.map { |p| p.text }.join("\n").gsub(/\s+/, " ").strip
        rescue LoadError
          raise "pdf-reader gem not installed. Please add it to use PDF extraction."
        end
      end
    end

    module DOCX
      module_function
      def extract(path)
        begin
          require "docx"
          doc = Docx::Document.open(path)
          doc.paragraphs.map(&:text).join("\n").gsub(/\s+/, " ").strip
        rescue LoadError
          raise "docx gem not installed. Please add it to use DOCX extraction."
        end
      end
    end

    module CSVFile
      module_function
      def extract(path)
        data = if path.downcase.end_with?(".gz")
                 Zlib::GzipReader.open(path, &:read)
               else
                 File.read(path)
               end
        text_from_csv(data)
      end

      def text_from_csv(data, col_sep: ",", headers: true)
        csv = CSV.new(data, headers: headers, col_sep: col_sep)
        rows = csv.read
        if rows.headers&.any?
          header_line = "Headers: " + rows.headers.map { |h| h.to_s.strip }.join(", ")
        else
          # try parsing without headers
          rows = CSV.parse(data, headers: false, col_sep: col_sep)
          header_line = nil
        end
        lines = []
        lines << header_line if header_line
        idx = 0
        rows.each do |row|
          idx += 1
          if row.is_a?(CSV::Row)
            kv = row.to_h.map { |k, v| "#{k}: #{v}" }.join(" | ")
          else
            kv = row.map.with_index { |v, i| "col#{i+1}: #{v}" }.join(" | ")
          end
          lines << kv
        end
        text = lines.join("\n")
        text.gsub(/[\r\t]/, " ").gsub(/ +/, " ").strip
      end

      def read_rows(path, col_sep: ",", headers: :auto)
        data = if path.downcase.end_with?(".gz")
                 Zlib::GzipReader.open(path, &:read)
               else
                 File.read(path)
               end
        # If headers explicitly false, return array rows without header list
        if headers == false || (headers.is_a?(String) && headers.downcase == "false")
          arr = CSV.parse(data, headers: false, col_sep: col_sep)
          return nil, arr
        end

        headers_opt = case headers
                      when :auto then true
                      when true, false then headers
                      when String then headers.downcase == "true"
                      else true
                      end
        csv = CSV.new(data, headers: headers_opt, col_sep: col_sep)
        rows = csv.read
        if rows.respond_to?(:headers) && rows.headers&.any?
          header_list = rows.headers
          arr = rows.map { |r| r.to_h }
          return header_list, arr
        else
          arr = CSV.parse(data, headers: false, col_sep: col_sep)
          return nil, arr
        end
      end

      def row_to_text(row, headers = nil)
        if headers && row.is_a?(Hash)
          row.map { |k, v| "#{k}: #{v}" }.join(" | ")
        elsif row.is_a?(Array)
          row.map.with_index { |v, i| "col#{i+1}: #{v}" }.join(" | ")
        else
          row.to_s
        end
      end
    end
  end
end
