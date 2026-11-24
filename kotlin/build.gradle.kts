import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    kotlin("jvm") version "2.4.21"
    kotlin("plugin.serialization") version "2.4.21"
    `java-library`
    `maven-publish`
}

val sdkVersion = "0.4.0" // Keep in step with SDK_VERSION in FoodApiClient.kt (a test checks)

// JitPack serves a tag as com.github.<owner>:<repo>:<tag> and says so in GROUP, ARTIFACT and VERSION: publishing under
// exactly those keeps the POM and Gradle's module metadata in step with the coordinates apps use. Built anywhere
// else (./gradlew publishToMavenLocal), the library is io.studio93:food-api:0.4.0.
val jitPack = System.getenv("JITPACK") == "true"
group = if (jitPack) System.getenv("GROUP") else "io.studio93"
version = if (jitPack) System.getenv("VERSION") else sdkVersion

repositories {
    mavenCentral()
}

dependencies {
    // Android has no java.net.http: OkHttp gives connection pooling, HTTP/2 and gzip on Android and the JVM alike
    api("com.squareup.okhttp3:okhttp:5.5.1")
    api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.13.0")

    testImplementation(kotlin("test"))
    testImplementation(platform("org.junit:junit-bom:5.14.4"))
    testImplementation("com.squareup.okhttp3:mockwebserver3:5.5.1")
}

java {
    // Android (minSdk 24) and JVM 11+ servers
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
    withSourcesJar()
}

kotlin {
    explicitApi()
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_11)
        freeCompilerArgs.add("-Xjdk-release=11")
        allWarningsAsErrors.set(true)
    }
}

tasks.test {
    useJUnitPlatform()
    systemProperty("foodapi.version", sdkVersion)
}

publishing {
    publications {
        create<MavenPublication>("release") {
            from(components["java"])
            artifactId = if (jitPack) System.getenv("ARTIFACT") else "food-api"
            pom {
                name.set("Studio93 Food API")
                description.set("Kotlin client for the Studio93 Food API (v2), for Android and JVM servers")
                url.set("https://github.com/Studio93-Org/food-api-sdk")
                licenses {
                    license {
                        name.set("MIT")
                        url.set("https://github.com/Studio93-Org/food-api-sdk/blob/main/LICENSE")
                    }
                }
            }
        }
    }
}
