package com.example;

/**
 * A service that processes data.
 */
public class Service {
    /**
     * Processes the given input.
     */
    public String process(String input) {
        return input.trim();
    }

    private void validate(String input) {
        if (input == null) throw new IllegalArgumentException();
    }
}

/**
 * Data transfer object.
 */
public record UserRecord(String name, int age) {}
