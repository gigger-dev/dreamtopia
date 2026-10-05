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
export class InstructorsService {
  constructor(private db: PrismaService) {}

  private window(s: string | Date, e: string | Date) {
    const startsAt = new Date(s),
      endsAt = new Date(e);
    if (!validWindow(startsAt, endsAt))
      throw new BadRequestException(
        "Choose a future start and an end within 12 hours.",
      );
    return { startsAt, endsAt };
  }

  async instructor(a: Actor, tx: Tx = this.db) {
    const i = await tx.instructor.findUnique({ where: { userId: a.id } });
    if (!i)
      throw new ForbiddenException("No instructor profile linked to your account.");
    return i;
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
        throw new BadRequestException("An admin account cannot become an instructor.");
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
}
