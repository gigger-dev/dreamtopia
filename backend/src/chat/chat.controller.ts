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
import { IsString, IsOptional, IsNotEmpty } from "class-validator";
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
  async getConversation(@Param("id") id: string) {
    return this.chatService.getConversationById(id);
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

  // Admin reply directly to customer
  @Roles(Role.ADMIN)
  @Post("conversation/:id/admin-reply")
  async adminReply(
    @Param("id") conversationId: string,
    @Req() req: AuthRequest,
    @Body() dto: AdminReplyDto,
  ) {
    return this.chatService.sendAdminMessage(
      conversationId,
      req.user.id,
      req.user.name,
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

  // Resolve chat
  @Roles(Role.ADMIN)
  @Post("conversation/:id/resolve")
  async resolveChat(@Param("id") conversationId: string) {
    return this.chatService.resolveConversation(conversationId);
  }

  // Admin view all chat history
  @Roles(Role.ADMIN)
  @Get("admin/conversations")
  async listAdminConversations(@Query("status") status?: ChatStatus) {
    return this.chatService.listConversations(status);
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
