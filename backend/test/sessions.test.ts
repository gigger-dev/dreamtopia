import "reflect-metadata";
import { test } from "node:test";
import assert from "node:assert/strict";
import { SessionsController } from "../src/sessions/sessions.controller";
import { SessionsService } from "../src/sessions/sessions.service";
import type { PrismaService } from "../src/prisma.service";
import type { Actor } from "../src/auth/auth";

test("SessionsController delegates to SessionsService properly", async () => {
  const member: Actor = { id: "m-1", email: "m@test.com", name: "Member", role: "MEMBER" };
  const admin: Actor = { id: "a-1", email: "a@test.com", name: "Admin", role: "ADMIN" };
  const instructor: Actor = { id: "i-1", email: "i@test.com", name: "Teacher", role: "INSTRUCTOR" };

  let calledMethod = "";
  const mockService = {
    sessions: async (actor: Actor, from?: string, to?: string) => {
      calledMethod = `sessions:${actor.role}:${from}:${to}`;
      return [{ id: "sess-1", title: "Pole Beginner" }];
    },
    createSession: async (dto: any) => {
      calledMethod = `createSession:${dto.title}`;
      return { id: "sess-created", ...dto };
    },
    updateSession: async (id: string, dto: any) => {
      calledMethod = `updateSession:${id}:${dto.title}`;
      return { id, ...dto };
    },
    cancelSession: async (id: string, hardDelete: boolean) => {
      calledMethod = `cancelSession:${id}:${hardDelete}`;
      return { id, cancelled: true };
    },
    accept: async (actor: Actor, id: string) => {
      calledMethod = `accept:${actor.id}:${id}`;
      return { id, status: "UPCOMING" };
    },
    decline: async (actor: Actor, id: string, reason?: string) => {
      calledMethod = `decline:${actor.id}:${id}:${reason}`;
      return { id, status: "CANCELLED" };
    },
    completeSession: async (actor: Actor, id: string) => {
      calledMethod = `completeSession:${actor.id}:${id}`;
      return { id, status: "COMPLETED" };
    },
  } as unknown as SessionsService;

  const controller = new SessionsController(mockService);

  // 1. Get sessions
  const list = await controller.sessions({ user: member } as any, "2026-10-01", "2026-10-07");
  assert.equal(calledMethod, "sessions:MEMBER:2026-10-01:2026-10-07");
  assert.equal(list.length, 1);

  // 2. Create session
  const created = await controller.createSession({
    title: "Level 1 Spin",
    type: "POLE_CLASS",
    startsAt: "2026-10-10T10:00:00Z",
    endsAt: "2026-10-10T11:00:00Z",
    capacity: 6,
    price: 35000,
    level: "Beginner",
  });
  assert.equal(calledMethod, "createSession:Level 1 Spin");
  assert.equal(created.id, "sess-created");

  // 3. Update session
  await controller.updateSession("sess-1", { title: "Updated Spin" });
  assert.equal(calledMethod, "updateSession:sess-1:Updated Spin");

  // 4. Cancel & Delete
  await controller.cancelSession("sess-1");
  assert.equal(calledMethod, "cancelSession:sess-1:false");
  await controller.deleteSession("sess-1");
  assert.equal(calledMethod, "cancelSession:sess-1:true");

  // 5. Accept, Decline, Complete
  await controller.accept({ user: instructor } as any, "sess-1");
  assert.equal(calledMethod, "accept:i-1:sess-1");

  await controller.decline({ user: instructor } as any, "sess-1", { reason: "Sick" });
  assert.equal(calledMethod, "decline:i-1:sess-1:Sick");

  await controller.complete({ user: admin } as any, "sess-1");
  assert.equal(calledMethod, "completeSession:a-1:sess-1");
});
