package com.example.legacy

/**
 * Kotlin source that lives under `src/main/java` rather than
 * `src/main/kotlin`. Gradle's Kotlin plugin adds the Java source directory to
 * the Kotlin source set, so mixed-language modules routinely keep Kotlin files
 * here beside the Java ones they replaced.
 */
class LegacyFormatter {
    fun format(message: String): String = "[legacy] $message"
}
