import {
  Body,
  CanActivate,
  Controller,
  ExecutionContext,
  Injectable,
  Post,
  UnauthorizedException,
  ConflictException,
  SetMetadata,
  ForbiddenException,
} from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";
import { Reflector } from "@nestjs/core";
import { IsEmail, IsString, MaxLength, MinLength } from "class-validator";
import { compare, hash } from "bcryptjs";
import { Throttle } from "@nestjs/throttler";
import { Role } from "@prisma/client";
import { PrismaService } from "../prisma.service";
import type { Request } from "express";
export type Actor = { id: string; email: string; role: Role; name: string };
export type AuthRequest = Request & { user: Actor };
export const Public = () => SetMetadata("public", true);
export const Roles = (...roles: Role[]) => SetMetadata("roles", roles);
class LoginDto {
  @IsEmail() email!: string;
  @IsString() @MinLength(8) @MaxLength(72) password!: string;
}
class RegisterDto extends LoginDto {
  @IsString() @MinLength(2) @MaxLength(80) name!: string;
}
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private reflector: Reflector,
    private jwt: JwtService,
    private db: PrismaService,
  ) {}
  async canActivate(ctx: ExecutionContext) {
    if (
      this.reflector.getAllAndOverride<boolean>("public", [
        ctx.getHandler(),
        ctx.getClass(),
      ])
    )
      return true;
    const req = ctx.switchToHttp().getRequest<AuthRequest>();
    try {
      const token = req.headers.authorization?.match(/^Bearer (.+)$/)?.[1];
      if (!token) throw new Error();
      const payload = await this.jwt.verifyAsync(token);
      const user = await this.db.user.findUnique({
        where: { id: payload.sub },
        select: { id: true, email: true, name: true, role: true },
      });
      if (!user) throw new Error();
      req.user = user;
    } catch {
      throw new UnauthorizedException("Please sign in again.");
    }
    const roles = this.reflector.getAllAndOverride<Role[]>("roles", [
      ctx.getHandler(),
      ctx.getClass(),
    ]);
    if (roles && !roles.includes(req.user.role))
      throw new ForbiddenException(
        "This action is not available for your role.",
      );
    return true;
  }
}
@Controller("auth")
export class AuthController {
  constructor(
    private db: PrismaService,
    private jwt: JwtService,
  ) {}
  private async token(user: Actor) {
    return {
      accessToken: await this.jwt.signAsync({ sub: user.id }),
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        role: user.role,
      },
    };
  }
  @Public()
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @Post("register")
  async register(@Body() d: RegisterDto) {
    const email = d.email.toLowerCase().trim();
    if (await this.db.user.findUnique({ where: { email } }))
      throw new ConflictException("This email is already registered.");
    // Instructor email is not sufficient proof of identity. New accounts always remain members
    // until an administrator explicitly links the verified instructor account.
    const user = await this.db.user.create({
      data: {
        email,
        name: d.name.trim(),
        passwordHash: await hash(d.password, 12),
      },
    });
    return this.token(user);
  }
  @Public()
  @Throttle({ default: { limit: 10, ttl: 60000 } })
  @Post("login")
  async login(@Body() d: LoginDto) {
    const user = await this.db.user.findUnique({
      where: { email: d.email.toLowerCase().trim() },
    });
    if (!user || !(await compare(d.password, user.passwordHash)))
      throw new UnauthorizedException("Email or password is incorrect.");
    return this.token(user);
  }
}
