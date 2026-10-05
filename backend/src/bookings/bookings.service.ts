import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../prisma.service";
import { Actor } from "../auth/auth";
import * as D from "../studio/dto";
import { discounted, mayCancel } from "../studio/rules";

type Tx = Prisma.TransactionClient;
const active = { in: ["PENDING", "CONFIRMED"] as ("PENDING" | "CONFIRMED")[] };
const memberSelect = { id: true, name: true, email: true } as const;

@Injectable()
export class BookingsService {
  constructor(private db: PrismaService) {}

  private notify(tx: Tx, userId: string, title: string, body: string) {
    return tx.notification.create({ data: { userId, title, body } });
  }

  private async restoreCredit(
    tx: Tx,
    b: { id: string; memberId: string; creditReserved: boolean; packageId?: string | null; creditsUsed?: number },
    reason: string,
  ) {
    if (!b.creditReserved) return;
    const creditsToRestore = b.creditsUsed && b.creditsUsed > 0 ? b.creditsUsed : 1;
    await tx.user.update({
      where: { id: b.memberId },
      data: { credits: { increment: creditsToRestore } },
    });
    if (b.packageId) {
      await tx.memberPackage.update({
        where: { id: b.packageId },
        data: {
          creditsRemaining: { increment: creditsToRestore },
          status: "ACTIVE",
        },
      });
    }
    await tx.creditLedger.create({
      data: {
        userId: b.memberId,
        packageId: b.packageId ?? null,
        delta: creditsToRestore,
        reason,
        bookingId: b.id,
      },
    });
  }

  async quote(sessionId: string, code?: string) {
    const s = await this.db.session.findUnique({ where: { id: sessionId } });
    if (!s) throw new NotFoundException();
    const p = code
      ? await this.db.promotion.findUnique({
          where: { code: code.trim().toUpperCase() },
        })
      : null;
    if (code && (!p || !p.active || p.expiresAt <= new Date()))
      throw new BadRequestException("This promotion is invalid or expired.");
    return {
      price: s.price,
      discount: s.price - discounted(s.price, p?.percent ?? 0),
      amount: discounted(s.price, p?.percent ?? 0),
    };
  }

  async book(a: Actor, d: D.BookingDto) {
    return this.db.serial(async (tx) => {
      const s = await tx.session.findUnique({ where: { id: d.sessionId } });
      if (
        !s ||
        s.status !== "SCHEDULED" ||
        s.deletedAt ||
        s.startsAt <= new Date()
      )
        throw new BadRequestException("This session is not available.");
      if (
        (await tx.booking.count({
          where: { sessionId: s.id, status: active },
        })) >= s.capacity
      )
        throw new ConflictException("This session is fully booked.");
      if (
        await tx.booking.count({
          where: { memberId: a.id, sessionId: s.id, status: active },
        })
      )
        throw new ConflictException("You already booked this session.");
      if (
        await tx.booking.count({
          where: {
            memberId: a.id,
            status: active,
            session: { startsAt: { lt: s.endsAt }, endsAt: { gt: s.startsAt } },
          },
        })
      )
        throw new ConflictException("You have another booking at this time.");

      const credit = d.paymentMethod === "CREDITS";

      if (credit && s.bookingMode === "WALK_IN_ONLY") {
        throw new BadRequestException(
          "This session is walk-in only. Package credits are not accepted.",
        );
      }
      if (!credit && s.bookingMode === "PACKAGE_ONLY") {
        throw new BadRequestException(
          "This session is reserved for package credit bookings only.",
        );
      }

      let amount = s.price,
        discount = 0,
        promoCode: string | null = null;
      if (!credit && d.promoCode) {
        const p = await tx.promotion.findUnique({
          where: { code: d.promoCode.trim().toUpperCase() },
        });
        if (!p || !p.active || p.expiresAt <= new Date())
          throw new BadRequestException("Promotion is invalid or expired.");
        amount = discounted(s.price, p.percent);
        discount = s.price - amount;
        promoCode = p.code;
      }
      if (!credit) {
        const proof = d.proofId
          ? await tx.paymentProof.findUnique({
              where: { id: d.proofId },
              include: { booking: true, memberPackage: true },
            })
          : null;
        if (!proof || proof.userId !== a.id || proof.booking || proof.memberPackage)
          throw new BadRequestException(
            "Upload an unused payment screenshot owned by your account.",
          );
      }
      let sourcePackageId: string | null = null;
      const creditCost = s.creditCost ?? 1;
      if (credit) {
        const now = new Date();
        const availablePackages = await tx.memberPackage.findMany({
          where: {
            userId: a.id,
            status: "ACTIVE",
            creditsRemaining: { gte: creditCost },
            OR: [
              { expiresAt: null },
              { expiresAt: { gt: now } },
            ],
            packageProduct: {
              allowedTypes: { has: s.type },
            },
          },
          orderBy: [
            { expiresAt: "asc" },
            { createdAt: "asc" },
          ],
          take: 1,
        });

        if (availablePackages.length > 0) {
          const selectedPackage = availablePackages[0];
          sourcePackageId = selectedPackage.id;
          const newRemaining = selectedPackage.creditsRemaining - creditCost;
          await tx.memberPackage.update({
            where: { id: selectedPackage.id },
            data: {
              creditsRemaining: newRemaining,
              status: newRemaining === 0 ? "EXHAUSTED" : "ACTIVE",
            },
          });
          const changed = await tx.user.updateMany({
            where: { id: a.id, credits: { gte: creditCost } },
            data: { credits: { decrement: creditCost } },
          });
          if (changed.count !== 1)
            throw new BadRequestException("Insufficient eligible class credits.");
        } else {
          const changed = await tx.user.updateMany({
            where: { id: a.id, credits: { gte: creditCost } },
            data: { credits: { decrement: creditCost } },
          });
          if (changed.count !== 1)
            throw new BadRequestException("Insufficient eligible class credits.");
        }
      }
      const b = await tx.booking.create({
        data: {
          memberId: a.id,
          sessionId: s.id,
          paymentMethod: d.paymentMethod,
          packageId: sourcePackageId,
          creditsUsed: credit ? creditCost : 0,
          proofId: credit ? null : d.proofId,
          amount: credit ? 0 : amount,
          discount: credit ? 0 : discount,
          promoCode,
          creditReserved: credit,
        },
      });
      if (credit)
        await tx.creditLedger.create({
          data: {
            userId: a.id,
            packageId: sourcePackageId,
            delta: -creditCost,
            reason: "Reserved for " + s.title,
            bookingId: b.id,
          },
        });
      await this.notify(
        tx,
        a.id,
        "Booking received",
        `${s.title} is waiting for studio confirmation.`,
      );
      const admins = await tx.user.findMany({ where: { role: "ADMIN" } });
      for (const admin of admins)
        await this.notify(
          tx,
          admin.id,
          "Booking to review",
          `${a.name} booked ${s.title}.`,
        );
      return b;
    });
  }

