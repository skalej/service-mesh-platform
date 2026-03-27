plugins {
    id("org.springframework.boot") version "3.4.4"
    id("io.spring.dependency-management") version "1.1.7"
    id("com.netflix.dgs.codegen") version "7.0.3"
    id("org.jlleitschuh.gradle.ktlint") version "12.1.2"
    kotlin("jvm") version "2.1.10"
    kotlin("plugin.spring") version "2.1.10"
}

group = "com.example"
version = "0.0.1-SNAPSHOT"

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

repositories {
    mavenCentral()
}

dependencyManagement {
    imports {
        mavenBom("com.netflix.graphql.dgs:graphql-dgs-platform-dependencies:10.0.4")
    }
}

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("org.springframework.boot:spring-boot-starter-actuator")
    implementation("com.netflix.graphql.dgs:graphql-dgs-spring-graphql-starter")
    implementation("org.jetbrains.kotlin:kotlin-reflect")

    testImplementation("org.springframework.boot:spring-boot-starter-test")
}

kotlin {
    compilerOptions {
        freeCompilerArgs.addAll("-Xjsr305=strict")
    }
}

tasks.withType<Test> {
    useJUnitPlatform()
}

tasks.generateJava {
    schemaPaths.add("${projectDir}/src/main/resources/schema")
    packageName = "com.example.catalog.generated"
    language = "kotlin"
}