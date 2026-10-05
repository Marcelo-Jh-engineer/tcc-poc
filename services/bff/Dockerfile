FROM maven:3.9.9-eclipse-temurin-21 AS build
WORKDIR /workspace
ARG MAVEN_PROXY_HOST
ARG MAVEN_PROXY_PORT
COPY pom.xml .
RUN if [ -n "$MAVEN_PROXY_HOST" ] && [ -n "$MAVEN_PROXY_PORT" ]; then \
      mkdir -p /root/.m2 && \
      printf '%s\n' '<settings><proxies><proxy><id>docker</id><active>true</active><protocol>http</protocol><host>'"$MAVEN_PROXY_HOST"'</host><port>'"$MAVEN_PROXY_PORT"'</port></proxy></proxies></settings>' > /root/.m2/settings.xml; \
    fi && \
    mvn -B dependency:go-offline
COPY src src
RUN mvn -B package -DskipTests

FROM eclipse-temurin:21-jre
WORKDIR /deployments
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
COPY --from=build /workspace/target/quarkus-app/ /deployments/
EXPOSE 8083
ENTRYPOINT ["java", "-jar", "/deployments/quarkus-run.jar"]
