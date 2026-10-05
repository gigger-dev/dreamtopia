import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Req,
} from "@nestjs/common";
import { AuthRequest, Roles } from "../auth/auth";
import { InstructorsService } from "./instructors.service";
import * as D from "../studio/dto";

@Controller()
export class InstructorsController {
  constructor(private service: InstructorsService) {}

  @Roles("ADMIN")
  @Get("instructors")
  instructors() {
    return this.service.instructors();
  }

  @Roles("ADMIN")
  @Post("instructors")
  addInstructor(@Body() d: D.InstructorDto) {
    return this.service.addInstructor(d);
  }

  @Roles("ADMIN")
  @Post("instructors/:id/link")
  linkInstructor(@Param("id", ParseUUIDPipe) id: string) {
    return this.service.linkInstructor(id);
  }

  @Roles("INSTRUCTOR")
  @Patch("instructor/settings")
  autoAccept(@Req() r: AuthRequest, @Body() d: D.AutoDto) {
    return this.service.autoAccept(r.user, d);
  }

  @Roles("INSTRUCTOR")
  @Get("instructor/blocks")
  blocks(@Req() r: AuthRequest) {
    return this.service.blocks(r.user);
  }

  @Roles("INSTRUCTOR")
  @Post("instructor/blocks")
  block(@Req() r: AuthRequest, @Body() d: D.BlockDto) {
    return this.service.block(r.user, d);
  }

  @Roles("INSTRUCTOR")
  @Delete("instructor/blocks/:id")
  unblock(@Req() r: AuthRequest, @Param("id", ParseUUIDPipe) id: string) {
    return this.service.unblock(r.user, id);
  }
}
