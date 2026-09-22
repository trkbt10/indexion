module Calculator
  # Formats calculation results for display.
  class Formatter
    def format(result)
      "Result: #{result}"
    end

    def format_history(history)
      history.to_a.map { |e| "#{e.op}(#{e.a}, #{e.b}) = #{e.result}" }.join("\n")
    end

    # Renders a full report, heredoc body and all.
    def report(history)
      <<~SUMMARY
        Calculator report
        =================
        #{format_history(history)}
        #{history.to_a.length} operation(s) recorded.
      SUMMARY
    end
  end
end
