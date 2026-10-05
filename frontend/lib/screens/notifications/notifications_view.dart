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
        for (final n in notices)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              color: n['readAt'] == null
                  ? const Color(0xFFF0EDE6)
                  : Colors.white,
              child: ListTile(
                contentPadding: const EdgeInsets.all(20),
                leading: Icon(
                  n['readAt'] == null
                      ? Icons.mark_email_unread_outlined
                      : Icons.drafts_outlined,
                  color: plum,
                ),
                title: Text(
                  n['title'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Text('${n['body']}\n\n${onFormatDate(n['createdAt'])}'),
                ),
                onTap: n['readAt'] == null
                    ? () => onAction(
                          'notifications/${n['id']}/read',
                          method: 'PATCH',
                          success: 'Marked as read',
                        )
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
