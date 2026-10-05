import "reflect-metadata";
import { test } from "node:test";
import assert from "node:assert/strict";
import { BookingsController } from "../src/bookings/bookings.controller";
import { BookingsService } from "../src/bookings/bookings.service";
import type { Actor } from "../src/auth/auth";

test("BookingsController routes and delegates correctly", async () => {
  const member: Actor = { id: "m-1", email: "m@test.com", name: "Member", role: "MEMBER" };
  const admin: Actor = { id: "a-1", email: "a@test.com", name: "Admin", role: "ADMIN" };
  const instructor: Actor = { id: "i-1", email: "i@test.com", name: "Teacher", role: "INSTRUCTOR" };
  let called = "";

  const mockService = {
    quote: async (sessionId: string, code?: string) => {
      called = `quote:${sessionId}:${code}`;
      return { price: 35000, discount: 5000, finalPrice: 30000 };
    },
    bookings: async (user: Actor) => {
      called = `bookings:${user.role}:${user.id}`;
      return [{ id: "b-1", status: "CONFIRMED" }];
    },
    book: async (user: Actor, dto: any) => {
      called = `book:${user.id}:${dto.sessionId}:${dto.paymentMethod}`;
      return { id: "b-new", status: "PENDING" };
    },
    cancelBooking: async (user: Actor, id: string) => {
      called = `cancelBooking:${user.id}:${id}`;
      return { id, status: "CANCELLED" };
    },
    adminBook: async (dto: any) => {
      called = `adminBook:${dto.memberId}:${dto.sessionId}`;
      return { id: "b-admin-created" };
    },
    adminCancelBooking: async (id: string, reason?: string) => {
      called = `adminCancelBooking:${id}:${reason}`;
      return { id, cancelled: true };
    },
    resolveBooking: async (id: string, dto: any) => {
      called = `resolveBooking:${id}:${dto.action}`;
      return { id, resolved: true };
    },
    review: async (id: string, approve: boolean, reason?: string) => {
      called = `review:${id}:${approve}:${reason}`;
      return { id, approved: approve };
    },
    attendance: async (user: Actor, id: string, dto: any) => {
      called = `attendance:${user.id}:${id}:${dto.attendance}`;
      return { id, attendance: dto.attendance };
    },
  } as unknown as BookingsService;

  const controller = new BookingsController(mockService);

  // 1. Quote
  const q = await controller.quote("sess-1", "PROMO10");
  assert.equal(called, "quote:sess-1:PROMO10");
  assert.equal(q.finalPrice, 30000);

  // 2. Bookings list
  const list = await controller.bookings({ user: member } as any);
  assert.equal(called, "bookings:MEMBER:m-1");
  assert.equal(list.length, 1);

  // 3. Member Book
  await controller.book({ user: member } as any, {
    sessionId: "sess-1",
    paymentMethod: "CREDITS",
  });
  assert.equal(called, "book:m-1:sess-1:CREDITS");

  // 4. Member Cancel
  await controller.cancelBooking({ user: member } as any, "b-1");
  assert.equal(called, "cancelBooking:m-1:b-1");

  // 5. Admin booking endpoints
  await controller.adminBook({
    memberId: "m-1",
    sessionId: "sess-1",
    paymentMethod: "CASH",
  } as any);
  assert.equal(called, "adminBook:m-1:sess-1");

  await controller.cancelBookingOverride("b-1", { reason: "Studio maintenance" });
  assert.equal(called, "adminCancelBooking:b-1:Studio maintenance");

  await controller.resolveBooking("b-1", { action: "APPROVE_TRANSFER" } as any);
  assert.equal(called, "resolveBooking:b-1:APPROVE_TRANSFER");

  // 6. Review approve & reject
  await controller.approve("b-1");
  assert.equal(called, "review:b-1:true:undefined");

  await controller.reject("b-1", { reason: "Bad slip" });
  assert.equal(called, "review:b-1:false:Bad slip");

  // 7. Attendance
  await controller.attendance({ user: instructor } as any, "b-1", { attendance: "PRESENT" });
  assert.equal(called, "attendance:i-1:b-1:PRESENT");
});
