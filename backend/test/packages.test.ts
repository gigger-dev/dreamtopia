import "reflect-metadata";
import { test } from "node:test";
import assert from "node:assert/strict";
import { PackagesController } from "../src/packages/packages.controller";
import { PackagesService } from "../src/packages/packages.service";
import type { Actor } from "../src/auth/auth";

test("PackagesController routes and delegates correctly", async () => {
  const member: Actor = { id: "m-1", email: "m@test.com", name: "Member", role: "MEMBER" };
  let called = "";

  const mockService = {
    packageProducts: async () => {
      called = "packageProducts";
      return [{ id: "prod-1", name: "10-Class Pack", credits: 10, price: 300000 }];
    },
    allPackageProducts: async () => {
      called = "allPackageProducts";
      return [{ id: "prod-1", active: true }, { id: "prod-2", active: false }];
    },
    createPackageProduct: async (dto: any) => {
      called = `createPackageProduct:${dto.name}:${dto.credits}:${dto.price}`;
      return { id: "prod-new", ...dto };
    },
    purchasePackage: async (user: Actor, dto: any) => {
      called = `purchasePackage:${user.id}:${dto.packageProductId}:${dto.paymentMethod}`;
      return { id: "pkg-purchase", status: "PENDING" };
    },
    memberPackages: async (user: Actor) => {
      called = `memberPackages:${user.id}`;
      return [{ id: "pkg-1", remainingCredits: 5 }];
    },
    reviewPackagePurchase: async (id: string, approved: boolean, reason?: string) => {
      called = `reviewPackagePurchase:${id}:${approved}:${reason}`;
      return { id, status: approved ? "ACTIVE" : "REJECTED" };
    },
  } as unknown as PackagesService;

  const controller = new PackagesController(mockService);

  // 1. package products
  const products = await controller.packageProducts();
  assert.equal(called, "packageProducts");
  assert.equal(products.length, 1);

  // 2. all package products (admin)
  const allProducts = await controller.allPackageProducts();
  assert.equal(called, "allPackageProducts");
  assert.equal(allProducts.length, 2);

  // 3. create package product
  await controller.createPackageProduct({
    name: "5-Class Pack",
    credits: 5,
    price: 160000,
    validityDays: 60,
  });
  assert.equal(called, "createPackageProduct:5-Class Pack:5:160000");

  // 4. purchase package
  const purchase = await controller.purchasePackage({ user: member } as any, {
    packageProductId: "prod-1",
    paymentMethod: "BANK_TRANSFER",
    proofId: "proof-123",
  });
  assert.equal(called, "purchasePackage:m-1:prod-1:BANK_TRANSFER");
  assert.equal(purchase.status, "PENDING");

  // 5. member packages
  const myPacks = await controller.memberPackages({ user: member } as any);
  assert.equal(called, "memberPackages:m-1");
  assert.equal(myPacks.length, 1);

  // 6. approve & reject package
  await controller.approvePackage("pkg-1");
  assert.equal(called, "reviewPackagePurchase:pkg-1:true:undefined");

  await controller.rejectPackage("pkg-2", { reason: "Payment slip mismatch" });
  assert.equal(called, "reviewPackagePurchase:pkg-2:false:Payment slip mismatch");
});
