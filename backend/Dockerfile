FROM public.ecr.aws/amazoncorretto/amazoncorretto:21 AS build
WORKDIR /app

COPY src ./src
RUN javac src/Main.java -d out


FROM public.ecr.aws/amazoncorretto/amazoncorretto:21
WORKDIR /app

COPY --from=build /app/out .

EXPOSE 8080
CMD ["java", "Main"]