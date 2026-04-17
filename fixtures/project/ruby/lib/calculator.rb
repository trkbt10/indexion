require "json"
require_relative "calculator/history"
require_relative "calculator/formatter"

# A simple calculator module.
module Calculator
  # Represents a basic calculator.
  class Basic
    def initialize
      @history = History.new
    end

    # Adds two numbers.
    def add(a, b)
      validate_input(a)
      validate_input(b)
      result = a + b
      @history.record(:add, a, b, result)
      result
    end

    # Subtracts b from a.
    def subtract(a, b)
      validate_input(a)
      validate_input(b)
      result = a - b
      @history.record(:subtract, a, b, result)
      result
    end

    attr_reader :history

    private

    def validate_input(value)
      raise ArgumentError unless value.is_a?(Numeric)
    end
  end
end
