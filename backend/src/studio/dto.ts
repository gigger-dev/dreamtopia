import { Attendance, PaymentMethod, SessionType } from "@prisma/client";
import {
  IsBoolean,
  IsDateString,
  IsEmail,
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
  MinLength,
  IsIn,
} from "class-validator";
export class SessionDto {
  @IsString() @MinLength(2) @MaxLength(100) title!: string;
  @IsEnum(SessionType) type!: SessionType;
  @IsDateString() startsAt!: string;
  @IsDateString() endsAt!: string;
  @IsInt() @Min(1) @Max(50) capacity!: number;
  @IsInt() @Min(0) @Max(100000000) price!: number;
  @IsString() @MaxLength(60) level!: string;
  @IsOptional() @IsString() @MaxLength(2000) description?: string;
  @IsOptional() @IsUUID() instructorId?: string;
}
export class BookingDto {
  @IsUUID() sessionId!: string;
  @IsEnum(PaymentMethod) paymentMethod!: PaymentMethod;
  @IsOptional() @IsUUID() proofId?: string;
  @IsOptional() @IsString() @MaxLength(40) promoCode?: string;
}
export class InstructorDto {
  @IsString() @MinLength(2) @MaxLength(80) name!: string;
  @IsEmail() email!: string;
  @IsString() @MaxLength(2000) bio!: string;
  @IsString() @MaxLength(100) specialty!: string;
}
export class AutoDto {
  @IsBoolean() autoAccept!: boolean;
}
export class BlockDto {
  @IsDateString() startsAt!: string;
  @IsDateString() endsAt!: string;
  @IsString() @MaxLength(300) reason!: string;
}
export class RequestDto {
  @IsDateString() startsAt!: string;
  @IsDateString() endsAt!: string;
  @IsEnum(SessionType) type!: SessionType;
  @IsString() @MaxLength(1000) note!: string;
}
export class RequestResponseDto {
  @IsIn(["REVIEWED", "DECLINED"]) status!: "REVIEWED" | "DECLINED";
  @IsString() @MinLength(2) @MaxLength(1000) response!: string;
}
export class PromotionDto {
  @IsString() @MinLength(3) @MaxLength(40) code!: string;
  @IsInt() @Min(1) @Max(100) percent!: number;
  @IsDateString() expiresAt!: string;
}
export class ActiveDto {
  @IsBoolean() active!: boolean;
}
export class CampaignDto {
  @IsString() @MinLength(2) @MaxLength(100) title!: string;
  @IsString() @MinLength(2) @MaxLength(2000) body!: string;
}
export class CreditDto {
  @IsInt() @Min(1) @Max(1000) amount!: number;
  @IsString() @MinLength(2) @MaxLength(200) reason!: string;
}
export class AttendanceDto {
  @IsEnum(Attendance) attendance!: Attendance;
}
export class ReasonDto {
  @IsString() @MinLength(2) @MaxLength(500) reason!: string;
}
