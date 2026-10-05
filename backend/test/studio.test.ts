import "reflect-metadata";
import { test } from "node:test";
import assert from "node:assert/strict";
import { StudioController } from "../src/studio/studio.controller";
import { StudioService } from "../src/studio/studio.service";
import type { PrismaService } from "../src/prisma.service";
import type { Actor } from "../src/auth/auth";

test("StudioController routes and delegates correctly", async () => {
  const member: Actor = { id: "m-1", email: "m@test.com", name: "Member", role: "MEMBER" };
  const admin: Actor = { id: "a-1", email: "a@test.com", name: "Admin", role: "ADMIN" };
  let calledService = "";

  const mockService = {
    me: async (user: Actor) => {
      calledService = `me:${user.id}`;
      return { id: user.id, email: user.email, name: user.name, role: user.role };
    },
    grant: async (id: string, dto: any) => {
      calledService = `grant:${id}:${dto.credits}:${dto.reason}`;
      return { id, credits: 10 };
    },
    promotion: async (dto: any) => {
      calledService = `promotion:${dto.code}:${dto.percent}`;
      return { id: "promo-1", ...dto };
    },
  } as unknown as StudioService;

  const mockDb = {
    user: {
      findMany: async () => [{ id: "m-1", name: "Member", credits: 5 }],
    },
    creditLedger: {
      findMany: async (args: any) => [{ id: "ledger-1", userId: args.where.userId, delta: 2 }],
    },
    promotion: {
      findMany: async () => [{ id: "promo-1", code: "WELCOME10" }],
      update: async (args: any) => ({ id: args.where.id, active: args.data.active }),
    },
    paymentProof: {
      findUnique: async () => ({ id: "proof-1", userId: "m-1", mime: "image/png", filename: "abc" }),
    },
  } as unknown as PrismaService;

  const controller = new StudioController(mockService, mockDb);

  // 1. /me
  const profile = await controller.me({ user: member } as any);
  assert.equal(calledService, "me:m-1");
  assert.equal(profile.name, "Member");

  // 2. /settings
  const settings = controller.settings();
  assert.equal(typeof settings.timezone, "string");
  assert.equal(settings.cancellationHours, 24);

  // 3. /members & /members/:id/credits
  const members = await controller.members();
  assert.equal(members.length, 1);

  await controller.credits("m-1", { credits: 3, reason: "Loyalty bonus" });
  assert.equal(calledService, "grant:m-1:3:Loyalty bonus");

  // 4. /credits (ledger)
  const ledger = await controller.ledger({ user: member } as any);
  assert.equal(ledger.length, 1);
  assert.equal(ledger[0].delta, 2);

  // 5. /promotions
  const promos = await controller.promotions();
  assert.equal(promos.length, 1);

  await controller.promotion({ code: "SUMMER", percent: 15, expiresAt: "2026-10-31T00:00:00Z" });
  assert.equal(calledService, "promotion:SUMMER:15");

  const toggled = await controller.active("promo-1", { active: false });
  assert.equal(toggled.active, false);
});
