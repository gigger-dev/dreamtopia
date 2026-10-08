import {
  Injectable,
  Logger,
  NotFoundException,
  BadRequestException,
  ForbiddenException,
} from "@nestjs/common";
import { PrismaService } from "../prisma.service";
import ExcelJS from "exceljs";
import * as path from "path";
import * as fs from "fs";
import { Readable } from "stream";
import { generateDefaultFaqExcel } from "./faq-excel.generator";
import { GoogleGenAI, type Content } from "@google/genai";
import { ChatSenderType, ChatStatus, Role } from "@prisma/client";
import { Actor } from "../auth/auth";

@Injectable()
export class ChatService {
  private readonly logger = new Logger(ChatService.name);
  private aiClient: GoogleGenAI | null = null;

  constructor(private db: PrismaService) {
    this.initGemini();
    this.ensureFaqLoaded();
  }

  private initGemini() {
    const apiKey = process.env.GEMINI_API_KEY;
    if (apiKey && apiKey.trim().length > 0 && !apiKey.includes("your_")) {
      try {
        this.aiClient = new GoogleGenAI({ apiKey });
        this.logger.log("Google Gemini AI client initialized successfully.");
      } catch (err) {
        this.logger.error("Failed to initialize Google Gemini client:", err);
      }
    } else {
      this.logger.warn(
        "GEMINI_API_KEY is not set or placeholder. AI chatbot will fallback to guided responses.",
      );
    }
  }

  async ensureFaqLoaded() {
    try {
      const count = await this.db.faqQuestion.count();
      if (count === 0) {
        const filePath = path.resolve(process.cwd(), "faq_template.xlsx");
        if (!fs.existsSync(filePath)) {
          await generateDefaultFaqExcel(filePath);
        }
        await this.syncFaqFromExcel(filePath);
        this.logger.log("Initialized FAQ database from Excel template.");
      }
    } catch (e) {
      this.logger.error("Error loading initial FAQ from Excel:", e);
    }
  }

  // --- EXCEL FAQ SYNC & EXPORT ---

  async syncFaqFromExcel(filePathOrBuffer: string | Buffer): Promise<number> {
    const workbook = new ExcelJS.Workbook();
    if (typeof filePathOrBuffer === "string") {
      await workbook.xlsx.readFile(filePathOrBuffer);
    } else {
      const stream = Readable.from(filePathOrBuffer);
      await workbook.xlsx.read(stream);
    }

    const sheet = workbook.worksheets[0];
    if (!sheet) throw new BadRequestException("Excel file is empty or missing sheets.");

    let rowCount = 0;
    // Iterate rows starting after header (row 2)
    sheet.eachRow((row, rowNumber) => {
      if (rowNumber > 1) {
        const category = String(row.getCell(1).value || "General").trim();
        const question = String(row.getCell(2).value || "").trim();
        const answer = String(row.getCell(3).value || "").trim();
        const keywords = String(row.getCell(4).value || "").trim();

        if (question && answer) {
          rowCount++;
          // Upsert or create FAQ in background
          this.db.faqQuestion
            .findFirst({ where: { question } })
            .then(async (existing) => {
              if (existing) {
                await this.db.faqQuestion.update({
                  where: { id: existing.id },
                  data: { category, answer, keywords },
                });
              } else {
                await this.db.faqQuestion.create({
                  data: { category, question, answer, keywords },
                });
              }
            })
            .catch((err) =>
              this.logger.error(`Error saving FAQ row ${rowNumber}:`, err),
            );
        }
      }
    });

    return rowCount;
  }

  async exportFaqToExcelBuffer(): Promise<Buffer> {
    const faqs = await this.db.faqQuestion.findMany({
      orderBy: [{ category: "asc" }, { hitCount: "desc" }],
    });

    const workbook = new ExcelJS.Workbook();
    const sheet = workbook.addWorksheet("FAQ");
    sheet.columns = [
      { header: "Category", key: "category", width: 20 },
      { header: "Question", key: "question", width: 45 },
      { header: "Answer", key: "answer", width: 60 },
      { header: "Keywords", key: "keywords", width: 35 },
      { header: "Interest Count", key: "hitCount", width: 15 },
    ];
    sheet.getRow(1).font = { bold: true };

    for (const faq of faqs) {
      sheet.addRow({
        category: faq.category,
        question: faq.question,
        answer: faq.answer,
        keywords: faq.keywords,
        hitCount: faq.hitCount,
      });
    }

    return Buffer.from(await workbook.xlsx.writeBuffer());
  }

