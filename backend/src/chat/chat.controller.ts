import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  Query,
  UseInterceptors,
  UploadedFile,
  Res,
  Req,
  Header,
} from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";
import { FileInterceptor } from "@nestjs/platform-express";
import { ChatService } from "./chat.service";
import { Roles, Public, AuthRequest, Actor } from "../auth/auth";
import { Role, ChatStatus } from "@prisma/client";
import { IsString, IsOptional, IsNotEmpty, IsBoolean } from "class-validator";
import type { Request, Response } from "express";

class StartConversationDto {
  @IsOptional() @IsString() visitorName?: string;
  @IsOptional() @IsString() visitorEmail?: string;
}

class FaqAnswerDto {
  @IsNotEmpty() @IsString() faqId!: string;
}

class AskAiDto {
  @IsNotEmpty() @IsString() message!: string;
  @IsOptional() @IsString() senderName?: string;
}

class AdminReplyDto {
  @IsNotEmpty() @IsString() content!: string;
}

class RedirectInstructorDto {
  @IsNotEmpty() @IsString() instructorId!: string;
  @IsOptional() @IsString() note?: string;
}

class RequestReopenPermissionDto {
  @IsOptional() @IsString() reason?: string;
}

class GrantReopenPermissionDto {
  @IsNotEmpty() @IsBoolean() shareGapHistory!: boolean;
}

@Controller("chat")
export class ChatController {
  constructor(
    private chatService: ChatService,
    private jwt: JwtService,
  ) {}

  // --- FLOW 1: FAQ Q&A ---

  @Public()
  @Get("faq")
  async getFaqs() {
    return this.chatService.getFaqCategoriesAndQuestions();
  }

  @Public()
  @Get("faq/search")
  async searchFaq(@Query("q") q: string) {
    if (!q) return [];
    return this.chatService.searchFaq(q);
  }

  @Public()
  @Post("conversation/start")
  async startConversation(
    @Req() req: Request & { user?: Actor },
    @Body() dto: StartConversationDto,
  ) {
    let userId = req.user?.id;
    if (!userId && req.headers?.authorization) {
      try {
        const token = req.headers.authorization.match(/^Bearer (.+)$/)?.[1];
        if (token) {
          const payload = this.jwt.verify<{ sub?: string }>(token);
          userId = payload.sub;
        }
      } catch (_) {}
    }
    const visitorName = req.user?.name || dto.visitorName || "Guest Member";
    const visitorEmail = req.user?.email || dto.visitorEmail;
    return this.chatService.getOrCreateConversation(
      userId,
      visitorName,
      visitorEmail,
    );
  }

  @Public()
  @Get("conversation/:id")
  async getConversation(
    @Param("id") id: string,
    @Req() req: Request & { user?: Actor },
  ) {
    let actor = req.user;
    if (!actor && req.headers?.authorization) {
      try {
        const token = req.headers.authorization.match(/^Bearer (.+)$/)?.[1];
        if (token) {
          actor = this.jwt.verify<Actor>(token);
        }
      } catch (_) {}
    }
    return this.chatService.getConversationById(id, actor);
  }

  @Public()
  @Post("conversation/:id/faq-answer")
  async answerFaq(
    @Param("id") conversationId: string,
    @Body() dto: FaqAnswerDto,
  ) {
    return this.chatService.answerFromFaq(conversationId, dto.faqId);
  }

  // --- FLOW 2: AI CHATBOT (GEMINI) ---

  @Public()
  @Post("conversation/:id/ask-ai")
  async askAi(
    @Param("id") conversationId: string,
    @Req() req: AuthRequest,
    @Body() dto: AskAiDto,
  ) {
    const senderName = req.user?.name || dto.senderName || "Member";
    return this.chatService.askAi(conversationId, dto.message, senderName);
  }

  // --- FLOW 3: CONNECT TO ADMIN & DIRECT CHAT ---

  @Public()
  @Post("conversation/:id/request-admin")
  async requestAdmin(
    @Param("id") conversationId: string,
    @Body("note") note?: string,
  ) {
    return this.chatService.requestAdminAssistance(conversationId, note);
  }

