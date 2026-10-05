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
import { validWindow } from "../studio/rules";

type Tx = Prisma.TransactionClient;

@Injectable()
export class SessionsService {
  constructor(private db: PrismaService) {}

  window(s: string | Date, e: string | Date) {
    const startsAt = new Date(s),
      endsAt = new Date(e);
    if (!validWindow(startsAt, endsAt))
      throw new BadRequestException(
        "Choose a future start and an end within 12 hours.",
      );
    return { startsAt, endsAt };
  }

  notify(tx: Tx, userId: string, title: string, body: string) {
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
      throw new BadRequestException("Invalid date range.");

    const where: Prisma.SessionWhereInput = {
      deletedAt: null,
      startsAt: { gte: start, lte: end },
    };

    if (a.role === "INSTRUCTOR") {
      const i = await this.db.instructor.findUnique({ where: { userId: a.id } });
      where.OR = [
        { status: "SCHEDULED" },
        ...(i ? [{ instructorId: i.id }] : []),
      ];
    } else if (a.role === "MEMBER") {
      where.status = "SCHEDULED";
    }

    const rows = await this.db.session.findMany({
      where,
      include: {
        instructor: { select: { id: true, name: true, specialty: true } },
        bookings: {
          where: { status: "CONFIRMED" },
          select: { id: true },
        },
      },
      orderBy: { startsAt: "asc" },
      take: 500,
    });

    return rows.map(({ bookings, ...s }) => ({
      ...s,
      spotsLeft: Math.max(0, s.capacity - bookings.length),
    }));
  }

  async createSession(d: D.SessionDto) {
    return this.db.serial(async (tx) => {
      const w = this.window(d.startsAt, d.endsAt);
      const i = d.instructorId
        ? await tx.instructor.findUnique({ where: { id: d.instructorId } })
        : null;
      if (d.type === "POLE_CLASS" && !i)
        throw new BadRequestException("Classes must have an instructor.");

      if (
        i &&
        ((await tx.unavailableSlot.count({
          where: {
            instructorId: i.id,
            startsAt: { lt: w.endsAt },
            endsAt: { gt: w.startsAt },
          },
        })) ||
          (await tx.session.count({
            where: {
              deletedAt: null,
              status: { in: ["SCHEDULED", "PENDING_INSTRUCTOR"] },
              instructorId: i.id,
              startsAt: { lt: w.endsAt },
              endsAt: { gt: w.startsAt },
            },
          })))
      )
        throw new ConflictException("The instructor is unavailable at that time.");

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
        throw new ConflictException("The studio already has a session at that time.");

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
      const i = await tx.instructor.findUnique({ where: { userId: a.id } });
      if (!i) throw new ForbiddenException();
      const s = await tx.session.findUnique({ where: { id } });
      if (!s || s.instructorId !== i.id) throw new ForbiddenException();
      if (s.status !== "PENDING_INSTRUCTOR" || s.startsAt <= new Date())
        throw new BadRequestException("This class is no longer awaiting acceptance.");

      return tx.session.update({
        where: { id },
        data: { status: "SCHEDULED" },
      });
    });
  }

  async decline(a: Actor, id: string, reason?: string) {
    return this.db.serial(async (tx) => {
      const i = await tx.instructor.findUnique({ where: { userId: a.id } });
      if (!i) throw new ForbiddenException();
      const s = await tx.session.findUnique({ where: { id } });
      if (!s || s.instructorId !== i.id) throw new ForbiddenException();
      if (s.status !== "PENDING_INSTRUCTOR" || s.startsAt <= new Date())
        throw new BadRequestException("This class is no longer awaiting response.");

      const updated = await tx.session.update({
        where: { id },
        data: {
          instructorId: null,
          status: "PENDING_INSTRUCTOR",
        },
      });

      const admins = await tx.user.findMany({ where: { role: "ADMIN" } });
      for (const admin of admins) {
        await this.notify(
          tx,
          admin.id,
          "Class declined by instructor",
          `${i.name} declined ${s.title}.${reason ? " Reason: " + reason : ""}`,
        );
      }

      return updated;
    });
  }

