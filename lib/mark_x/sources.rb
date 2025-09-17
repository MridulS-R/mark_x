# frozen_string_literal: true

require "sequel"

module MarkX
  module Sources
    class DB
      def initialize(url:, table: nil, id_column: nil, text_column: nil, where: nil, query: nil)
        @db = Sequel.connect(url)
        @table = table&.to_sym
        @id_column = id_column&.to_sym
        @text_column = text_column&.to_sym
        @where = where
        @query = query
      end

      def each_row
        ds = if @query && !@query.strip.empty?
          @db[@query]
        else
          raise "table and text_column are required" unless @table && @text_column
          dset = @db[@table]
          dset = dset.where(Sequel.lit(@where)) if @where && !@where.empty?
          dset
        end
        ds.each do |row|
          id = @id_column ? row[@id_column] : row.values.first
          text = @text_column ? row[@text_column] : row.values.last
          yield({ id: id, text: text.to_s, row: row })
        end
      ensure
        @db.disconnect if @db
      end
    end
  end
end

