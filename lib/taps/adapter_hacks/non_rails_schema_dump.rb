module ActiveRecord
	class SchemaDumper
		private

		def header(stream)
			stream.puts "ActiveRecord::Schema.define do"
		end

		def tables(stream)
			@connection.tables.sort.each do |tbl|
				table(tbl, stream)
			end
		end
	end
end
