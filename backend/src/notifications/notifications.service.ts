import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { Cron } from "@nestjs/schedule";
import { PrismaService } from "../prisma.service";
import { Actor } from "../auth/auth";
import * as D from "../studio/dto";

@Injectable()
export class NotificationsService {
  constructor(private db: PrismaService) {}

  async campaign(d: D.CampaignDto) {
    const members = await this.db.user.findMany({ select: { id: true } });
    await this.db.notification.createMany({
      data: members.map((m) => ({
        userId: m.id,
        title: d.title,
        body: d.body,
      })),
    });
    return { sent: members.length };
  }

  async notifications(a: Actor) {
    return this.db.notification.findMany({
      where: { userId: a.id },
      orderBy: { createdAt: "desc" },
      take: 200,
    });
  }

  async read(a: Actor, id: string) {
    return this.db.notification.updateMany({
      where: { id, userId: a.id },
      data: { readAt: new Date() },
    });
  }

  async requests(a: Actor) {
    return this.db.timeslotRequest.findMany({
      where: a.role === "ADMIN" ? {} : { memberId: a.id },
      include: { member: { select: { name: true } } },
      orderBy: { createdAt: "desc" },
      take: 500,
    });
  }

  async request(a: Actor, d: D.RequestDto) {
    return this.db.serial(async (tx) => {
      const startsAt = new Date(d.startsAt),
        endsAt = new Date(d.endsAt);
      if (
        !Number.isFinite(+startsAt) ||
        !Number.isFinite(+endsAt) ||
        startsAt <= new Date() ||
        endsAt <= startsAt
      )
        throw new BadRequestException("Select a valid upcoming time.");
      const r = await tx.timeslotRequest.create({
        data: {
          memberId: a.id,
          type: d.type,
          startsAt,
          endsAt,
          note: d.note,
        },
      });
      const admins = await tx.user.findMany({ where: { role: "ADMIN" } });
      for (const admin of admins)
        await tx.notification.create({
          data: {
            userId: admin.id,
            title: "Timeslot request",
            body: `${a.name} requested a ${d.type} timeslot.`,
          },
        });
      return r;
    });
  }

  async respond(id: string, d: D.RequestResponseDto) {
    return this.db.serial(async (tx) => {
      const r = await tx.timeslotRequest.findUnique({ where: { id } });
      if (!r) throw new NotFoundException();
      if (r.status !== "PENDING")
        throw new ConflictException("This request was already reviewed.");
      const result = await tx.timeslotRequest.update({
        where: { id },
        data: d,
      });
      await tx.notification.create({
        data: {
          userId: r.memberId,
          title: "Timeslot request update",
          body: d.response,
        },
      });
      return result;
    });
  }

  @Cron("*/5 * * * *")
  async reminders() {
    const now = new Date(),
      soon = new Date(+now + 24 * 3600000);
    const upcoming = await this.db.booking.findMany({
      where: {
        status: "CONFIRMED",
        session: { status: "SCHEDULED", startsAt: { gt: now, lte: soon } },
      },
      include: { session: true },
    });
    await this.db.notification.createMany({
      data: upcoming.map((b) => ({
        userId: b.memberId,
        title: "Your class is coming up",
        body: `${b.session.title} starts ${b.session.startsAt.toLocaleString("en-GB", { timeZone: process.env.STUDIO_TIMEZONE || "Asia/Yangon" })}.`,
        dedupeKey: "reminder:" + b.id,
      })),
      skipDuplicates: true,
    });
  }

  @Cron("0 * * * *")
  async expirePackages() {
    const now = new Date();
    const expired = await this.db.memberPackage.findMany({
      where: {
        status: "ACTIVE",
        expiresAt: { lte: now },
      },
      include: { packageProduct: true },
    });

    for (const p of expired) {
      await this.db.serial(async (tx) => {
        await tx.memberPackage.update({
          where: { id: p.id },
          data: { status: "EXPIRED" },
        });

        if (p.creditsRemaining > 0) {
          await tx.user.update({
            where: { id: p.userId },
            data: { credits: { decrement: p.creditsRemaining } },
          });

          await tx.creditLedger.create({
            data: {
              userId: p.userId,
              packageId: p.id,
              delta: -p.creditsRemaining,
              reason: `Package expired: ${p.packageProduct.name}`,
            },
          });
        }

        await tx.notification.create({
          data: {
            userId: p.userId,
            title: "Package expired",
            body: `Your ${p.packageProduct.name} pass has expired. Unused credits have been removed per studio validity terms.`,
          },
        });
      });
    }
  }

  @Cron("*/15 * * * *")
  async autoCompleteSessions() {
    const now = new Date();
    await this.db.session.updateMany({
      where: {
        status: "SCHEDULED",
        endsAt: { lt: now },
      },
      data: {
        status: "COMPLETED",
      },
    });
  }
}
