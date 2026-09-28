import "reflect-metadata";
import { test } from "node:test";
import assert from "node:assert/strict";
import { Reflector } from "@nestjs/core";
import { JwtService } from "@nestjs/jwt";
import { ForbiddenException, UnauthorizedException } from "@nestjs/common";
import type { ExecutionContext } from "@nestjs/common";
import { AuthGuard } from "../src/auth/auth";
import type { PrismaService } from "../src/prisma.service";
const key = "test-only-key-with-more-than-thirty-two-characters";
const jwt = new JwtService({ secret: key });
function context(header?: string) {
  const request = { headers: { authorization: header } };
  return {
    switchToHttp: () => ({ getRequest: () => request }),
    getHandler: () => function () {},
    getClass: () => class {},
  } as unknown as ExecutionContext;
}
function guard(role: string, required: string[] = ["ADMIN"]) {
  const reflector = {
    getAllAndOverride: (key: string) => (key === "roles" ? required : false),
  } as Reflector;
  const db = {
    user: {
      findUnique: async () => ({
        id: "member",
        email: "test@example.test",
        name: "Test",
        role,
      }),
    },
  } as unknown as PrismaService;
  return new AuthGuard(reflector, jwt, db);
}
test("unauthenticated and invalid-token requests are rejected", async () => {
  await assert.rejects(
    () => guard("ADMIN").canActivate(context()),
    UnauthorizedException,
  );
  await assert.rejects(
    () => guard("ADMIN").canActivate(context("Bearer broken")),
    UnauthorizedException,
  );
});
test("role authorization uses current database role, not token role", async () => {
  const token = await jwt.signAsync({ sub: "member", role: "ADMIN" });
  await assert.rejects(
    () => guard("MEMBER").canActivate(context("Bearer " + token)),
    ForbiddenException,
  );
  assert.equal(
    await guard("ADMIN").canActivate(context("Bearer " + token)),
    true,
  );
});
