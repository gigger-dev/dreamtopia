import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Req,
  Res,
  UploadedFile,
  UseInterceptors,
  BadRequestException,
  ForbiddenException,
  NotFoundException,
} from "@nestjs/common";
import { FileInterceptor } from "@nestjs/platform-express";
import { memoryStorage } from "multer";
import { randomUUID } from "node:crypto";
import { mkdir, writeFile, unlink } from "node:fs/promises";
import { resolve } from "node:path";
import type { Response } from "express";
import { AuthRequest, Roles } from "../auth/auth";
import { PrismaService } from "../prisma.service";
import { StudioService } from "./studio.service";
import { imageMime } from "./rules";
import * as D from "./dto";

@Controller()
export class StudioController {
  constructor(
    private service: StudioService,
    private db: PrismaService,
  ) {}

  @Get("me")
  me(@Req() r: AuthRequest) {
    return this.service.me(r.user);
  }

  @Get("settings")
  settings() {
    return {
      timezone: process.env.STUDIO_TIMEZONE || "Asia/Yangon",
      currency: process.env.STUDIO_CURRENCY || "MMK",
      bankInstructions:
        process.env.BANK_INSTRUCTIONS ||
        "Please ask the studio for bank details before transferring.",
      cancellationHours: 24,
    };
  }

  @Roles("ADMIN")
  @Get("members")
  members() {
    return this.db.user.findMany({
      where: { role: "MEMBER" },
      select: {
        id: true,
        name: true,
        email: true,
        credits: true,
        _count: { select: { bookings: { where: { attendance: "PRESENT" } } } },
      },
      orderBy: { name: "asc" },
    });
  }

  @Roles("ADMIN")
  @Post("members/:id/credits")
  credits(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() d: D.CreditDto,
  ) {
    return this.service.grant(id, d);
  }

  @Roles("MEMBER")
  @Get("credits")
  ledger(@Req() r: AuthRequest) {
    return this.db.creditLedger.findMany({
      where: { userId: r.user.id },
      include: { package: { include: { packageProduct: true } } },
      orderBy: { createdAt: "desc" },
      take: 300,
    });
  }

  @Roles("ADMIN")
  @Get("promotions")
  promotions() {
    return this.db.promotion.findMany({ orderBy: { expiresAt: "desc" } });
  }

  @Roles("ADMIN")
  @Post("promotions")
  promotion(@Body() d: D.PromotionDto) {
    return this.service.promotion(d);
  }

  @Roles("ADMIN")
  @Patch("promotions/:id")
  active(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() d: D.ActiveDto,
  ) {
    return this.db.promotion.update({ where: { id }, data: d });
  }

  @Roles("MEMBER")
  @Post("proofs")
  @UseInterceptors(
    FileInterceptor("file", {
      storage: memoryStorage(),
      limits: { fileSize: 5 * 1024 * 1024, files: 1 },
    }),
  )
  async upload(
    @Req() r: AuthRequest,
    @UploadedFile() file: Express.Multer.File,
  ) {
    if (!file) throw new BadRequestException("Choose a payment screenshot.");
    const mime = imageMime(file.buffer);
    if (!mime)
      throw new BadRequestException(
        "Only PNG, JPEG, and WebP images are accepted.",
      );
    const filename = randomUUID(),
      folder = resolve(process.env.UPLOAD_DIR || "./uploads");
    await mkdir(folder, { recursive: true });
    await writeFile(resolve(folder, filename), file.buffer, { flag: "wx" });
    try {
      return await this.db.paymentProof.create({
        data: { userId: r.user.id, filename, mime },
        select: { id: true, mime: true },
      });
    } catch (e) {
      await unlink(resolve(folder, filename));
      throw e;
    }
  }

  @Get("proofs/:id")
  async proof(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Res() res: Response,
  ) {
    const p = await this.db.paymentProof.findUnique({ where: { id } });
    if (!p) throw new NotFoundException();
    if (r.user.role !== "ADMIN" && p.userId !== r.user.id)
      throw new ForbiddenException();
    res.setHeader("Content-Type", p.mime);
    res.setHeader("Cache-Control", "private, no-store");
    res.setHeader("Content-Disposition", "inline");
    return res.sendFile(
      resolve(process.env.UPLOAD_DIR || "./uploads", p.filename),
    );
  }
}
