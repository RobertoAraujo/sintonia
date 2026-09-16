import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/user_avatar_widget.dart';

class GroupDetailScreen extends StatefulWidget {
  final Map<String, dynamic> group;

  const GroupDetailScreen({required this.group, super.key});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isMember = false;
  bool _isLoadingMembership = true;
  bool _isTogglingMembership = false;

  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _members = [];
  bool _isLoadingPosts = true;
  bool _isLoadingMembers = true;

  RealtimeChannel? _postsChannel;

  String get _groupId => widget.group['id'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _isMember = widget.group['isMember'] == true;
    _checkMembership();
    _loadPosts();
    _loadMembers();
    _subscribeToGroupPosts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _postsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _checkMembership() async {
    if (_groupId.isEmpty) {
      setState(() => _isLoadingMembership = false);
      return;
    }
    final isMember = await SupabaseService.instance.isGroupMember(_groupId);
    if (mounted) {
      setState(() {
        _isMember = isMember;
        _isLoadingMembership = false;
      });
    }
  }

  Future<void> _loadPosts() async {
    if (_groupId.isEmpty) {
      setState(() => _isLoadingPosts = false);
      return;
    }
    try {
      final posts = await SupabaseService.instance.fetchGroupPosts(_groupId);
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _isLoadingPosts = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingPosts = false);
    }
  }

  Future<void> _loadMembers() async {
    if (_groupId.isEmpty) {
      setState(() => _isLoadingMembers = false);
      return;
    }
    try {
      final members = await SupabaseService.instance.fetchGroupMembers(
        _groupId,
      );
      if (!mounted) return;
      setState(() {
        _members = members;
        _isLoadingMembers = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMembers = false);
    }
  }

  void _subscribeToGroupPosts() {
    if (_groupId.isEmpty) return;
    _postsChannel = SupabaseService.instance.client
        .channel('group_posts:$_groupId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'group_posts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: _groupId,
          ),
          callback: (_) => _loadPosts(),
        )
        .subscribe();
  }

  Future<void> _toggleMembership() async {
    if (_isTogglingMembership) return;
    setState(() => _isTogglingMembership = true);

    bool success;
    if (_isMember) {
      success = await SupabaseService.instance.leaveGroup(_groupId);
    } else {
      success = await SupabaseService.instance.joinGroup(_groupId);
    }

    if (!mounted) return;
    setState(() => _isTogglingMembership = false);

    if (success) {
      setState(() => _isMember = !_isMember);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isMember ? 'Você entrou no grupo! 🎉' : 'Você saiu do grupo',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _isMember
              ? AppTheme.primary
              : Theme.of(context).colorScheme.error,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      _loadMembers();
    }
  }

