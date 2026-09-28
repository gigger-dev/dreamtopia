import "reflect-metadata";
import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { PrismaService } from "../../src/prisma.service";
import { StudioService } from "../../src/studio/studio.service";
import { Actor } from "../../src/auth/auth";
import type { SessionDto } from "../../src/studio/dto";
const db = new PrismaService(),
  service = new StudioService(db),
  tag = randomUUID();
let m1: Actor, m2: Actor, teacher: Actor, instructorId: string;
const userIds: string[] = [],
  sessionIds: string[] = [],
  proofIds: string[] = [],
  promoIds: string[] = [];
const at = (day: number, hour = 0) =>
  new Date(Date.now() + (day * 24 + hour) * 3600000).toISOString();
const dto = (day: number, extra: Partial<SessionDto> = {}): SessionDto => ({
  title: "Test " + tag,
  type: "POLE_CLASS",
  startsAt: at(day),
  endsAt: at(day, 1),
  capacity: 1,
  price: 35000,
  level: "Beginner",
  instructorId,
  ...extra,
});
async function session(day: number, extra: Partial<SessionDto> = {}) {
  const s = await service.createSession(dto(day, extra));
  sessionIds.push(s.id);
  return s;
}
before(async () => {
  if (!process.env.DATABASE_URL?.includes("dreamtopia_test"))
    throw new Error("Use a dedicated database named dreamtopia_test.");
  await db.$connect();
  for (const [n, role] of [
    ["m1", "MEMBER"],
    ["m2", "MEMBER"],
    ["teacher", "INSTRUCTOR"],
  ] as const) {
    const u = await db.user.create({
      data: {
        email: `${n}-${tag}@example.test`,
        name: n,
        passwordHash: "not-a-login",
        role,
        credits: 2,
      },
    });
    userIds.push(u.id);
    if (n === "m1") m1 = u;
    else if (n === "m2") m2 = u;
    else teacher = u;
  }
  const i = await db.instructor.create({
    data: {
      userId: teacher.id,
      email: teacher.email,
      name: "Test teacher",
      autoAccept: true,
    },
  });
  instructorId = i.id;
});
after(async () => {
  await db.notification.deleteMany({ where: { userId: { in: userIds } } });
  await db.timeslotRequest.deleteMany({ where: { memberId: { in: userIds } } });
  await db.creditLedger.deleteMany({ where: { userId: { in: userIds } } });
  await db.booking.deleteMany({ where: { memberId: { in: userIds } } });
  await db.paymentProof.deleteMany({ where: { id: { in: proofIds } } });
  await db.session.deleteMany({ where: { id: { in: sessionIds } } });
  if (instructorId) {
    await db.unavailableSlot.deleteMany({ where: { instructorId } });
    await db.instructor.delete({ where: { id: instructorId } });
  }
  await db.promotion.deleteMany({ where: { id: { in: promoIds } } });
  await db.user.deleteMany({ where: { id: { in: userIds } } });
  await db.$disconnect();
});
test("concurrent bookings cannot oversell; cancellation restores exactly one credit", async () => {
  const s = await session(5);
  const outcomes = await Promise.allSettled([
    service.book(m1, { sessionId: s.id, paymentMethod: "CREDITS" }),
    service.book(m2, { sessionId: s.id, paymentMethod: "CREDITS" }),
  ]);
  assert.equal(outcomes.filter((x) => x.status === "fulfilled").length, 1);
  const b = await db.booking.findFirstOrThrow({ where: { sessionId: s.id } });
  const winner = b.memberId === m1.id ? m1 : m2;
  assert.equal(
    (await db.user.findUniqueOrThrow({ where: { id: winner.id } })).credits,
    1,
  );
  await assert.rejects(() =>
    service.cancelBooking(winner.id === m1.id ? m2 : m1, b.id),
  );
  await service.cancelBooking(winner, b.id);
  assert.equal(
    (await db.user.findUniqueOrThrow({ where: { id: winner.id } })).credits,
    2,
  );
  await assert.rejects(() => service.cancelBooking(winner, b.id));
  assert.equal(
    (await db.user.findUniqueOrThrow({ where: { id: winner.id } })).credits,
    2,
  );
});
test("manual instructor acceptance precedes member availability", async () => {
  await service.autoAccept(teacher, { autoAccept: false });
  const s = await session(6);
  assert.equal(s.status, "PENDING_INSTRUCTOR");
  await assert.rejects(() =>
    service.book(m1, { sessionId: s.id, paymentMethod: "CREDITS" }),
  );
  await service.accept(teacher, s.id);
  await service.autoAccept(teacher, { autoAccept: true });
  const b = await service.book(m1, {
    sessionId: s.id,
    paymentMethod: "CREDITS",
  });
  const reviews = await Promise.allSettled([
    service.review(b.id, true),
    service.review(b.id, false, "Invalid"),
  ]);
  assert.equal(reviews.filter((r) => r.status === "fulfilled").length, 1);
  await service.cancelSession(s.id, false);
  assert.equal(
    (await db.user.findUniqueOrThrow({ where: { id: m1.id } })).credits,
    2,
  );
});
test("blocked instructor times and overlapping studio sessions are rejected", async () => {
  await service.block(teacher, {
    startsAt: at(7),
    endsAt: at(7, 2),
    reason: "Away",
  });
  await assert.rejects(() => session(7));
  await session(8);
  await assert.rejects(() =>
    session(8, { type: "RENTAL", instructorId: undefined }),
  );
  await assert.rejects(() =>
    service.block(teacher, {
      startsAt: at(8),
      endsAt: at(8, 1),
      reason: "Conflict",
    }),
  );
});
test("proof ownership, reuse and authoritative discounts", async () => {
  const s = await session(9, { capacity: 2 });
  const proof = await db.paymentProof.create({
    data: { userId: m1.id, filename: tag, mime: "image/png" },
  });
  proofIds.push(proof.id);
  const promo = await service.promotion({
    code: tag,
    percent: 20,
    expiresAt: at(20),
  });
  promoIds.push(promo.id);
  await assert.rejects(() =>
    service.book(m2, {
      sessionId: s.id,
      paymentMethod: "BANK_TRANSFER",
      proofId: proof.id,
    }),
  );
  const b = await service.book(m1, {
    sessionId: s.id,
    paymentMethod: "BANK_TRANSFER",
    proofId: proof.id,
    promoCode: tag,
  });
  assert.equal(b.amount, 28000);
  assert.equal(b.discount, 7000);
  await service.cancelBooking(m1, b.id);
  await assert.rejects(() =>
    service.book(m1, {
      sessionId: s.id,
      paymentMethod: "BANK_TRANSFER",
      proofId: proof.id,
    }),
  );
});
test("attendance cannot be set before class; taught count needs an ended class", async () => {
  const s = await session(10);
  const b = await service.book(m1, {
    sessionId: s.id,
    paymentMethod: "CREDITS",
  });
  await service.review(b.id, true);
  await assert.rejects(() =>
    service.attendance(teacher, b.id, { attendance: "PRESENT" }),
  );
  await assert.rejects(() => service.completeSession(teacher, s.id));
  await db.session.update({
    where: { id: s.id },
    data: {
      startsAt: new Date(Date.now() - 7200000),
      endsAt: new Date(Date.now() - 3600000),
    },
  });
  await service.attendance(teacher, b.id, { attendance: "PRESENT" });
  await service.completeSession(teacher, s.id);
  assert.equal(
    (await service.instructors()).find((i) => i.id === instructorId)
      ?.classesTaught,
    1,
  );
  await assert.rejects(() => service.completeSession(teacher, s.id));
  await assert.rejects(() => service.cancelSession(s.id, true));
});
test("timeslot request response creates a member notification", async () => {
  const r = await service.request(m2, {
    type: "PRACTICE",
    startsAt: at(11),
    endsAt: at(11, 1),
    note: "Morning please",
  });
  await service.respond(r.id, {
    status: "REVIEWED",
    response: "We can open a session.",
  });
  assert.equal(
    await db.notification.count({
      where: { userId: m2.id, title: "Timeslot request update" },
    }),
    1,
  );
  await assert.rejects(() =>
    service.respond(r.id, { status: "DECLINED", response: "Already reviewed" }),
  );
});