  // --- CONVERSATION LIFECYCLE ---

  async getOrCreateConversation(
    userId?: string,
    visitorName = "Guest Member",
    visitorEmail?: string,
  ) {
    const email = visitorEmail?.toLowerCase().trim();
    // 1. Check if an existing conversation exists for this user (by userId OR visitorEmail)
    const existing = await this.db.chatConversation.findFirst({
      where: {
        OR: [
          ...(userId ? [{ userId }] : []),
          ...(email ? [{ visitorEmail: email }] : []),
        ],
      },
      include: {
        messages: { orderBy: { createdAt: "asc" } },
        instructor: { select: { id: true, name: true, specialty: true } },
      },
      orderBy: { updatedAt: "desc" },
    });

    if (existing) {
      // Keep info up to date (associate userId if previously guest)
      if ((userId && !existing.userId) || (visitorName && existing.visitorName !== visitorName)) {
        await this.db.chatConversation.update({
          where: { id: existing.id },
          data: {
            userId: userId || existing.userId,
            visitorName: visitorName || existing.visitorName,
            visitorEmail: email || existing.visitorEmail,
          },
        });
      }
      return existing;
    }

    // Create fresh conversation
    return this.db.chatConversation.create({
      data: {
        userId,
        visitorName,
        visitorEmail,
        status: ChatStatus.BOT,
      },
      include: {
        messages: true,
        instructor: { select: { id: true, name: true, specialty: true } },
      },
    });
  }

  async getConversationById(id: string, actor?: Actor) {
    const conv = await this.db.chatConversation.findUnique({
      where: { id },
      include: {
        user: { select: { id: true, name: true, email: true, role: true } },
        assignedAdmin: { select: { id: true, name: true, email: true } },
        instructor: { select: { id: true, name: true, specialty: true, phone: true } },
        messages: {
          orderBy: { createdAt: "asc" },
          include: { faq: true },
        },
      },
    });
    if (!conv) throw new NotFoundException("Conversation not found");

    if (actor && actor.role === Role.INSTRUCTOR) {
      const instructor = await this.db.instructor.findFirst({
        where: {
          OR: [{ userId: actor.id }, { email: actor.email.toLowerCase() }],
        },
      });
      if (!instructor || conv.instructorId !== instructor.id) {
        throw new ForbiddenException(
          "You can only view conversations redirected to you.",
        );
      }

      // If Admin chose NOT to share time gap chat history, hide gap messages
      if (
        conv.hideGapMessagesFromInstructor &&
        conv.gapStartTime &&
        conv.gapEndTime
      ) {
        const gapStart = new Date(conv.gapStartTime).getTime();
        const gapEnd = new Date(conv.gapEndTime).getTime();

        conv.messages = conv.messages.filter((m) => {
          if (m.senderType === "BOT") return true;
          const mTime = new Date(m.createdAt).getTime();
          return mTime < gapStart || mTime > gapEnd;
        });
      }
    }

    return conv;
  }

  // --- FLOW 1: FAQ QUESTION & ANSWER & INTEREST TRACKING ---

  async getFaqCategoriesAndQuestions() {
    const faqs = await this.db.faqQuestion.findMany({
      orderBy: [{ hitCount: "desc" }, { question: "asc" }],
    });

    const categories: Record<string, typeof faqs> = {};
    for (const item of faqs) {
      if (!categories[item.category]) categories[item.category] = [];
      categories[item.category].push(item);
    }

    return {
      total: faqs.length,
      categories,
      popularQuestions: faqs.slice(0, 5),
    };
  }

