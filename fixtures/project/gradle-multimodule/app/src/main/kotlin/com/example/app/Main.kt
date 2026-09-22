package com.example.app

import com.example.core.Ledger
import com.example.core.Money
import com.example.core.util.CurrencyCodes
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

/**
 * The `:app` module depends on `:core` through a Gradle project dependency,
 * so these imports cross a module boundary: each module anchors its own
 * source roots at its own `build.gradle.kts`.
 */
class Report {
    private val ledger = Ledger()

    fun run(): String {
        ledger.add(Money(1200, "USD"))
        val symbol = CurrencyCodes.symbolFor("USD")
        logger.info { "default symbol is $symbol" }
        return ledger.toJson()
    }
}

fun main() {
    println(Report().run())
}
