# Dreamtopia Studio

A Flutter client and NestJS REST API for a pole and movement studio, with a seven-chakra palette.

- `frontend/`: responsive Flutter screens for members, instructors, and administrators.
- `backend/`: NestJS, PostgreSQL, Prisma, JWT authentication, protected payment screenshots, and scheduled in-app notifications.
- `compose.yaml`: local PostgreSQL database.

## Requirements

Node.js 22+, npm, Docker (or PostgreSQL 16+), and Flutter. Tested with Flutter 3.47.5 / Dart 3.13.4; this version is recommended for the included native scaffolds.

## Run locally

From this directory:

```sh
docker compose up -d
cd backend
cp .env.example .env
```

Edit `.env` before starting:

- Set a random `JWT_SECRET` of at least 32 characters (`openssl rand -hex 32`).
- Set `ADMIN_EMAIL` and a unique `ADMIN_PASSWORD` of at least 12 characters.
- Set the studio's real bank details in `BANK_INSTRUCTIONS`.
- Configure the IANA timezone, currency, and exact Flutter web origin. Defaults are `Asia/Yangon`, `MMK`, and `http://localhost:8080`; these are provisional studio settings.

```sh
npm ci
npm run db:generate
npm run db:migrate
npm run db:seed
npm run start:dev
```

In another terminal:

```sh
cd frontend
flutter pub get
flutter run -d chrome --web-port 8080 --dart-define=API_URL=http://localhost:3000/api
```

For Android emulator use `http://10.0.2.2:3000/api`. For a physical device use your development machine's LAN address. Production builds must use an HTTPS API.

The Flutter platform scaffolds are included when generated. If adding a new target later, run `flutter create --project-name dreamtopia --platforms=android,ios,web .` from `frontend/` and retain the application files in `lib/` and `pubspec.yaml`.

## First studio setup

1. Sign in with the seeded admin account. Seeding is idempotent and does not reset an existing password or create fake customers/payments.
2. Add instructor profiles. Instructors register with the matching email through the app. After independently verifying the account belongs to the instructor, select **Link registered account**. Registration alone never grants instructor access.
3. Create studio sessions with date, time, fee, capacity, level, and instructor. An instructor must accept an assigned class before members can book it. Auto-accept applies to future assignments.
4. Members create their own accounts. Add purchased class credits through **Members → Add credits** after verifying package payment.
5. Set rental, practice, trial, and pole-class fees on each session. Rental capacity is always one booking for the whole studio.
6. Review each payment screenshot against actual bank records before confirming the booking.

## Booking rules

- One shared studio: overlapping active sessions are rejected. Instructors cannot block assigned time; ask the admin to cancel it first.
- Only published future sessions are bookable. Pending bookings hold a seat. Duplicate or overlapping member bookings are rejected.
- Bank-transfer bookings require a private PNG, JPEG, or WebP proof (up to 5 MB). An uploaded proof may only be used once and only by its owner. Admin and proof owner can view it.
- Admin approval confirms payment and the booking. Instructor approval occurs when the admin creates the class, before member booking becomes available.
- Class credits apply to pole classes. One credit is reserved at booking, restored on rejection or eligible cancellation, and retained for confirmed attendance/no-show.
- Members may cancel **strictly more than 24 hours** before class. Exactly 24 hours and later are blocked server-side.
- Admin cancellation/delete cancels active bookings and restores credits. Delete is soft deletion, preserving financial and attendance history. Completed sessions cannot be deleted.
- Bank-transfer refunds are manual and explicitly communicated. The app does not send money or promise an automatic refund.
- Attendance can be recorded after class begins. An assigned instructor or admin marks a class taught after it ends. Instructor totals count completed sessions once, not individual students.
- Preferred timeslots are requests, not reservations. An admin response notifies the member; publishing a session is a separate action.
- Promotion percentages are validated on the server, expire at their configured timestamp, and apply only to bank-transfer bookings.
- Serializable PostgreSQL transactions protect seats, overlapping slots, review transitions, and credit balances against concurrent updates.

## Notifications

Persistent **in-app** notifications cover booking approval/rejection/cancellation, class assignments, timeslot responses, credits, and marketing campaigns. A NestJS cron job runs every five minutes to generate deduplicated reminders for confirmed bookings starting within 24 hours. The Flutter inbox refreshes every minute while signed in. The API process must be running for reminders.

Email, SMS, mobile push, and operating-system background notifications are **not connected**. Add an FCM/APNs/email provider for those channels. No marketing campaign is sent merely by generating or running this code.

## Verification

See [the verification report](VERIFICATION.md) for completed checks and build limitations.

```sh
cd backend
npm run db:generate
npm run typecheck
npm test
npm run build

cd ../frontend
flutter analyze
flutter test
flutter build web --dart-define=API_URL=https://your-api.example.com/api
```

The PostgreSQL integration suite is separate and requires a dedicated empty test database:

```sh
# Set DATABASE_URL to a disposable test database in your shell.
npm run db:migrate
npm run test:integration
```

Run integration commands from `backend/`. The test database name must contain `dreamtopia_test`. Never run integration tests against production data.

## Deployment

Deploy the NestJS service on a Node.js host with PostgreSQL; serve the Flutter web build from any HTTPS static host or build Android/iOS binaries. Set `API_URL` at Flutter build time. Run `prisma migrate deploy` before starting each new server version. Restrict `CORS_ORIGINS`, keep secrets out of source control, and back up PostgreSQL.

`UPLOAD_DIR` must be a persistent private volume. The included disk upload adapter is suitable for one API instance; replace it with private S3/R2 storage for horizontally scaled or ephemeral deployments. Never serve the upload directory as public static files. Unused screenshots are retained; add a retention job suitable for your studio policy.

JWTs expire after 12 hours and are held by `flutter_secure_storage`. Role checks read current roles from PostgreSQL on every request. HTTPS is required for secure web token storage outside localhost. Registration does not verify email ownership; admin linking must be verified independently. Password reset, email verification, refresh tokens, and payment-provider reconciliation are future production additions.

This code has not been deployed to a live studio service. The earlier web-only prototype was superseded by this requested Flutter/NestJS implementation.
# dreamtopia
