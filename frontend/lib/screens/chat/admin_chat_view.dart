import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../api.dart';
import '../../theme.dart';

class AdminChatView extends StatefulWidget {
  final Api api;
  final List<dynamic> instructors;
  final void Function(String) onShowMessage;

  const AdminChatView({
    super.key,
    required this.api,
    required this.instructors,
    required this.onShowMessage,
  });

  @override
  State<AdminChatView> createState() => _AdminChatViewState();
}

class _AdminChatViewState extends State<AdminChatView>
    with SingleTickerProviderStateMixin {
  late TabController tabController;
  bool loading = true;
  bool sending = false;

  List<dynamic> conversations = [];
  Map<String, dynamic>? selectedConv;
  Map<String, dynamic>? analytics;

  final TextEditingController replyController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  String filterStatus = 'ALL';
  Timer? pollTimer;

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 2, vsync: this);
    loadAll();
    // Fast live-polling every 1.5s for real-time WebSocket-like experience
    pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (mounted) {
        loadConversationsSilently();
      }
    });
  }

  @override
  void dispose() {
    pollTimer?.cancel();
    tabController.dispose();
    replyController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> loadAll() async {
    setState(() => loading = true);
    await Future.wait([
      loadConversations(),
      loadAnalytics(),
    ]);
    if (mounted) setState(() => loading = false);
  }

  Future<void> loadConversationsSilently() async {
    try {
      final res = await widget.api.call('chat/admin/conversations');
      if (mounted) {
        final newConvList = List.from(res as List);
        Map<String, dynamic>? updatedActive;
        if (selectedConv != null) {
          final updated = await widget.api.call('chat/conversation/${selectedConv!['id']}');
          updatedActive = Map<String, dynamic>.from(updated as Map);
        }
        final oldMsgCount = (selectedConv?['messages'] as List?)?.length ?? 0;
        final newMsgCount = (updatedActive?['messages'] as List?)?.length ?? 0;

        setState(() {
          conversations = newConvList;
          if (updatedActive != null) {
            selectedConv = updatedActive;
          }
        });

        if (newMsgCount > oldMsgCount) {
          scrollBottom();
        }
      }
    } catch (_) {}
  }

  Future<void> loadConversations() async {
    try {
      final res = await widget.api.call('chat/admin/conversations');
      if (mounted) {
        conversations = List.from(res as List);
        if (selectedConv != null) {
          // Refresh active conversation details
          final updated = await widget.api.call('chat/conversation/${selectedConv!['id']}');
          selectedConv = Map<String, dynamic>.from(updated as Map);
        }
      }
    } catch (_) {}
  }

  Future<void> loadAnalytics() async {
    try {
      final res = await widget.api.call('chat/admin/analytics');
      if (mounted) {
        analytics = Map<String, dynamic>.from(res as Map);
      }
    } catch (_) {}
  }

  Future<void> selectConversation(String id) async {
    setState(() => loading = true);
    try {
      final res = await widget.api.call('chat/conversation/$id');
      if (mounted) {
        setState(() {
          selectedConv = Map<String, dynamic>.from(res as Map);
          loading = false;
        });
        scrollBottom();
      }
    } catch (e) {
      if (mounted) setState(() => loading = false);
    }
  }

  void scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent + 60,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Admin replies to customer
  Future<void> sendAdminReply() async {
    if (selectedConv == null) return;
    final text = replyController.text.trim();
    if (text.isEmpty) return;
    replyController.clear();

    setState(() => sending = true);
    try {
      await widget.api.call(
        'chat/conversation/${selectedConv!['id']}/admin-reply',
        method: 'POST',
        body: {'content': text},
      );
      await selectConversation(selectedConv!['id']);
      await loadConversations();
      widget.onShowMessage('Reply sent to customer!');
    } catch (e) {
      widget.onShowMessage('Error sending reply: $e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  // Admin re-direct to instructor
  Future<void> showRedirectInstructorDialog() async {
    if (selectedConv == null) return;
    String? selectedInstructorId = widget.instructors.isNotEmpty
        ? widget.instructors.first['id'].toString()
        : null;
    final noteController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('Re-direct to Instructor'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select an instructor to take over this member\'s inquiry:',
                  style: TextStyle(fontSize: 13, color: muted),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: selectedInstructorId,
                  decoration: const InputDecoration(labelText: 'Instructor'),
                  items: widget.instructors.map((i) {
                    return DropdownMenuItem<String>(
                      value: i['id'].toString(),
                      child: Text('${i['name']} (${i['specialty'] ?? ''})'),
                    );
                  }).toList(),
                  onChanged: (val) => setDlgState(() => selectedInstructorId = val),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'Handoff note (optional)',
                    hintText: 'e.g. Inquiring about private foundation coaching…',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selectedInstructorId == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      try {
                        await widget.api.call(
                          'chat/conversation/${selectedConv!['id']}/redirect-instructor',
                          method: 'POST',
                          body: {
                            'instructorId': selectedInstructorId,
                            'note': noteController.text.trim(),
                          },
                        );
                        await selectConversation(selectedConv!['id']);
                        await loadConversations();
                        widget.onShowMessage('Conversation assigned to instructor!');
                      } catch (e) {
                        widget.onShowMessage('Failed to assign: $e');
                      }
                    },
              child: const Text('Confirm Redirect'),
            ),
          ],
        ),
      ),
    );
  }

  // Admin resolves conversation
  Future<void> resolveConversation() async {
    if (selectedConv == null) return;
    try {
      await widget.api.call(
        'chat/conversation/${selectedConv!['id']}/resolve',
        method: 'POST',
      );
      await selectConversation(selectedConv!['id']);
      await loadConversations();
      widget.onShowMessage('Conversation marked as resolved!');
    } catch (e) {
      widget.onShowMessage('Error resolving: $e');
    }
  }

  // Upload FAQ Excel (.xlsx)
  Future<void> uploadFaqExcel() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;

      final file = res.files.first;
      if (file.bytes == null) {
        widget.onShowMessage('Could not read the selected file.');
        return;
      }

      setState(() => loading = true);
      final uploadRes = await widget.api.uploadGeneric(
        'chat/admin/faq/upload',
        file.bytes!,
        file.name,
      );
      await loadAll();
      widget.onShowMessage(uploadRes['message'] ?? 'FAQ questions updated from Excel!');
    } catch (e) {
      widget.onShowMessage('Upload error: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 768;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Customer Chat Management & Analytics',
                  style: GoogleFonts.cinzel(fontSize: isMobile ? 18 : 22, fontWeight: FontWeight.bold, color: sageGreen),
                ),
                const SizedBox(height: 4),
                Text(
                  'Direct admin messaging, instructor reassignment, Excel Q&A database, and inquiry metrics.',
                  style: GoogleFonts.lato(color: muted, fontSize: isMobile ? 11 : 13),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: uploadFaqExcel,
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: Text(isMobile ? 'Upload FAQ' : 'Update FAQ from Excel'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        TabBar(
          controller: tabController,
          labelColor: plum,
          unselectedLabelColor: muted,
          indicatorColor: plum,
          isScrollable: isMobile,
          tabs: const [
            Tab(icon: Icon(Icons.forum_outlined), text: 'Conversations & Chat History'),
            Tab(icon: Icon(Icons.analytics_outlined), text: 'Interest & Keyword Analysis'),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: isMobile ? 680 : 660,
          child: TabBarView(
            controller: tabController,
            children: [
              _buildConversationsTab(),
              _buildAnalyticsTab(),
            ],
          ),
        ),
      ],
    );
  }

  // --- TAB 1: CONVERSATIONS & LIVE ADMIN MESSAGING ---

  Widget _buildConversationsTab() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 768;

    // Responsive: On mobile, if a conversation is selected, show the chat detail view full width
    if (isMobile && selectedConv != null) {
      return Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
          side: const BorderSide(color: sageBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildChatDetailHeader(isMobile: true),
            Expanded(child: _buildChatDetailMessages()),
            _buildChatDetailReplyBox(),
          ],
        ),
      );
    }

    final listCard = Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
        side: const BorderSide(color: sageBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: DropdownButtonFormField<String>(
              value: filterStatus,
              decoration: InputDecoration(
                labelText: 'Status Filter',
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(3),
                  borderSide: const BorderSide(color: sageBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(3),
                  borderSide: const BorderSide(color: sageBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(3),
                  borderSide: const BorderSide(color: sageGreen, width: 1.5),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'ALL', child: Text('All Conversations')),
                DropdownMenuItem(value: 'WAITING_ADMIN', child: Text('Waiting for Admin')),
                DropdownMenuItem(value: 'ADMIN_ACTIVE', child: Text('Active with Admin')),
                DropdownMenuItem(value: 'REDIRECTED_INSTRUCTOR', child: Text('Redirected to Instructor')),
                DropdownMenuItem(value: 'AI', child: Text('AI / Bot Conversations')),
                DropdownMenuItem(value: 'RESOLVED', child: Text('Resolved')),
              ],
              onChanged: (val) {
                setState(() => filterStatus = val ?? 'ALL');
              },
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: filteredConversations.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: sageBorder),
              itemBuilder: (context, i) {
                final c = filteredConversations[i];
                final isSelected = selectedConv?['id'] == c['id'];
                final status = c['status']?.toString() ?? 'BOT';
                final isWaiting = status == 'WAITING_ADMIN';
                final msgs = (c['messages'] as List?) ?? [];
                final lastMsg = msgs.isNotEmpty ? msgs.first['content'] : 'No messages';

                return ListTile(
                  selected: isSelected,
                  selectedTileColor: sageLight,
                  leading: CircleAvatar(
                    backgroundColor: isWaiting ? Colors.amber.shade200 : sageLight,
                    child: Icon(
                      isWaiting
                          ? Icons.priority_high
                          : status == 'RESOLVED'
                              ? Icons.check
                              : Icons.person_outline,
                      color: isWaiting ? Colors.brown : plum,
                      size: 18,
                    ),
                  ),
                  title: Text(
                    c['visitorName'] ?? 'Guest Member',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  subtitle: Text(
                    lastMsg,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isWaiting ? Colors.red.shade100 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: isWaiting ? Colors.red.shade800 : Colors.black54,
                      ),
                    ),
                  ),
                  onTap: () => selectConversation(c['id']),
                );
              },
            ),
          ),
        ],
      ),
    );

    // Desktop/Tablet dual column
    if (!isMobile) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 320,
            child: listCard,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: selectedConv == null
                ? Center(
                    child: Text(
                      'Select a customer conversation on the left to view history and reply.',
                      style: GoogleFonts.lato(color: muted),
                    ),
                  )
                : Card(
                    elevation: 0,
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(3),
                      side: const BorderSide(color: sageBorder),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildChatDetailHeader(isMobile: false),
                        Expanded(child: _buildChatDetailMessages()),
                        _buildChatDetailReplyBox(),
                      ],
                    ),
                  ),
          ),
        ],
      );
    }

    // Mobile single column (when no conversation is currently selected)
    return listCard;
  }

  List<dynamic> get filteredConversations {
    if (filterStatus == 'ALL') return conversations;
    if (filterStatus == 'REDIRECTED_INSTRUCTOR') {
      return conversations.where((c) => c['instructorId'] != null || c['instructor'] != null).toList();
    }
    return conversations.where((c) => c['status'] == filterStatus).toList();
  }

  Widget _buildChatDetailHeader({bool isMobile = false}) {
    final status = selectedConv!['status'] ?? 'BOT';
    final instructor = selectedConv!['instructor'];
    final isNarrow = MediaQuery.sizeOf(context).width < 900;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 10 : 18,
        vertical: isMobile ? 10 : 14,
      ),
      decoration: const BoxDecoration(
        color: sageLight,
        borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
        border: Border(bottom: BorderSide(color: sageBorder, width: 1.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Back button on mobile to return to conversation list
              if (isMobile) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: charcoal, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Back to conversations list',
                  onPressed: () => setState(() => selectedConv = null),
                ),
                const SizedBox(width: 8),
              ],
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: sageBorder),
                ),
                child: const Icon(Icons.person, color: sageGreen, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            selectedConv!['visitorName'] ?? 'Guest Member',
                            style: GoogleFonts.cinzel(
                              fontSize: isMobile ? 14 : 16,
                              fontWeight: FontWeight.bold,
                              color: charcoal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (selectedConv!['visitorEmail'] != null && !isMobile) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '•  ${selectedConv!['visitorEmail']}',
                              style: const TextStyle(fontSize: 12, color: muted),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: status == 'WAITING_ADMIN'
                                ? Colors.red.shade50
                                : status == 'RESOLVED'
                                    ? Colors.grey.shade100
                                    : sageGreen.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: status == 'WAITING_ADMIN'
                                  ? Colors.red.shade200
                                  : status == 'RESOLVED'
                                      ? Colors.grey.shade300
                                      : sageGreen.withOpacity(0.3),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: status == 'WAITING_ADMIN'
                                  ? Colors.red.shade800
                                  : status == 'RESOLVED'
                                      ? Colors.grey.shade700
                                      : sageGreen,
                            ),
                          ),
                        ),
                        if (instructor != null) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Assigned: ${instructor['name']}',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: sageGreen,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (!isMobile) ...[
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: showRedirectInstructorDialog,
                      icon: const Icon(Icons.person_pin, size: 15),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      label: Text(
                        isNarrow ? 'Re-direct' : 'Re-direct to Instructor',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: status == 'RESOLVED' ? null : resolveConversation,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      child: const Text('Resolve', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ],
          ),
          // On mobile, show action buttons below user info in a clean row
          if (isMobile) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: showRedirectInstructorDialog,
                    icon: const Icon(Icons.person_pin, size: 14),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    label: const Text('Re-direct', style: TextStyle(fontSize: 11)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: status == 'RESOLVED' ? null : resolveConversation,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    child: const Text('Resolve', style: TextStyle(fontSize: 11)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatDateTime(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return DateFormat('d MMM, HH:mm').format(dt);
    } catch (_) {
      final s = raw.toString();
      return s.length >= 16 ? s.substring(0, 16).replaceAll('T', ' ') : s;
    }
  }

  Widget _buildChatDetailMessages() {
    final msgs = (selectedConv!['messages'] as List?) ?? [];
    if (msgs.isEmpty) {
      return const Center(child: Text('No messages yet.'));
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: msgs.length,
      itemBuilder: (context, i) {
        final m = msgs[i];
        final type = m['senderType']?.toString() ?? 'USER';
        final isUser = type == 'USER';
        final isAdminMsg = type == 'ADMIN' || type == 'INSTRUCTOR';
        final isAi = type == 'AI';
        final timeStr = _formatDateTime(m['createdAt']);

        final screenWidth = MediaQuery.sizeOf(context).width;
        final isMobile = screenWidth < 768;

        return Align(
          alignment: isUser ? Alignment.centerLeft : Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            constraints: BoxConstraints(
              maxWidth: screenWidth * (isMobile ? 0.82 : 0.45),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isUser
                  ? Colors.grey.shade100
                  : isAdminMsg
                      ? sageLight
                      : isAi
                          ? Colors.purple.shade50
                          : Colors.amber.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isUser
                    ? sageBorder
                    : isAdminMsg
                        ? sageGreen
                        : isAi
                            ? Colors.purple.shade200
                            : Colors.amber.shade300,
              ),
            ),
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      m['senderName'] ?? type,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isAdminMsg ? sageGreen : isAi ? Colors.purple : muted,
                      ),
                    ),
                    if (timeStr.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        timeStr,
                        style: const TextStyle(fontSize: 10, color: muted),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                SelectableText(
                  m['content'] ?? '',
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChatDetailReplyBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(3)),
        border: Border(top: BorderSide(color: sageBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: replyController,
              decoration: InputDecoration(
                hintText: 'Type your admin reply to this customer…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(3),
                  borderSide: const BorderSide(color: sageBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(3),
                  borderSide: const BorderSide(color: sageBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(3),
                  borderSide: const BorderSide(color: sageGreen, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onSubmitted: (_) => sendAdminReply(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: sending ? null : sendAdminReply,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            icon: const Icon(Icons.send, size: 16),
            label: Text(sending ? 'Sending…' : 'Send Reply'),
          ),
        ],
      ),
    );
  }

  // --- TAB 2: ANALYTICS & FREQUENTLY ASKED QUESTIONS ---

  Widget _buildAnalyticsTab() {
    if (analytics == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final stats = analytics!['stats'] as Map? ?? {};
    final topQuestions = (analytics!['topInterestedQuestions'] as List?) ?? [];
    final categoryAnalytics = (analytics!['categoryAnalytics'] as List?) ?? [];
    final topKeywords = (analytics!['topCustomerKeywords'] as List?) ?? [];

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 768;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 4 Key metrics matching the style of the 3 stat cards under Create Session button (centered content)
          if (isMobile)
            Column(
              children: [
                Row(
                  children: [
                    _metricTile('Total Inquiries', '${stats['totalConversations'] ?? 0}', 'All conversation threads', sageGreen),
                    const SizedBox(width: 10),
                    _metricTile('Needs Admin', '${stats['waitingAdmin'] ?? 0}', 'Waiting for staff', Colors.amber.shade800),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _metricTile('Active Admin', '${stats['withAdmin'] ?? 0}', 'In conversation', chakra[1]),
                    const SizedBox(width: 10),
                    _metricTile('Resolved', '${stats['resolved'] ?? 0}', 'Closed inquiries', Colors.teal),
                  ],
                ),
              ],
            )
          else
            Row(
              children: [
                _metricTile('Total Inquiries', '${stats['totalConversations'] ?? 0}', 'All conversation threads', sageGreen),
                const SizedBox(width: 12),
                _metricTile('Needs Admin', '${stats['waitingAdmin'] ?? 0}', 'Waiting for staff', Colors.amber.shade800),
                const SizedBox(width: 12),
                _metricTile('Active Admin', '${stats['withAdmin'] ?? 0}', 'In conversation', chakra[1]),
                const SizedBox(width: 12),
                _metricTile('Resolved', '${stats['resolved'] ?? 0}', 'Closed inquiries', Colors.teal),
              ],
            ),
          const SizedBox(height: 20),

          // Two analytical cards (Stacked on mobile, side-by-side on wide screens)
          Flex(
            direction: isMobile ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Most Interested Default Questions (Interest Count)
              Expanded(
                flex: isMobile ? 0 : 3,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: sageBorder.withOpacity(0.7)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with subtle sageLight background & accent badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: const BoxDecoration(
                          color: sageLight,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
                          border: Border(bottom: BorderSide(color: sageBorder, width: 1)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: gold.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Icon(Icons.trending_up, color: gold, size: 16),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Most Interested FAQ Questions',
                                    style: GoogleFonts.cinzel(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: ink,
                                    ),
                                  ),
                                  const Text(
                                    'Ranked by member inquiries and tap count',
                                    style: TextStyle(fontSize: 10.5, color: muted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: topQuestions.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                  child: Text('No question engagement recorded yet.', style: TextStyle(color: muted, fontSize: 12)),
                                ),
                              )
                            : Column(
                                children: topQuestions.map((q) {
                                  final hitCount = q['hitCount'] ?? 0;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFCFBF9),
                                      borderRadius: BorderRadius.circular(3),
                                      border: Border.all(color: sageBorder.withOpacity(0.55)),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: gold.withOpacity(0.14),
                                            borderRadius: BorderRadius.circular(3),
                                            border: Border.all(color: gold.withOpacity(0.4), width: 0.8),
                                          ),
                                          child: Text(
                                            '★ $hitCount',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                              color: gold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                q['question'] ?? '',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                  color: ink,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                    decoration: BoxDecoration(
                                                      color: sageLight,
                                                      borderRadius: BorderRadius.circular(2),
                                                    ),
                                                    child: Text(
                                                      'Category: ${q['category']}',
                                                      style: const TextStyle(fontSize: 10, color: muted, fontWeight: FontWeight.w500),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              if (isMobile)
                const SizedBox(height: 14)
              else
                const SizedBox(width: 14),

              // 2. Customer Inquiries Keywords & Category Breakdown Analysis
              Expanded(
                flex: isMobile ? 0 : 2,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: sageBorder.withOpacity(0.7)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with subtle sageLight background & accent badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: const BoxDecoration(
                          color: sageLight,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
                          border: Border(bottom: BorderSide(color: sageBorder, width: 1)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: sageGreen.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Icon(Icons.pie_chart_outline, color: sageGreen, size: 16),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Inquiries & Keywords Analysis',
                                    style: GoogleFonts.cinzel(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: ink,
                                    ),
                                  ),
                                  const Text(
                                    'Trending terms and topic volume breakdown',
                                    style: TextStyle(fontSize: 10.5, color: muted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Frequent keywords in customer inquiries:',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: muted),
                            ),
                            const SizedBox(height: 10),
                            if (topKeywords.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('No keywords extracted yet.', style: TextStyle(color: muted, fontSize: 12)),
                              )
                            else
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: topKeywords.map((k) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: sageLight,
                                      borderRadius: BorderRadius.circular(3),
                                      border: Border.all(color: sageBorder),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${k['word']}',
                                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: ink),
                                        ),
                                        const SizedBox(width: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: sageGreen.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                          child: Text(
                                            '${k['count']}',
                                            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: sageGreen),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            const SizedBox(height: 20),
                            const Divider(height: 1, color: sageBorder),
                            const SizedBox(height: 14),
                            Text(
                              'Topic Volume Breakdown:',
                              style: GoogleFonts.lato(fontSize: 12, fontWeight: FontWeight.bold, color: ink),
                            ),
                            const SizedBox(height: 10),
                            if (categoryAnalytics.isEmpty)
                              const Text('No topic breakdown available.', style: TextStyle(color: muted, fontSize: 12))
                            else
                              for (final cat in categoryAnalytics) ...[
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('${cat['category']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ink)),
                                          Text(
                                            '${cat['totalInterestHits']} hits (${cat['questionsCount']} questions)',
                                            style: const TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(2),
                                        child: LinearProgressIndicator(
                                          value: 0.6,
                                          minHeight: 4,
                                          backgroundColor: sageLight,
                                          valueColor: const AlwaysStoppedAnimation<Color>(sageGreen),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricTile(String title, String value, String subtitle, Color accentColor) {
    return Expanded(
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: sageBorder.withOpacity(0.7),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: accentColor, width: 4),
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: ink,
                      fontFamily: GoogleFonts.cinzel().fontFamily,
                    ),
                    maxLines: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: muted, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