  async answerFromFaq(conversationId: string, faqId: string) {
    const faq = await this.db.faqQuestion.findUnique({ where: { id: faqId } });
    if (!faq) throw new NotFoundException("FAQ not found");

    // Increment interest count
    await this.db.faqQuestion.update({
      where: { id: faqId },
      data: { hitCount: { increment: 1 } },
    });

    // Record question message from user
    await this.db.chatMessage.create({
      data: {
        conversationId,
        senderType: ChatSenderType.USER,
        senderName: "Customer",
        content: faq.question,
        faqId: faq.id,
      },
    });

    // Record answer message from bot
    const botMsg = await this.db.chatMessage.create({
      data: {
        conversationId,
        senderType: ChatSenderType.BOT,
        senderName: "Dreamtopia Bot",
        content: faq.answer,
        faqId: faq.id,
      },
    });

    // Update conversation topic and timestamp
    await this.db.chatConversation.update({
      where: { id: conversationId },
      data: { primaryTopic: faq.category },
    });

    return {
      faq,
      message: botMsg,
    };
  }

  // Search FAQ by keyword/query
  async searchFaq(query: string) {
    const q = query.toLowerCase().trim();
    const faqs = await this.db.faqQuestion.findMany();
    return faqs.filter(
      (f) =>
        f.question.toLowerCase().includes(q) ||
        f.answer.toLowerCase().includes(q) ||
        f.keywords.toLowerCase().includes(q) ||
        f.category.toLowerCase().includes(q),
    );
  }

  // --- FLOW 2: AI CHATBOT (GEMINI) ---

  async askAi(conversationId: string, userMessage: string, senderName = "Customer") {
    const conv = await this.db.chatConversation.findUnique({
      where: { id: conversationId },
      include: { instructor: true, assignedAdmin: true },
    });
    if (!conv) {
      throw new NotFoundException("Conversation not found");
    }

    // 1. Record customer's message
    const userMsg = await this.db.chatMessage.create({
      data: {
        conversationId,
        senderType: ChatSenderType.USER,
        senderName,
        content: userMessage,
      },
    });

    // 2. CHECK IF ADMIN OR INSTRUCTOR IS CURRENTLY ACTIVE IN CHAT
    const isStaffActive =
      conv.status === ChatStatus.ADMIN_ACTIVE ||
      conv.status === ChatStatus.WAITING_ADMIN;

    if (isStaffActive) {
      // AI AUTO REPLY IS CLOSED: Staff (admin or instructor) is actively handling the chat.
      await this.db.chatConversation.update({
        where: { id: conversationId },
        data: { updatedAt: new Date() },
      });

      // Send push notification to assigned instructor or admin
      const recipientUserId =
        conv.instructor?.userId || conv.assignedAdminId;
      if (recipientUserId) {
        await this.db.notification.create({
          data: {
            userId: recipientUserId,
            title: `New message from ${conv.visitorName}`,
            body:
              userMessage.length > 60
                ? `${userMessage.substring(0, 60)}…`
                : userMessage,
          },
        });
      } else if (conv.status === ChatStatus.WAITING_ADMIN) {
        const admins = await this.db.user.findMany({ where: { role: Role.ADMIN } });
        for (const adm of admins) {
          await this.db.notification.create({
            data: {
              userId: adm.id,
              title: `New message from ${conv.visitorName}`,
              body:
                userMessage.length > 60
                  ? `${userMessage.substring(0, 60)}…`
                  : userMessage,
            },
          });
        }
      }

      // Return user message; NO AI auto-reply is generated
      return {
        ...userMsg,
        aiReplyClosed: true,
        staffActive: true,
      };
    }

    // 3. ADMIN OR INSTRUCTOR IS INACTIVE (status is BOT, AI, or RESOLVED) -> OPEN AI AUTO REPLY!
    if (conv.status === ChatStatus.RESOLVED || conv.status === ChatStatus.BOT) {
      await this.db.chatConversation.update({
        where: { id: conversationId },
        data: { status: ChatStatus.AI },
      });
    }

    // Fetch conversation context for AI
    const history = await this.db.chatMessage.findMany({
      where: { conversationId },
      orderBy: { createdAt: "desc" },
      take: 6,
    });
    const reversedHistory = history.reverse();

    // Fetch all FAQ summaries for studio grounding
    const allFaqs = await this.db.faqQuestion.findMany({ take: 25 });
    const faqContext = allFaqs
      .map((f) => `Q: ${f.question}\nA: ${f.answer}`)
      .join("\n\n");

    let aiReply = "";

    if (this.aiClient) {
      try {
        const systemPrompt = `You are "Aura", the warm, helpful, and knowledgeable AI assistant for Dreamtopia Yoga & Movement Studio.
Here is the official studio FAQ and information:
${faqContext}

Studio Details:
- Location: Yangon
- Classes: Pole classes, Trial classes, Pole practice, Studio rental
- Booking: Through the app using class credits or walk-in bank transfer.
- Cancellation: Up to 12 hours before class.

Instructions:
- Give concise, friendly, and accurate answers.
- If the customer asks something specific that you cannot resolve or wants direct human help, kindly offer to connect them with a human admin or an instructor.
- Keep responses within 2 to 4 sentences unless more explanation is directly asked.`;

        const contents: Content[] = [
          { role: "user", parts: [{ text: systemPrompt }] },
          ...reversedHistory.map((m) => ({
            role: m.senderType === ChatSenderType.USER ? "user" : "model",
            parts: [{ text: m.content }],
          })),
        ];

        let response;
        const candidateModels = ["gemini-flash-latest", "gemini-flash-lite-latest", "gemini-3.8-flash"];
        for (const mod of candidateModels) {
          try {
            response = await this.aiClient.models.generateContent({
              model: mod,
              contents,
            });
            if (response && response.text) break;
          } catch (mErr) {
            this.logger.warn(`Model ${mod} attempt failed: ${mErr}`);
          }
        }

        aiReply = response?.text || "I am here to help you with your Dreamtopia classes and studio questions!";
      } catch (err) {
        this.logger.error("Gemini API call failed, falling back to FAQ search:", err);
      }
    }

    if (!aiReply) {
      // Fallback: keyword match from FAQ
      const matched = await this.searchFaq(userMessage);
      if (matched.length > 0) {
        aiReply = `Here is what I found from our studio guide:\n\n${matched[0].answer}\n\nWould you like me to connect you to our studio admin?`;
      } else {
        aiReply = `Thank you for your message! Our AI assistant is currently connecting to our studio team. Would you like me to transfer your chat directly to our studio admin or an instructor?`;
      }
    }

    // Save AI reply message
    const botMessage = await this.db.chatMessage.create({
      data: {
        conversationId,
        senderType: ChatSenderType.AI,
        senderName: "Dreamtopia AI",
        content: aiReply,
      },
    });

    return botMessage;
  }

