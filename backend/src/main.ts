import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { ValidationPipe } from "@nestjs/common";
import helmet from "helmet";
import { DatabaseErrorFilter } from "./errors.filter";
import { AppModule } from "./app.module";
async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.use(helmet());
  app.useGlobalFilters(new DatabaseErrorFilter());
  app.setGlobalPrefix("api");
  app.enableCors({
    origin: (process.env.CORS_ORIGINS || "http://localhost:8080")
      .split(",")
      .map((s) => s.trim()),
  });
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );
  app.enableShutdownHooks();
  await app.listen(Number(process.env.PORT || 3000), "0.0.0.0");
}
void bootstrap();
