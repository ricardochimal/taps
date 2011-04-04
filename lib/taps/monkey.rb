class Hash
  def symbolize_keys
    Hash[ map { |(k,v)| [(k.to_sym rescue k) || k, v] } ]
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