  async bookings(a: Actor) {
    const isInstructor = a.role === "INSTRUCTOR";
    let instructorId: string | undefined;
    if (isInstructor) {
      const i = await this.db.instructor.findUnique({ where: { userId: a.id } });
      instructorId = i?.id;
    }

    return this.db.booking.findMany({
      where:
        a.role === "ADMIN"
          ? {}
          : isInstructor
            ? {
                session: { instructorId },
                status: "CONFIRMED",
              }
            : { memberId: a.id },
      include: {
        session: { include: { instructor: { select: { name: true } } } },
        member: { select: memberSelect },
      },
      orderBy: { createdAt: "desc" },
      take: 1000,
    });
  }

  async review(id: string, approve: boolean, reason?: string) {
    return this.db.serial(async (tx) => {
      const b = await tx.booking.findUnique({
        where: { id },
        include: { session: true },
      });
      if (!b) throw new NotFoundException();
      if (b.status !== "PENDING")
        throw new ConflictException("This booking has already been reviewed.");
      if (
        approve &&
        (!["SCHEDULED", "COMPLETED"].includes(b.session.status) ||
          b.session.startsAt <= new Date())
      )
        throw new BadRequestException("This session is no longer open for confirmation.");
      if (!approve) await this.restoreCredit(tx, b, "Booking rejected");

      let finalStatus: "CONFIRMED" | "REJECTED" | "PAID_AWAITING_RESOLUTION" =
        approve ? "CONFIRMED" : "REJECTED";

      if (approve) {
        const confirmedCount = await tx.booking.count({
          where: {
            sessionId: b.sessionId,
            status: "CONFIRMED",
            id: { not: b.id },
          },
        });
        if (confirmedCount >= b.session.capacity) {
          finalStatus = "PAID_AWAITING_RESOLUTION";
        }
      }

      const result = await tx.booking.update({
        where: { id },
        data: {
          status: finalStatus,
          rejectionReason: approve ? null : reason,
          creditReserved: approve && finalStatus === "CONFIRMED" ? b.creditReserved : false,
        },
      });

      let noticeTitle = "Booking confirmed";
      let noticeBody = `${b.session.title} — see you in the studio!`;
      if (!approve) {
        noticeTitle = "Booking rejected";
        noticeBody = `${b.session.title}: ${reason}`;
      } else if (finalStatus === "PAID_AWAITING_RESOLUTION") {
        noticeTitle = "Payment verified — session full";
        noticeBody = `Payment for ${b.session.title} was verified, but the session reached full capacity. The studio will contact you to reschedule or refund.`;
      }

      await this.notify(tx, b.memberId, noticeTitle, noticeBody);
      return result;
    });
  }

  async adminCancelBooking(id: string, reason: string) {
    return this.db.serial(async (tx) => {
      const b = await tx.booking.findUnique({
        where: { id },
        include: { session: true },
      });
      if (!b) throw new NotFoundException();
      if (!["PENDING", "CONFIRMED", "PAID_AWAITING_RESOLUTION"].includes(b.status))
        throw new BadRequestException("This booking is not active.");
      await this.restoreCredit(tx, b, `Admin cancelled: ${reason}`);
      const r = await tx.booking.update({
        where: { id },
        data: {
          status: "CANCELLED",
          creditReserved: false,
          overrideReason: reason,
        },
      });
      await this.notify(
        tx,
        b.memberId,
        "Booking cancelled by studio",
        `${b.session.title} was cancelled by administrator. Reason: ${reason}.${b.paymentMethod === "CREDITS" ? " Your credit was restored." : " Contact the studio about your refund."}`,
      );
      return r;
    });
  }

