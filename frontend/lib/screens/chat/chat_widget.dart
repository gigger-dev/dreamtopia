import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../api.dart';
import '../../theme.dart';

class ChatWidget extends StatefulWidget {
  final Api api;
  final Map<String, dynamic>? currentUser;

  const ChatWidget({
    super.key,
    required this.api,
    this.currentUser,
  });

  @override
  State<ChatWidget> createState() => _ChatWidgetState();
}

class _ChatWidgetState extends State<ChatWidget>
    with SingleTickerProviderStateMixin {
  bool isOpen = false;
  bool isMinimized = false;
  bool loading = false;
  bool sending = false;

  late AnimationController animController;
  late Animation<Offset> slideAnimation;
  late Animation<double> fadeAnimation;

  String? conversationId;
  String? conversationStatus; // BOT, AI, WAITING_ADMIN, ADMIN_ACTIVE, RESOLVED
  String? instructorName;

  List<dynamic> messages = [];
  Map<String, dynamic> faqData = {'categories': {}, 'popularQuestions': []};
  String activeCategory = '';

  final TextEditingController textController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  Timer? pollTimer;

  bool get isAdmin => widget.currentUser?['role'] == 'ADMIN';

  @override
  void initState() {
    super.initState();
    animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
    fadeAnimation = CurvedAnimation(
      parent: animController,
      curve: Curves.easeOut,
    );
    loadFaqs();
  }

  @override
  void dispose() {
    animController.dispose();
    pollTimer?.cancel();
    textController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> loadFaqs() async {
    try {
      final res = await widget.api.call('chat/faq');
      if (mounted) {
        setState(() {
          faqData = Map<String, dynamic>.from(res as Map);
          final cats = (faqData['categories'] as Map?)?.keys.toList() ?? [];
          if (cats.isNotEmpty) activeCategory = cats.first.toString();
        });
      }
    } catch (_) {}
  }

  Future<void> initConversation() async {
    setState(() => loading = true);
    try {
      final res = await widget.api.call('chat/conversation/start', method: 'POST', body: {
        'visitorName': widget.currentUser?['name'] ?? 'Guest Member',
        'visitorEmail': widget.currentUser?['email'],
      });
      if (mounted) {
        final conv = res as Map<String, dynamic>;
        conversationId = conv['id'] as String;
        conversationStatus = conv['status'] as String?;
        messages = List.from(conv['messages'] ?? []);
        if (conv['instructor'] != null) {
          instructorName = conv['instructor']['name'] as String?;
        }
        loading = false;
        setState(() {});
        startPolling();
        scrollToBottom();
      }
    } catch (e) {
      if (mounted) setState(() => loading = false);
    }
  }

  void startPolling() {
    pollTimer?.cancel();
    pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      if (conversationId == null || !isOpen) return;
      try {
        final res = await widget.api.call('chat/conversation/$conversationId');
        if (mounted) {
          final conv = res as Map<String, dynamic>;
          final newMsgs = List.from(conv['messages'] ?? []);
          final newStatus = conv['status'] as String?;
          final newInstructor = conv['instructor']?['name'] as String?;
          
          if (newMsgs.length != messages.length || newStatus != conversationStatus) {
            setState(() {
              messages = newMsgs;
              conversationStatus = newStatus;
              instructorName = newInstructor;
            });
            scrollToBottom();
          }
        }
      } catch (_) {}
    });
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // FLOW 1: FAQ Selected
  Future<void> onSelectFaq(String faqId) async {
    if (conversationId == null) await initConversation();
    if (conversationId == null) return;

    setState(() => sending = true);
    try {
      final res = await widget.api.call(
        'chat/conversation/$conversationId/faq-answer',
        method: 'POST',
        body: {'faqId': faqId},
      );
      if (mounted) {
        // Refresh FAQ interest counts in background
        loadFaqs();
        final botMsg = (res as Map)['message'];
        final faq = res['faq'];
        setState(() {
          messages.add({
            'senderType': 'USER',
            'senderName': widget.currentUser?['name'] ?? 'You',
            'content': faq['question'],
          });
          messages.add(botMsg);
          sending = false;
        });
        scrollToBottom();
      }
    } catch (e) {
      if (mounted) setState(() => sending = false);
    }
  }

  // FLOW 2: Ask AI (Gemini)
  Future<void> onSendAi() async {
    final query = textController.text.trim();
    if (query.isEmpty) return;
    textController.clear();

    if (conversationId == null) await initConversation();
    if (conversationId == null) return;

    setState(() {
      messages.add({
        'senderType': 'USER',
        'senderName': widget.currentUser?['name'] ?? 'You',
        'content': query,
      });
      sending = true;
      if (conversationStatus != 'ADMIN_ACTIVE' &&
          conversationStatus != 'WAITING_ADMIN') {
        conversationStatus = 'AI';
      }
    });
    scrollToBottom();

    try {
      final res = await widget.api.call(
        'chat/conversation/$conversationId/ask-ai',
        method: 'POST',
        body: {
          'message': query,
          'senderName': widget.currentUser?['name'] ?? 'Customer',
        },
      );
      if (mounted) {
        setState(() {
          sending = false;
          // Only add response if AI actually replied (res is AI/BOT and not user echo)
          if (res is Map<String, dynamic> &&
              res['senderType'] != 'USER' &&
              res['aiReplyClosed'] != true) {
            messages.add(res);
          }
        });
        scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          sending = false;
          messages.add({
            'senderType': 'BOT',
            'senderName': 'System',
            'content': 'Unable to connect to AI assistant. Please try requesting admin support.',
          });
        });
        scrollToBottom();
      }
    }
  }

  // FLOW 3: Request Human Admin
  Future<void> onRequestAdmin() async {
    if (conversationId == null) await initConversation();
    if (conversationId == null) return;

    setState(() => sending = true);
    try {
      await widget.api.call(
        'chat/conversation/$conversationId/request-admin',
        method: 'POST',
        body: {'note': 'Customer requested live admin support.'},
      );
      if (mounted) {
        setState(() {
          conversationStatus = 'WAITING_ADMIN';
          messages.add({
            'senderType': 'BOT',
            'senderName': 'System',
            'content': 'Connecting you to studio staff! An admin will join your conversation shortly.',
          });
          sending = false;
        });
        scrollToBottom();
      }
    } catch (_) {
      if (mounted) setState(() => sending = false);
    }
  }

  void openChat() {
    setState(() => isOpen = true);
    animController.forward();
    if (conversationId == null) {
      initConversation();
    }
  }

  void closeChat() {
    animController.reverse().then((_) {
      if (mounted) setState(() => isOpen = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!isOpen) {
      return Positioned(
        bottom: 24,
        right: 24,
        child: FloatingActionButton(
          heroTag: 'chat_fab',
          backgroundColor: plum,
          foregroundColor: Colors.white,
          elevation: 6,
          shape: const CircleBorder(),
          tooltip: 'Open Chat',
          onPressed: openChat,
          child: const Icon(Icons.chat_bubble_outline_rounded, size: 26),
        ),
      );
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final isMobile = screenWidth < 600;
    final double chatHeight = isMobile ? screenHeight * 0.85 : 620;

    return Stack(
      children: [
        // Semi-transparent light grey backdrop covering the entire screen & topbar with FadeTransition
        Positioned.fill(
          child: FadeTransition(
            opacity: fadeAnimation,
            child: GestureDetector(
              onTap: closeChat,
              child: Container(
                color: Colors.black.withOpacity(0.24),
              ),
            ),
          ),
        ),
        // Full width chat box with SlideTransition from bottom
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SlideTransition(
            position: slideAnimation,
            child: Material(
              elevation: 24,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              color: Colors.white,
              child: Container(
                width: double.infinity,
                height: chatHeight,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                  border: Border(
                    top: BorderSide(color: sageBorder, width: 1.5),
                    left: BorderSide(color: sageBorder),
                    right: BorderSide(color: sageBorder),
                  ),
                ),
              child: Column(
                children: [
                  _buildHeader(),
                  _buildStatusBanner(),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : Column(
                            children: [
                              Expanded(child: _buildMessagesList()),
                              if (sending)
                                const LinearProgressIndicator(
                                  minHeight: 2,
                                  color: plum,
                                  backgroundColor: sageLight,
                                ),
                              _buildFaqQuickPills(),
                              _buildInputArea(),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: sageGreen,
        borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dreamtopia Assistant',
                  style: GoogleFonts.cinzel(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  conversationStatus == 'WAITING_ADMIN'
                      ? 'Waiting for studio admin…'
                      : conversationStatus == 'ADMIN_ACTIVE'
                          ? (instructorName != null
                              ? 'Assigned to Instructor $instructorName'
                              : 'Chatting with Studio Admin')
                          : 'FAQ & AI Assistant (Gemini)',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            onPressed: closeChat,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    if (conversationStatus == 'WAITING_ADMIN') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: Colors.amber.shade100,
        child: Row(
          children: const [
            Icon(Icons.hourglass_top, size: 14, color: Colors.brown),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Connecting to an administrator. Please hold on!',
                style: TextStyle(fontSize: 11, color: Colors.brown, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }
    if (conversationStatus == 'ADMIN_ACTIVE') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: Colors.green.shade50,
        child: Row(
          children: [
            const Icon(Icons.verified_user, size: 14, color: sageGreen),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                instructorName != null
                  ? 'Redirected to Instructor $instructorName • AI Paused'
                  : 'Live chat active with Studio Admin • AI Paused',
                style: const TextStyle(fontSize: 11, color: sageGreen, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildFaqQuickPills() {
    final popQuestions = (faqData['popularQuestions'] as List?) ?? [];
    final topQuestions = popQuestions.take(3).toList();

    return Container(
      decoration: const BoxDecoration(
        color: sageLight,
        border: Border(
          top: BorderSide(color: sageBorder),
          bottom: BorderSide(color: sageBorder),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (topQuestions.isNotEmpty) ...[
            Row(
              children: const [
                Icon(Icons.local_fire_department, size: 12, color: plum),
                SizedBox(width: 4),
                Text(
                  'Top FAQs (Tap to ask):',
                  style: TextStyle(fontSize: 10, color: muted, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 110),
              child: SingleChildScrollView(
                child: Column(
                  children: topQuestions.map((q) {
                    final id = q['id'].toString();
                    final text = q['question'].toString();
                    final hits = q['hitCount'] ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: InkWell(
                        onTap: () => onSelectFaq(id),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: sageBorder),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: gold.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '★$hits',
                                  style: const TextStyle(fontSize: 9, color: gold, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, color: charcoal),
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios, size: 10, color: muted),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 5),
          ],
          // Always visible human admin assistance prompt under default messages
          InkWell(
            onTap: onRequestAdmin,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: sageGreen.withOpacity(0.35)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: const [
                  Icon(Icons.headset_mic_rounded, size: 15, color: sageGreen),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Need help from our team? Connect to a human admin',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: sageGreen,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward, size: 13, color: sageGreen),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(dynamic raw) {
    if (raw == null) {
      final now = DateTime.now();
      return DateFormat('d MMM, HH:mm').format(now);
    }
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return DateFormat('d MMM, HH:mm').format(dt);
    } catch (_) {
      final s = raw.toString();
      return s.length >= 16 ? s.substring(0, 16).replaceAll('T', ' ') : s;
    }
  }

  Widget _buildMessagesList() {
    if (messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline, size: 40, color: sageBorder),
              const SizedBox(height: 12),
              Text(
                'Welcome to Dreamtopia!',
                style: GoogleFonts.cinzel(fontSize: 15, fontWeight: FontWeight.bold, color: plum),
              ),
              const SizedBox(height: 6),
              const Text(
                'Click a popular FAQ question above, ask our AI assistant any question, or request human admin assistance directly!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final m = messages[index];
        final type = m['senderType']?.toString() ?? 'BOT';
        final isUser = type == 'USER';
        final isAi = type == 'AI';
        final isAdminMsg = type == 'ADMIN' || type == 'INSTRUCTOR';
        final senderName = m['senderName']?.toString() ?? 'Bot';
        final content = m['content']?.toString() ?? '';
        final timeStr = _formatDateTime(m['createdAt']);

        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.72,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isUser
                  ? sageLight
                  : isAdminMsg
                      ? Colors.teal.shade50
                      : isAi
                          ? Colors.purple.shade50
                          : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isUser
                    ? sageGreen
                    : isAdminMsg
                        ? Colors.teal.shade300
                        : isAi
                            ? Colors.purple.shade200
                            : sageBorder,
                width: isUser ? 1.2 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isUser) ...[
                      Icon(
                        isAdminMsg
                            ? Icons.verified
                            : isAi
                                ? Icons.auto_awesome
                                : Icons.smart_toy_outlined,
                        size: 13,
                        color: isAdminMsg ? Colors.teal : isAi ? Colors.purple : sageGreen,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      senderName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isUser ? sageGreen : isAdminMsg ? Colors.teal.shade800 : isAi ? Colors.purple : muted,
                      ),
                    ),
                    if (timeStr.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: muted.withOpacity(0.85),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                SelectableText(
                  content,
                  style: const TextStyle(
                    fontSize: 13,
                    color: charcoal,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: sageBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: textController,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Ask AI or type your question…',
                hintStyle: TextStyle(fontSize: 12, color: muted),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              onSubmitted: (_) => onSendAi(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send_rounded, color: plum),
            tooltip: 'Send message (AI Flow)',
            onPressed: sending ? null : onSendAi,
          ),
        ],
      ),
    );
  }
}
