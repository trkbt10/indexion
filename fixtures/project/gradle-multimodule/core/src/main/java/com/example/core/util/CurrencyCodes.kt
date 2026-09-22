package com.example.core.util

/**
 * Kotlin source kept in the `:core` module's `src/main/java` root, the layout
 * left behind when a Java utility class is rewritten in Kotlin in place.
 */
object CurrencyCodes {
    fun symbolFor(currency: String): String = when (currency) {
        "USD" -> "USD "
        "EUR" -> "EUR "
        else -> currency
    }
}
