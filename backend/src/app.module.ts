import { Module } from "@nestjs/common";
import { ConfigModule } from "@nestjs/config";
import { JwtModule } from "@nestjs/jwt";
import { ScheduleModule } from "@nestjs/schedule";
import { ThrottlerGuard, ThrottlerModule } from "@nestjs/throttler";
import { APP_GUARD } from "@nestjs/core";
import { AuthController, AuthGuard } from "./auth/auth";
import { PrismaService } from "./prisma.service";
import { StudioModule } from "./studio/studio.module";
import { SessionsModule } from "./sessions/sessions.module";
import { PackagesModule } from "./packages/packages.module";
import { BookingsModule } from "./bookings/bookings.module";
import { InstructorsModule } from "./instructors/instructors.module";
import { NotificationsModule } from "./notifications/notifications.module";

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    JwtModule.registerAsync({
      global: true,
      useFactory: () => {
        const secret = process.env.JWT_SECRET;
        if (!secret || secret.length < 32 || secret.includes("replace-with"))
          throw new Error("Set JWT_SECRET to at least 32 random characters.");
        return { secret, signOptions: { expiresIn: "12h" } };
      },
    }),
    ScheduleModule.forRoot(),
    ThrottlerModule.forRoot([{ ttl: 60000, limit: 120 }]),
    StudioModule,
    SessionsModule,
    PackagesModule,
    BookingsModule,
    InstructorsModule,
    NotificationsModule,
  ],
  controllers: [AuthController],
  providers: [
    PrismaService,
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useClass: AuthGuard },
  ],
})
export class AppModule {}