  // --- FLOW 3: CONNECT TO ADMIN & REDIRECT TO INSTRUCTOR ---

  async requestAdminAssistance(conversationId: string, note?: string) {
    const conv = await this.db.chatConversation.update({
      where: { id: conversationId },
      data: {
        status: ChatStatus.WAITING_ADMIN,
      },
    });

    await this.db.chatMessage.create({
      data: {
        conversationId,
        senderType: ChatSenderType.BOT,
        senderName: "System",
        content:
          note ||
          "Your request has been routed to our studio admin. An admin will respond to your chat shortly!",
      },
    });

    // Notify admins
    const admins = await this.db.user.findMany({ where: { role: "ADMIN" } });
    for (const adm of admins) {
      await this.db.notification.create({
        data: {
          userId: adm.id,
          title: "New Customer Chat",
          body: `${conv.visitorName} is waiting for support in live chat.`,
        },
      });
    }

    return conv;
  }

  async sendAdminMessage(
    conversationId: string,
    actor: Actor,
    content: string,
  ) {
    let senderType: ChatSenderType = ChatSenderType.ADMIN;
    let senderName = `${actor.name} (Admin)`;
    let notificationTitle = "Message from Studio Admin";

    if (actor.role === Role.INSTRUCTOR) {
      const instructor = await this.db.instructor.findFirst({
        where: {
          OR: [{ userId: actor.id }, { email: actor.email.toLowerCase() }],
        },
      });
      if (!instructor) {
        throw new ForbiddenException(
          "No instructor profile linked to your account.",
        );
      }

      const conv = await this.db.chatConversation.findUnique({
        where: { id: conversationId },
      });
      if (!conv) {
        throw new NotFoundException("Conversation not found");
      }
      if (conv.instructorId !== instructor.id) {
        throw new ForbiddenException(
          "You can only reply to chats assigned to you.",
        );
      }

      // If conversation is resolved or was resolved by instructor without admin permission, block reply
      if (
        conv.status === ChatStatus.RESOLVED ||
        (conv.resolvedByRole === "INSTRUCTOR" && !conv.instructorPermissionGranted)
      ) {
        throw new ForbiddenException(
          "This conversation was marked resolved. You cannot send messages to this customer again without admin permission.",
        );
      }

      senderType = ChatSenderType.INSTRUCTOR;
      senderName = `${actor.name} (Instructor)`;
      notificationTitle = `Message from Instructor ${actor.name}`;
    }

    await this.db.chatConversation.update({
      where: { id: conversationId },
      data: {
        status: ChatStatus.ADMIN_ACTIVE,
        ...(actor.role === Role.ADMIN ? { assignedAdminId: actor.id } : {}),
      },
    });

    const msg = await this.db.chatMessage.create({
      data: {
        conversationId,
        senderType,
        senderId: actor.id,
        senderName,
        content,
      },
    });

    // Also send in-app notification to member if user is registered
    const conv = await this.db.chatConversation.findUnique({
      where: { id: conversationId },
    });
    if (conv?.userId) {
      await this.db.notification.create({
        data: {
          userId: conv.userId,
          title: notificationTitle,
          body: content.length > 60 ? `${content.substring(0, 60)}…` : content,
        },
      });
    }

    return msg;
  }

