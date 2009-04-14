module ActiveRecord
	module ConnectionAdapters
		class TableDefinition
			alias_method :original_binary, :binary
			def binary(*args)
				options = args.extract_options!
				options.delete(:limit)
				column_names = args
				column_names.each { |name| column(name, 'binary', options) }
			end
		end
	end
end
