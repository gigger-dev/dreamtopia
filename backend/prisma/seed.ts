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

  // --- Clean existing data to ensure a fresh, consistent seed ---
  await db.notification.deleteMany({});
  await db.creditLedger.deleteMany({});
  await db.booking.deleteMany({});
  await db.memberPackage.deleteMany({});
  await db.paymentProof.deleteMany({});
  await db.timeslotRequest.deleteMany({});
  await db.unavailableSlot.deleteMany({});
  await db.session.deleteMany({});
  await db.packageProduct.deleteMany({});
  await db.promotion.deleteMany({});
  await db.instructor.deleteMany({});
  await db.user.deleteMany({});

  // 1. Seed Admin User
  const adminUser = await db.user.create({
    data: {
      email,
      name: "Dreamtopia Studio Admin",
      role: "ADMIN",
      passwordHash: await hash(password, 12),
      credits: 0,
    },
  });

  const instructorPasswordHash = await hash("Instructor123!456", 12);
  const memberPasswordHash = await hash("Member123!456", 12);

  // 2. Seed Instructors
  // Instructor 1: Maya Lin (Auto-Accept: true)
  const mayaUser = await db.user.create({
    data: {
      name: "Maya Lin",
      email: "maya@dreamtopia.com",
      passwordHash: instructorPasswordHash,
      role: "INSTRUCTOR",
    },
  });

  const ins1 = await db.instructor.create({
    data: {
      name: "Maya Lin",
      email: "maya@dreamtopia.com",
      phone: "+95 9 1234 5678",
      specialty: "Pole Flow & Foundations",
      bio: "Certified pole movement and vinyasa instructor with 8 years of coaching experience.",
      autoAccept: true,
      userId: mayaUser.id,
    },
  });

  // Instructor 2: Clara Vance (Auto-Accept: false)
  const claraUser = await db.user.create({
    data: {
      name: "Clara Vance",
      email: "clara@dreamtopia.com",
      passwordHash: instructorPasswordHash,
      role: "INSTRUCTOR",
    },
  });

  const ins2 = await db.instructor.create({
    data: {
      name: "Clara Vance",
      email: "clara@dreamtopia.com",
      phone: "+95 9 8765 4321",
      specialty: "Restorative Yin & Inversions",
      bio: "Focuses on mindful breathing, mobility, and spine health.",
      autoAccept: false,
      userId: claraUser.id,
    },
  });

  // Instructor 3: Alex Rivera (Auto-Accept: true)
  const alexUser = await db.user.create({
    data: {
      name: "Alex Rivera",
      email: "alex@dreamtopia.com",
      passwordHash: instructorPasswordHash,
      role: "INSTRUCTOR",
    },
  });

  const ins3 = await db.instructor.create({
    data: {
      name: "Alex Rivera",
      email: "alex@dreamtopia.com",
      phone: "+95 9 5555 7777",
      specialty: "Strength & Conditioning",
      bio: "Athletic movement specialist dedicated to safe progression and body alignment.",
      autoAccept: true,
      userId: alexUser.id,
    },
  });

  // 3. Seed Instructor Unavailable Block (Clara taking Friday off)
  const now = new Date();
  const blockStart = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 4, 9, 0, 0);
  const blockEnd = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 4, 18, 0, 0);
  await db.unavailableSlot.create({
    data: {
      instructorId: ins2.id,
      startsAt: blockStart,
      endsAt: blockEnd,
      reason: "Teacher workshop and certification training",
    },
  });

  // 4. Seed Package Products
  const pkg4 = await db.packageProduct.create({
    data: {
      name: "4-Class Starter Package",
      description: "Great for regular practice. Valid for 30 days from activation.",
      credits: 4,
      price: 90000,
      validityDays: 30,
      allowedTypes: ["POLE_CLASS", "TRIAL", "PRACTICE"],
      active: true,
    },
  });

  const pkg8 = await db.packageProduct.create({
    data: {
      name: "8-Class Studio Flow Pass",
      description: "Best value pass for frequent movers. Valid for 60 days from activation.",
      credits: 8,
      price: 160000,
      validityDays: 60,
      allowedTypes: ["POLE_CLASS", "TRIAL", "PRACTICE"],
      active: true,
    },
  });

  const pkg12 = await db.packageProduct.create({
    data: {
      name: "12-Class Dedicated Athlete Pass",
      description: "Complete immersion package. Valid for 90 days from activation.",
      credits: 12,
      price: 220000,
      validityDays: 90,
      allowedTypes: ["POLE_CLASS", "TRIAL", "PRACTICE", "RENTAL"],
      active: true,
    },
  });

  // 5. Seed Members
  const sophia = await db.user.create({
    data: {
      name: "Sophia Chen",
      email: "sophia@example.com",
      passwordHash: memberPasswordHash,
      role: "MEMBER",
      credits: 3, // Currently has 3 credits
    },
  });

  const thura = await db.user.create({
    data: {
      name: "Thura Zaw",
      email: "thura@example.com",
      passwordHash: memberPasswordHash,
      role: "MEMBER",
      credits: 7, // Currently has 7 credits
    },
  });

  const elena = await db.user.create({
    data: {
      name: "Elena Rostova",
      email: "elena@example.com",
      passwordHash: memberPasswordHash,
      role: "MEMBER",
      credits: 0, // Walk-in member
    },
  });

  // 6. Seed Payment Proofs for Members
  const proof1 = await db.paymentProof.create({
    data: {
      userId: sophia.id,
      filename: "proof-sophia-starter.jpg",
      mime: "image/jpeg",
    },
  });

  const proof2 = await db.paymentProof.create({
    data: {
      userId: thura.id,
      filename: "proof-thura-flow.png",
      mime: "image/png",
    },
  });

  const proof3 = await db.paymentProof.create({
    data: {
      userId: elena.id,
      filename: "proof-elena-walkin.jpg",
      mime: "image/jpeg",
    },
  });

  const proof4Pending = await db.paymentProof.create({
    data: {
      userId: elena.id,
      filename: "proof-elena-package-pending.jpg",
      mime: "image/jpeg",
    },
  });

  // 7. Seed Member Packages
  // Sophia's Active 4-Class Package (1 used, 3 left, expires in 25 days)
  const sophiaPkg = await db.memberPackage.create({
    data: {
      userId: sophia.id,
      packageProductId: pkg4.id,
      creditsTotal: 4,
      creditsRemaining: 3,
      pricePaid: 90000,
      status: "ACTIVE",
      proofId: proof1.id,
      activatedAt: new Date(now.getTime() - 5 * 86400000),
      expiresAt: new Date(now.getTime() + 25 * 86400000),
    },
  });

  // Thura's Active 8-Class Package (1 used, 7 left, expires in 50 days)
  const thuraPkg = await db.memberPackage.create({
    data: {
      userId: thura.id,
      packageProductId: pkg8.id,
      creditsTotal: 8,
      creditsRemaining: 7,
      pricePaid: 160000,
      status: "ACTIVE",
      proofId: proof2.id,
      activatedAt: new Date(now.getTime() - 10 * 86400000),
      expiresAt: new Date(now.getTime() + 50 * 86400000),
    },
  });

  // Elena's Pending Package Purchase (submitted, awaiting admin review)
  await db.memberPackage.create({
    data: {
      userId: elena.id,
      packageProductId: pkg4.id,
      creditsTotal: 4,
      creditsRemaining: 4,
      pricePaid: 90000,
      status: "PENDING_REVIEW",
      proofId: proof4Pending.id,
    },
  });

  // 8. Seed Credit Ledger Entries
  await db.creditLedger.create({
    data: {
      userId: sophia.id,
      packageId: sophiaPkg.id,
      delta: 4,
      reason: "Purchased 4-Class Starter Package",
      createdAt: new Date(now.getTime() - 5 * 86400000),
    },
  });

  await db.creditLedger.create({
    data: {
      userId: sophia.id,
      packageId: sophiaPkg.id,
      delta: -1,
      reason: "Reserved for Pole Flow Foundations",
      createdAt: new Date(now.getTime() - 2 * 86400000),
    },
  });

  await db.creditLedger.create({
    data: {
      userId: thura.id,
      packageId: thuraPkg.id,
      delta: 8,
      reason: "Purchased 8-Class Studio Flow Pass",
      createdAt: new Date(now.getTime() - 10 * 86400000),
    },
  });

  await db.creditLedger.create({
    data: {
      userId: thura.id,
      packageId: thuraPkg.id,
      delta: -1,
      reason: "Reserved for Restorative Yin",
      createdAt: new Date(now.getTime() - 1 * 86400000),
    },
  });

  // 9. Seed Schedule Sessions (Across Today, Tomorrow, and Later This Week)
  const today10 = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 10, 0, 0);
  const today1130 = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 11, 30, 0);

  const today17 = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 17, 0, 0);
  const today1830 = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 18, 30, 0);

  const tomorrow10 = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 10, 0, 0);
  const tomorrow1130 = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 11, 30, 0);

  const tomorrow15 = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 15, 0, 0);
  const tomorrow1630 = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 16, 30, 0);

  const day3At11 = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 2, 11, 0, 0);
  const day3At1230 = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 2, 12, 30, 0);

  const pastSessionStart = new Date(now.getTime() - 3 * 86400000);
  const pastSessionEnd = new Date(now.getTime() - 3 * 86400000 + 90 * 60000);

  // Completed Past Session
  const pastSession = await db.session.create({
    data: {
      title: "Weekend Foundation Workshop",
      type: "POLE_CLASS",
      bookingMode: "BOTH",
      creditCost: 1,
      startsAt: pastSessionStart,
      endsAt: pastSessionEnd,
      capacity: 8,
      price: 25000,
      level: "All levels",
      description: "Technique breakdown and mindful conditioning.",
      instructorId: ins1.id,
      status: "COMPLETED",
    },
  });

  // Today Morning Class (Scheduled & Confirmed)
  const sessionToday = await db.session.create({
    data: {
      title: "Pole Flow Foundations",
      type: "POLE_CLASS",
      bookingMode: "BOTH",
      creditCost: 1,
      startsAt: today10,
      endsAt: today1130,
      capacity: 6,
      price: 30000,
      level: "Beginner",
      description: "Learn foundational spins, core stability, and graceful transitions.",
      instructorId: ins1.id,
      status: "SCHEDULED",
    },
  });

  // Today Evening Yin Yoga (Package Only Mode)
  const sessionEvening = await db.session.create({
    data: {
      title: "Evening Candlelight Yin & Mobility",
      type: "TRIAL",
      bookingMode: "PACKAGE_ONLY",
      creditCost: 1,
      startsAt: today17,
      endsAt: today1830,
      capacity: 8,
      price: 25000,
      level: "All levels",
      description: "Slow-paced style of modern yoga with postures held for longer periods.",
      instructorId: ins2.id,
      status: "SCHEDULED",
    },
  });

  // Tomorrow Morning Conditioning (Pending Instructor Acceptance)
  const sessionTomorrowPending = await db.session.create({
    data: {
      title: "Morning Core & Inversion Prep",
      type: "PRACTICE",
      bookingMode: "BOTH",
      creditCost: 1,
      startsAt: tomorrow10,
      endsAt: tomorrow1130,
      capacity: 8,
      price: 28000,
      level: "Intermediate",
      description: "Shoulder engagement and core strength drills for clean climbs and inversions.",
      instructorId: ins2.id,
      status: "PENDING_INSTRUCTOR", // Waiting for Clara to accept/decline
    },
  });

  // Tomorrow Afternoon Walk-In Only Trial
  const sessionWalkIn = await db.session.create({
    data: {
      title: "Introductory Discovery Class",
      type: "TRIAL",
      bookingMode: "WALK_IN_ONLY",
      creditCost: 1,
      startsAt: tomorrow15,
      endsAt: tomorrow1630,
      capacity: 10,
      price: 20000,
      level: "First-timers",
      description: "A welcoming, zero-pressure first taste of pole movement.",
      instructorId: ins3.id,
      status: "SCHEDULED",
    },
  });

  // Day 3 Open Studio Rental
  await db.session.create({
    data: {
      title: "Private Studio Rental Session",
      type: "RENTAL",
      bookingMode: "WALK_IN_ONLY",
      creditCost: 2,
      startsAt: day3At11,
      endsAt: day3At1230,
      capacity: 1,
      price: 75000,
      level: "Private",
      description: "Exclusive full studio rental for filming and personal training.",
      instructorId: null,
      status: "SCHEDULED",
    },
  });

  // 10. Seed Realistic Bookings
  // Booking 1: Sophia booked today's class using package credit (CONFIRMED)
  await db.booking.create({
    data: {
      memberId: sophia.id,
      sessionId: sessionToday.id,
      status: "CONFIRMED",
      paymentMethod: "CREDITS",
      packageId: sophiaPkg.id,
      creditsUsed: 1,
      creditReserved: true,
      amount: 0,
      attendance: "UNMARKED",
    },
  });

  // Booking 2: Past attended class for Sophia
  await db.booking.create({
    data: {
      memberId: sophia.id,
      sessionId: pastSession.id,
      status: "CONFIRMED",
      paymentMethod: "CREDITS",
      packageId: sophiaPkg.id,
      creditsUsed: 1,
      creditReserved: true,
      amount: 0,
      attendance: "PRESENT",
    },
  });

  // Booking 3: Thura booked Evening Yin with package credit (CONFIRMED)
  await db.booking.create({
    data: {
      memberId: thura.id,
      sessionId: sessionEvening.id,
      status: "CONFIRMED",
      paymentMethod: "CREDITS",
      packageId: thuraPkg.id,
      creditsUsed: 1,
      creditReserved: true,
      amount: 0,
      attendance: "UNMARKED",
    },
  });

  // Booking 4: Elena submitted walk-in payment proof for tomorrow's trial (PENDING Review)
  await db.booking.create({
    data: {
      memberId: elena.id,
      sessionId: sessionWalkIn.id,
      status: "PENDING",
      paymentMethod: "BANK_TRANSFER",
      proofId: proof3.id,
      amount: 20000,
      creditReserved: false,
      attendance: "UNMARKED",
    },
  });

  // Booking 5: Full session resolution case (PAID_AWAITING_RESOLUTION)
  // Demonstrating Phase 3 resolution engine
  await db.booking.create({
    data: {
      memberId: thura.id,
      sessionId: sessionWalkIn.id,
      status: "PAID_AWAITING_RESOLUTION",
      paymentMethod: "BANK_TRANSFER",
      amount: 20000,
      overrideReason: "Session reached full capacity before manual bank verification completed.",
      creditReserved: false,
    },
  });

  // 11. Seed Timeslot Request (Member asking for Saturday session)
  const reqStart = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 5, 16, 0, 0);
  const reqEnd = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 5, 17, 30, 0);
  await db.timeslotRequest.create({
    data: {
      memberId: sophia.id,
      type: "POLE_CLASS",
      startsAt: reqStart,
      endsAt: reqEnd,
      note: "Looking for a late Saturday afternoon intermediate spinning pole session!",
      status: "PENDING",
    },
  });

  // 12. Seed Studio Promotion
  await db.promotion.create({
    data: {
      code: "WELCOME20",
      percent: 20,
      expiresAt: new Date(now.getFullYear() + 1, now.getMonth(), 1),
      active: true,
    },
  });

  // 13. Seed In-App Notifications
  await db.notification.create({
    data: {
      userId: sophia.id,
      title: "Booking confirmed",
      body: "Pole Flow Foundations — see you in the studio!",
      dedupeKey: "seed-notice-sophia-1",
    },
  });

  await db.notification.create({
    data: {
      userId: claraUser.id,
      title: "New class assignment",
      body: "Morning Core & Inversion Prep requires your confirmation.",
      dedupeKey: "seed-notice-clara-1",
    },
  });

  await db.notification.create({
    data: {
      userId: adminUser.id,
      title: "Walk-in Payment Pending",
      body: "Elena Rostova submitted a bank transfer slip for Introductory Discovery Class.",
      dedupeKey: "seed-notice-admin-1",
    },
  });

  console.log(
    "✅ Realistic studio seed complete!\n" +
      "  - 1 Studio Admin (admin@dreamtopia.com / SuperSecretPassword123!)\n" +
      "  - 3 Instructors (Maya Lin [auto-accept], Clara Vance [manual accept], Alex Rivera)\n" +
      "  - 3 Members (Sophia Chen [package holder], Thura Zaw [package holder], Elena Rostova [walk-in])\n" +
      "  - 3 Package Products (4-class, 8-class, 12-class passes)\n" +
      "  - 3 Member Packages (Active, Pending Review)\n" +
      "  - 5 Sessions (Completed, Scheduled, Pending Instructor, Package-only, Walk-in only, Rental)\n" +
      "  - 5 Bookings (Confirmed, Pending review, Attended, Paid awaiting resolution)\n" +
      "  - 1 Instructor Unavailable Time Block\n" +
      "  - 1 Timeslot Request\n" +
      "  - 1 Active Promotion (WELCOME20)\n" +
      "  - Real ledger entries and notifications",
  );
}

main()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(() => db.$disconnect());