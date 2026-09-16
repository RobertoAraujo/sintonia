import 'package:flutter/material.dart';

import '../../../core/app_export.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/report_content_dialog.dart';

class MessageBubbleWidget extends StatelessWidget {
  final Map<String, dynamic> message;

  const MessageBubbleWidget({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSent = message['isSent'] as bool;
    final text = message['text'] as String?;
    final imageUrl = message['imageUrl'] as String?;
    final timestamp = message['timestamp'] as String;
    final isRead = message['isRead'] as bool;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isSent
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isSent) const SizedBox(width: 4),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            child: GestureDetector(
              onLongPress: !isSent
                  ? () {
                      showReportDialog(
                        context,
                        contentType: 'message',
                        contentId: message['id']?.toString(),
                        reportedUserId: message['senderId']?.toString(),
                      );
                    }
                  : null,
              child: Column(
                crossAxisAlignment: isSent
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (imageUrl != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      child: ClipRRect(
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(20),
                          topRight: const Radius.circular(20),
                          bottomLeft: isSent
                              ? const Radius.circular(20)
                              : const Radius.circular(4),
                          bottomRight: isSent
                              ? const Radius.circular(4)
                              : const Radius.circular(20),
                        ),
                        child: Container(
                          constraints: const BoxConstraints(
                            maxWidth: 260,
                            maxHeight: 320,
                          ),
                          color: Colors.black.withAlpha(8),
                          child: Image.network(
                            imageUrl,
                            fit: BoxFit.contain,
                            semanticLabel:
                                message['imageSemantic'] as String? ??
                                'Imagem na conversa',
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const SizedBox(
                                width: 180,
                                height: 140,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return const SizedBox(
                                width: 180,
                                height: 100,
                                child: Center(
                                  child: Icon(
                                    Icons.broken_image,
                                    color: Colors.grey,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  if (text != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSent
                            ? AppTheme.primary
                            : theme.colorScheme.surface,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(20),
                          topRight: const Radius.circular(20),
                          bottomLeft: isSent
                              ? const Radius.circular(20)
                              : const Radius.circular(4),
                          bottomRight: isSent
                              ? const Radius.circular(4)
                              : const Radius.circular(20),
                        ),
                        border: isSent
                            ? null
                            : Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                      ),
                      child: Text(
                        text,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isSent
                              ? Colors.white
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timestamp,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                      if (isSent) ...[
                        const SizedBox(width: 3),
                        Icon(
                          isRead ? Icons.done_all_rounded : Icons.done_rounded,
                          size: 13,
                          color: isRead
                              ? AppTheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isSent) const SizedBox(width: 4),
        ],
      ),
    );
  }
}
