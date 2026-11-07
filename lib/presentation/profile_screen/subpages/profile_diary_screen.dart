import 'package:flutter/material.dart';

import '../../../core/app_export.dart';
import '../../../services/supabase_service.dart';
import '../../../theme/app_theme.dart';

class ProfileDiaryScreen extends StatefulWidget {
  const ProfileDiaryScreen({super.key});

  @override
  State<ProfileDiaryScreen> createState() => _ProfileDiaryScreenState();
}

class _ProfileDiaryScreenState extends State<ProfileDiaryScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final rows = await SupabaseService.instance.fetchDiaryEntries();
      if (!mounted) return;
      setState(() {
        _entries = rows.map((r) {
          final createdAt = r['created_at'] != null
              ? DateTime.tryParse(r['created_at'].toString())?.toLocal()
              : null;
          final tags = (r['tags'] as List?)?.cast<String>() ?? [];
          final isPrivate = r['is_private'] as bool? ?? true;
          final friendsOnly = r['friends_only'] as bool? ?? true;
          return {
            'id': r['id'] ?? '',
            'date': createdAt != null ? _formatDate(createdAt) : 'Hoje',
            'mood': (r['mood'] as String?)?.isNotEmpty == true
                ? r['mood']
                : '🌟',
            'title': r['title'] ?? '',
            'content': r['content'] ?? '',
            'petName': null,
            'petImageUrl': null,
            'tags': tags,
            'is_private': isPrivate,
            'friends_only': friendsOnly,
          };
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Não foi possível carregar o diário.';
          _isLoading = false;
        });
      }
    }
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Fev',
      'Mar',
      'Abr',
      'Mai',
      'Jun',
      'Jul',
      'Ago',
      'Set',
      'Out',
      'Nov',
      'Dez',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  /// Returns the visibility label and icon for an entry
  _VisibilityInfo _getVisibilityInfo(Map<String, dynamic> entry) {
    final isPrivate = entry['is_private'] as bool? ?? true;
    final friendsOnly = entry['friends_only'] as bool? ?? true;
    if (isPrivate && !friendsOnly) {
      // Truly private — only me
      return _VisibilityInfo(
        label: 'Privado',
        icon: Icons.lock_rounded,
        color: Colors.red.shade400,
      );
    } else if (friendsOnly) {
      // Friends only (default)
      return _VisibilityInfo(
        label: 'Amigos',
        icon: Icons.people_rounded,
        color: AppTheme.primary,
      );
    } else {
      // Public
      return _VisibilityInfo(
        label: 'Público',
        icon: Icons.public_rounded,
        color: Colors.green.shade600,
      );
    }
  }

  Future<void> _toggleVisibility(Map<String, dynamic> entry) async {
    final entryId = entry['id'] as String;
    final isPrivate = entry['is_private'] as bool? ?? true;
    final friendsOnly = entry['friends_only'] as bool? ?? true;

    // Cycle: friends_only → private → public → friends_only
    bool newIsPrivate;
    bool newFriendsOnly;

    if (friendsOnly && isPrivate) {
      // Currently friends → go to private (only me)
      newIsPrivate = true;
      newFriendsOnly = false;
    } else if (isPrivate && !friendsOnly) {
      // Currently private → go to public
      newIsPrivate = false;
      newFriendsOnly = false;
    } else {
      // Currently public → go back to friends
      newIsPrivate = true;
      newFriendsOnly = true;
    }

    // Optimistic update
    setState(() {
      final idx = _entries.indexWhere((e) => e['id'] == entryId);
      if (idx != -1) {
        _entries[idx] = {
          ..._entries[idx],
          'is_private': newIsPrivate,
          'friends_only': newFriendsOnly,
        };
      }
    });

    final success = await SupabaseService.instance.updateDiaryEntryVisibility(
      entryId: entryId,
      isPrivate: newIsPrivate,
      friendsOnly: newFriendsOnly,
    );

    if (!success && mounted) {
      // Revert on failure
      setState(() {
        final idx = _entries.indexWhere((e) => e['id'] == entryId);
        if (idx != -1) {
          _entries[idx] = {
            ..._entries[idx],
            'is_private': isPrivate,
            'friends_only': friendsOnly,
          };
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro ao alterar visibilidade. Tente novamente.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showAddEntryModal() {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    String selectedMood = '🌟';
    bool isSaving = false;
    bool isPosting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          final bottomPadding = MediaQuery.of(ctx).padding.bottom;
          return Padding(
            padding: EdgeInsets.only(
              bottom: bottomInset > 0 ? bottomInset : bottomPadding,
            ),
            child: Container(
              margin: EdgeInsets.fromLTRB(12, 0, 12, bottomInset > 0 ? 8 : 12),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(ctx).colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      'Nova Entrada no Diário',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Como você está?',
                      style: Theme.of(ctx).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: ['🌟', '😊', '😌', '😔', '💜', '🌿']
                          .map(
                            (mood) => GestureDetector(
                              onTap: () =>
                                  setModalState(() => selectedMood = mood),
                              child: Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: selectedMood == mood
                                      ? AppTheme.primaryContainer
                                      : Theme.of(
                                          ctx,
                                        ).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(10),
                                  border: selectedMood == mood
                                      ? Border.all(color: AppTheme.primary)
                                      : null,
                                ),
                                child: Text(
                                  mood,
                                  style: const TextStyle(fontSize: 20),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleCtrl,
                      maxLength: 200,
                      decoration: InputDecoration(
                        labelText: 'Título',
                        counterText: '',
                        filled: true,
                        fillColor: Theme.of(
                          ctx,
                        ).colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: contentCtrl,
                      maxLines: 4,
                      maxLength: 10000,
                      decoration: InputDecoration(
                        hintText: 'Escreva sobre seu dia...',
                        counterText: '',
                        filled: true,
                        fillColor: Theme.of(
                          ctx,
                        ).colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Visibility info note
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withAlpha(15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.people_rounded,
                            size: 16,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Visível apenas para seus amigos por padrão',
                              style: Theme.of(ctx).textTheme.bodySmall
                                  ?.copyWith(color: AppTheme.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Save to diary button (friends_only by default)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: (isSaving || isPosting)
                            ? null
                            : () async {
                                if (titleCtrl.text.trim().isEmpty ||
                                    contentCtrl.text.trim().isEmpty) {
                                  return;
                                }
                                setModalState(() => isSaving = true);
                                final result = await SupabaseService.instance
                                    .addDiaryEntry(
                                      content: contentCtrl.text.trim(),
                                      title: titleCtrl.text.trim(),
                                      mood: selectedMood,
                                      isPrivate: true,
                                      friendsOnly: true,
                                    );
                                if (!ctx.mounted) return;
                                Navigator.pop(ctx);
                                if (result != null) {
                                  _loadEntries();
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Erro ao salvar entrada. Tente novamente.',
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                        icon: isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.book_rounded, size: 18),
                        label: const Text('Salvar no Diário'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Post to feed button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: (isSaving || isPosting)
                            ? null
                            : () async {
                                if (contentCtrl.text.trim().isEmpty) {
                                  return;
                                }
                                setModalState(() => isPosting = true);
                                final title = titleCtrl.text.trim();
                                final content = contentCtrl.text.trim();
                                final postContent = title.isNotEmpty
                                    ? '$selectedMood $title\n\n$content'
                                    : '$selectedMood $content';

                                // Save diary entry (public)
                                await SupabaseService.instance.addDiaryEntry(
                                  content: content,
                                  title: title,
                                  mood: selectedMood,
                                  isPrivate: false,
                                  friendsOnly: false,
                                );

                                // Also post to feed
                                final postResult = await SupabaseService
                                    .instance
                                    .createPost(
                                      content: postContent,
                                      postType: 'diary',
                                    );

                                if (!ctx.mounted) return;
                                Navigator.pop(ctx);
                                if (postResult != null) {
                                  _loadEntries();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Entrada publicada no feed!',
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Erro ao publicar. Tente novamente.',
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                        icon: isPosting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.public_rounded, size: 18),
                        label: const Text('Postar no Feed'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: BorderSide(color: AppTheme.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Meu Diário'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        ),
        actions: [
          IconButton(
            onPressed: _showAddEntryModal,
            icon: const Icon(Icons.add_rounded),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.primary.withAlpha(20),
              foregroundColor: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _loadEntries,
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            )
          : _entries.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('📔', style: const TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  Text(
                    'Seu diário está vazio',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Toque em + para adicionar sua primeira entrada',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _showAddEntryModal,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Nova entrada'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadEntries,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _entries.length,
                itemBuilder: (_, i) {
                  final entry = _entries[i];
                  final tags = (entry['tags'] as List?)?.cast<String>() ?? [];
                  final visInfo = _getVisibilityInfo(entry);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              entry['mood'] as String,
                              style: const TextStyle(fontSize: 24),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry['title'] as String,
                                    style: theme.textTheme.titleSmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    entry['date'] as String,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Visibility toggle button
                            GestureDetector(
                              onTap: () => _toggleVisibility(entry),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: visInfo.color.withAlpha(20),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: visInfo.color.withAlpha(60),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      visInfo.icon,
                                      size: 13,
                                      color: visInfo.color,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      visInfo.label,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: visInfo.color,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          entry['content'] as String,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.5,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (tags.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: tags.map((tag) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withAlpha(15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  tag,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: AppTheme.primary,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _VisibilityInfo {
  final String label;
  final IconData icon;
  final Color color;

  const _VisibilityInfo({
    required this.label,
    required this.icon,
    required this.color,
  });
}
