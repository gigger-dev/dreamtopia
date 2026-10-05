import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
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
  @Get("me") me(@Req() r: AuthRequest) {
    return this.service.me(r.user);
  }
  @Get("settings") settings() {
    return {
      timezone: process.env.STUDIO_TIMEZONE || "Asia/Yangon",
      currency: process.env.STUDIO_CURRENCY || "MMK",
      bankInstructions:
        process.env.BANK_INSTRUCTIONS ||
        "Please ask the studio for bank details before transferring.",
      cancellationHours: 24,
    };
  }
  @Get("sessions") sessions(
    @Req() r: AuthRequest,
    @Query("from") from?: string,
    @Query("to") to?: string,
  ) {
    return this.service.sessions(r.user, from, to);
  }
  @Roles("ADMIN") @Post("sessions") createSession(@Body() d: D.SessionDto) {
    return this.service.createSession(d);
  }
  @Roles("ADMIN") @Post("sessions/:id/cancel") cancelSession(
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.service.cancelSession(id, false);
  }
  @Roles("ADMIN") @Delete("sessions/:id") deleteSession(
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.service.cancelSession(id, true);
  }
  @Roles("ADMIN") @Patch("sessions/:id") updateSession(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() d: D.UpdateSessionDto,
  ) {
    return this.service.updateSession(id, d);
  }
  @Roles("INSTRUCTOR") @Post("sessions/:id/accept") accept(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.service.accept(r.user, id);
  }
  @Roles("INSTRUCTOR") @Post("sessions/:id/decline") decline(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() d: D.DeclineSessionDto,
  ) {
    return this.service.decline(r.user, id, d.reason);
  }
  @Roles("ADMIN", "INSTRUCTOR") @Post("sessions/:id/complete") complete(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.service.completeSession(r.user, id);
  }
  @Get("sessions/:id/quote") quote(
    @Param("id", ParseUUIDPipe) id: string,
    @Query("code") code?: string,
  ) {
    return this.service.quote(id, code);
  }
  @Get("bookings") bookings(@Req() r: AuthRequest) {
    return this.service.bookings(r.user);
  }
  @Roles("MEMBER") @Post("bookings") book(
    @Req() r: AuthRequest,
    @Body() d: D.BookingDto,
  ) {
    return this.service.book(r.user, d);
  }
  @Roles("MEMBER") @Post("bookings/:id/cancel") cancelBooking(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.service.cancelBooking(r.user, id);
  }
  @Roles("ADMIN") @Post("admin/bookings") adminBook(
    @Body() d: D.AdminBookingDto,
  ) {
    return this.service.adminBook(d);
  }
  @Roles("ADMIN") @Post("admin/bookings/:id/cancel") cancelBookingOverride(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() d: D.CancelOverrideDto,
  ) {
    return this.service.adminCancelBooking(id, d.reason);
  }
  @Roles("ADMIN") @Post("admin/bookings/:id/resolve") resolveBooking(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() d: D.ResolveBookingDto,
  ) {
    return this.service.resolveBooking(id, d);
  }
  @Roles("ADMIN") @Post("bookings/:id/approve") approve(
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.service.review(id, true);
  }
  @Roles("ADMIN") @Post("bookings/:id/reject") reject(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() d: D.ReasonDto,
  ) {
    return this.service.review(id, false, d.reason);
  }
  @Roles("ADMIN", "INSTRUCTOR") @Patch("bookings/:id/attendance") attendance(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() d: D.AttendanceDto,
  ) {
    return this.service.attendance(r.user, id, d);
  }
  @Roles("ADMIN") @Get("instructors") instructors() {
    return this.service.instructors();
  }
  @Roles("ADMIN") @Post("instructors") addInstructor(
    @Body() d: D.InstructorDto,
  ) {
    return this.service.addInstructor(d);
  }
  @Roles("ADMIN") @Post("instructors/:id/link") linkInstructor(
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.service.linkInstructor(id);
  }
  @Roles("INSTRUCTOR") @Patch("instructor/settings") auto(
    @Req() r: AuthRequest,
    @Body() d: D.AutoDto,
  ) {
    return this.service.autoAccept(r.user, d);
  }
  @Roles("INSTRUCTOR") @Get("instructor/blocks") blocks(@Req() r: AuthRequest) {
    return this.service.blocks(r.user);
  }
  @Roles("INSTRUCTOR") @Post("instructor/blocks") block(
    @Req() r: AuthRequest,
    @Body() d: D.BlockDto,
  ) {
    return this.service.block(r.user, d);
  }
  @Roles("INSTRUCTOR") @Delete("instructor/blocks/:id") unblock(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.service.unblock(r.user, id);
  }
  @Roles("ADMIN") @Get("members") members() {
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
  @Roles("ADMIN") @Post("members/:id/credits") credits(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() d: D.CreditDto,
  ) {
    return this.service.grant(id, d);
  }
  @Get("packages/products") packageProducts() {
    return this.service.packageProducts();
  }
  @Roles("ADMIN") @Get("admin/packages/products") allPackageProducts() {
    return this.service.allPackageProducts();
  }
  @Roles("ADMIN") @Post("admin/packages/products") createPackageProduct(
    @Body() d: D.PackageProductDto,
  ) {
    return this.service.createPackageProduct(d);
  }
  @Roles("MEMBER") @Post("packages/purchase") purchasePackage(
    @Req() r: AuthRequest,
    @Body() d: D.PurchasePackageDto,
  ) {
    return this.service.purchasePackage(r.user, d);
  }
  @Get("packages") memberPackages(@Req() r: AuthRequest) {
    return this.service.memberPackages(r.user);
  }
  @Roles("ADMIN") @Post("packages/:id/approve") approvePackage(
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.service.reviewPackagePurchase(id, true);
  }
  @Roles("ADMIN") @Post("packages/:id/reject") rejectPackage(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() d: D.ReasonDto,
  ) {
    return this.service.reviewPackagePurchase(id, false, d.reason);
  }
  @Roles("MEMBER") @Get("credits") ledger(@Req() r: AuthRequest) {
    return this.db.creditLedger.findMany({
      where: { userId: r.user.id },
      include: { package: { include: { packageProduct: true } } },
      orderBy: { createdAt: "desc" },
      take: 300,
    });
  }
  @Roles("ADMIN") @Get("promotions") promotions() {
    return this.db.promotion.findMany({ orderBy: { expiresAt: "desc" } });
  }
  @Roles("ADMIN") @Post("promotions") promotion(@Body() d: D.PromotionDto) {
    return this.service.promotion(d);
  }
  @Roles("ADMIN") @Patch("promotions/:id") active(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() d: D.ActiveDto,
  ) {
    return this.db.promotion.update({ where: { id }, data: d });
  }
  @Roles("ADMIN") @Post("campaigns") campaign(@Body() d: D.CampaignDto) {
    return this.service.campaign(d);
  }
  @Get("notifications") notifications(@Req() r: AuthRequest) {
    return this.db.notification.findMany({
      where: { userId: r.user.id },
      orderBy: { createdAt: "desc" },
      take: 200,
    });
  }
  @Patch("notifications/:id/read") read(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.db.notification.updateMany({
      where: { id, userId: r.user.id },
      data: { readAt: new Date() },
    });
  }
  @Roles("ADMIN", "MEMBER") @Get("requests") requests(@Req() r: AuthRequest) {
    return this.db.timeslotRequest.findMany({
      where: r.user.role === "ADMIN" ? {} : { memberId: r.user.id },
      include: { member: { select: { name: true } } },
      orderBy: { createdAt: "desc" },
      take: 500,
    });
  }
  @Roles("MEMBER") @Post("requests") request(
    @Req() r: AuthRequest,
    @Body() d: D.RequestDto,
  ) {
    return this.service.request(r.user, d);
  }
  @Roles("ADMIN") @Patch("requests/:id") respond(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() d: D.RequestResponseDto,
  ) {
    return this.service.respond(id, d);
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
  @Get("proofs/:id") async proof(
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
