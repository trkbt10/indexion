package com.example.service

import com.example.legacy.LegacyFormatter
import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import mu.KotlinLogging
import org.springframework.stereotype.Service

private val logger = KotlinLogging.logger {}

@Service
class GreetingService {
    private val mapper = jacksonObjectMapper()
    private val formatter = LegacyFormatter()

    fun greet(name: String): String {
        logger.info { "greeting $name" }
        return mapper.writeValueAsString(
            mapOf("message" to formatter.format("Hello, $name!")),
        )
    }
}
