package com.example.service

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import mu.KotlinLogging
import org.springframework.stereotype.Service

private val logger = KotlinLogging.logger {}

@Service
class GreetingService {
    private val mapper = jacksonObjectMapper()

    fun greet(name: String): String {
        logger.info { "greeting $name" }
        return mapper.writeValueAsString(mapOf("message" to "Hello, $name!"))
    }
}
