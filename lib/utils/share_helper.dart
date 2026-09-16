import 'package:share_plus/share_plus.dart';

class ShareHelper {
  static Future<void> sharePost({
    required String postId,
    required String authorName,
    String? postContentText,
  }) async {
    final String postUrl = 'https://sintonia.app/post/$postId';

    String previewText = '';
    if (postContentText != null && postContentText.isNotEmpty) {
      previewText = postContentText.length > 80
          ? ' "${postContentText.substring(0, 80)}..."'
          : ' "$postContentText"';
    }

    final String shareMessage =
        'Veja esta publicação de $authorName no SintonIA:$previewText\n\n'
        'Acesse pelo link: $postUrl';

    await Share.share(
      shareMessage,
      subject: 'Publicação de $authorName no SintonIA',
    );
  }
}
