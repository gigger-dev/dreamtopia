import "reflect-metadata";
import { test } from "node:test";
import assert from "node:assert/strict";
import { InstructorsController } from "../src/instructors/instructors.controller";
import { InstructorsService } from "../src/instructors/instructors.service";
import type { Actor } from "../src/auth/auth";

test("InstructorsController routes and delegates correctly", async () => {
  const instructor: Actor = { id: "u-inst", email: "inst@test.com", name: "May", role: "INSTRUCTOR" };
  let called = "";

  const mockService = {
    instructors: async () => {
      called = "instructors";
      return [{ id: "inst-1", name: "May", classesTaught: 5 }];
    },
    addInstructor: async (dto: any) => {
      called = `addInstructor:${dto.name}:${dto.email}`;
      return { id: "inst-new", ...dto };
    },
    linkInstructor: async (id: string) => {
      called = `linkInstructor:${id}`;
      return { id, linked: true };
    },
    autoAccept: async (user: Actor, dto: any) => {
      called = `autoAccept:${user.id}:${dto.autoAccept}`;
      return { id: "inst-1", autoAccept: dto.autoAccept };
    },
    blocks: async (user: Actor) => {
      called = `blocks:${user.id}`;
      return [{ id: "block-1", startsAt: "2026-10-10T00:00:00Z" }];
    },
    block: async (user: Actor, dto: any) => {
      called = `block:${user.id}:${dto.reason}`;
      return { id: "block-new", ...dto };
    },
    unblock: async (user: Actor, id: string) => {
      called = `unblock:${user.id}:${id}`;
      return { id, deleted: true };
    },
  } as unknown as InstructorsService;

  const controller = new InstructorsController(mockService);

  // 1. List instructors
  const list = await controller.instructors();
  assert.equal(called, "instructors");
  assert.equal(list.length, 1);

  // 2. Add instructor
  await controller.addInstructor({
    name: "Elena",
    email: "elena@test.com",
    bio: "Exotic specialist",
  });
  assert.equal(called, "addInstructor:Elena:elena@test.com");

  // 3. Link instructor
  await controller.linkInstructor("inst-1");
  assert.equal(called, "linkInstructor:inst-1");

  // 4. Auto accept
  await controller.autoAccept({ user: instructor } as any, { autoAccept: true });
  assert.equal(called, "autoAccept:u-inst:true");

  // 5. Blocks: get, add, delete
  const blocks = await controller.blocks({ user: instructor } as any);
  assert.equal(called, "blocks:u-inst");
  assert.equal(blocks.length, 1);

  await controller.block({ user: instructor } as any, {
    startsAt: "2026-10-12T09:00:00Z",
    endsAt: "2026-10-12T13:00:00Z",
    reason: "Personal appointment",
  });
  assert.equal(called, "block:u-inst:Personal appointment");

  await controller.unblock({ user: instructor } as any, "block-1");
  assert.equal(called, "unblock:u-inst:block-1");
});
