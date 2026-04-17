module Calculator
  # Formats calculation results for display.
  class Formatter
    def format(result)
      "Result: #{result}"
    end

    def format_history(history)
      history.to_a.map { |e| "#{e.op}(#{e.a}, #{e.b}) = #{e.result}" }.join("\n")
    end
  end
end
