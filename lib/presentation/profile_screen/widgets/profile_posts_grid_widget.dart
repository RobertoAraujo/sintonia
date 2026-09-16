import 'package:flutter/material.dart';

import '../../../core/app_export.dart';
import '../../../widgets/custom_image_widget.dart';
import '../../post_detail_screen/post_detail_screen.dart';

class ProfilePostsGridWidget extends StatelessWidget {
  final List<Map<String, dynamic>> posts;
  final Map<String, dynamic>? author;
  final double bottomPadding;

  const ProfilePostsGridWidget({
    super.key,
    required this.posts,
    this.author,
    this.bottomPadding = 100,
  });

  void _openPostDetail(BuildContext context, Map<String, dynamic> post) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) =>
            PostDetailScreen(post: post, author: author),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 56,
                color: theme.colorScheme.outlineVariant,
              ),
              const SizedBox(height: 12),
              Text(
                'Nenhuma publicação ainda',
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        final hasImage = post['hasImage'] as bool;

        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openPostDetail(context, post),
              child: hasImage
                  ? CustomImageWidget(
                      imageUrl: post['imageUrl'] as String,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      semanticLabel: post['semanticLabel'] as String,
                    )
                  : Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Center(
                        child: Icon(
                          Icons.article_outlined,
                          color: theme.colorScheme.onSurfaceVariant,
                          size: 28,
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}