  // Staff reply directly to customer (Admin or Assigned Instructor)
  @Roles(Role.ADMIN, Role.INSTRUCTOR)
  @Post("conversation/:id/admin-reply")
  async adminReply(
    @Param("id") conversationId: string,
    @Req() req: AuthRequest,
    @Body() dto: AdminReplyDto,
  ) {
    return this.chatService.sendAdminMessage(
      conversationId,
      req.user,
      dto.content,
    );
  }

  // Admin re-direct customer chat to instructor
  @Roles(Role.ADMIN)
  @Post("conversation/:id/redirect-instructor")
  async redirectInstructor(
    @Param("id") conversationId: string,
    @Body() dto: RedirectInstructorDto,
  ) {
    return this.chatService.redirectToInstructor(
      conversationId,
      dto.instructorId,
      dto.note,
    );
  }

  // Resolve chat (Admin or Assigned Instructor)
  @Roles(Role.ADMIN, Role.INSTRUCTOR)
  @Post("conversation/:id/resolve")
  async resolveChat(
    @Param("id") conversationId: string,
    @Req() req: AuthRequest,
  ) {
    return this.chatService.resolveConversation(conversationId, req.user);
  }

  // Staff handover chat back to AI (opens AI auto reply)
  @Roles(Role.ADMIN, Role.INSTRUCTOR)
  @Post("conversation/:id/handover-ai")
  async handoverToAi(
    @Param("id") conversationId: string,
    @Req() req: AuthRequest,
  ) {
    return this.chatService.handoverToAi(conversationId, req.user);
  }

  // Instructor requests permission from admin to re-open chat
  @Roles(Role.INSTRUCTOR)
  @Post("conversation/:id/request-reopen-permission")
  async requestReopenPermission(
    @Param("id") conversationId: string,
    @Req() req: AuthRequest,
    @Body() dto: RequestReopenPermissionDto,
  ) {
    return this.chatService.requestReopenPermission(
      conversationId,
      req.user,
      dto.reason,
    );
  }

  // Admin grants reopen permission and decides whether to share time gap history
  @Roles(Role.ADMIN)
  @Post("conversation/:id/grant-reopen-permission")
  async grantReopenPermission(
    @Param("id") conversationId: string,
    @Req() req: AuthRequest,
    @Body() dto: GrantReopenPermissionDto,
  ) {
    return this.chatService.grantReopenPermission(
      conversationId,
      req.user,
      dto.shareGapHistory,
    );
  }

  // Admin and Instructor view chat history (Instructors see only redirected chats)
  @Roles(Role.ADMIN, Role.INSTRUCTOR)
  @Get("admin/conversations")
  async listAdminConversations(
    @Req() req: AuthRequest,
    @Query("status") status?: ChatStatus,
  ) {
    return this.chatService.listConversations(req.user, status);
  }

  // Analytics for interest counts and question analysis
  @Roles(Role.ADMIN)
  @Get("admin/analytics")
  async getAnalytics() {
    return this.chatService.getChatAnalytics();
  }

  // Export FAQ with current hitCounts to Excel
  @Roles(Role.ADMIN)
  @Get("admin/faq/export")
  @Header(
    "Content-Type",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  )
  @Header("Content-Disposition", 'attachment; filename="dreamtopia_faq.xlsx"')
  async exportFaq(@Res() res: Response) {
    const buffer = await this.chatService.exportFaqToExcelBuffer();
    res.send(buffer);
  }

  // Upload new or edited Excel FAQ
  @Roles(Role.ADMIN)
  @Post("admin/faq/upload")
  @UseInterceptors(FileInterceptor("file"))
  async uploadFaq(@UploadedFile() file: Express.Multer.File) {
    const count = await this.chatService.syncFaqFromExcel(file.buffer);
    return {
      success: true,
      message: `Successfully synchronized ${count} FAQ questions from Excel.`,
    };
  }
}