  async redirectToInstructor(
    conversationId: string,
    instructorId: string,
    note?: string,
  ) {
    const instructor = await this.db.instructor.findUnique({
      where: { id: instructorId },
      include: { user: true },
    });
    if (!instructor) throw new NotFoundException("Instructor not found");

    const conv = await this.db.chatConversation.update({
      where: { id: conversationId },
      data: {
        instructorId,
        status: ChatStatus.ADMIN_ACTIVE,
        instructorPermissionRequested: false,
        instructorPermissionGranted: true,
      },
    });

    const contactParts: string[] = [];
    contactParts.push(`Email: ${instructor.email}`);
    if (instructor.phone) {
      contactParts.push(`Phone: ${instructor.phone}`);
    }
    const contactStr =
      contactParts.length > 0
        ? `\nInstructor Contact:\n• ${contactParts.join("\n• ")}`
        : "";
    const noteStr = note ? `\n\nAdmin Note: ${note}` : "";

    const noticeText = `This conversation has been redirected to instructor ${instructor.name} (${instructor.specialty}).${contactStr}${noteStr}`;

    await this.db.chatMessage.create({
      data: {
        conversationId,
        senderType: ChatSenderType.BOT,
        senderName: "System",
        content: noticeText,
        metadata: {
          instructorEmail: instructor.email,
          instructorPhone: instructor.phone,
        },
      },
    });

    if (instructor.userId) {
      await this.db.notification.create({
        data: {
          userId: instructor.userId,
          title: "Customer Chat Assigned",
          body: `Admin assigned a member chat to you: ${conv.visitorName}`,
        },
      });
    }

    return conv;
  }

  async resolveConversation(conversationId: string, actor?: Actor) {
    let resolvedByRole = "ADMIN";
    if (actor && actor.role === Role.INSTRUCTOR) {
      const instructor = await this.db.instructor.findFirst({
        where: {
          OR: [{ userId: actor.id }, { email: actor.email.toLowerCase() }],
        },
      });
      if (!instructor) {
        throw new ForbiddenException(
          "No instructor profile linked to your account.",
        );
      }

      const conv = await this.db.chatConversation.findUnique({
        where: { id: conversationId },
      });
      if (!conv) {
        throw new NotFoundException("Conversation not found");
      }
      if (conv.instructorId !== instructor.id) {
        throw new ForbiddenException(
          "You can only resolve chats assigned to you.",
        );
      }
      resolvedByRole = "INSTRUCTOR";
    }

    const updated = await this.db.chatConversation.update({
      where: { id: conversationId },
      data: {
        status: ChatStatus.RESOLVED,
        resolvedAt: new Date(),
        resolvedByRole,
        instructorPermissionRequested: false,
        instructorPermissionGranted: false,
      },
    });

    await this.db.chatMessage.create({
      data: {
        conversationId,
        senderType: ChatSenderType.BOT,
        senderName: "System",
        content: `Conversation marked as resolved by ${actor?.name || "Staff"} (${resolvedByRole === "INSTRUCTOR" ? "Instructor" : "Admin"}).`,
      },
    });

    return updated;
  }

