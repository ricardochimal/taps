module Taps
  class BaseError < StandardError
    attr_reader :original_backtrace

    def initialize(message, opts={})
      @original_backtrace = opts.delete(:backtrace)
    end
  end

  class NotImplemented < BaseError; end
  class DuplicatePrimaryKeyError < BaseError; end
  class CorruptedData < BaseError; end
end
