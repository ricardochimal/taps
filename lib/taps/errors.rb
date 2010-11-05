module Taps
  class BaseError < StandardError
    attr_reader :original_backtrace

    def initialize(message, opts={})
      @original_backtrace = opts.delete(:backtrace)
      super(message)
    end
  end

  class NotImplemented < BaseError; end
  class DuplicatePrimaryKeyError < BaseError; end
  class CorruptedData < BaseError; end
  class InvalidData < BaseError; end
end