  async requestReopenPermission(
    conversationId: string,
    actor: Actor,
    reason?: string,
  ) {
    const instructor = await this.db.instructor.findFirst({
      where: {
        OR: [{ userId: actor.id }, { email: actor.email.toLowerCase() }],
      },
    });
    if (!instructor) {
      throw new ForbiddenException("Instructor profile not found.");
    }

    const conv = await this.db.chatConversation.findUnique({
      where: { id: conversationId },
    });
    if (!conv) {
      throw new NotFoundException("Conversation not found");
    }
    if (conv.instructorId !== instructor.id) {
      throw new ForbiddenException(
        "You can only request permission for chats assigned to you.",
      );
    }

    const updated = await this.db.chatConversation.update({
      where: { id: conversationId },
      data: {
        instructorPermissionRequested: true,
        instructorPermissionReason: reason || "Follow-up customer inquiry",
        instructorPermissionRequestedAt: new Date(),
      },
    });

    // Notify all admins about the request
    const admins = await this.db.user.findMany({ where: { role: Role.ADMIN } });
    for (const adm of admins) {
      await this.db.notification.create({
        data: {
          userId: adm.id,
          title: `Re-open Chat Request: ${instructor.name}`,
          body: `${instructor.name} requested permission to re-open chat with ${conv.visitorName}. Reason: ${reason || "Follow-up"}`,
        },
      });
    }

    await this.db.chatMessage.create({
      data: {
        conversationId,
        senderType: ChatSenderType.BOT,
        senderName: "System",
        content: `Instructor ${instructor.name} requested permission from admin to re-open chat. (${reason || "Follow-up"})`,
      },
    });

    return updated;
  }

  async grantReopenPermission(
    conversationId: string,
    adminActor: Actor,
    shareGapHistory = true,
  ) {
    const conv = await this.db.chatConversation.findUnique({
      where: { id: conversationId },
      include: { instructor: true },
    });
    if (!conv) {
      throw new NotFoundException("Conversation not found");
    }

    const gapStart =
      conv.resolvedAt || conv.instructorPermissionRequestedAt || new Date();
    const gapEnd = new Date();

    const updated = await this.db.chatConversation.update({
      where: { id: conversationId },
      data: {
        status: ChatStatus.ADMIN_ACTIVE,
        instructorPermissionRequested: false,
        instructorPermissionGranted: true,
        gapStartTime: gapStart,
        gapEndTime: gapEnd,
        hideGapMessagesFromInstructor: !shareGapHistory,
      },
    });

    const gapHistoryNote = shareGapHistory
      ? "Full chat history shared with instructor."
      : "Time gap chat history kept private from instructor.";

    await this.db.chatMessage.create({
      data: {
        conversationId,
        senderType: ChatSenderType.BOT,
        senderName: "System",
        content: `Admin (${adminActor.name}) approved permission for Instructor ${conv.instructor?.name || "Instructor"} to resume chat. (${gapHistoryNote})`,
      },
    });

    // Notify instructor
    if (conv.instructor?.userId) {
      await this.db.notification.create({
        data: {
          userId: conv.instructor.userId,
          title: "Chat Permission Granted by Admin",
          body: `Admin approved your request to chat with ${conv.visitorName}. You can now send messages!`,
        },
      });
    }

    return updated;
  }

  async handoverToAi(conversationId: string, actor: Actor) {
    if (actor.role === Role.INSTRUCTOR) {
      const instructor = await this.db.instructor.findFirst({
        where: {
          OR: [{ userId: actor.id }, { email: actor.email.toLowerCase() }],
        },
      });
      if (!instructor) {
        throw new ForbiddenException(
          "No instructor profile linked to your account.",
        );
      }
      const conv = await this.db.chatConversation.findUnique({
        where: { id: conversationId },
      });
      if (!conv) {
        throw new NotFoundException("Conversation not found");
      }
      if (conv.instructorId !== instructor.id) {
        throw new ForbiddenException(
          "You can only hand over chats assigned to you.",
        );
      }
    }

    const conv = await this.db.chatConversation.update({
      where: { id: conversationId },
      data: {
        status: ChatStatus.AI,
      },
    });

    const staffRole = actor.role === Role.INSTRUCTOR ? "Instructor" : "Admin";
    await this.db.chatMessage.create({
      data: {
        conversationId,
        senderType: ChatSenderType.BOT,
        senderName: "System",
        content: `${actor.name} (${staffRole}) handed conversation back to Dreamtopia AI Assistant. AI auto-reply is now active.`,
      },
    });

    return conv;
  }