  async updateSession(id: string, d: D.UpdateSessionDto) {
    return this.db.serial(async (tx) => {
      const s = await tx.session.findUnique({
        where: { id },
        include: {
          bookings: {
            where: { status: { in: ["PENDING", "CONFIRMED", "PAID_AWAITING_RESOLUTION"] } },
          },
        },
      });
      if (!s || s.deletedAt) throw new NotFoundException("Session not found");
      if (s.status === "COMPLETED" || s.status === "CANCELLED")
        throw new BadRequestException("Cannot edit a completed or cancelled session.");

      const activeBookingsCount = s.bookings.filter((b) => b.status === "CONFIRMED").length;
      if (d.capacity !== undefined && d.capacity < activeBookingsCount) {
        throw new BadRequestException(
          `Cannot reduce capacity to ${d.capacity}. There are currently ${activeBookingsCount} confirmed bookings.`,
        );
      }

      const newStartsAt = d.startsAt ? new Date(d.startsAt) : s.startsAt;
      const newEndsAt = d.endsAt ? new Date(d.endsAt) : s.endsAt;
      const w = this.window(newStartsAt, newEndsAt);

      const timeChanged =
        newStartsAt.getTime() !== s.startsAt.getTime() ||
        newEndsAt.getTime() !== s.endsAt.getTime();

      if (
        await tx.session.count({
          where: {
            id: { not: s.id },
            deletedAt: null,
            status: { in: ["SCHEDULED", "PENDING_INSTRUCTOR"] },
            startsAt: { lt: w.endsAt },
            endsAt: { gt: w.startsAt },
          },
        })
      ) {
        throw new ConflictException("The studio room already has another session at this time.");
      }

      const targetInstructorId =
        d.instructorId !== undefined ? d.instructorId : s.instructorId;

      let targetInstructor = null;
      if (targetInstructorId) {
        targetInstructor = await tx.instructor.findUnique({
          where: { id: targetInstructorId },
        });
        if (!targetInstructor)
          throw new BadRequestException("Instructor not found.");

        if (
          await tx.unavailableSlot.count({
            where: {
              instructorId: targetInstructor.id,
              startsAt: { lt: w.endsAt },
              endsAt: { gt: w.startsAt },
            },
          })
        ) {
          throw new ConflictException(
            "The instructor has blocked unavailable time during this slot.",
          );
        }

        if (
          await tx.session.count({
            where: {
              id: { not: s.id },
              instructorId: targetInstructor.id,
              status: { in: ["SCHEDULED", "PENDING_INSTRUCTOR"] },
              startsAt: { lt: w.endsAt },
              endsAt: { gt: w.startsAt },
            },
          })
        ) {
          throw new ConflictException(
            "The instructor already has another class assigned during this time.",
          );
        }
      }

      const instructorChanged = targetInstructorId !== s.instructorId;
      let newStatus = s.status;
      if (targetInstructor) {
        if (instructorChanged || timeChanged) {
          const needsConfirmation =
            d.requireConfirmation !== undefined
              ? d.requireConfirmation
              : !targetInstructor.autoAccept;
          newStatus = needsConfirmation ? "PENDING_INSTRUCTOR" : "SCHEDULED";
        }
      }

      const updated = await tx.session.update({
        where: { id },
        data: {
          title: d.title ?? s.title,
          type: d.type ?? s.type,
          bookingMode: d.bookingMode ?? s.bookingMode,
          creditCost: d.creditCost ?? s.creditCost,
          capacity: d.capacity ?? s.capacity,
          price: d.price ?? s.price,
          level: d.level ?? s.level,
          description: d.description ?? s.description,
          instructorId: targetInstructorId,
          status: newStatus,
          ...w,
        },
      });

      if (timeChanged) {
        for (const b of s.bookings) {
          await this.notify(
            tx,
            b.memberId,
            "Schedule update: " + updated.title,
            `The time for ${updated.title} was changed to ${this.window(updated.startsAt, updated.endsAt).startsAt.toISOString()}. You can attend or cancel without penalty.`,
          );
        }
      }

      if (targetInstructor?.userId && (instructorChanged || timeChanged)) {
        await this.notify(
          tx,
          targetInstructor.userId,
          "Session assignment updated",
          `${updated.title} schedule or assignment was updated. Status: ${newStatus}.`,
        );
      }

      return updated;
    });
  }

  async cancelSession(id: string, remove: boolean) {
    return this.db.serial(async (tx) => {
      const s = await tx.session.findUnique({
        where: { id },
        include: { bookings: { where: { status: { in: ["PENDING", "CONFIRMED"] } } } },
      });
      if (!s) throw new NotFoundException();
      if (s.status === "COMPLETED")
        throw new BadRequestException("Completed classes remain in attendance history.");

      for (const b of s.bookings) {
        if (b.creditReserved) {
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
              reason: "Studio cancelled class",
              bookingId: b.id,
            },
          });
        }

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
        const i = await tx.instructor.findUnique({ where: { id: s.instructorId } });
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
      if (a.role !== "ADMIN") {
        const i = await tx.instructor.findUnique({ where: { userId: a.id } });
        if (!i || s.instructorId !== i.id) throw new ForbiddenException();
      }
      if (s.status !== "SCHEDULED" || s.endsAt > new Date())
        throw new BadRequestException("Only a scheduled class that has ended can be completed.");

      return tx.session.update({
        where: { id },
        data: { status: "COMPLETED" },
      });
    });
  }
}
