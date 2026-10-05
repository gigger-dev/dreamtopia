import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { Cron } from "@nestjs/schedule";
import { Prisma, Role } from "@prisma/client";
import { PrismaService } from "../prisma.service";
import { Actor } from "../auth/auth";
import * as D from "./dto";
import { discounted, mayCancel, validWindow } from "./rules";
type Tx = Prisma.TransactionClient;
const active = { in: ["PENDING", "CONFIRMED"] as ("PENDING" | "CONFIRMED")[] };
const memberSelect = { id: true, name: true, email: true } as const;
@Injectable()
export class StudioService {
  constructor(private db: PrismaService) {}
  async me(a: Actor) {
    const user = await this.db.user.findUniqueOrThrow({
      where: { id: a.id },
      select: { ...memberSelect, role: true, credits: true, instructor: true },
    });
    const classesTaught = user.instructor
      ? await this.db.session.count({
          where: { instructorId: user.instructor.id, status: "COMPLETED" },
        })
      : 0;
    return { ...user, classesTaught };
  }
  async instructor(a: Actor, tx: Tx = this.db) {
    const i = await tx.instructor.findUnique({ where: { userId: a.id } });
    if (!i)
      throw new ForbiddenException(
        "No instructor profile linked to your account.",
      );
    return i;
  }
  private window(s: string, e: string) {
    const startsAt = new Date(s),
      endsAt = new Date(e);
    if (!validWindow(startsAt, endsAt))
      throw new BadRequestException(
        "Choose a future start and an end within 12 hours.",
      );
    return { startsAt, endsAt };
  }
  private notify(tx: Tx, userId: string, title: string, body: string) {
    return tx.notification.create({ data: { userId, title, body } });
  }
  async sessions(a: Actor, from?: string, to?: string) {
    const start = from ? new Date(from) : new Date(Date.now() - 86400000),
      end = to ? new Date(to) : new Date(Date.now() + 90 * 86400000);
    if (
      !Number.isFinite(+start) ||
      !Number.isFinite(+end) ||
      end <= start ||
      +end - +start > 366 * 86400000
    )
      throw new BadRequestException(
        "Invalid calendar range (maximum 366 days).",
      );
    const where: Prisma.SessionWhereInput = {
      deletedAt: null,
      startsAt: { gte: start, lt: end },
    };
    if (a.role === "MEMBER") where.status = "SCHEDULED";
    if (a.role === "INSTRUCTOR")
      where.instructorId = (await this.instructor(a)).id;
    const rows = await this.db.session.findMany({
      where,
      include: {
        instructor: {
          select: { id: true, name: true, bio: true, specialty: true },
        },
        _count: { select: { bookings: { where: { status: active } } } },
      },
      orderBy: { startsAt: "asc" },
    });
    return rows.map(({ _count, ...r }) => ({
      ...r,
      spotsLeft: r.capacity - _count.bookings,
    }));
  }
  async createSession(d: D.SessionDto) {
    return this.db.serial(async (tx) => {
      const w = this.window(d.startsAt, d.endsAt);
      if (["POLE_CLASS", "TRIAL"].includes(d.type) && !d.instructorId)
        throw new BadRequestException("A class needs an instructor.");
      const i = d.instructorId
        ? await tx.instructor.findUnique({ where: { id: d.instructorId } })
        : null;
      if (d.instructorId && !i)
        throw new BadRequestException("Instructor does not exist.");
      if (
        i &&
        (await tx.unavailableSlot.count({
          where: {
            instructorId: i.id,
            startsAt: { lt: w.endsAt },
            endsAt: { gt: w.startsAt },
          },
        }))
      )
        throw new ConflictException(
          "The instructor is unavailable at that time.",
        );
      // Dreamtopia has one shared studio. A rental or a class reserves the entire room.
      if (
        await tx.session.count({
          where: {
            deletedAt: null,
            status: { in: ["SCHEDULED", "PENDING_INSTRUCTOR"] },
            startsAt: { lt: w.endsAt },
            endsAt: { gt: w.startsAt },
          },
        })
      )
        throw new ConflictException(
          "The studio already has a session at that time.",
        );
      const { requireConfirmation, bookingMode, creditCost, ...sessionData } = d;
      const needsConfirmation =
        i &&
        (requireConfirmation !== undefined
          ? requireConfirmation
          : !i.autoAccept);
      const session = await tx.session.create({
        data: {
          ...sessionData,
          bookingMode: bookingMode ?? "BOTH",
          creditCost: creditCost ?? 1,
          ...w,
          capacity: d.type === "RENTAL" ? 1 : d.capacity,
          status: needsConfirmation ? "PENDING_INSTRUCTOR" : "SCHEDULED",
        },
      });
      if (i?.userId)
        await this.notify(
          tx,
          i.userId,
          "New class assignment",
          `${d.title} has been approved by admin.${!needsConfirmation ? " No confirmation needed." : " Please accept it in your calendar."}`,
        );
      return session;
    });
  }
  async accept(a: Actor, id: string) {
    return this.db.serial(async (tx) => {
      const i = await this.instructor(a, tx);
      const s = await tx.session.findUnique({ where: { id } });
      if (!s || s.instructorId !== i.id) throw new ForbiddenException();
      if (s.status !== "PENDING_INSTRUCTOR" || s.startsAt <= new Date())
        throw new BadRequestException(
          "This class is no longer awaiting acceptance.",
        );
      return tx.session.update({
        where: { id },
        data: { status: "SCHEDULED" },
      });
    });
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
          status: "ACTIVE", // revert from EXHAUSTED if it was exhausted
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
  async cancelSession(id: string, remove: boolean) {
    return this.db.serial(async (tx) => {
      const s = await tx.session.findUnique({
        where: { id },
        include: { bookings: { where: { status: active } } },
      });
      if (!s) throw new NotFoundException();
      if (s.status === "COMPLETED")
        throw new BadRequestException(
          "Completed classes remain in attendance history.",
        );
      for (const b of s.bookings) {
        await this.restoreCredit(tx, b, "Studio cancelled class");
        await tx.booking.update({
          where: { id: b.id },
          data: { status: "CANCELLED", creditReserved: false },
        });
        await this.notify(
          tx,
          b.memberId,
          "Session cancelled",
          `${s.title} was cancelled.${b.paymentMethod === "CREDITS" ? " Your credit has been returned." : " Contact the studio about your bank-transfer refund."}`,
        );
      }
      if (s.instructorId) {
        const i = await tx.instructor.findUnique({
          where: { id: s.instructorId },
        });
        if (i?.userId)
          await this.notify(tx, i.userId, "Class cancelled", s.title);
      }
      return tx.session.update({
        where: { id },
        data: {
          status: "CANCELLED",
          ...(remove ? { deletedAt: new Date() } : {}),
        },
      });
    });
  }
  async completeSession(a: Actor, id: string) {
    return this.db.serial(async (tx) => {
      const s = await tx.session.findUnique({ where: { id } });
      if (!s) throw new NotFoundException();
      if (
        a.role !== "ADMIN" &&
        s.instructorId !== (await this.instructor(a, tx)).id
      )
        throw new ForbiddenException();
      if (s.status !== "SCHEDULED" || s.endsAt > new Date())
        throw new BadRequestException(
          "Only a scheduled class that has ended can be completed.",
        );
      return tx.session.update({
        where: { id },
        data: { status: "COMPLETED" },
      });
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
      if (credit && s.bookingMode === "WALK_IN_ONLY")
        throw new BadRequestException("This class accepts walk-in bank transfer only.");
      if (!credit && s.bookingMode === "PACKAGE_ONLY")
        throw new BadRequestException("This class is package-credits only.");
      if (credit && d.promoCode)
        throw new BadRequestException(
          "A promotion cannot be used with a class credit.",
        );
      let amount = s.price,
        discount = 0,
        promoCode: string | undefined;
      if (d.promoCode) {
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
        // Find active package with earliest expiry (FIFO) that allows this session type
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
          const pkg = availablePackages[0];
          sourcePackageId = pkg.id;
          const remaining = pkg.creditsRemaining - creditCost;
          await tx.memberPackage.update({
            where: { id: pkg.id },
            data: {
              creditsRemaining: remaining,
              status: remaining === 0 ? "EXHAUSTED" : "ACTIVE",
            },
          });
          await tx.user.update({
            where: { id: a.id },
            data: { credits: { decrement: creditCost } },
          });
        } else {
          // Fallback to legacy/direct user.credits if sufficient
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
    return this.db.booking.findMany({
      where:
        a.role === "ADMIN"
          ? {}
          : a.role === "INSTRUCTOR"
            ? {
                session: { instructorId: (await this.instructor(a)).id },
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
        throw new BadRequestException(
          "This session is no longer open for confirmation.",
        );
      if (!approve) await this.restoreCredit(tx, b, "Booking rejected");

      // Per spec: recheck session capacity on walk-in approval.
      // If session filled up while proof was pending, mark PAID_AWAITING_RESOLUTION.
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
      if (
        a.role !== "ADMIN" &&
        b.session.instructorId !== (await this.instructor(a, tx)).id
      )
        throw new ForbiddenException();
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
  async addInstructor(d: D.InstructorDto) {
    if (
      await this.db.instructor.findUnique({
        where: { email: d.email.trim().toLowerCase() },
      })
    )
      throw new ConflictException("This instructor already exists.");
    return this.db.instructor.create({
      data: { ...d, email: d.email.trim().toLowerCase() },
    });
  }
  async linkInstructor(id: string) {
    return this.db.serial(async (tx) => {
      const i = await tx.instructor.findUnique({ where: { id } });
      if (!i) throw new NotFoundException();
      const user = await tx.user.findUnique({ where: { email: i.email } });
      if (!user)
        throw new BadRequestException(
          "The instructor must register with this email first.",
        );
      if (user.role === "ADMIN")
        throw new BadRequestException(
          "An admin account cannot become an instructor.",
        );
      await tx.user.update({
        where: { id: user.id },
        data: { role: "INSTRUCTOR" },
      });
      return tx.instructor.update({ where: { id }, data: { userId: user.id } });
    });
  }
  async instructors() {
    const list = await this.db.instructor.findMany({
      include: {
        _count: { select: { sessions: { where: { status: "COMPLETED" } } } },
      },
      orderBy: { name: "asc" },
    });
    return list.map(({ _count, ...i }) => ({
      ...i,
      classesTaught: _count.sessions,
    }));
  }
  async autoAccept(a: Actor, d: D.AutoDto) {
    const i = await this.instructor(a);
    return this.db.instructor.update({ where: { id: i.id }, data: d });
  }
  async blocks(a: Actor) {
    return this.db.unavailableSlot.findMany({
      where: { instructorId: (await this.instructor(a)).id },
      orderBy: { startsAt: "asc" },
    });
  }
  async block(a: Actor, d: D.BlockDto) {
    return this.db.serial(async (tx) => {
      const i = await this.instructor(a, tx),
        w = this.window(d.startsAt, d.endsAt);
      if (
        await tx.session.count({
          where: {
            instructorId: i.id,
            status: { in: ["PENDING_INSTRUCTOR", "SCHEDULED"] },
            startsAt: { lt: w.endsAt },
            endsAt: { gt: w.startsAt },
          },
        })
      )
        throw new ConflictException(
          "You already have an assigned class. Ask the admin to cancel or reassign it before blocking this time.",
        );
      if (
        await tx.unavailableSlot.count({
          where: {
            instructorId: i.id,
            startsAt: { lt: w.endsAt },
            endsAt: { gt: w.startsAt },
          },
        })
      )
        throw new ConflictException("This time overlaps an existing block.");
      return tx.unavailableSlot.create({
        data: { ...w, reason: d.reason, instructorId: i.id },
      });
    });
  }
  async unblock(a: Actor, id: string) {
    const i = await this.instructor(a);
    const r = await this.db.unavailableSlot.deleteMany({
      where: { id, instructorId: i.id },
    });
    if (!r.count) throw new NotFoundException();
    return { ok: true };
  }
  async grant(id: string, d: D.CreditDto) {
    return this.db.serial(async (tx) => {
      const u = await tx.user.findUnique({ where: { id } });
      if (!u || u.role !== "MEMBER")
        throw new BadRequestException("Select a member.");
      await tx.user.update({
        where: { id },
        data: { credits: { increment: d.amount } },
      });
      await tx.creditLedger.create({
        data: { userId: id, delta: d.amount, reason: d.reason },
      });
      await this.notify(
        tx,
        id,
        "Class package updated",
        `${d.amount} credits added: ${d.reason}`,
      );
      return { ok: true };
    });
  }

  // --- Package Products and Member Purchases (SBQS_V1 FR02, FR04, FR10, AC03) ---

  async packageProducts() {
    return this.db.packageProduct.findMany({
      where: { active: true },
      orderBy: { price: "asc" },
    });
  }

  async allPackageProducts() {
    return this.db.packageProduct.findMany({
      orderBy: { createdAt: "desc" },
    });
  }

  async createPackageProduct(d: D.PackageProductDto) {
    return this.db.packageProduct.create({
      data: {
        name: d.name,
        description: d.description ?? "",
        credits: d.credits,
        price: d.price,
        validityDays: d.validityDays,
        allowedTypes: d.allowedTypes ?? ["POLE_CLASS"],
        active: d.active ?? true,
      },
    });
  }

  async purchasePackage(a: Actor, d: D.PurchasePackageDto) {
    return this.db.serial(async (tx) => {
      const product = await tx.packageProduct.findUnique({
        where: { id: d.packageProductId },
      });
      if (!product || !product.active)
        throw new BadRequestException("This package product is not available.");

      const proof = await tx.paymentProof.findUnique({
        where: { id: d.proofId },
        include: { booking: true, memberPackage: true },
      });
      if (!proof || proof.userId !== a.id || proof.booking || proof.memberPackage)
        throw new BadRequestException(
          "Upload an unused payment screenshot owned by your account.",
        );

      const mp = await tx.memberPackage.create({
        data: {
          userId: a.id,
          packageProductId: product.id,
          creditsTotal: product.credits,
          creditsRemaining: product.credits,
          pricePaid: product.price,
          status: "PENDING_REVIEW",
          proofId: d.proofId,
        },
      });

      await this.notify(
        tx,
        a.id,
        "Package order received",
        `Your order for ${product.name} is waiting for studio verification.`,
      );

      const admins = await tx.user.findMany({ where: { role: "ADMIN" } });
      for (const admin of admins) {
        await this.notify(
          tx,
          admin.id,
          "Package payment to review",
          `${a.name} submitted payment for ${product.name}.`,
        );
      }

      return mp;
    });
  }

  async memberPackages(a: Actor) {
    return this.db.memberPackage.findMany({
      where: a.role === "ADMIN" ? {} : { userId: a.id },
      include: {
        packageProduct: true,
        user: { select: memberSelect },
      },
      orderBy: { createdAt: "desc" },
      take: 500,
    });
  }

  async reviewPackagePurchase(id: string, approve: boolean, reason?: string) {
    return this.db.serial(async (tx) => {
      const mp = await tx.memberPackage.findUnique({
        where: { id },
        include: { packageProduct: true, user: true },
      });
      if (!mp) throw new NotFoundException();
      if (mp.status !== "PENDING_REVIEW")
        throw new ConflictException("This purchase has already been reviewed.");

      if (approve) {
        const now = new Date();
        const expiresAt = new Date(+now + mp.packageProduct.validityDays * 86400000);

        const updated = await tx.memberPackage.update({
          where: { id },
          data: {
            status: "ACTIVE",
            activatedAt: now,
            expiresAt,
          },
        });

        // Atomically grant credits to the user profile
        await tx.user.update({
          where: { id: mp.userId },
          data: { credits: { increment: mp.creditsTotal } },
        });

        // Append to credit ledger
        await tx.creditLedger.create({
          data: {
            userId: mp.userId,
            packageId: mp.id,
            delta: mp.creditsTotal,
            reason: `Package activated: ${mp.packageProduct.name}`,
          },
        });

        await this.notify(
          tx,
          mp.userId,
          "Package activated!",
          `${mp.packageProduct.name} is now active. ${mp.creditsTotal} class credits added to your balance.`,
        );

        return updated;
      } else {
        const updated = await tx.memberPackage.update({
          where: { id },
          data: {
            status: "REJECTED",
            rejectionReason: reason,
          },
        });

        await this.notify(
          tx,
          mp.userId,
          "Package payment rejected",
          `Payment for ${mp.packageProduct.name} could not be verified: ${reason}`,
        );

        return updated;
      }
    });
  }
  async promotion(d: D.PromotionDto) {
    if (new Date(d.expiresAt) <= new Date())
      throw new BadRequestException("Expiry must be in the future.");
    const code = d.code.trim().toUpperCase();
    if (await this.db.promotion.findUnique({ where: { code } }))
      throw new ConflictException("This code already exists.");
    return this.db.promotion.create({
      data: { ...d, code, expiresAt: new Date(d.expiresAt) },
    });
  }
  async campaign(d: D.CampaignDto) {
    const users = await this.db.user.findMany({
      where: { role: "MEMBER" },
      select: { id: true },
    });
    const result = await this.db.notification.createMany({
      data: users.map((u) => ({ ...d, userId: u.id })),
    });
    return { recipients: result.count };
  }
  async request(a: Actor, d: D.RequestDto) {
    return this.db.serial(async (tx) => {
      const w = this.window(d.startsAt, d.endsAt);
      const r = await tx.timeslotRequest.create({
        data: { ...d, ...w, memberId: a.id },
      });
      const admins = await tx.user.findMany({ where: { role: "ADMIN" } });
      for (const admin of admins)
        await this.notify(
          tx,
          admin.id,
          "Preferred timeslot requested",
          `${a.name} requested ${d.type.toLowerCase().replace("_", " ")}.`,
        );
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
      await this.notify(tx, r.memberId, "Timeslot request update", d.response);
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
}
