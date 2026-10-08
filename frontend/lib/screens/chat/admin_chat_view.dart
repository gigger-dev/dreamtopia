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
  final bool isInstructor;

  const AdminChatView({
    super.key,
    required this.api,
    this.instructors = const [],
    required this.onShowMessage,
    this.isInstructor = false,
  });

  @override
  State<AdminChatView> createState() => _AdminChatViewState();
}

class _AdminChatViewState extends State<AdminChatView>
    with SingleTickerProviderStateMixin {
  TabController? tabController;
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
    if (!widget.isInstructor) {
      tabController = TabController(length: 2, vsync: this);
    }
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
    tabController?.dispose();
    replyController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> loadAll() async {
    setState(() => loading = true);
    if (widget.isInstructor) {
      await loadConversations();
    } else {
      await Future.wait([
        loadConversations(),
        loadAnalytics(),
      ]);
    }
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

  // Hand over conversation to AI (re-opens AI auto-reply)
  Future<void> handoverToAi() async {
    if (selectedConv == null) return;
    try {
      await widget.api.call(
        'chat/conversation/${selectedConv!['id']}/handover-ai',
        method: 'POST',
      );
      await selectConversation(selectedConv!['id']);
      await loadConversations();
      widget.onShowMessage('Conversation returned to AI. AI auto-reply is now active!');
    } catch (e) {
      widget.onShowMessage('Error handing over: $e');
    }
  }

  // Instructor requests permission from Admin to re-open chat with customer
  Future<void> showRequestPermissionDialog() async {
    if (selectedConv == null) return;
    final reasonController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: Row(
          children: const [
            Icon(Icons.vpn_key_outlined, color: sageGreen, size: 22),
            SizedBox(width: 8),
            Text('Request Permission from Admin', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This inquiry with ${selectedConv!['visitorName'] ?? 'Member'} was previously resolved. To send messages to this customer again, please submit a permission request to the admin.',
                style: const TextStyle(fontSize: 13, color: muted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Reason for follow-up (optional)',
                  hintText: 'e.g. Customer inquired about upcoming choreography sessions...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(3),
                    borderSide: const BorderSide(color: sageBorder),
                  ),
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
          FilledButton.icon(
            icon: const Icon(Icons.send, size: 15),
            label: const Text('Submit Request'),
            style: FilledButton.styleFrom(
              backgroundColor: sageGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await widget.api.call(
                  'chat/conversation/${selectedConv!['id']}/request-reopen-permission',
                  method: 'POST',
                  body: {
                    'reason': reasonController.text.trim().isEmpty
                        ? 'Follow-up customer inquiry'
                        : reasonController.text.trim(),
                  },
                );
                await selectConversation(selectedConv!['id']);
                await loadConversations();
                widget.onShowMessage('Permission request submitted to Admin!');
              } catch (e) {
                widget.onShowMessage('Failed to request permission: $e');
              }
            },
          ),
        ],
      ),
    );
  }

  // Admin reviews instructor's request and decides on time-gap history sharing
  Future<void> showGrantPermissionDialog() async {
    if (selectedConv == null) return;
    bool shareGapHistory = true;

    final instructorName = selectedConv!['instructor']?['name'] ?? 'Instructor';
    final customerName = selectedConv!['visitorName'] ?? 'Customer';
    final reason = selectedConv!['instructorPermissionReason'] ?? 'Follow-up inquiry';
    final resolvedAt = _formatDateTime(selectedConv!['resolvedAt']);
    final requestedAt = _formatDateTime(selectedConv!['instructorPermissionRequestedAt']);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          title: Row(
            children: [
              Icon(Icons.verified_user_outlined, color: Colors.amber.shade900, size: 22),
              const SizedBox(width: 8),
              const Text('Grant Chat Permission', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Instructor $instructorName is requesting permission to resume chatting with $customerName.',
                  style: const TextStyle(fontSize: 13, color: charcoal),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: sageBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Reason: "$reason"', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                      const SizedBox(height: 4),
                      if (resolvedAt.isNotEmpty)
                        Text('Resolved on: $resolvedAt', style: const TextStyle(fontSize: 11, color: muted)),
                      if (requestedAt.isNotEmpty)
                        Text('Permission requested: $requestedAt', style: const TextStyle(fontSize: 11, color: muted)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.access_time_rounded, size: 18, color: Colors.amber.shade900),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Time Gap Privacy: Admin or customer may have exchanged messages between the time the instructor resolved the chat and now. Decide whether to share those messages with the instructor:',
                          style: TextStyle(fontSize: 12, color: Colors.amber.shade900, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                RadioListTile<bool>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: sageGreen,
                  value: true,
                  groupValue: shareGapHistory,
                  title: const Text('Share time-gap messages with instructor', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Instructor can view all messages exchanged with customer during the time gap.', style: TextStyle(fontSize: 11, color: muted)),
                  onChanged: (val) => setDlgState(() => shareGapHistory = val ?? true),
                ),
                RadioListTile<bool>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: sageGreen,
                  value: false,
                  groupValue: shareGapHistory,
                  title: const Text('Hide time-gap messages from instructor', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Messages exchanged during the gap remain private between Admin & Customer only.', style: TextStyle(fontSize: 11, color: muted)),
                  onChanged: (val) => setDlgState(() => shareGapHistory = val ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('Grant Permission'),
              style: FilledButton.styleFrom(
                backgroundColor: sageGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await widget.api.call(
                    'chat/conversation/${selectedConv!['id']}/grant-reopen-permission',
                    method: 'POST',
                    body: {'shareGapHistory': shareGapHistory},
                  );
                  await selectConversation(selectedConv!['id']);
                  await loadConversations();
                  widget.onShowMessage('Permission granted! Instructor can now message customer.');
                } catch (e) {
                  widget.onShowMessage('Failed to grant permission: $e');
                }
              },
            ),
          ],
        ),
      ),
    );
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
                  widget.isInstructor
                      ? 'Assigned Customer Chats'
                      : 'Customer Chat Management & Analytics',
                  style: GoogleFonts.cinzel(fontSize: isMobile ? 18 : 22, fontWeight: FontWeight.bold, color: sageGreen),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.isInstructor
                      ? 'Customer inquiries redirected to you by studio admin.'
                      : 'Direct admin messaging, instructor reassignment, Excel Q&A database, and inquiry metrics.',
                  style: GoogleFonts.lato(color: muted, fontSize: isMobile ? 11 : 13),
                ),
              ],
            ),
            if (!widget.isInstructor)
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
        if (widget.isInstructor)
          SizedBox(
            height: isMobile ? 680 : 660,
            child: _buildConversationsTab(),
          )
        else ...[
          if (tabController != null)
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
            _buildPermissionRequestBanner(),
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
          if (!widget.isInstructor)
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
                  DropdownMenuItem(value: 'PERMISSION_REQUESTS', child: Text('⚠️ Permission Requests Pending')),
                  DropdownMenuItem(value: 'REDIRECTED_INSTRUCTOR', child: Text('Redirected to Instructor')),
                  DropdownMenuItem(value: 'AI', child: Text('AI / Bot Conversations')),
                  DropdownMenuItem(value: 'RESOLVED', child: Text('Resolved')),
                ],
                onChanged: (val) {
                  setState(() => filterStatus = val ?? 'ALL');
                },
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: const BoxDecoration(
                color: sageLight,
                border: Border(bottom: BorderSide(color: sageBorder)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.forum_outlined, size: 16, color: sageGreen),
                  const SizedBox(width: 8),
                  Text(
                    'Assigned Inquiries',
                    style: GoogleFonts.cinzel(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: charcoal,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: sageBorder),
                    ),
                    child: Text(
                      '${conversations.length} Active',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: sageGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: filteredConversations.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.isInstructor
                                ? Icons.mark_chat_read_outlined
                                : Icons.chat_bubble_outline,
                            size: 38,
                            color: muted,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.isInstructor
                                ? 'No Assigned Chats'
                                : 'No Conversations Found',
                            style: GoogleFonts.cinzel(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: charcoal,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.isInstructor
                                ? 'Customer chats redirected to you by studio admin will appear here in real time.'
                                : 'Incoming chats will appear here.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, color: muted),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: filteredConversations.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: sageBorder),
                    itemBuilder: (context, i) {
                      final c = filteredConversations[i];
                      final isSelected = selectedConv?['id'] == c['id'];
                      final status = c['status']?.toString() ?? 'BOT';
                      final isWaiting = status == 'WAITING_ADMIN';
                      final msgs = (c['messages'] as List?) ?? [];
                      final lastMsg = msgs.isNotEmpty ? msgs.first['content'] : 'No messages';

                        final isReqPerm = c['instructorPermissionRequested'] == true;
                        final isInstructorLocked = widget.isInstructor && (
                          status == 'RESOLVED' ||
                          (c['resolvedByRole'] == 'INSTRUCTOR' && c['instructorPermissionGranted'] != true)
                        );

                        return ListTile(
                          selected: isSelected,
                          selectedTileColor: sageLight,
                          leading: CircleAvatar(
                            backgroundColor: isReqPerm
                                ? Colors.amber.shade200
                                : isWaiting
                                    ? Colors.amber.shade200
                                    : sageLight,
                            child: Icon(
                              isReqPerm
                                  ? Icons.vpn_key
                                  : isWaiting
                                      ? Icons.priority_high
                                      : status == 'RESOLVED'
                                          ? Icons.check
                                          : Icons.person_outline,
                              color: isReqPerm
                                  ? Colors.amber.shade900
                                  : isWaiting
                                      ? Colors.brown
                                      : plum,
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
                          trailing: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (isReqPerm) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(color: Colors.amber.shade400, width: 0.8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.vpn_key, size: 9, color: Colors.amber.shade900),
                                      const SizedBox(width: 3),
                                      Text(
                                        'REQ PERM',
                                        style: TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amber.shade900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 3),
                              ],
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isWaiting
                                      ? Colors.red.shade100
                                      : isInstructorLocked
                                          ? Colors.grey.shade200
                                          : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  isInstructorLocked ? 'LOCKED' : status,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: isWaiting
                                        ? Colors.red.shade800
                                        : isInstructorLocked
                                            ? Colors.brown.shade700
                                            : Colors.black54,
                                  ),
                                ),
                              ),
                            ],
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
                      widget.isInstructor
                          ? 'Select an assigned customer conversation on the left to view history and reply.'
                          : 'Select a customer conversation on the left to view history and reply.',
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
                        _buildPermissionRequestBanner(),
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
    if (widget.isInstructor) return conversations;
    if (filterStatus == 'ALL') return conversations;
    if (filterStatus == 'PERMISSION_REQUESTS') {
      return conversations.where((c) => c['instructorPermissionRequested'] == true).toList();
    }
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
                            status == 'ADMIN_ACTIVE'
                                ? 'ACTIVE (AI PAUSED)'
                                : status == 'WAITING_ADMIN'
                                    ? 'WAITING STAFF'
                                    : status == 'RESOLVED'
                                        ? 'RESOLVED'
                                        : 'AI ACTIVE',
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
                              widget.isInstructor
                                  ? 'Assigned to you'
                                  : 'Assigned: ${instructor['name']}',
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
                Flexible(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (!widget.isInstructor)
                        OutlinedButton.icon(
                          onPressed: showRedirectInstructorDialog,
                          icon: const Icon(Icons.person_pin, size: 14),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          label: Text(
                            isNarrow ? 'Re-direct' : 'Re-direct to Instructor',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                      if (status == 'ADMIN_ACTIVE')
                        OutlinedButton.icon(
                          onPressed: handoverToAi,
                          icon: const Icon(Icons.smart_toy_outlined, size: 14),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          label: Text(
                            isNarrow ? 'To AI' : 'Handover to AI',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                      FilledButton.tonal(
                        onPressed: status == 'RESOLVED' ? null : resolveConversation,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        child: const Text('Resolve', style: TextStyle(fontSize: 11.5)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          // On mobile or narrow widths, show action buttons below user info in a wrap
          if (isMobile) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (!widget.isInstructor)
                  OutlinedButton.icon(
                    onPressed: showRedirectInstructorDialog,
                    icon: const Icon(Icons.person_pin, size: 13),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    label: const Text('Re-direct', style: TextStyle(fontSize: 11)),
                  ),
                if (status == 'ADMIN_ACTIVE')
                  OutlinedButton.icon(
                    onPressed: handoverToAi,
                    icon: const Icon(Icons.smart_toy_outlined, size: 13),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    label: const Text('To AI', style: TextStyle(fontSize: 11)),
                  ),
                FilledButton.tonal(
                  onPressed: status == 'RESOLVED' ? null : resolveConversation,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  child: const Text('Resolve', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPermissionRequestBanner() {
    if (selectedConv == null) return const SizedBox.shrink();

    // 1. Admin view: Instructor requested permission
    if (!widget.isInstructor && selectedConv!['instructorPermissionRequested'] == true) {
      final insName = selectedConv!['instructor']?['name'] ?? 'Instructor';
      final reason = selectedConv!['instructorPermissionReason'] ?? 'Follow-up inquiry';
      final reqTime = _formatDateTime(selectedConv!['instructorPermissionRequestedAt']);

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.amber.shade400, width: 1.2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Icon(Icons.vpn_key_rounded, size: 20, color: Colors.amber.shade900),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        'Instructor $insName requested permission to re-open chat',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade800,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const Text(
                          'ACTION REQUIRED',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Reason: "$reason"${reqTime.isNotEmpty ? " • Requested: $reqTime" : ""}',
                    style: TextStyle(fontSize: 11.5, color: Colors.brown.shade800),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: showGrantPermissionDialog,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.amber.shade900,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              icon: const Icon(Icons.fact_check_outlined, size: 15),
              label: const Text('Review & Grant', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }

    // 2. Instructor view: Time gap privacy note if gap messages are hidden
    if (widget.isInstructor && selectedConv!['hideGapMessagesFromInstructor'] == true) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: sageBorder),
        ),
        child: Row(
          children: const [
            Icon(Icons.privacy_tip_outlined, size: 15, color: muted),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Note: Messages exchanged between admin and customer during resolution gap remain private.',
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
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
    if (selectedConv == null) return const SizedBox.shrink();

    // Instructor resolve lockout logic
    if (widget.isInstructor) {
      final status = selectedConv!['status']?.toString() ?? 'BOT';
      final isResolved = status == 'RESOLVED';
      final isInstructorLocked = isResolved ||
          (selectedConv!['resolvedByRole'] == 'INSTRUCTOR' &&
              selectedConv!['instructorPermissionGranted'] != true);

      if (isInstructorLocked) {
        final isReqPending = selectedConv!['instructorPermissionRequested'] == true;
        final screenWidth = MediaQuery.sizeOf(context).width;
        final isNarrow = screenWidth < 680;

        if (isReqPending) {
          final reason = selectedConv!['instructorPermissionReason'] ?? 'Follow-up inquiry';
          final reqTime = _formatDateTime(selectedConv!['instructorPermissionRequestedAt']);

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
              border: const Border(top: BorderSide(color: sageBorder)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.hourglass_top_rounded, color: Colors.amber.shade900, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Permission Request Pending Admin Review',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade900,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade200,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              'PENDING',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Reason: "$reason"${reqTime.isNotEmpty ? " • Submitted: $reqTime" : ""}',
                        style: TextStyle(fontSize: 11.5, color: Colors.brown.shade800),
                      ),
                      const SizedBox(height: 1),
                      const Text(
                        'You will be able to message this customer once an admin approves your request.',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        // Not yet requested -> show Resolved lock card + Request button
        final resolvedTime = _formatDateTime(selectedConv!['resolvedAt']);

        final infoText = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Conversation Resolved by Instructor',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: charcoal,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'This chat was resolved${resolvedTime.isNotEmpty ? " on $resolvedTime" : ""}. You cannot send messages to this customer again without admin approval.',
              style: const TextStyle(fontSize: 11.5, color: muted),
            ),
          ],
        );

        final reqButton = FilledButton.icon(
          onPressed: showRequestPermissionDialog,
          style: FilledButton.styleFrom(
            backgroundColor: sageGreen,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          icon: const Icon(Icons.vpn_key_outlined, size: 15),
          label: const Text('Request Permission from Admin', style: TextStyle(fontSize: 12)),
        );

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
            border: const Border(top: BorderSide(color: sageBorder)),
          ),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(Icons.lock_outline, color: charcoal, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: infoText),
                      ],
                    ),
                    const SizedBox(height: 10),
                    reqButton,
                  ],
                )
              : Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.lock_outline, color: charcoal, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: infoText),
                    const SizedBox(width: 12),
                    reqButton,
                  ],
                ),
        );
      }
    }

    // Default reply input box (for Admin, or unlocked Instructor)
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
                hintText: widget.isInstructor
                    ? 'Type your reply to this customer…'
                    : 'Type your admin reply to this customer…',
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