  // --- ADMIN & INSTRUCTOR VIEW: CHAT HISTORY ---

  async listConversations(actor: Actor, status?: ChatStatus) {
    if (actor.role === Role.INSTRUCTOR) {
      const instructor = await this.db.instructor.findFirst({
        where: {
          OR: [{ userId: actor.id }, { email: actor.email.toLowerCase() }],
        },
      });
      if (!instructor) {
        return [];
      }
      return this.db.chatConversation.findMany({
        where: {
          instructorId: instructor.id,
        },
        include: {
          user: { select: { id: true, name: true, email: true } },
          assignedAdmin: { select: { id: true, name: true } },
          instructor: { select: { id: true, name: true, specialty: true } },
          messages: {
            orderBy: { createdAt: "desc" },
            take: 1,
          },
        },
        orderBy: { updatedAt: "desc" },
      });
    }

    return this.db.chatConversation.findMany({
      where: status ? { status } : undefined,
      include: {
        user: { select: { id: true, name: true, email: true } },
        assignedAdmin: { select: { id: true, name: true } },
        instructor: { select: { id: true, name: true, specialty: true } },
        messages: {
          orderBy: { createdAt: "desc" },
          take: 1,
        },
      },
      orderBy: { updatedAt: "desc" },
    });
  }

  // --- ANALYTICS: POPULAR QUESTIONS & TOPIC ANALYSIS ---

  async getChatAnalytics() {
    // 1. Most interested FAQ questions (by hitCount)
    const topFaqs = await this.db.faqQuestion.findMany({
      orderBy: { hitCount: "desc" },
      take: 10,
    });

    // 2. Category distribution
    const faqsByCategory = await this.db.faqQuestion.groupBy({
      by: ["category"],
      _sum: { hitCount: true },
      _count: { id: true },
    });

    // 3. User message counts and inquiry breakdown
    const totalConversations = await this.db.chatConversation.count();
    const totalMessages = await this.db.chatMessage.count();
    const waitingAdmin = await this.db.chatConversation.count({
      where: { status: ChatStatus.WAITING_ADMIN },
    });
    const withAdmin = await this.db.chatConversation.count({
      where: { status: ChatStatus.ADMIN_ACTIVE },
    });
    const resolved = await this.db.chatConversation.count({
      where: { status: ChatStatus.RESOLVED },
    });

    // 4. Analysis of customer question queries (aggregate common keyword occurrences)
    const recentUserMessages = await this.db.chatMessage.findMany({
      where: { senderType: ChatSenderType.USER },
      select: { content: true },
      orderBy: { createdAt: "desc" },
      take: 200,
    });

    const keywordCounts: Record<string, number> = {};
    const ignoreWords = new Set([
      "the", "and", "a", "to", "of", "in", "i", "is", "that", "it",
      "on", "you", "this", "for", "but", "with", "are", "have", "be",
      "at", "or", "from", "as", "what", "how", "can", "do", "my", "me",
      "please", "want", "like", "will"
    ]);

    for (const msg of recentUserMessages) {
      const words = msg.content
        .toLowerCase()
        .replace(/[^a-zA-Z0-9\s]/g, " ")
        .split(/\s+/);
      for (const w of words) {
        if (w.length > 2 && !ignoreWords.has(w)) {
          keywordCounts[w] = (keywordCounts[w] || 0) + 1;
        }
      }
    }

    const topCustomerKeywords = Object.entries(keywordCounts)
      .map(([word, count]) => ({ word, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 15);

    return {
      stats: {
        totalConversations,
        totalMessages,
        waitingAdmin,
        withAdmin,
        resolved,
      },
      topInterestedQuestions: topFaqs.map((f) => ({
        id: f.id,
        category: f.category,
        question: f.question,
        hitCount: f.hitCount,
      })),
      categoryAnalytics: faqsByCategory.map((c) => ({
        category: c.category,
        questionsCount: c._count.id,
        totalInterestHits: c._sum.hitCount || 0,
      })),
      topCustomerKeywords,
    };
  }
}
