# Dockerfile for the Spring Boot Ecommerce application
# This container runs the packaged Java application in production-like mode.
# It does not compile the code; it expects the JAR to already be built by Maven.

# Use a portable Java 17 runtime image that works reliably across environments
# The Alpine variant can fail on some Docker platforms/registries, so this fixed tag is safer.
FROM eclipse-temurin:17-jre

# Set the working directory inside the container
WORKDIR /app

# Copy the built JAR file into the container.
# The JAR is created by Maven using: mvn clean package
# Example output: target/ecommerce-1.0.0.jar
COPY target/ecommerce-1.0.0.jar app.jar

# Expose the application port used by Spring Boot
# The app listens on port 8080
EXPOSE 8080

# Start the application when the container runs
# This runs the Spring Boot executable JAR
ENTRYPOINT ["java", "-jar", "app.jar"]