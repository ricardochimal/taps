class Hash
  def symbolize_keys
    each_with_object({}) do |(key, value), options|
      options[(begin
                 key.to_sym
               rescue
                 key
               end) || key] = value
    end
  end

  def symbolize_keys!
    replace(symbolize_keys)
  end

  def symbolize_recursively!
    replace(symbolize_keys)
    each do |_k, v|
      v.symbolize_keys! if v.is_a?(Hash)
    end
  end
end
