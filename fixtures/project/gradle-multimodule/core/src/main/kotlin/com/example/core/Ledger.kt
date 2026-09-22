package com.example.core

import com.fasterxml.jackson.databind.ObjectMapper

/**
 * Collects [Money] entries. Lives in the same source root as [Money], so the
 * import below is resolved within one module's `src/main/kotlin`.
 */
class Ledger {
    private val mapper = ObjectMapper()
    private val entries = mutableListOf<Money>()

    fun add(entry: Money) {
        entries.add(entry)
    }

    fun toJson(): String = mapper.writeValueAsString(entries.map { it.format() })
}
