import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../widgets/studio_common.dart';

class NotificationsView extends StatelessWidget {
  final List<dynamic> notices;
  final Future<void> Function(String path, {String method, Map<String, dynamic>? body, String success}) onAction;
  final String Function(dynamic iso, [String pattern]) onFormatDate;

  const NotificationsView({
    super.key,
    required this.notices,
    required this.onAction,
    required this.onFormatDate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        studioHeading(
          context,
          'STAY IN THE LOOP',
          'Your studio inbox.',
          'Booking updates, class reminders, and a little inspiration.',
        ),
        if (notices.isEmpty)
          studioEmpty('You’re all caught up.', Icons.notifications_none),
        for (int idx = 0; idx < notices.length; idx++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final n = notices[idx];
                final isUnread = n['readAt'] == null;
                final accentColor = chakra[idx % chakra.length];
                final cardWidth = constraints.maxWidth >= 700
                    ? constraints.maxWidth * (2 / 3)
                    : double.infinity;

                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: cardWidth,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: sageBorder.withValues(alpha: 0.6),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: isUnread ? accentColor : muted.withValues(alpha: 0.4),
                              width: 4,
                            ),
                          ),
                        ),
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Header: Title on left, Status / Unread badge on right
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Icon(
                                        isUnread
                                            ? Icons.mark_email_unread_outlined
                                            : Icons.drafts_outlined,
                                        size: 18,
                                        color: isUnread ? plum : muted,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          n['title'] as String,
                                          style: TextStyle(
                                            fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                                            fontSize: 16,
                                            color: ink,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: (isUnread ? plum : muted)
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isUnread ? 'Unread' : 'Read',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isUnread ? plum : muted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Body text with formatted date preserved
                            Text(
                              '${n['body']}\n\n${onFormatDate(n['createdAt'])}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: ink,
                                height: 1.45,
                              ),
                            ),

                            if (isUnread) ...[
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: plum,
                                  ),
                                  onPressed: () => onAction(
                                    'notifications/${n['id']}/read',
                                    method: 'PATCH',
                                    success: 'Marked as read',
                                  ),
                                  icon: const Icon(Icons.done_all, size: 16),
                                  label: const Text('Mark as read'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
