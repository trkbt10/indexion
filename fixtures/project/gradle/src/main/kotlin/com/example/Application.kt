package com.example

import com.example.service.GreetingService
import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication

@SpringBootApplication
class Application {
    fun entryPoint(service: GreetingService): String = service.greet("World")
}

fun main(args: Array<String>) {
    runApplication<Application>(*args)
}
