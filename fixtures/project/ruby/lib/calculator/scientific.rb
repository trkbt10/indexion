require_relative "../calculator"

module Calculator
  # A calculator that adds the transcendental operations on top of Basic.
  #
  # Every operation still goes through Basic so the shared history and input
  # validation apply unchanged; `super` is what routes them there.
  class Scientific < Basic
    # The operations this calculator adds beyond the basic four.
    EXTRA_OPS = %i[power root].freeze

    def initialize(precision = 6)
      super()
      @precision = precision
    end

    # Raises a to the b-th power, recording it like any other operation.
    def power(a, b)
      result = a**b
      history.record(:power, a, b, round_out(result))
      round_out(result)
    end

    # The b-th root of a.
    def root(a, b)
      raise ArgumentError, "root of a negative" if a.negative?

      power(a, 1.0 / b)
    end

    # Names this calculator for a log line — `self.class` is the subclass.
    def describe
      "#{self.class.name} at precision #{@precision}"
    end

    alias to_s describe

    # Builds one with the default precision.
    def self.default
      new
    end

    private

    def round_out(value)
      value.round(@precision)
    end
  end
end
