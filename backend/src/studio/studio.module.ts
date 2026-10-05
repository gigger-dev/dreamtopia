import { Module } from "@nestjs/common";
import { PrismaService } from "../prisma.service";
import { StudioController } from "./studio.controller";
import { StudioService } from "./studio.service";

@Module({
  controllers: [StudioController],
  providers: [StudioService, PrismaService],
  exports: [StudioService],
})
export class StudioModule {}
