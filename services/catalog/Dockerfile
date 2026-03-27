FROM gradle:8-jdk21 AS build
WORKDIR /app
COPY . .
RUN gradle bootJar --no-daemon

FROM eclipse-temurin:21-jre-jammy
WORKDIR /app
COPY --from=build /app/build/libs/catalog-0.0.1-SNAPSHOT.jar app.jar
EXPOSE 4001
CMD ["java", "-jar", "app.jar"]
