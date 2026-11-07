import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_export.dart';
import '../../models/profile_match_result.dart';
import '../../models/user_profile.dart';
import '../../repositories/supabase_recommendation_repository.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_navigation.dart';
import '../../widgets/app_scaffold.dart' show navBarVisibleNotifier;
import '../user_profile_screen/user_profile_screen.dart';
import './widgets/friend_list_item_widget.dart';
import './widgets/friend_request_card_widget.dart';
import './widgets/suggestion_card_widget.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _suggestionsSearchController =
      TextEditingController();
  String _searchQuery = '';
  String _suggestionsSearchQuery = '';

  // ── Scroll controllers for hide-on-scroll nav bar ─────────────────────────
  final ScrollController _suggestionsScrollController = ScrollController();
  final ScrollController _requestsScrollController = ScrollController();
  final ScrollController _friendsScrollController = ScrollController();
  double _lastScrollOffset = 0.0;

  // ── Real Supabase recommendation engine ──────────────────────────────────
  final SupabaseRecommendationRepository _repository =
      const SupabaseRecommendationRepository();

  List<ProfileMatchResult> _recommendations = [];
  bool _loadingRecommendations = true;
  String? _recommendationError;

  // The current user's profile for scoring — loaded from Supabase
  UserProfile? _currentUserProfile;

  // ── Live Supabase data ────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _requestsMaps = [];
  final List<Map<String, dynamic>> _friendsMaps = [];
  bool _loadingRequests = true;
  bool _loadingFriends = true;

  // Tracks which suggestion ids have been connected
  final Set<String> _connectedIds = {};

  // ── Hyperfocus filter ─────────────────────────────────────────────────────
  String? _selectedHyperfocusFilter; // null = "Todos"

  // ── Realtime subscription ─────────────────────────────────────────────────
  RealtimeChannel? _friendshipsChannel;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadCurrentUserAndRecommendations();
    _loadFriendRequests();
    _loadFriends();
    _subscribeFriendships();
    _suggestionsScrollController.addListener(_onScroll);
    _requestsScrollController.addListener(_onScroll);
    _friendsScrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _friendshipsChannel?.unsubscribe();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    _suggestionsSearchController.dispose();
    _suggestionsScrollController.removeListener(_onScroll);
    _requestsScrollController.removeListener(_onScroll);
    _friendsScrollController.removeListener(_onScroll);
    _suggestionsScrollController.dispose();
    _requestsScrollController.dispose();
    _friendsScrollController.dispose();
    // Restore nav bar when leaving this screen
    navBarVisibleNotifier.value = true;
    super.dispose();
  }

  void _onScroll() {
    // Use the active tab's controller offset
    final ScrollController active;
    switch (_tabController.index) {
      case 0:
        active = _suggestionsScrollController;
        break;
      case 1:
        active = _requestsScrollController;
        break;
      default:
        active = _friendsScrollController;
    }
    if (!active.hasClients) return;
    final offset = active.offset;
    final delta = offset - _lastScrollOffset;
    _lastScrollOffset = offset;

    if (offset <= 10) {
      if (!navBarVisibleNotifier.value) navBarVisibleNotifier.value = true;
      return;
    }
    if (delta > 8 && navBarVisibleNotifier.value) {
      navBarVisibleNotifier.value = false;
    } else if (delta < -8 && !navBarVisibleNotifier.value) {
      navBarVisibleNotifier.value = true;
    }
  }

  void _onTabChanged() {
    // When user opens the Pedidos tab (index 1), clear the badge
    if (_tabController.index == 1) {
      pendingFriendRequestsNotifier.value = 0;
    }
  }

  /// Subscribe to Realtime changes on friendships so new requests appear
  /// instantly without requiring a manual refresh.
  void _subscribeFriendships() {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;

    _friendshipsChannel = SupabaseService.instance.client
        .channel('friendships_screen_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'friendships',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'addressee_id',
            value: uid,
          ),
          callback: (payload) {
            // A new friend request arrived — refresh the requests list
            if (mounted) {
              _loadFriendRequests();
              // Update global badge (only if not on Pedidos tab)
              if (_tabController.index != 1) {
                pendingFriendRequestsNotifier.value++;
              }
            }
          },
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
          callback: (payload) {
            final newStatus = payload.newRecord['status'] as String?;
            if (newStatus == 'accepted' && mounted) {
              _loadFriends();
            }
          },
        )
        .subscribe();
  }

  Future<void> _loadFriendRequests() async {
    try {
      final rows = await SupabaseService.instance.fetchFriendRequests();
      if (!mounted) return;
      final mapped = rows.map((r) {
        final requester = r['requester'] as Map<String, dynamic>? ?? {};
        return {
          'id': r['id'] ?? '',
          'requesterId': requester['id'] ?? r['requester_id'] ?? '',
          'name': requester['full_name'] ?? 'Usuário',
          'neurodivType': requester['neurodiv_type'] ?? '',
          'compatibilityPct': 0,
          'sharedHyperfocuses': <String>[],
          'imageUrl': requester['avatar_url'] ?? '',
          'imageSemantic': 'Foto de ${requester['full_name'] ?? 'Usuário'}',
          'timeAgo': '',
          'friendshipId': r['id'] ?? '',
        };
      }).toList();
      setState(() {
        _requestsMaps
          ..clear()
          ..addAll(mapped);
        _loadingRequests = false;
      });
      // Sync global badge with actual count (only if not viewing Pedidos tab)
      if (_tabController.index != 1) {
        pendingFriendRequestsNotifier.value = mapped.length;
      }
    } catch (_) {
      if (mounted) setState(() => _loadingRequests = false);
    }
  }

  Future<void> _loadFriends() async {
    try {
      final rows = await SupabaseService.instance.fetchFriends();
      if (!mounted) return;
      final uid = SupabaseService.instance.currentUserId;
      final mapped = rows.map((r) {
        final requester = r['requester'] as Map<String, dynamic>? ?? {};
        final addressee = r['addressee'] as Map<String, dynamic>? ?? {};
        final friend = requester['id'] == uid ? addressee : requester;
        return {
          'id': friend['id'] ?? '',
          'name': friend['full_name'] ?? 'Usuário',
          'neurodivType': friend['neurodiv_type'] ?? '',
          'isOnline': false,
          'lastSeen': '',
          'sharedHyperfocuses': <String>[],
          'imageUrl': friend['avatar_url'] ?? '',
          'imageSemantic': 'Foto de ${friend['full_name'] ?? 'Usuário'}',
        };
      }).toList();
      setState(() {
        _friendsMaps
          ..clear()
          ..addAll(mapped);
        _loadingFriends = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingFriends = false);
    }
  }

  // ── Recommendation loading ────────────────────────────────────────────────

  Future<void> _loadCurrentUserAndRecommendations() async {
    if (!mounted) return;
    setState(() {
      _loadingRecommendations = true;
      _recommendationError = null;
    });
    try {
      // Load the real current user profile for scoring
      final currentProfile = await _repository.fetchCurrentUserProfile();

      if (currentProfile == null) {
        if (mounted) {
          setState(() {
            _recommendationError =
                'Complete seu perfil para ver sugestões compatíveis.';
            _loadingRecommendations = false;
          });
        }
        return;
      }

      _currentUserProfile = currentProfile;

      final results = await _repository.fetchRecommendations(
        currentUser: currentProfile,
        limit: 30,
      );

      if (mounted) {
        setState(() {
          _recommendations = results;
          _loadingRecommendations = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _recommendationError = 'Não foi possível carregar sugestões.';
          _loadingRecommendations = false;
        });
      }
    }
  }

  /// Returns the list of unique hyperfocus tags from the current user's profile.
  List<String> get _myHyperfocusTags {
    final interests = _currentUserProfile?.hyperfocusInterests ?? [];
    final seen = <String>{};
    return interests
        .where((t) => t.isNotEmpty && seen.add(t.toLowerCase()))
        .toList();
  }

  /// Returns recommendations filtered by the selected hyperfocus tag AND search query.
  List<ProfileMatchResult> get _filteredRecommendations {
    var list = _recommendations;

    // Filter by hyperfocus chip
    if (_selectedHyperfocusFilter != null) {
      final filter = _selectedHyperfocusFilter!.toLowerCase();
      list = list.where((r) {
        final interests = r.profile.hyperfocusInterests
            .map((i) => i.toLowerCase())
            .toList();
        return interests.contains(filter);
      }).toList();
    }

    // Filter by search query (name or hyperfocus tags)
    if (_suggestionsSearchQuery.isNotEmpty) {
      final q = _suggestionsSearchQuery.toLowerCase();
      list = list.where((r) {
        final nameMatch = r.profile.displayName.toLowerCase().contains(q);
        final tagMatch = r.profile.hyperfocusInterests.any(
          (tag) => tag.toLowerCase().contains(q),
        );
        return nameMatch || tagMatch;
      }).toList();
    }

    return list;
  }

  /// Converts a [ProfileMatchResult] to the Map shape expected by
  /// [SuggestionCardWidget], preserving the existing widget contract.
  Map<String, dynamic> _resultToMap(ProfileMatchResult result) {
    final p = result.profile;

    // Map Neurotype enum to display string
    String neurodivLabel = _neurotypLabel(p.neurotypes);

    // Derive shared hyperfocuses between current user and candidate
    final currentInterests = (_currentUserProfile?.hyperfocusInterests ?? [])
        .map((e) => e.toLowerCase().trim())
        .toSet();
    final shared = p.hyperfocusInterests
        .where((i) => currentInterests.contains(i.toLowerCase().trim()))
        .toList();
    // If no exact overlap, show top interests from candidate
    final displayInterests = shared.isNotEmpty
        ? shared
        : p.hyperfocusInterests.take(2).toList();

    // Format distance label
    String? distanceLabel;
    if (result.distanceKm != null) {
      final km = result.distanceKm!;
      distanceLabel = km < 1.0 ? '< 1 km' : '${km.toStringAsFixed(1)} km';
    }

    return {
      'id': p.id,
      'name': p.displayName,
      'neurodivType': neurodivLabel,
      'compatibilityPct': result.matchPercentage,
      'sharedHyperfocuses': displayInterests,
      'sharedCount': displayInterests.length,
      'imageUrl': p.avatarUrl ?? '',
      'imageSemantic': '${p.displayName}, perfil de usuário na rede Sintonia',
      'bio': p.bio ?? '',
      'isConnecting': _connectedIds.contains(p.id),
      // Breakdown scores for the enhanced card
      'interestsScore': (result.interestsScore * 100).round(),
      'valuesScore': (result.valuesScore * 100).round(),
      'neurotypesScore': (result.neurotypesScore * 100).round(),
      'communicationScore': (result.communicationScore * 100).round(),
      // AI refinement data
      'aiInsight': result.aiInsight,
      'shortInsight': result.shortInsight,
      'aiRefined': result.aiRefined,
      'connectionPotential': result.connectionPotential,
      // Distance from RPC
      'distanceLabel': distanceLabel,
    };
  }

  String _neurotypLabel(List<Neurotype> types) {
    if (types.isEmpty) return 'ND';
    switch (types.first) {
      case Neurotype.adhd:
        return 'TDAH';
      case Neurotype.asd:
        return 'TEA';
      case Neurotype.dyslexia:
        return 'Dislexia';
      case Neurotype.giftedHighAbility:
        return 'AH/SD';
      case Neurotype.dyscalculia:
        return 'Discalculia';
      case Neurotype.dyspraxia:
        return 'Dispraxia';
      case Neurotype.tourette:
        return 'Tourette';
      case Neurotype.anxiety:
        return 'Ansiedade';
      case Neurotype.depression:
        return 'Depressão';
      case Neurotype.bipolar:
        return 'Bipolar';
      case Neurotype.neurotypical:
        return 'NT';
    }
  }

  void _connectSuggestion(String id) {
    setState(() => _connectedIds.add(id));
    SupabaseService.instance.sendFriendRequest(id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.person_add_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Pedido de amizade enviado! 🎉'),
          ],
        ),
        backgroundColor: AppTheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _acceptRequest(String id) {
    final req = _requestsMaps.firstWhere(
      (r) => r['id'] == id,
      orElse: () => {},
    );
    final friendshipId = req['friendshipId'] as String? ?? id;
    SupabaseService.instance.acceptFriendRequest(friendshipId);
    setState(() => _requestsMaps.removeWhere((r) => r['id'] == id));
    // Update global badge count
    if (pendingFriendRequestsNotifier.value > 0) {
      pendingFriendRequestsNotifier.value--;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Amizade aceita! 🎉'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    _loadFriends();
  }

  void _declineRequest(String id) {
    final req = _requestsMaps.firstWhere(
      (r) => r['id'] == id,
      orElse: () => {},
    );
    final friendshipId = req['friendshipId'] as String? ?? id;
    SupabaseService.instance.declineFriendRequest(friendshipId);
    setState(() => _requestsMaps.removeWhere((r) => r['id'] == id));
    // Update global badge count
    if (pendingFriendRequestsNotifier.value > 0) {
      pendingFriendRequestsNotifier.value--;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    // With extendBody: true, padding.bottom already includes the full nav bar height.
    final listBottomPadding = bottomPadding + 16.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Amigos', style: theme.textTheme.headlineSmall),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
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
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                tabs: [
                  const Tab(text: 'Sugestões'),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Pedidos'),
                        if (_requestsMaps.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(80),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                _requestsMaps.length.toString(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Tab(text: 'Amigos'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // ── Suggestions tab (engine-powered) ──────────────────────
                  _buildSuggestionsTab(theme, listBottomPadding),

                  // ── Requests tab ──────────────────────────────────────────
                  _loadingRequests
                      ? const Center(child: CircularProgressIndicator())
                      : _requestsMaps.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_add_outlined,
                                size: 56,
                                color: theme.colorScheme.outlineVariant,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Nenhum pedido pendente',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _requestsScrollController,
                          padding: EdgeInsets.fromLTRB(
                            16,
                            16,
                            16,
                            listBottomPadding,
                          ),
                          itemCount: _requestsMaps.length,
                          itemBuilder: (context, index) =>
                              FriendRequestCardWidget(
                                request: _requestsMaps[index],
                                onTap: () {
                                  final req = _requestsMaps[index];
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => UserProfileScreen(
                                        userData: {
                                          'id': req['requesterId'],
                                          'full_name': req['name'],
                                          'avatar_url': req['imageUrl'],
                                          'neurodiv_type': req['neurodivType'],
                                        },
                                      ),
                                    ),
                                  );
                                },
                                onAccept: () => _acceptRequest(
                                  _requestsMaps[index]['id'] as String,
                                ),
                                onDecline: () => _declineRequest(
                                  _requestsMaps[index]['id'] as String,
                                ),
                              ),
                        ),

                  // ── Friends tab ───────────────────────────────────────────
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (v) =>
                              setState(() => _searchQuery = v.toLowerCase()),
                          decoration: InputDecoration(
                            hintText: 'Buscar amigos...',
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: theme.colorScheme.onSurfaceVariant,
                              size: 20,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            filled: true,
                            fillColor: theme.colorScheme.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(100),
                              borderSide: BorderSide(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(100),
                              borderSide: BorderSide(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(100),
                              borderSide: const BorderSide(
                                color: AppTheme.primary,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: _friendsScrollController,
                          padding: EdgeInsets.fromLTRB(
                            16,
                            4,
                            16,
                            listBottomPadding,
                          ),
                          itemCount: _friendsMaps
                              .where(
                                (f) =>
                                    _searchQuery.isEmpty ||
                                    (f['name'] as String)
                                        .toLowerCase()
                                        .contains(_searchQuery),
                              )
                              .length,
                          itemBuilder: (context, index) {
                            final filtered = _friendsMaps
                                .where(
                                  (f) =>
                                      _searchQuery.isEmpty ||
                                      (f['name'] as String)
                                          .toLowerCase()
                                          .contains(_searchQuery),
                                )
                                .toList();
                            return FriendListItemWidget(
                              friend: filtered[index],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionsTab(ThemeData theme, double bottomPadding) {
    if (_loadingRecommendations) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Analisando compatibilidade com IA...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Gemini está refinando suas sugestões 🧠✨',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_recommendationError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 48,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _recommendationError!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadCurrentUserAndRecommendations,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    if (_recommendations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 56,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Nenhuma sugestão disponível',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Complete seu perfil com hiperfocuses e interesses\npara encontrar pessoas compatíveis.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final aiRefinedCount = _recommendations.where((r) => r.aiRefined).length;
    final isAiRefined = aiRefinedCount > 0;
    final myTags = _myHyperfocusTags;
    final filtered = _filteredRecommendations;

    return Column(
      children: [
        // ── Search bar for suggestions ─────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _suggestionsSearchController,
            onChanged: (v) =>
                setState(() => _suggestionsSearchQuery = v.toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Buscar por nome ou hiperfoco...',
              prefixIcon: Icon(
                Icons.search_rounded,
                color: theme.colorScheme.onSurfaceVariant,
                size: 20,
              ),
              suffixIcon: _suggestionsSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () {
                        _suggestionsSearchController.clear();
                        setState(() => _suggestionsSearchQuery = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              filled: true,
              fillColor: theme.colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(100),
                borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(100),
                borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(100),
                borderSide: const BorderSide(color: AppTheme.primary, width: 2),
              ),
            ),
          ),
        ),

        // ── Hyperfocus filter chip bar ─────────────────────────────────────
        if (myTags.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              children: [
                // "Todos" chip
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('Todos'),
                    selected: _selectedHyperfocusFilter == null,
                    onSelected: (_) =>
                        setState(() => _selectedHyperfocusFilter = null),
                    selectedColor: AppTheme.primary.withAlpha(30),
                    checkmarkColor: AppTheme.primary,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _selectedHyperfocusFilter == null
                          ? AppTheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    side: BorderSide(
                      color: _selectedHyperfocusFilter == null
                          ? AppTheme.primary
                          : theme.colorScheme.outlineVariant,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                // One chip per hyperfocus tag
                ...myTags.map((tag) {
                  final isSelected = _selectedHyperfocusFilter == tag;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(tag),
                      selected: isSelected,
                      onSelected: (_) => setState(
                        () =>
                            _selectedHyperfocusFilter = isSelected ? null : tag,
                      ),
                      selectedColor: AppTheme.primary.withAlpha(30),
                      checkmarkColor: AppTheme.primary,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? AppTheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      side: BorderSide(
                        color: isSelected
                            ? AppTheme.primary
                            : theme.colorScheme.outlineVariant,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  );
                }),
              ],
            ),
          ),

        // Engine info banner
        Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isAiRefined
                  ? [
                      AppTheme.primary.withAlpha(30),
                      const Color(0xFF7C3AED).withAlpha(20),
                    ]
                  : [
                      AppTheme.primary.withAlpha(25),
                      AppTheme.secondary.withAlpha(20),
                    ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isAiRefined
                  ? const Color(0xFF7C3AED).withAlpha(80)
                  : AppTheme.primary.withAlpha(60),
            ),
          ),
          child: Row(
            children: [
              Text(
                isAiRefined ? '🤖' : '✨',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isAiRefined
                              ? 'Sugestões Refinadas por Gemini IA'
                              : 'Motor de Compatibilidade Ativo',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: isAiRefined
                                ? const Color(0xFF7C3AED)
                                : AppTheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (isAiRefined) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C3AED).withAlpha(30),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              'IA',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: const Color(0xFF7C3AED),
                                fontWeight: FontWeight.w800,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      _suggestionsSearchQuery.isNotEmpty
                          ? '${filtered.length} resultado${filtered.length != 1 ? 's' : ''} para "$_suggestionsSearchQuery"'
                          : _selectedHyperfocusFilter != null
                          ? '${filtered.length} perfis com hiperfoco em "$_selectedHyperfocusFilter"'
                          : isAiRefined
                          ? '${_recommendations.length} perfis analisados por hiperfocuses, comunicação e neurotipo'
                          : '${_recommendations.length} perfis ranqueados por hiperfocuses, valores, neurotipo e comunicação',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _loadCurrentUserAndRecommendations,
                child: Icon(
                  Icons.refresh_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 48,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _suggestionsSearchQuery.isNotEmpty
                            ? 'Nenhum resultado para "$_suggestionsSearchQuery"'
                            : 'Nenhum perfil com esse hiperfoco',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          _suggestionsSearchController.clear();
                          setState(() {
                            _suggestionsSearchQuery = '';
                            _selectedHyperfocusFilter = null;
                          });
                        },
                        child: const Text('Limpar filtros'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _suggestionsScrollController,
                  padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final result = filtered[index];
                    final suggestionMap = _resultToMap(result);
                    final isFriend = _friendsMaps.any(
                      (f) => f['id'] == result.profile.id,
                    );
                    return SuggestionCardWidget(
                      suggestion: suggestionMap,
                      onConnect: () => _connectSuggestion(result.profile.id),
                      isFriend: isFriend,
                      onViewProfile: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UserProfileScreen(
                              userData: {
                                'id': result.profile.id,
                                'full_name': result.profile.displayName,
                                'avatar_url': result.profile.avatarUrl ?? '',
                                'neurodiv_type': suggestionMap['neurodivType'],
                              },
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
