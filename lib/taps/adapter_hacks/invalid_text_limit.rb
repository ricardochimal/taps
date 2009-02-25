module ActiveRecord
	module ConnectionAdapters
		class TableDefinition
			alias_method :original_text, :text
			def text(*args)
				options = args.extract_options!
				options.delete(:limit)
				column_names = args
				column_names.each { |name| column(name, 'text', options) }
			end
		end
	end
end