  void _showPostModal(BuildContext context) {
    final ctrl = TextEditingController();
    bool isPosting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Nova Publicação no Grupo',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Compartilhe algo com o grupo...',
                    filled: true,
                    fillColor: Theme.of(
                      ctx,
                    ).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: isPosting
                        ? null
                        : () async {
                            if (ctrl.text.trim().isEmpty) return;
                            setModalState(() => isPosting = true);
                            final post = await SupabaseService.instance
                                .createGroupPost(
                                  groupId: _groupId,
                                  content: ctrl.text.trim(),
                                );
                            if (!mounted) return;
                            Navigator.pop(ctx);
                            if (post != null) {
                              setState(() => _posts.insert(0, post));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Publicado no grupo! 🎉'),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: AppTheme.primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
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
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      'Publicar no Grupo',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = widget.group;
    final tags = (group['tags'] as List?)?.cast<String>() ?? [];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: theme.colorScheme.surface,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(50),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    group['imageUrl'] as String? ??
                        'https://images.pexels.com/photos/1169754/pexels-photo-1169754.jpeg',
                    fit: BoxFit.cover,
                    semanticLabel:
                        group['imageSemantic'] as String? ?? 'Imagem do grupo',
                    errorBuilder: (_, __, ___) =>
                        Container(color: AppTheme.primary.withAlpha(40)),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withAlpha(180),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    left: 20,
                    right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group['name'] as String? ?? 'Grupo',
                          style: GoogleFonts.manrope(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.people_rounded,
                              color: Colors.white70,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${group['members'] ?? 0} membros',
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                            if (tags.isNotEmpty) ...[
                              const SizedBox(width: 12),
                              ...tags
                                  .take(2)
                                  .map(
                                    (tag) => Container(
                                      margin: const EdgeInsets.only(right: 6),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary.withAlpha(180),
                                        borderRadius: BorderRadius.circular(
                                          100,
                                        ),
                                      ),
                                      child: Text(
                                        tag,
                                        style: GoogleFonts.manrope(
                                          fontSize: 10,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          group['description'] as String? ??
                              'Grupo da comunidade Sintonia',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _isLoadingMembership
                          ? const SizedBox(
                              width: 100,
                              height: 40,
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : FilledButton.icon(
                              onPressed: _isTogglingMembership
                                  ? null
                                  : _toggleMembership,
                              icon: _isTogglingMembership
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(
                                      _isMember
                                          ? Icons.check_rounded
                                          : Icons.group_add_rounded,
                                      size: 16,
                                    ),
                              label: Text(_isMember ? 'Membro' : 'Participar'),
                              style: FilledButton.styleFrom(
                                backgroundColor: _isMember
                                    ? AppTheme.primary.withAlpha(180)
                                    : AppTheme.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: Colors.white,
                    unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                    indicator: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelStyle: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    unselectedLabelStyle: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    tabs: const [
                      Tab(text: 'Publicações'),
                      Tab(text: 'Membros'),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [_buildPostsTab(theme), _buildMembersTab(theme)],
        ),
      ),
      floatingActionButton: _isMember
          ? FloatingActionButton.extended(
              onPressed: () => _showPostModal(context),
              backgroundColor: AppTheme.primary,
              icon: const Icon(Icons.edit_rounded, color: Colors.white),
              label: Text(
                'Publicar',
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildPostsTab(ThemeData theme) {
    if (_isLoadingPosts) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.article_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Nenhuma publicação ainda',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_isMember) ...[
              const SizedBox(height: 8),
              Text(
                'Seja o primeiro a publicar!',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.primary,
                ),
              ),
            ],
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: _posts.length,
      itemBuilder: (_, i) {
        final post = _posts[i];
        return _GroupPostCard(
          post: post,
          onLike: () async {
            // Optimistic update
            setState(() {
              _posts[i] = {
                ..._posts[i],
                'likes_count': (_posts[i]['likes_count'] as int? ?? 0) + 1,
              };
            });
          },
        );
      },
    );
  }

  Widget _buildMembersTab(ThemeData theme) {
    if (_isLoadingMembers) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_members.isEmpty) {
      return Center(
        child: Text(
          'Nenhum membro encontrado',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: _members.length,
      itemBuilder: (_, i) {
        final row = _members[i];
        final member = row['member'] as Map<String, dynamic>? ?? {};
        final name =
            member['full_name'] as String? ??
            member['username'] as String? ??
            'Usuário';
        final avatarUrl = member['avatar_url'] as String? ?? '';
        final neurodivType = member['neurodiv_type'] as String? ?? '';
        final isAdmin = row['is_admin'] as bool? ?? false;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 6,
            ),
            leading: UserAvatar(
              avatarUrl: avatarUrl.isNotEmpty ? avatarUrl : null,
              displayName: name,
              radius: 22,
            ),
            title: Text(
              name,
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            subtitle: neurodivType.isNotEmpty
                ? Text(
                    neurodivType,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.primary,
                    ),
                  )
                : null,
            trailing: isAdmin
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.secondary.withAlpha(30),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      'Admin',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.secondary,
                      ),
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }
}

class _GroupPostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final VoidCallback onLike;

  const _GroupPostCard({required this.post, required this.onLike});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final author = post['author'] as Map<String, dynamic>? ?? {};
    final authorName =
        author['full_name'] as String? ??
        author['username'] as String? ??
        'Usuário';
    final authorAvatar = author['avatar_url'] as String? ?? '';
    final content = post['content'] as String? ?? '';
    final imageUrl = post['image_url'] as String?;
    final likesCount = post['likes_count'] as int? ?? 0;
    final commentsCount = post['comments_count'] as int? ?? 0;
    final createdAt = post['created_at'] as String? ?? '';

    String timeAgo = '';
    if (createdAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(createdAt).toLocal();
        final diff = DateTime.now().difference(dt);
        if (diff.inMinutes < 60) {
          timeAgo = '${diff.inMinutes}min';
        } else if (diff.inHours < 24) {
          timeAgo = '${diff.inHours}h';
        } else {
          timeAgo = '${diff.inDays}d';
        }
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                UserAvatar(
                  avatarUrl: authorAvatar.isNotEmpty ? authorAvatar : null,
                  displayName: authorName,
                  radius: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        authorName,
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      if (timeAgo.isNotEmpty)
                        Text(
                          timeAgo,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Text(content, style: theme.textTheme.bodyMedium),
          ),
          if (imageUrl != null && imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              child: Image.network(
                imageUrl,
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
                semanticLabel: 'Imagem da publicação do grupo',
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: onLike,
                  icon: const Icon(
                    Icons.favorite_border_rounded,
                    color: Colors.grey,
                    size: 20,
                  ),
                ),
                Text('$likesCount', style: theme.textTheme.bodySmall),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {},
                  icon: Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                ),
                Text('$commentsCount', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
