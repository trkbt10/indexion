module Calculator
  # Records the sequence of operations performed by a calculator.
  class History
    Entry = Struct.new(:op, :a, :b, :result)

    def initialize
      @entries = []
    end

    def record(op, a, b, result)
      @entries << Entry.new(op, a, b, result)
    end

    def to_a
      @entries.dup
    end

    def to_json(*args)
      @entries.map(&:to_h).to_json(*args)
    end
  end
end
