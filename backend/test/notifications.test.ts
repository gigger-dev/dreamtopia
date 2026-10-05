import "reflect-metadata";
import { test } from "node:test";
import assert from "node:assert/strict";
import { NotificationsController } from "../src/notifications/notifications.controller";
import { NotificationsService } from "../src/notifications/notifications.service";
import type { Actor } from "../src/auth/auth";

test("NotificationsController routes and delegates correctly", async () => {
  const member: Actor = { id: "m-1", email: "m@test.com", name: "Member", role: "MEMBER" };
  const admin: Actor = { id: "a-1", email: "a@test.com", name: "Admin", role: "ADMIN" };
  let called = "";

  const mockService = {
    campaign: async (dto: any) => {
      called = `campaign:${dto.title}:${dto.targetRole}`;
      return { id: "camp-1", sentCount: 15 };
    },
    notifications: async (user: Actor) => {
      called = `notifications:${user.id}`;
      return [{ id: "notif-1", title: "New Class Added", readAt: null }];
    },
    read: async (user: Actor, id: string) => {
      called = `read:${user.id}:${id}`;
      return { count: 1 };
    },
    requests: async (user: Actor) => {
      called = `requests:${user.role}:${user.id}`;
      return [{ id: "req-1", status: "PENDING" }];
    },
    request: async (user: Actor, dto: any) => {
      called = `request:${user.id}:${dto.type}`;
      return { id: "req-new", status: "PENDING" };
    },
    respond: async (id: string, dto: any) => {
      called = `respond:${id}:${dto.status}:${dto.response}`;
      return { id, status: dto.status };
    },
  } as unknown as NotificationsService;

  const controller = new NotificationsController(mockService);

  // 1. Broadcast campaign
  const camp = await controller.campaign({
    title: "Weekend Promotion",
    body: "Get 20% off all packages this weekend!",
    targetRole: "MEMBER",
  });
  assert.equal(called, "campaign:Weekend Promotion:MEMBER");
  assert.equal(camp.sentCount, 15);

  // 2. Notifications query & mark read
  const notifs = await controller.notifications({ user: member } as any);
  assert.equal(called, "notifications:m-1");
  assert.equal(notifs.length, 1);

  await controller.read({ user: member } as any, "notif-1");
  assert.equal(called, "read:m-1:notif-1");

  // 3. Requests query
  const reqs = await controller.requests({ user: member } as any);
  assert.equal(called, "requests:MEMBER:m-1");
  assert.equal(reqs.length, 1);

  // 4. Create request
  await controller.request({ user: member } as any, {
    type: "WORKSHOP",
    startsAt: "2026-10-15T10:00:00Z",
    endsAt: "2026-10-15T12:00:00Z",
    note: "Please host a heels workshop",
  });
  assert.equal(called, "request:m-1:WORKSHOP");

  // 5. Admin response to request
  await controller.respond("req-1", {
    status: "REVIEWED",
    response: "Scheduled for next Saturday!",
  });
  assert.equal(called, "respond:req-1:REVIEWED:Scheduled for next Saturday!");
});
