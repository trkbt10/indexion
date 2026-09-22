package com.example.core

import com.example.core.util.CurrencyCodes

/**
 * A minimal value type owned by the `:core` module.
 */
data class Money(val amount: Long, val currency: String) {
    fun format(): String = CurrencyCodes.symbolFor(currency) + amount.toString()
}
