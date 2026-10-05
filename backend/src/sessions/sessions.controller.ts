import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  Req,
} from "@nestjs/common";
import { AuthRequest, Roles } from "../auth/auth";
import { SessionsService } from "./sessions.service";
import * as D from "../studio/dto";

@Controller()
export class SessionsController {
  constructor(private service: SessionsService) {}

  @Get("sessions")
  sessions(
    @Req() r: AuthRequest,
    @Query("from") from?: string,
    @Query("to") to?: string,
  ) {
    return this.service.sessions(r.user, from, to);
  }

  @Roles("ADMIN")
  @Post("sessions")
  createSession(@Body() d: D.SessionDto) {
    return this.service.createSession(d);
  }

  @Roles("ADMIN")
  @Patch("sessions/:id")
  updateSession(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() d: D.UpdateSessionDto,
  ) {
    return this.service.updateSession(id, d);
  }

  @Roles("ADMIN")
  @Post("sessions/:id/cancel")
  cancelSession(@Param("id", ParseUUIDPipe) id: string) {
    return this.service.cancelSession(id, false);
  }

  @Roles("ADMIN")
  @Delete("sessions/:id")
  deleteSession(@Param("id", ParseUUIDPipe) id: string) {
    return this.service.cancelSession(id, true);
  }

  @Roles("INSTRUCTOR")
  @Post("sessions/:id/accept")
  accept(@Req() r: AuthRequest, @Param("id", ParseUUIDPipe) id: string) {
    return this.service.accept(r.user, id);
  }

  @Roles("INSTRUCTOR")
  @Post("sessions/:id/decline")
  decline(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() d: D.DeclineSessionDto,
  ) {
    return this.service.decline(r.user, id, d.reason);
  }

  @Roles("ADMIN", "INSTRUCTOR")
  @Post("sessions/:id/complete")
  complete(@Req() r: AuthRequest, @Param("id", ParseUUIDPipe) id: string) {
    return this.service.completeSession(r.user, id);
  }
}
