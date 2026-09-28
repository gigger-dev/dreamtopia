import { ArgumentsHost, Catch, ExceptionFilter } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import type { Response } from "express";
@Catch(Prisma.PrismaClientKnownRequestError)
export class DatabaseErrorFilter implements ExceptionFilter {
  catch(error: Prisma.PrismaClientKnownRequestError, host: ArgumentsHost) {
    const response = host.switchToHttp().getResponse<Response>();
    if (error.code === "P2002")
      return response
        .status(409)
        .json({
          message: "This record already exists. Refresh and try again.",
        });
    if (error.code === "P2025")
      return response
        .status(404)
        .json({ message: "This record was not found." });
    console.error("Database operation failed", error.code);
    return response
      .status(503)
      .json({
        message: "The studio could not save your changes. Please try again.",
      });
  }
}
