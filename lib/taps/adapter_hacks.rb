module Taps
	module AdapterHacks
		extend self

		LIST = {
			:all => ['non_rails_schema_dump'],
			:mysql => ['invalid_text_limit', 'mysql_invalid_primary_key'],
			:postgresql => ['invalid_text_limit']
		}

		def load(adapter)
			LIST[:all].each do |r|
				require File.dirname(__FILE__) + "/adapter_hacks/#{r}"
			end

			(LIST[adapter.to_sym] || []).each do |r|
				require File.dirname(__FILE__) + "/adapter_hacks/#{r}"
			end
		end
	end
end
