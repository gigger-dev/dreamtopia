import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Req,
} from "@nestjs/common";
import { AuthRequest, Roles } from "../auth/auth";
import { NotificationsService } from "./notifications.service";
import * as D from "../studio/dto";

@Controller()
export class NotificationsController {
  constructor(private service: NotificationsService) {}

  @Roles("ADMIN")
  @Post("campaigns")
  campaign(@Body() d: D.CampaignDto) {
    return this.service.campaign(d);
  }

  @Get("notifications")
  notifications(@Req() r: AuthRequest) {
    return this.service.notifications(r.user);
  }

  @Patch("notifications/:id/read")
  read(@Req() r: AuthRequest, @Param("id", ParseUUIDPipe) id: string) {
    return this.service.read(r.user, id);
  }

  @Roles("ADMIN", "MEMBER")
  @Get("requests")
  requests(@Req() r: AuthRequest) {
    return this.service.requests(r.user);
  }

  @Roles("MEMBER")
  @Post("requests")
  request(@Req() r: AuthRequest, @Body() d: D.RequestDto) {
    return this.service.request(r.user, d);
  }

  @Roles("ADMIN")
  @Patch("requests/:id")
  respond(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() d: D.RequestResponseDto,
  ) {
    return this.service.respond(id, d);
  }
}
