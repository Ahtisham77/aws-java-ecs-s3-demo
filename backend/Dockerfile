FROM eclipse-temurin:21-jdk AS build
WORKDIR /app
COPY src ./src
RUN javac src/Main.java -d out

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /app/out .
EXPOSE 8080
CMD ["java", "Main"]