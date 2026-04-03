package com.example;

/**
 * Main application entry point.
 */
public class App {
    /**
     * Returns the application name.
     */
    public String getName() {
        return "example-app";
    }

    public static void main(String[] args) {
        System.out.println(new App().getName());
    }
}

/**
 * Application configuration.
 */
public interface Config {
    String getHost();
    int getPort();
}
