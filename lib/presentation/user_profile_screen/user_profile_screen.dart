import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_image_widget.dart';
import '../chat_screen/widgets/private_chat_screen.dart';
import '../post_detail_screen/post_detail_screen.dart';
import './widgets/friends_list_page.dart';

class UserProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const UserProfileScreen({super.key, required this.userData});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Connection state ──────────────────────────────────────────────────────
  _ConnectionStatus _connectionStatus = _ConnectionStatus.none;
  bool _isLoadingFriendship = true;

  // ── Counters ──────────────────────────────────────────────────────────────
  int _postsCount = 0;
  int _friendsCount = 0;
  int _compatScore = 0;
  bool _isLoadingCounters = true;
  bool _isLoadingCompat = false;

  // ── Full profile data loaded from Supabase ────────────────────────────────
  Map<String, dynamic> _profileData = {};
  bool _isLoadingProfile = true;

  // ── Posts feed ────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _posts = [];
  bool _isLoadingPosts = true;

  // ── Pet data ──────────────────────────────────────────────────────────────
  Map<String, dynamic>? _activePet;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _profileData = Map<String, dynamic>.from(widget.userData);
    _loadFullProfile();
    _checkFriendshipStatus();
    _loadCompatibilityScore();
    _loadUserPosts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadFullProfile() async {
    final otherId = widget.userData['id'] as String?;
    if (otherId == null) {
      setState(() => _isLoadingProfile = false);
      return;
    }
    try {
      // Use the public_user_profiles view which includes computed counters
      final data = await SupabaseService.instance.client
          .from('public_user_profiles')
          .select()
          .eq('id', otherId)
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          _profileData = {
            ..._profileData,
            ...data,
            // Normalize field names for UI
            'name': data['name'] ?? _profileData['name'] ?? 'Usuário',
            'avatarUrl': data['avatar_url'] ?? _profileData['avatarUrl'] ?? '',
            'neurodivType':
                data['neurodiv_type'] ?? _profileData['neurodivType'],
          };
          _postsCount = (data['posts_count'] as int?) ?? 0;
          _friendsCount = (data['friends_count'] as int?) ?? 0;
          _isLoadingCounters = false;
          _isLoadingProfile = false;
        });

        // Load active pet if set
        final activePetId = data['active_pet_id'] as String?;
        if (activePetId != null) {
          _loadActivePet(activePetId);
        }
      } else {
        // Fallback: load counters separately
        await _loadCountersFallback(otherId);
        if (mounted) setState(() => _isLoadingProfile = false);
      }
    } catch (e) {
      // Fallback if view doesn't exist yet
      await _loadCountersFallback(otherId);
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  Future<void> _loadCountersFallback(String userId) async {
    try {
      // Count posts
      final postsResp = await SupabaseService.instance.client
          .from('posts')
          .select('id')
          .eq('author_id', userId)
          .eq('is_published', true);
      final postsCount = (postsResp as List).length;

      // Count friends
      final friendsResp = await SupabaseService.instance.client
          .from('friendships')
          .select('id')
          .or('requester_id.eq.$userId,addressee_id.eq.$userId')
          .eq('status', 'accepted');
      final friendsCount = (friendsResp as List).length;

      if (mounted) {
        setState(() {
          _postsCount = postsCount;
          _friendsCount = friendsCount;
          _isLoadingCounters = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingCounters = false);
    }
  }

  Future<void> _loadActivePet(String petId) async {
    try {
      final pet = await SupabaseService.instance.client
          .from('pets')
          .select()
          .eq('id', petId)
          .maybeSingle();
      if (pet != null && mounted) {
        setState(() => _activePet = pet);
      }
    } catch (_) {}
  }

  Future<void> _loadCompatibilityScore() async {
    final otherId = widget.userData['id'] as String?;
    final myId = SupabaseService.instance.currentUserId;
    if (otherId == null || myId == null || otherId == myId) return;

    final precomputed = widget.userData['compatScore'] as int?;
    if (precomputed != null && precomputed > 0) {
      setState(() => _compatScore = precomputed);
      return;
    }

    setState(() => _isLoadingCompat = true);
    try {
      // 1. Check if a cached score exists in user_matches
      final cached = await SupabaseService.instance.client
          .from('user_matches')
          .select('compatibility_score')
          .or(
            'and(user_id_1.eq.$myId,user_id_2.eq.$otherId),and(user_id_1.eq.$otherId,user_id_2.eq.$myId)',
          )
          .maybeSingle();

      if (cached != null && mounted) {
        setState(() {
          _compatScore = (cached['compatibility_score'] as int?) ?? 0;
          _isLoadingCompat = false;
        });
        return;
      }

      // 2. No cached score — calculate via Gemini Lambda and persist
      final score = await SupabaseService.instance.calculateAndSaveMatchScore(
        currentUserId: myId,
        targetUserId: otherId,
      );
      if (mounted) {
        setState(() {
          _compatScore = score;
          _isLoadingCompat = false;
        });
      }
    } catch (_) {
      // Final fallback: local Supabase RPC
      try {
        final result = await SupabaseService.instance.client.rpc(
          'calculate_compatibility',
          params: {'user_a_id': myId, 'user_b_id': otherId},
        );
        if (mounted) {
          setState(() {
            _compatScore = (result as int?) ?? 0;
            _isLoadingCompat = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isLoadingCompat = false);
      }
    }
  }

  Future<void> _loadUserPosts() async {
    final otherId = widget.userData['id'] as String?;
    if (otherId == null) {
      setState(() => _isLoadingPosts = false);
      return;
    }
    try {
      final rows = await SupabaseService.instance.client
          .from('posts')
          .select()
          .eq('author_id', otherId)
          .eq('is_published', true)
          .order('created_at', ascending: false);

      final posts = (rows as List).map((p) {
        return {
          'id': p['id'] ?? '',
          'content': p['content'] ?? '',
          'imageUrl': (p['image_url'] as String?)?.isNotEmpty == true
              ? p['image_url']
              : null,
          'imageSemantic': p['image_semantic'] ?? '',
          'hasImage': (p['image_url'] as String?)?.isNotEmpty == true,
          'likes': p['likes_count'] ?? 0,
          'comments': p['comments_count'] ?? 0,
          'createdAt': p['created_at'] ?? '',
          'hyperfocusTags':
              (p['hyperfocus_tags'] as List?)?.cast<String>() ?? [],
          'isLiked': false,
          'isSaved': false,
          'authorId': otherId,
          'authorName': _profileData['name'] ?? 'Usuário',
          'authorImage': _profileData['avatarUrl'] ?? '',
          'neurodivType': _profileData['neurodivType'] ?? '',
        };
      }).toList();

      if (mounted) {
        setState(() {
          _posts = posts;
          _isLoadingPosts = false;
          _postsCount = posts.length;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPosts = false);
    }
  }

  Future<void> _checkFriendshipStatus() async {
    final otherId = widget.userData['id'] as String?;
    final myId = SupabaseService.instance.currentUserId;
    if (otherId == null || myId == null || otherId == myId) {
      if (mounted) setState(() => _isLoadingFriendship = false);
      return;
    }
    try {
      final status = await SupabaseService.instance.checkFriendshipStatus(
        otherId,
      );
      if (!mounted) return;
      setState(() {
        _isLoadingFriendship = false;
        if (status == 'accepted') {
          _connectionStatus = _ConnectionStatus.connected;
        } else if (status == 'pending_sent') {
          _connectionStatus = _ConnectionStatus.pending;
        } else if (status == 'pending_received') {
          _connectionStatus = _ConnectionStatus.pendingReceived;
        } else {
          _connectionStatus = _ConnectionStatus.none;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingFriendship = false);
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _openPrivateChat() {
    final data = _profileData;
    final otherId = data['id'] as String? ?? '';
    final otherName = data['name'] as String? ?? 'Usuário';
    final otherAvatar = data['avatarUrl'] as String? ?? '';
    final otherAvatarSemantic =
        data['avatarSemantic'] as String? ?? 'Foto de perfil';

    SupabaseService.instance.createOrGetDirectConversation(otherId).then((
      chatId,
    ) {
      if (chatId == null || !mounted) return;
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => PrivateChatScreen(
            chatId: chatId,
            otherUserId: otherId,
            otherUserName: otherName,
            otherUserAvatar: otherAvatar,
            otherUserAvatarSemantic: otherAvatarSemantic,
          ),
          transitionsBuilder: (_, animation, __, child) => SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    });
  }

  Future<void> _sendFriendRequest() async {
    final otherId = _profileData['id'] as String?;
    if (otherId == null) return;
    setState(() => _connectionStatus = _ConnectionStatus.pending);
    final success = await SupabaseService.instance.sendFriendRequest(otherId);
    if (!mounted) return;
    if (!success) {
      setState(() => _connectionStatus = _ConnectionStatus.none);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível enviar a solicitação.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Solicitação enviada para ${_profileData['name'] ?? 'usuário'}! 🎉',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _cancelFriendRequest() async {
    final otherId = _profileData['id'] as String?;
    if (otherId == null) return;
    setState(() => _connectionStatus = _ConnectionStatus.none);
    await SupabaseService.instance.removeFriend(otherId);
  }

  Future<void> _acceptIncomingRequest() async {
    final otherId = _profileData['id'] as String?;
    if (otherId == null) return;
    try {
      final uid = SupabaseService.instance.currentUserId;
      final data = await SupabaseService.instance.client
          .from('friendships')
          .select('id')
          .eq('requester_id', otherId)
          .eq('addressee_id', uid!)
          .eq('status', 'pending')
          .maybeSingle();
      if (data != null) {
        await SupabaseService.instance.acceptFriendRequest(
          data['id'] as String,
        );
        if (mounted) {
          setState(() {
            _connectionStatus = _ConnectionStatus.connected;
            _friendsCount += 1;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Agora você e ${_profileData['name'] ?? 'usuário'} são amigos! 🎉',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _declineIncomingRequest() async {
    final otherId = _profileData['id'] as String?;
    if (otherId == null) return;
    try {
      final uid = SupabaseService.instance.currentUserId;
      final data = await SupabaseService.instance.client
          .from('friendships')
          .select('id')
          .eq('requester_id', otherId)
          .eq('addressee_id', uid!)
          .eq('status', 'pending')
          .maybeSingle();
      if (data != null) {
        await SupabaseService.instance.declineFriendRequest(
          data['id'] as String,
        );
        if (mounted) setState(() => _connectionStatus = _ConnectionStatus.none);
      }
    } catch (_) {}
  }

  void _showRemoveDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remover amigo'),
        content: Text(
          'Deseja remover ${_profileData['name'] ?? 'este usuário'} dos seus amigos?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final otherId = _profileData['id'] as String?;
              if (otherId != null) {
                await SupabaseService.instance.removeFriend(otherId);
              }
              if (mounted) {
                setState(() {
                  _connectionStatus = _ConnectionStatus.none;
                  if (_friendsCount > 0) _friendsCount -= 1;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${_profileData['name'] ?? 'Usuário'} removido dos amigos.',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
  }

  void _showReportDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Denunciar usuário'),
        content: Text(
          'Deseja denunciar ${_profileData['name'] ?? 'este usuário'}? Nossa equipe irá analisar o caso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final otherId = _profileData['id'] as String?;
              if (otherId != null) {
                try {
                  await SupabaseService.instance.client.from('reports').insert({
                    'reporter_id': SupabaseService.instance.currentUserId,
                    'reported_user_id': otherId,
                    'reason': 'other',
                    'status': 'open',
                  });
                } catch (_) {}
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Denúncia enviada. Obrigado! 🙏'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Denunciar'),
          ),
        ],
      ),
    );
  }

  void _showBlockDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Bloquear usuário'),
        content: Text(
          'Deseja bloquear ${_profileData['name'] ?? 'este usuário'}? Ele não poderá mais ver seu perfil ou enviar mensagens.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final otherId = _profileData['id'] as String?;
              final myId = SupabaseService.instance.currentUserId;
              if (otherId != null && myId != null) {
                try {
                  await SupabaseService.instance.client
                      .from('blocked_users')
                      .upsert({
                        'blocker_id': myId,
                        'blocked_user_id': otherId,
                      }, onConflict: 'blocker_id,blocked_user_id');
                } catch (_) {}
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${_profileData['name'] ?? 'Usuário'} foi bloqueado.',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                Navigator.of(context).pop();
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Bloquear'),
          ),
        ],
      ),
    );
  }

  void _shareProfile() {
    final name = _profileData['name'] as String? ?? 'Usuário';
    final username = _profileData['username'] as String? ?? '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Link do perfil de $name ($username) copiado! 🔗'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _openFriendsList() {
    final otherId = _profileData['id'] as String?;
    final name = _profileData['name'] as String? ?? 'Usuário';
    if (otherId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FriendsListPage(userId: otherId, userName: name),
      ),
    );
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  Color _neurodivColor(String type) {
    switch (type) {
      case 'TEA':
        return AppTheme.teaColor;
      case 'TDAH':
        return AppTheme.tdahColor;
      case 'Dislexia':
        return AppTheme.dyslexiaColor;
      case 'Tourette':
        return AppTheme.touretteColor;
      default:
        return AppTheme.primary;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = _profileData;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            backgroundColor: theme.scaffoldBackgroundColor,
            elevation: 0,
            floating: true,
            snap: true,
            leading: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            actions: [
              IconButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    useRootNavigator: true,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => SafeArea(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 12, bottom: 8),
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            ListTile(
                              leading: const Icon(
                                Icons.flag_outlined,
                                color: Colors.orange,
                              ),
                              title: const Text('Denunciar usuário'),
                              onTap: () {
                                Navigator.pop(context);
                                _showReportDialog();
                              },
                            ),
                            ListTile(
                              leading: Icon(
                                Icons.block_rounded,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              title: Text(
                                'Bloquear usuário',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                _showBlockDialog();
                              },
                            ),
                            ListTile(
                              leading: Icon(
                                Icons.share_rounded,
                                color: AppTheme.primary,
                              ),
                              title: const Text('Compartilhar perfil'),
                              onTap: () {
                                Navigator.pop(context);
                                _shareProfile();
                              },
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(child: _buildProfileHeader(theme, data)),
          SliverToBoxAdapter(child: _buildActionButtons(theme)),
          if (_buildTagsSection(theme, data) != null)
            SliverToBoxAdapter(child: _buildTagsSection(theme, data)!),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabDelegate(
              TabBar(
                controller: _tabController,
                labelColor: AppTheme.primary,
                unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                indicatorColor: AppTheme.primary,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                tabs: const [
                  Tab(text: 'Publicações'),
                  Tab(text: 'Sobre'),
                ],
              ),
              theme.colorScheme.surface,
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildPostsTab(theme, bottomPadding),
            _buildAboutTab(theme, data),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(ThemeData theme, Map<String, dynamic> data) {
    final neurodivType =
        data['neurodivType'] as String? ??
        data['neurodiv_type'] as String? ??
        '';
    final name = data['name'] as String? ?? 'Usuário';
    final username = data['username'] as String? ?? '';
    final bio = data['bio'] as String? ?? '';
    final avatarUrl =
        data['avatarUrl'] as String? ?? data['avatar_url'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        children: [
          Row(
            children: [
              Hero(
                tag: 'avatar_${data['id'] ?? name}',
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.primary.withAlpha(60),
                      width: 3,
                    ),
                  ),
                  child: ClipOval(
                    child: CustomImageWidget(
                      imageUrl: avatarUrl,
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                      semanticLabel:
                          data['avatarSemantic'] as String? ??
                          'Foto de perfil de $name',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatItem(
                      label: 'Posts',
                      value: _isLoadingCounters ? '...' : '$_postsCount',
                      theme: theme,
                    ),
                    GestureDetector(
                      onTap: _openFriendsList,
                      child: _StatItem(
                        label: 'Amigos',
                        value: _isLoadingCounters ? '...' : '$_friendsCount',
                        theme: theme,
                        tappable: true,
                      ),
                    ),
                    _StatItem(
                      label: 'Compat.',
                      value: _isLoadingCompat ? '...%' : '$_compatScore%',
                      theme: theme,
                      valueColor: AppTheme.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: theme.textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (neurodivType.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _neurodivColor(neurodivType).withAlpha(20),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: _neurodivColor(neurodivType).withAlpha(80),
                          ),
                        ),
                        child: Text(
                          neurodivType,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: _neurodivColor(neurodivType),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                if (username.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '@$username',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (bio.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    bio,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ],
                // Active pet badge
                if (_activePet != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if ((_activePet!['photo_url'] as String?)?.isNotEmpty ==
                          true)
                        ClipOval(
                          child: CustomImageWidget(
                            imageUrl: _activePet!['photo_url'] as String,
                            width: 24,
                            height: 24,
                            fit: BoxFit.cover,
                            semanticLabel: 'Pet de $name',
                          ),
                        ),
                      const SizedBox(width: 6),
                      const Text('🐾', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Text(
                        _activePet!['name'] as String? ?? '',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ] else if ((data['petName'] as String?)?.isNotEmpty ==
                    true) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if ((data['petAvatarUrl'] as String?)?.isNotEmpty == true)
                        ClipOval(
                          child: CustomImageWidget(
                            imageUrl: data['petAvatarUrl'] as String,
                            width: 24,
                            height: 24,
                            fit: BoxFit.cover,
                            semanticLabel: 'Pet de $name',
                          ),
                        ),
                      const SizedBox(width: 6),
                      const Text('🐾', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Text(
                        data['petName'] as String,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(ThemeData theme) {
    final myId = SupabaseService.instance.currentUserId;
    final otherId = _profileData['id'] as String?;
    final isMe = myId != null && myId == otherId;
    if (isMe) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_connectionStatus != _ConnectionStatus.none) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: _connectionStatus == _ConnectionStatus.connected
                    ? AppTheme.primary.withAlpha(18)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _connectionStatus == _ConnectionStatus.connected
                      ? AppTheme.primary.withAlpha(60)
                      : theme.colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _connectionStatus == _ConnectionStatus.connected
                        ? Icons.people_rounded
                        : _connectionStatus == _ConnectionStatus.pendingReceived
                        ? Icons.person_add_alt_1_rounded
                        : Icons.schedule_rounded,
                    size: 15,
                    color: _connectionStatus == _ConnectionStatus.connected
                        ? AppTheme.primary
                        : _connectionStatus == _ConnectionStatus.pendingReceived
                        ? AppTheme.secondary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _connectionStatus == _ConnectionStatus.connected
                        ? 'Vocês são amigos'
                        : _connectionStatus == _ConnectionStatus.pendingReceived
                        ? 'Enviou uma solicitação para você'
                        : 'Solicitação enviada',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: _connectionStatus == _ConnectionStatus.connected
                          ? AppTheme.primary
                          : _connectionStatus ==
                                _ConnectionStatus.pendingReceived
                          ? AppTheme.secondary
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            children: [
              // Connect / Pending / Remove / Accept button
              Expanded(
                child: _isLoadingFriendship
                    ? const SizedBox(
                        height: 44,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : _connectionStatus == _ConnectionStatus.connected
                    ? OutlinedButton.icon(
                        onPressed: _showRemoveDialog,
                        icon: const Icon(Icons.person_remove_rounded, size: 18),
                        label: const Text('Remover'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                          side: BorderSide(
                            color: theme.colorScheme.error.withAlpha(120),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      )
                    : _connectionStatus == _ConnectionStatus.pending
                    ? OutlinedButton.icon(
                        onPressed: _cancelFriendRequest,
                        icon: const Icon(Icons.schedule_rounded, size: 18),
                        label: const Text('Pendente'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.onSurfaceVariant,
                          side: BorderSide(
                            color: theme.colorScheme.outlineVariant,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      )
                    : _connectionStatus == _ConnectionStatus.pendingReceived
                    ? FilledButton.icon(
                        onPressed: _acceptIncomingRequest,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Aceitar'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.secondary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: _sendFriendRequest,
                        icon: const Icon(Icons.person_add_rounded, size: 18),
                        label: const Text('Conectar'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              // Message button — always enabled (creates/opens conversation)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openPrivateChat,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Mensagem'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        _connectionStatus == _ConnectionStatus.connected
                        ? AppTheme.secondary
                        : theme.colorScheme.onSurfaceVariant,
                    side: BorderSide(
                      color: _connectionStatus == _ConnectionStatus.connected
                          ? AppTheme.secondary
                          : theme.colorScheme.outlineVariant,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          if (_connectionStatus == _ConnectionStatus.pendingReceived) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _declineIncomingRequest,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Recusar solicitação'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(
                    color: theme.colorScheme.error.withAlpha(120),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Returns the tags/badges section (hyperfocuses, interests) or null if empty
  Widget? _buildTagsSection(ThemeData theme, Map<String, dynamic> data) {
    final hyperfocuses = (data['hyperfocuses'] as List?)?.cast<dynamic>() ?? [];
    final interests = (data['interests'] as List?)?.cast<dynamic>() ?? [];
    if (hyperfocuses.isEmpty && interests.isEmpty) return null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hyperfocuses.isNotEmpty) ...[
            Text(
              'Hiperfocos',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: hyperfocuses.map((h) {
                String label;
                int colorVal = 0xFF2D7D6F;
                if (h is Map) {
                  label = h['name'] as String? ?? h.toString();
                  colorVal = h['color'] as int? ?? 0xFF2D7D6F;
                } else {
                  label = h.toString();
                }
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Color(colorVal).withAlpha(20),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Color(colorVal).withAlpha(80)),
                  ),
                  child: Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Color(colorVal),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
          if (interests.isNotEmpty) ...[
            Text(
              'Interesses',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: interests.map((i) {
                final label = i is String ? i : i.toString();
                return Chip(
                  label: Text(label),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                  labelStyle: theme.textTheme.labelMedium,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ── Publications tab ──────────────────────────────────────────────────────

  Widget _buildPostsTab(ThemeData theme, double bottomPadding) {
    if (_isLoadingPosts) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.grid_off_rounded,
              size: 48,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Nenhuma publicação ainda',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(2, 2, 2, bottomPadding + 80),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _posts.length,
      itemBuilder: (_, i) {
        final post = _posts[i];
        return ClipRRect(
          borderRadius: BorderRadius.zero,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (_, animation, __) =>
                        PostDetailScreen(post: post, author: _profileData),
                    transitionsBuilder: (_, animation, __, child) =>
                        FadeTransition(
                          opacity: CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOut,
                          ),
                          child: child,
                        ),
                    transitionDuration: const Duration(milliseconds: 250),
                  ),
                );
              },
              child: post['hasImage'] == true && post['imageUrl'] != null
                  ? Image.network(post['imageUrl'] as String, fit: BoxFit.cover)
                  : Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Center(
                        child: Icon(
                          Icons.article_outlined,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  // ── About tab ─────────────────────────────────────────────────────────────

  Widget _buildAboutTab(ThemeData theme, Map<String, dynamic> data) {
    final bio = data['bio'] as String? ?? '';
    final commPrefs =
        data['communication_preferences'] as Map<String, dynamic>? ?? {};
    final socialBattery = commPrefs['social_battery'] as int?;
    final sensorySensitivity = commPrefs['sensory_sensitivity'] as int?;
    final sensoryTriggers =
        (data['sensory_triggers'] as List?)?.cast<String>() ?? [];
    final politicalViews =
        (data['political_views'] as List?)?.cast<String>() ?? [];
    final religions = (data['religions'] as List?)?.cast<String>() ?? [];
    final valuesAndIdeas =
        (data['values_and_ideas'] as List?)?.cast<dynamic>() ?? [];

    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).padding.bottom + 80,
      ),
      children: [
        // Bio
        if (bio.isNotEmpty) ...[
          _SectionTitle(title: 'Bio', theme: theme),
          const SizedBox(height: 8),
          Text(bio, style: theme.textTheme.bodyMedium?.copyWith(height: 1.6)),
          const SizedBox(height: 20),
        ],

        // Compatibility score
        _SectionTitle(title: 'Compatibilidade', theme: theme),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.primaryContainer.withAlpha(40),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primary.withAlpha(40)),
          ),
          child: Row(
            children: [
              Text(
                _isLoadingCompat ? '...%' : '$_compatScore%',
                style: theme.textTheme.displaySmall?.copyWith(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'de interesses em comum',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: _compatScore / 100,
                      backgroundColor: AppTheme.primaryContainer,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppTheme.primary,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Sensory profile
        if (socialBattery != null || sensorySensitivity != null) ...[
          _SectionTitle(title: 'Perfil Sensorial', theme: theme),
          const SizedBox(height: 12),
          if (socialBattery != null)
            _SensoryBar(
              label: 'Bateria Social',
              value: socialBattery,
              max: 10,
              color: AppTheme.primary,
              theme: theme,
            ),
          if (sensorySensitivity != null) ...[
            const SizedBox(height: 10),
            _SensoryBar(
              label: 'Sensibilidade Sensorial',
              value: sensorySensitivity,
              max: 10,
              color: AppTheme.secondary,
              theme: theme,
            ),
          ],
          const SizedBox(height: 20),
        ],

        // Sensory triggers
        if (sensoryTriggers.isNotEmpty) ...[
          _SectionTitle(title: 'Gatilhos Sensoriais', theme: theme),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: sensoryTriggers
                .map(
                  (t) => _TagChip(label: t, color: Colors.orange, theme: theme),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
        ],

        // Political views
        if (politicalViews.isNotEmpty) ...[
          _SectionTitle(title: 'Visão Política', theme: theme),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: politicalViews
                .map(
                  (v) => _TagChip(label: v, color: Colors.blue, theme: theme),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
        ],

        // Religions
        if (religions.isNotEmpty) ...[
          _SectionTitle(title: 'Religião / Espiritualidade', theme: theme),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: religions
                .map(
                  (r) => _TagChip(label: r, color: Colors.purple, theme: theme),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
        ],

        // Values and ideas
        if (valuesAndIdeas.isNotEmpty) ...[
          _SectionTitle(title: 'Valores e Ideias', theme: theme),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: valuesAndIdeas.map((v) {
              final label = v is String ? v : v.toString();
              return Chip(
                label: Text(label),
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                side: BorderSide(color: theme.colorScheme.outlineVariant),
                labelStyle: theme.textTheme.labelMedium,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],

        // Active pet details
        if (_activePet != null) ...[
          _SectionTitle(title: 'Pet Ativo', theme: theme),
          const SizedBox(height: 12),
          _PetCard(pet: _activePet!, theme: theme),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

// ── Enums ─────────────────────────────────────────────────────────────────────

enum _ConnectionStatus { none, pending, pendingReceived, connected }

// ── Helper Widgets ────────────────────────────────────────────────────────────

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;
  final Color? valueColor;
  final bool tappable;

  const _StatItem({
    required this.label,
    required this.value,
    required this.theme,
    this.valueColor,
    this.tappable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tappable
                    ? AppTheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                decoration: tappable ? TextDecoration.underline : null,
              ),
            ),
            if (tappable) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 10,
                color: AppTheme.primary,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final ThemeData theme;
  const _SectionTitle({required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final Color color;
  final ThemeData theme;
  const _TagChip({
    required this.label,
    required this.color,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(color: color),
      ),
    );
  }
}

class _SensoryBar extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  final Color color;
  final ThemeData theme;

  const _SensoryBar({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (value / max).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            Text(
              '$value/$max',
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: pct,
          backgroundColor: color.withAlpha(30),
          valueColor: AlwaysStoppedAnimation<Color>(color),
          borderRadius: BorderRadius.circular(4),
          minHeight: 8,
        ),
      ],
    );
  }
}

class _PetCard extends StatelessWidget {
  final Map<String, dynamic> pet;
  final ThemeData theme;
  const _PetCard({required this.pet, required this.theme});

  @override
  Widget build(BuildContext context) {
    final photoUrl = pet['photo_url'] as String? ?? '';
    final name = pet['name'] as String? ?? 'Pet';
    final species = pet['species'] as String? ?? '';
    final breed = pet['breed'] as String? ?? '';
    final age = pet['age'] as String? ?? '';
    final role = pet['role'] as String? ?? '';
    final bio = pet['bio'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          if (photoUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomImageWidget(
                imageUrl: photoUrl,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                semanticLabel: 'Foto de $name',
              ),
            )
          else
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('🐾', style: TextStyle(fontSize: 28)),
              ),
            ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (species.isNotEmpty || breed.isNotEmpty)
                  Text(
                    [species, breed].where((s) => s.isNotEmpty).join(' • '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (age.isNotEmpty)
                  Text(
                    '$age anos',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (role.isNotEmpty)
                  Text(
                    role,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (bio.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    bio,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;

  _TabDelegate(this.tabBar, this.backgroundColor);

  @override
  double get minExtent => tabBar.preferredSize.height + 1;
  @override
  double get maxExtent => tabBar.preferredSize.height + 1;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: backgroundColor,
      child: Column(children: [tabBar, const Divider(height: 1)]),
    );
  }

  @override
  bool shouldRebuild(_TabDelegate oldDelegate) => false;
}