  async resolveBooking(id: string, d: D.ResolveBookingDto) {
    return this.db.serial(async (tx) => {
      const b = await tx.booking.findUnique({
        where: { id },
        include: { session: true },
      });
      if (!b) throw new NotFoundException();
      if (b.status !== "PAID_AWAITING_RESOLUTION")
        throw new BadRequestException(
          "Only bookings awaiting resolution can be resolved through this workflow.",
        );

      if (d.action === "REFUND") {
        const note = d.note?.trim() || "Refund completed by studio administration";
        const updated = await tx.booking.update({
          where: { id },
          data: {
            status: "CANCELLED",
            overrideReason: note,
          },
        });
        await this.notify(
          tx,
          b.memberId,
          "Refund completed",
          `Your payment for ${b.session.title} was refunded. Note: ${note}`,
        );
        return updated;
      }

      if (d.action === "REASSIGN") {
        if (!d.targetSessionId)
          throw new BadRequestException("Target session is required for reassignment.");

        const target = await tx.session.findUnique({
          where: { id: d.targetSessionId },
          include: {
            bookings: { where: { status: { in: ["CONFIRMED", "PENDING"] } } },
          },
        });
        if (!target || target.deletedAt || target.status !== "SCHEDULED")
          throw new BadRequestException("Selected target session is not open for bookings.");
        if (target.startsAt <= new Date())
          throw new BadRequestException("Target session has already started or passed.");

        const confirmedCount = target.bookings.filter((x) => x.status === "CONFIRMED").length;
        if (confirmedCount >= target.capacity)
          throw new ConflictException("Target session is already at full capacity.");

        if (
          await tx.booking.count({
            where: {
              memberId: b.memberId,
              sessionId: target.id,
              status: { in: ["CONFIRMED", "PENDING"] },
            },
          })
        )
          throw new ConflictException("Member is already enrolled in the target session.");

        const updated = await tx.booking.update({
          where: { id },
          data: {
            sessionId: target.id,
            status: "CONFIRMED",
            overrideReason: `Reassigned from ${b.session.title}: ${d.note ?? "Session reassignment"}`,
          },
        });

        await this.notify(
          tx,
          b.memberId,
          "Booking reassigned",
          `Your booking was confirmed for ${target.title} on ${target.startsAt.toISOString()}.`,
        );

        return updated;
      }

      throw new BadRequestException("Invalid resolution action.");
    });
  }

  async adminBook(d: D.AdminBookingDto) {
    return this.db.serial(async (tx) => {
      const member = await tx.user.findUnique({ where: { id: d.memberId } });
      if (!member || member.role !== "MEMBER")
        throw new BadRequestException("Selected user is not a member.");
      const actor: Actor = { id: member.id, role: "MEMBER", email: member.email, name: member.name };
      return this.book(actor, {
        sessionId: d.sessionId,
        paymentMethod: d.paymentMethod,
        proofId: d.proofId,
      });
    });
  }

  async cancelBooking(a: Actor, id: string) {
    return this.db.serial(async (tx) => {
      const b = await tx.booking.findUnique({
        where: { id },
        include: { session: true },
      });
      if (!b) throw new NotFoundException();
      if (b.memberId !== a.id) throw new ForbiddenException();
      if (!["PENDING", "CONFIRMED"].includes(b.status))
        throw new BadRequestException("This booking is not active.");
      if (!mayCancel(b.session.startsAt))
        throw new BadRequestException(
          "Cancellation is allowed only more than 24 hours before the session.",
        );
      await this.restoreCredit(tx, b, "Member cancellation");
      const r = await tx.booking.update({
        where: { id },
        data: { status: "CANCELLED", creditReserved: false },
      });
      await this.notify(
        tx,
        a.id,
        "Booking cancelled",
        `${b.session.title}.${b.paymentMethod === "BANK_TRANSFER" ? " Contact the studio about any bank-transfer refund." : " Your class credit was returned."}`,
      );
      return r;
    });
  }

  async attendance(a: Actor, id: string, d: D.AttendanceDto) {
    return this.db.serial(async (tx) => {
      const b = await tx.booking.findUnique({
        where: { id },
        include: { session: true },
      });
      if (!b) throw new NotFoundException();
      if (a.role !== "ADMIN") {
        const i = await tx.instructor.findUnique({ where: { userId: a.id } });
        if (!i || b.session.instructorId !== i.id) throw new ForbiddenException();
      }
      if (b.status !== "CONFIRMED" || b.session.startsAt > new Date())
        throw new BadRequestException(
          "Attendance can be recorded after a confirmed session starts.",
        );
      return tx.booking.update({
        where: { id },
        data: { attendance: d.attendance },
      });
    });
  }
}
