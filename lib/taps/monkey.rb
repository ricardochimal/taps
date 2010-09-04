class Hash
  def symbolize_keys
    inject({}) do |options, (key, value)|
      options[(key.to_sym rescue key) || key] = value
      options
    end
  end

  def symbolize_keys!
    self.replace(symbolize_keys)
  end

  def symbolize_recursively!
    self.replace(symbolize_keys)
    self.each do |k, v|
      if v.kind_of?(Hash)
        v.symbolize_keys!
      end
    end
  end
end
