import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_export.dart';
import '../../services/avatar_notifier.dart';
import '../../services/media_processing_service.dart';
import '../../services/notification_service.dart';
import '../../services/pet_avatar_notifier.dart';
import '../../services/supabase_service.dart';
import '../media_upload/media_upload_modal.dart';
import '../user_profile_screen/widgets/friends_list_page.dart';
import './subpages/edit_profile_and_feed_screen.dart';
import './subpages/followers_screen.dart';
import './subpages/profile_diary_screen.dart';
import './subpages/profile_settings_screen.dart';
import './widgets/hyperfocus_section_widget.dart';
import './widgets/profile_posts_grid_widget.dart';
import './widgets/profile_stats_widget.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoadingProfile = true;

  Map<String, dynamic> _profileData = {
    'name': '',
    'username': '',
    'bio': '',
    'neurodivType': '',
    'avatarUrl': '',
    'avatarSemantic': 'Foto de perfil',
    'petName': null,
    'petAvatarUrl': null,
    'petAvatarSemantic': null,
    'friendsCount': 0,
    'postsCount': 0,
    'compatScore': 0,
    'hyperfocuses': <Map<String, dynamic>>[],
    'interests': <String>[],
  };

  final List<Map<String, dynamic>> _postsMaps = [];
  final List<Map<String, dynamic>> _savedPostsMaps = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  bool _isLoadingRequests = false;
  RealtimeChannel? _friendshipChannel;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    AvatarNotifier.instance.addListener(_onAvatarChanged);
    PetAvatarNotifier.instance.addListener(_onPetAvatarChanged);
    _loadProfileData();
    _loadUserPosts();
    _loadSavedPosts();
    _loadPendingRequests();
    _subscribeFriendshipRealtime();
  }

  void _onAvatarChanged() {
    if (!mounted) return;
    final newUrl = AvatarNotifier.instance.value;
    if (newUrl.isNotEmpty) {
      setState(() {
        _profileData = {..._profileData, 'avatarUrl': newUrl};
      });
    }
  }

  void _onPetAvatarChanged() {
    if (!mounted) return;
    final newUrl = PetAvatarNotifier.instance.value;
    if (newUrl.isNotEmpty) {
      setState(() {
        _profileData = {
          ..._profileData,
          'petAvatarUrl': newUrl,
          'petPhotoUrl': newUrl,
        };
      });
    }
  }

  Future<void> _loadPendingRequests() async {
    if (!mounted) return;
    setState(() => _isLoadingRequests = true);
    try {
      final requests = await SupabaseService.instance.fetchFriendRequests();
      if (!mounted) return;
      setState(() {
        _pendingRequests = requests;
        _isLoadingRequests = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingRequests = false);
    }
  }

  void _subscribeFriendshipRealtime() {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;

    _friendshipChannel = SupabaseService.instance.client
        .channel('profile_friendships:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'friendships',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'addressee_id',
            value: uid,
          ),
          callback: (_) => _loadPendingRequests(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'friendships',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'addressee_id',
            value: uid,
          ),
          callback: (_) => _loadPendingRequests(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'friendships',
          callback: (_) => _loadPendingRequests(),
        )
        .subscribe();
  }

  Future<void> _acceptRequest(String friendshipId) async {
    final ok = await SupabaseService.instance.acceptFriendRequest(friendshipId);
    if (ok && mounted) {
      setState(() {
        _pendingRequests.removeWhere((r) => r['id'] == friendshipId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solicitação aceita! Vocês agora são amigos 🎉'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
      // Refresh notification service so bell count updates
      NotificationService.instance.fetchNotifications();
    }
  }

  Future<void> _declineRequest(String friendshipId) async {
    final ok = await SupabaseService.instance.declineFriendRequest(
      friendshipId,
    );
    if (ok && mounted) {
      setState(() {
        _pendingRequests.removeWhere((r) => r['id'] == friendshipId);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Solicitação recusada.')));
      NotificationService.instance.fetchNotifications();
    }
  }

  Future<void> _loadUserPosts() async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;
    try {
      final posts = await SupabaseService.instance.fetchUserPosts(uid);
      if (!mounted) return;
      final mapped = posts
          .map(
            (p) => {
              'id': p['id'] ?? '',
              'imageUrl': (p['image_url'] as String?)?.isNotEmpty == true
                  ? p['image_url']
                  : null,
              'semanticLabel': p['image_semantic'] ?? '',
              'likes': p['likes_count'] ?? 0,
              'hasImage': (p['image_url'] as String?)?.isNotEmpty == true,
              'content': p['content'] ?? '',
            },
          )
          .toList();
      setState(() {
        _postsMaps
          ..clear()
          ..addAll(mapped);
        _profileData = {..._profileData, 'postsCount': mapped.length};
      });
    } catch (_) {}
  }

  Future<void> _loadSavedPosts() async {
    try {
      final saved = await SupabaseService.instance.fetchSavedPostsMapped();
      if (!mounted) return;
      setState(() {
        _savedPostsMaps
          ..clear()
          ..addAll(saved);
      });
    } catch (_) {}
  }

  Future<void> _loadProfileData() async {
    try {
      final profile = await SupabaseService.instance
          .fetchProfileWithActivePet();
      if (profile != null && mounted) {
        final hyperfocuses =
            (profile['hyperfocuses'] as List?)
                ?.map(
                  (h) => {
                    'name': h['name'] ?? '',
                    'icon': 'star_outlined',
                    'color': h['color'] ?? 0xFF4A90D9,
                  },
                )
                .toList() ??
            <Map<String, dynamic>>[];

        final interests =
            (profile['interests'] as List?)
                ?.map((i) => i.toString())
                .toList() ??
            <String>[];

        final activePet = profile['activePet'] as Map<String, dynamic>?;

        setState(() {
          _profileData = {
            ..._profileData,
            'name': profile['full_name'] ?? '',
            'username': '@${profile['username'] ?? ''}',
            'bio': profile['bio'] ?? '',
            'neurodivType': profile['neurodiv_type'] ?? '',
            'avatarUrl': (profile['avatar_url'] as String?)?.isNotEmpty == true
                ? profile['avatar_url']
                : '',
            'hyperfocuses': hyperfocuses,
            'interests': interests,
            'activePetId': activePet?['id'] ?? '',
            'petName': activePet?['name'],
            'petAvatarUrl':
                (activePet?['thumbnailUrl'] as String?)?.isNotEmpty == true
                ? activePet!['thumbnailUrl']
                : null,
            'petPhotoUrl':
                (activePet?['photoUrl'] as String?)?.isNotEmpty == true
                ? activePet!['photoUrl']
                : null,
            'petAvatarSemantic': activePet != null
                ? 'Foto do pet ${activePet['name'] ?? ''}'
                : 'Foto do pet',
          };
          _isLoadingProfile = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingProfile = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  Future<void> _loadPetData() async {
    // No-op: pet data is now loaded via fetchProfileWithActivePet
  }

  void _openPetPhotoFullscreen() {
    final petPhotoUrl =
        _profileData['petPhotoUrl'] as String? ??
        _profileData['petAvatarUrl'] as String?;
    final petName = _profileData['petName'] as String? ?? 'Pet';
    if (petPhotoUrl == null || petPhotoUrl.isEmpty) return;

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Center(
                child: Hero(
                  tag: 'pet_badge_photo',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: CustomImageWidget(
                      imageUrl: petPhotoUrl,
                      width: 85.w,
                      height: 85.w,
                      fit: BoxFit.cover,
                      semanticLabel: 'Foto em tamanho cheio de $petName',
                    ),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 16,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🐾', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Text(
                          petName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    AvatarNotifier.instance.removeListener(_onAvatarChanged);
    PetAvatarNotifier.instance.removeListener(_onPetAvatarChanged);
    _tabController.dispose();
    _friendshipChannel?.unsubscribe();
    super.dispose();
  }

  void _navigateToEditProfile() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const EditProfileAndFeedScreen()),
    );
    if (mounted) {
      _loadProfileData();
    }
  }

  void _openProfilePictureModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MediaUploadModal(
        initialAction: MediaActionType.updateProfilePicture,
        currentUser: _profileData,
        onProfilePictureUpdated: (newUrl) {
          if (mounted) {
            setState(() {
              _profileData = {..._profileData, 'avatarUrl': newUrl};
            });
          }
        },
      ),
    );
  }

  void _navigateToFollowers() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            FollowersScreen(friendsCount: _profileData['friendsCount'] as int),
      ),
    );
  }

  void _navigateToFriendsList() {
    final uid = SupabaseService.instance.currentUserId ?? '';
    final name = _profileData['name'] as String? ?? '';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FriendsListPage(userId: uid, userName: name),
      ),
    );
  }

  void _scrollToPublications() {
    // Switch to the first tab (Publicações) and scroll to top
    _tabController.animateTo(0);
  }

  void _navigateToDiary() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ProfileDiaryScreen()));
  }

  void _navigateToSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final listBottomPadding = bottomPadding + 16.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              backgroundColor: theme.scaffoldBackgroundColor,
              elevation: 0,
              floating: true,
              snap: true,
              automaticallyImplyLeading: false,
              title: Text('Meu Perfil', style: theme.textTheme.headlineSmall),
              actions: [
                // Friend requests badge button
                if (_pendingRequests.isNotEmpty)
                  Stack(
                    children: [
                      IconButton(
                        onPressed: _showFriendRequestsSheet,
                        icon: const Icon(Icons.person_add_rounded),
                        tooltip: 'Solicitações de amizade',
                      ),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: Color(0xFFE91E63),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              _pendingRequests.length > 9
                                  ? '9+'
                                  : '${_pendingRequests.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                IconButton(
                  onPressed: _navigateToDiary,
                  icon: const Icon(Icons.book_outlined),
                  tooltip: 'Diário',
                ),
                IconButton(
                  onPressed: _navigateToSettings,
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Configurações',
                ),
              ],
            ),
            SliverToBoxAdapter(child: _buildProfileHeader(theme)),
            // Friend requests inline section
            if (_pendingRequests.isNotEmpty)
              SliverToBoxAdapter(child: _buildFriendRequestsSection(theme)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: HyperfocusSectionWidget(
                  hyperfocuses: (_profileData['hyperfocuses'] as List)
                      .cast<Map<String, dynamic>>(),
                  interests: (_profileData['interests'] as List).cast<String>(),
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
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
                    Tab(text: 'Salvos'),
                  ],
                ),
                theme.colorScheme.surface,
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              ProfilePostsGridWidget(
                posts: _postsMaps,
                author: _profileData,
                bottomPadding: listBottomPadding,
              ),
              ProfilePostsGridWidget(
                posts: _savedPostsMaps,
                author: _profileData,
                bottomPadding: listBottomPadding,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendRequestsSection(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.person_add_rounded,
                  color: AppTheme.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Solicitações de amizade',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.sp,
                    color: AppTheme.primary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '${_pendingRequests.length}',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...(_pendingRequests
              .take(3)
              .map(
                (req) => _FriendRequestTile(
                  request: req,
                  onAccept: () => _acceptRequest(req['id'] as String),
                  onDecline: () => _declineRequest(req['id'] as String),
                ),
              )),
          if (_pendingRequests.length > 3)
            InkWell(
              onTap: _showFriendRequestsSheet,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Text(
                    'Ver todas (${_pendingRequests.length})',
                    style: GoogleFonts.inter(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.sp,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showFriendRequestsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FriendRequestsSheet(
        requests: _pendingRequests,
        onAccept: (id) => _acceptRequest(id),
        onDecline: (id) => _declineRequest(id),
      ),
    );
  }

  Widget _buildProfileHeader(ThemeData theme) {
    final avatarUrl = _profileData['avatarUrl'] as String? ?? '';
    final petAvatarUrl = _profileData['petAvatarUrl'] as String?;
    final petAvatarSemantic =
        _profileData['petAvatarSemantic'] as String? ?? 'Foto do pet';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GestureDetector(
                      onTap: _openProfilePictureModal,
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
                          child: avatarUrl.isNotEmpty
                              ? CustomImageWidget(
                                  key: ValueKey(avatarUrl),
                                  imageUrl: avatarUrl,
                                  width: 88,
                                  height: 88,
                                  fit: BoxFit.cover,
                                  semanticLabel:
                                      _profileData['avatarSemantic'] as String,
                                )
                              : Container(
                                  width: 88,
                                  height: 88,
                                  color: AppTheme.primary.withAlpha(30),
                                  child: const Icon(
                                    Icons.person_rounded,
                                    size: 44,
                                    color: AppTheme.primary,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () {
                          final petUrl =
                              _profileData['petAvatarUrl'] as String?;
                          if (petUrl != null && petUrl.isNotEmpty) {
                            _openPetPhotoFullscreen();
                          } else {
                            _navigateToEditProfile();
                          }
                        },
                        child: Hero(
                          tag: 'pet_badge_photo',
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).scaffoldBackgroundColor,
                                width: 2,
                              ),
                              color: AppTheme.primary.withAlpha(30),
                            ),
                            child: ClipOval(
                              child:
                                  (_profileData['petAvatarUrl'] as String?) !=
                                          null &&
                                      (_profileData['petAvatarUrl'] as String)
                                          .isNotEmpty
                                  ? CustomImageWidget(
                                      key: ValueKey(
                                        _profileData['petAvatarUrl'],
                                      ),
                                      imageUrl:
                                          _profileData['petAvatarUrl']
                                              as String,
                                      width: 34,
                                      height: 34,
                                      fit: BoxFit.cover,
                                      semanticLabel:
                                          _profileData['petAvatarSemantic']
                                              as String? ??
                                          'Foto do pet',
                                    )
                                  : const Icon(
                                      Icons.pets_rounded,
                                      size: 18,
                                      color: AppTheme.primary,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: ProfileStatsWidget(
                  friendsCount: _profileData['friendsCount'] as int,
                  postsCount: _profileData['postsCount'] as int,
                  compatScore: _profileData['compatScore'] as int,
                  onFriendsTap: _navigateToFriendsList,
                  onPostsTap: _scrollToPublications,
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
                        _profileData['name'] as String,
                        style: theme.textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if ((_profileData['neurodivType'] as String)
                        .isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.teaColor.withAlpha(20),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: AppTheme.teaColor.withAlpha(80),
                          ),
                        ),
                        child: Text(
                          _profileData['neurodivType'] as String,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppTheme.teaColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _profileData['username'] as String,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                if ((_profileData['bio'] as String).isNotEmpty)
                  Text(
                    _profileData['bio'] as String,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                if (_profileData['petName'] != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('🐾', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Text(
                        _profileData['petName'] as String,
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _navigateToEditProfile,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Editar Perfil'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: _navigateToDiary,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.secondary,
                  side: const BorderSide(color: AppTheme.secondary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 16,
                  ),
                ),
                child: const Icon(Icons.book_outlined, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Friend Request Tile ──────────────────────────────────────────────────────

class _FriendRequestTile extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _FriendRequestTile({
    required this.request,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final requester = request['requester'] as Map<String, dynamic>? ?? {};
    final name =
        requester['full_name'] as String? ??
        requester['username'] as String? ??
        'Usuário';
    final avatarUrl = requester['avatar_url'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppTheme.primary.withAlpha(30),
            backgroundImage: avatarUrl.isNotEmpty
                ? CachedNetworkImageProvider(avatarUrl)
                : null,
            child: avatarUrl.isEmpty
                ? const Icon(
                    Icons.person_rounded,
                    color: AppTheme.primary,
                    size: 22,
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 13.sp,
                color: theme.colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onAccept,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              minimumSize: const Size(72, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Aceitar',
              style: GoogleFonts.inter(
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          OutlinedButton(
            onPressed: onDecline,
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurfaceVariant,
              side: BorderSide(color: theme.colorScheme.outlineVariant),
              minimumSize: const Size(72, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Recusar',
              style: GoogleFonts.inter(
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Friend Requests Bottom Sheet ────────────────────────────────────────────

class _FriendRequestsSheet extends StatelessWidget {
  final List<Map<String, dynamic>> requests;
  final void Function(String id) onAccept;
  final void Function(String id) onDecline;

  const _FriendRequestsSheet({
    required this.requests,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: bottomPadding + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.person_add_rounded, color: AppTheme.primary),
                const SizedBox(width: 10),
                Text(
                  'Solicitações de amizade',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 16.sp,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '${requests.length}',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.55,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: requests.length,
              itemBuilder: (context, index) {
                final req = requests[index];
                return _FriendRequestTile(
                  request: req,
                  onAccept: () {
                    onAccept(req['id'] as String);
                    if (requests.length <= 1) Navigator.of(context).pop();
                  },
                  onDecline: () {
                    onDecline(req['id'] as String);
                    if (requests.length <= 1) Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tab Bar Delegate ─────────────────────────────────────────────────────────

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;

  _TabBarDelegate(this.tabBar, this.backgroundColor);

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
  bool shouldRebuild(_TabBarDelegate oldDelegate) => false;
}
