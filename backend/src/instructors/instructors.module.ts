import { Module } from "@nestjs/common";
import { InstructorsController } from "./instructors.controller";
import { InstructorsService } from "./instructors.service";
import { PrismaService } from "../prisma.service";

@Module({
  controllers: [InstructorsController],
  providers: [InstructorsService, PrismaService],
  exports: [InstructorsService],
})
export class InstructorsModule {}
