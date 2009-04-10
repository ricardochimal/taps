module ActiveRecord
	module ConnectionAdapters
		class MysqlAdapter < AbstractAdapter
			alias_method :orig_pk_and_sequence_for, :pk_and_sequence_for
			# mysql accepts varchar as a primary key but most others do not.
			# only say that a field is a primary key if mysql says so
			# and the field is a kind of integer
			def pk_and_sequence_for(table)
				keys = []
				execute("describe #{quote_table_name(table)}").each_hash do |h|
					keys << h["Field"] if h["Key"] == "PRI" and !(h["Type"] =~ /int/).nil?
				end
				keys.length == 1 ? [keys.first, nil] : nil
			end
		end
	end
end
