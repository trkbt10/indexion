plugins {
    kotlin("jvm")
}

group = "com.example.app"
version = "0.2.0"

dependencies {
    implementation(project(":core"))
    implementation("io.github.microutils:kotlin-logging-jvm:3.0.5")
}
