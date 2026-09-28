import "dotenv/config";
import { PrismaClient } from "@prisma/client";
import { hash } from "bcryptjs";
const db = new PrismaClient();
async function main() {
  const email = process.env.ADMIN_EMAIL?.trim().toLowerCase(),
    password = process.env.ADMIN_PASSWORD;
  if (
    !email ||
    !password ||
    password.length < 12 ||
    password.includes("replace-with")
  )
    throw new Error(
      "Set ADMIN_EMAIL and a unique ADMIN_PASSWORD of at least 12 characters.",
    );
  const existing = await db.user.findUnique({ where: { email } });
  if (existing && existing.role !== "ADMIN")
    throw new Error(
      "This email belongs to a non-admin account. Refusing to elevate it.",
    );
  await db.user.upsert({
    where: { email },
    update: {},
    create: {
      email,
      name: "Dreamtopia Studio",
      role: "ADMIN",
      passwordHash: await hash(password, 12),
    },
  });
  console.log(
    "Admin account ready. No sample bookings or payment records were created.",
  );
}
main()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(() => db.$disconnect());
