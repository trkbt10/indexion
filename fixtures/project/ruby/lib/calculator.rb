# A simple calculator module.
module Calculator
  # Represents a basic calculator.
  class Basic
    # Adds two numbers.
    def add(a, b)
      a + b
    end

    # Subtracts b from a.
    def subtract(a, b)
      a - b
    end

    private

    def validate_input(value)
      raise ArgumentError unless value.is_a?(Numeric)
    end
  end

  # Formats calculation results.
  class Formatter
    def format(result)
      "Result: #{result}"
    end
  end
end
