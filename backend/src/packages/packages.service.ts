import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../prisma.service";
import { Actor } from "../auth/auth";
import * as D from "../studio/dto";

type Tx = Prisma.TransactionClient;

@Injectable()
export class PackagesService {
  constructor(private db: PrismaService) {}

  private notify(tx: Tx, userId: string, title: string, body: string) {
    return tx.notification.create({ data: { userId, title, body } });
  }

  async packageProducts() {
    return this.db.packageProduct.findMany({
      where: { active: true },
      orderBy: { price: "asc" },
    });
  }

  async allPackageProducts() {
    return this.db.packageProduct.findMany({
      orderBy: { createdAt: "desc" },
    });
  }

  async createPackageProduct(d: D.PackageProductDto) {
    return this.db.packageProduct.create({
      data: {
        name: d.name,
        description: d.description ?? "",
        credits: d.credits,
        price: d.price,
        validityDays: d.validityDays,
        allowedTypes: d.allowedTypes ?? ["POLE_CLASS"],
        active: d.active ?? true,
      },
    });
  }

  async purchasePackage(a: Actor, d: D.PurchasePackageDto) {
    return this.db.serial(async (tx) => {
      const product = await tx.packageProduct.findUnique({
        where: { id: d.packageProductId },
      });
      if (!product || !product.active)
        throw new BadRequestException("This package product is not available.");

      const proof = await tx.paymentProof.findUnique({
        where: { id: d.proofId },
        include: { booking: true, memberPackage: true },
      });
      if (!proof || proof.userId !== a.id || proof.booking || proof.memberPackage)
        throw new BadRequestException(
          "Upload an unused payment screenshot owned by your account.",
        );

      const mp = await tx.memberPackage.create({
        data: {
          userId: a.id,
          packageProductId: product.id,
          creditsTotal: product.credits,
          creditsRemaining: product.credits,
          pricePaid: product.price,
          status: "PENDING_REVIEW",
          proofId: d.proofId,
        },
      });

      await this.notify(
        tx,
        a.id,
        "Package order received",
        `Your payment for ${product.name} is waiting for studio verification.`,
      );

      const admins = await tx.user.findMany({ where: { role: "ADMIN" } });
      for (const admin of admins) {
        await this.notify(
          tx,
          admin.id,
          "Package order to review",
          `${a.name} submitted payment for ${product.name}.`,
        );
      }

      return mp;
    });
  }

  async memberPackages(a: Actor) {
    return this.db.memberPackage.findMany({
      where: a.role === "ADMIN" ? {} : { userId: a.id },
      include: {
        packageProduct: true,
        user: { select: { id: true, name: true, email: true } },
      },
      orderBy: { createdAt: "desc" },
    });
  }

  async reviewPackagePurchase(id: string, approve: boolean, reason?: string) {
    return this.db.serial(async (tx) => {
      const mp = await tx.memberPackage.findUnique({
        where: { id },
        include: { packageProduct: true },
      });
      if (!mp) throw new NotFoundException();
      if (mp.status !== "PENDING_REVIEW")
        throw new ConflictException("This package purchase has already been reviewed.");

      const now = new Date();
      let expiresAt: Date | null = null;
      if (approve) {
        expiresAt = new Date(now.getTime() + mp.packageProduct.validityDays * 86400000);
      }

      const updated = await tx.memberPackage.update({
        where: { id },
        data: {
          status: approve ? "ACTIVE" : "REJECTED",
          rejectionReason: approve ? null : reason,
          activatedAt: approve ? now : null,
          expiresAt,
        },
      });

      if (approve) {
        await tx.user.update({
          where: { id: mp.userId },
          data: { credits: { increment: mp.creditsTotal } },
        });

        await tx.creditLedger.create({
          data: {
            userId: mp.userId,
            packageId: mp.id,
            delta: mp.creditsTotal,
            reason: `Package activated: ${mp.packageProduct.name}`,
          },
        });

        await this.notify(
          tx,
          mp.userId,
          "Package activated!",
          `${mp.packageProduct.name} is now active with ${mp.creditsTotal} class credits.`,
        );
      } else {
        await this.notify(
          tx,
          mp.userId,
          "Package purchase rejected",
          `Your package order could not be approved. Reason: ${reason ?? "Please check your receipt."}`,
        );
      }

      return updated;
    });
  }
}
