import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  Req,
} from "@nestjs/common";
import { AuthRequest, Roles } from "../auth/auth";
import { BookingsService } from "./bookings.service";
import * as D from "../studio/dto";

@Controller()
export class BookingsController {
  constructor(private service: BookingsService) {}

  @Get("sessions/:id/quote")
  quote(
    @Param("id", ParseUUIDPipe) id: string,
    @Query("code") code?: string,
  ) {
    return this.service.quote(id, code);
  }

  @Get("bookings")
  bookings(@Req() r: AuthRequest) {
    return this.service.bookings(r.user);
  }

  @Roles("MEMBER")
  @Post("bookings")
  book(@Req() r: AuthRequest, @Body() d: D.BookingDto) {
    return this.service.book(r.user, d);
  }

  @Roles("MEMBER")
  @Post("bookings/:id/cancel")
  cancelBooking(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.service.cancelBooking(r.user, id);
  }

  @Roles("ADMIN")
  @Post("admin/bookings")
  adminBook(@Body() d: D.AdminBookingDto) {
    return this.service.adminBook(d);
  }

  @Roles("ADMIN")
  @Post("admin/bookings/:id/cancel")
  cancelBookingOverride(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() d: D.CancelOverrideDto,
  ) {
    return this.service.adminCancelBooking(id, d.reason);
  }

  @Roles("ADMIN")
  @Post("admin/bookings/:id/resolve")
  resolveBooking(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() d: D.ResolveBookingDto,
  ) {
    return this.service.resolveBooking(id, d);
  }

  @Roles("ADMIN")
  @Post("bookings/:id/approve")
  approve(@Param("id", ParseUUIDPipe) id: string) {
    return this.service.review(id, true);
  }

  @Roles("ADMIN")
  @Post("bookings/:id/reject")
  reject(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() d: D.ReasonDto,
  ) {
    return this.service.review(id, false, d.reason);
  }

  @Roles("ADMIN", "INSTRUCTOR")
  @Patch("bookings/:id/attendance")
  attendance(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() d: D.AttendanceDto,
  ) {
    return this.service.attendance(r.user, id, d);
  }
}
