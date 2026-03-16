# ─────────────────────────────────────────
# Stage 1: Build with Maven
# ─────────────────────────────────────────
FROM maven:3.9.6-eclipse-temurin-11 AS builder

WORKDIR /build

# Clone the boardgame repo
RUN apt-get update && apt-get install -y git && \
    git clone https://github.com/pathakotasanthoshreddy/CloudShield_DevSecOps_Hackathon_2026_Solution_AWS_DevSecOps.git . && \
    cd board && \
    mvn clean package -DskipTests

# ─────────────────────────────────────────
# Stage 2: Production image
# ─────────────────────────────────────────
FROM eclipse-temurin:11-jre

WORKDIR /usr/src/app

COPY --from=builder /build/board/target/database_service_project-*.jar app.jar

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]
