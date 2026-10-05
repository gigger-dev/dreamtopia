import "dotenv/config";
import { PrismaClient } from "@prisma/client";
import { hash } from "bcryptjs";

const db = new PrismaClient();

async function main() {
  const email = process.env.ADMIN_EMAIL?.trim().toLowerCase();
  const password = process.env.ADMIN_PASSWORD;

  if (
    !email ||
    !password ||
    password.length < 12 ||
    password.includes("replace-with")
  ) {
    throw new Error(
      "Set ADMIN_EMAIL and a unique ADMIN_PASSWORD of at least 12 characters in your .env file.",
    );
  }

  const existing = await db.user.findUnique({ where: { email } });
  if (existing && existing.role !== "ADMIN") {
    throw new Error(
      "This email belongs to a non-admin account. Refusing to elevate it.",
    );
  }

  // Seed Admin User
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

  // Common password hash for test instructors (or set custom ones)
  const instructorPasswordHash = await hash("Instructor123!456", 12);

  // --- Instructor 1: Maya Lin ---
  // 1. Create/Update User Account for Login
  const mayaUser = await db.user.upsert({
    where: { email: "maya@dreamtopia.com" },
    update: {},
    create: {
      name: "Maya Lin",
      email: "maya@dreamtopia.com",
      passwordHash: instructorPasswordHash,
      role: "INSTRUCTOR",
    },
  });

  // 2. Create/Update Instructor Profile
  const ins1 = await db.instructor.upsert({
    where: { email: "maya@dreamtopia.com" },
    update: {
      name: "Maya Lin",
      phone: "+95 9 1234 5678",
      specialty: "Vinyasa & Hatha Yoga",
      bio: "Certified yoga instructor with 8 years of experience leading mindfulness and flow sessions.",
      autoAccept: true,
      userId: mayaUser.id, // Re-link on every seed run
    },
    create: {
      name: "Maya Lin",
      email: "maya@dreamtopia.com",
      phone: "+95 9 1234 5678",
      specialty: "Vinyasa & Hatha Yoga",
      bio: "Certified yoga instructor with 8 years of experience leading mindfulness and flow sessions.",
      autoAccept: true,
      userId: mayaUser.id, // Links instructor record to user login account
    },
  });

  // --- Instructor 2: Clara Vance ---
  // 1. Create/Update User Account for Login
  const claraUser = await db.user.upsert({
    where: { email: "clara@dreamtopia.com" },
    update: {},
    create: {
      name: "Clara Vance",
      email: "clara@dreamtopia.com",
      passwordHash: instructorPasswordHash,
      role: "INSTRUCTOR",
    },
  });

  // 2. Create/Update Instructor Profile
  const ins2 = await db.instructor.upsert({
    where: { email: "clara@dreamtopia.com" },
    update: {},
    create: {
      name: "Clara Vance",
      email: "clara@dreamtopia.com",
      phone: "+95 9 8765 4321",
      specialty: "Yin Yoga & Breathwork",
      bio: "Specializes in deep restoration, joint mobility, and calming meditation flow.",
      autoAccept: false,
      userId: claraUser.id, // Links instructor record to user login account
    },
  });

  // Seed Members
  const memberPasswordHash = await hash("Member123!456", 12);
  await db.user.upsert({
    where: { email: "sophia@example.com" },
    update: {},
    create: {
      name: "Sophia Chen",
      email: "sophia@example.com",
      passwordHash: memberPasswordHash,
      role: "MEMBER",
      credits: 5,
    },
  });

  // Seed Sessions
  const now = new Date();
  const todayAt10 = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 10, 0, 0);
  const todayAt1130 = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 11, 30, 0);

  const tomorrowAt14 = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 14, 0, 0);
  const tomorrowAt1530 = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 15, 30, 0);

  await db.session.create({
    data: {
      title: "Morning Sun Salutation & Flow",
      type: "POLE_CLASS",
      startsAt: todayAt10,
      endsAt: todayAt1130,
      capacity: 10,
      price: 25000,
      level: "All levels",
      description: "Start your day with energizing postures and rhythmic breathing.",
      instructorId: ins1.id,
      status: "SCHEDULED",
    },
  });

  await db.session.create({
    data: {
      title: "Restorative Yin & Breathwork",
      type: "TRIAL",
      startsAt: tomorrowAt14,
      endsAt: tomorrowAt1530,
      capacity: 8,
      price: 20000,
      level: "Beginner",
      description: "Gentle stretch held for longer durations to ease body tension.",
      instructorId: ins2.id,
      status: "SCHEDULED",
    },
  });

  // Seed Promotion
  await db.promotion.upsert({
    where: { code: "YOGA20" },
    update: {},
    create: {
      code: "YOGA20",
      percent: 20,
      expiresAt: new Date(now.getFullYear() + 1, now.getMonth(), 1),
      active: true,
    },
  });

  console.log(
    "Seed complete: Admin, instructor users & profiles, members, sessions, and promotion created.",
  );
}

main()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(() => db.$disconnect());