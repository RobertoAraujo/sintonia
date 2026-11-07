import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sizer/sizer.dart';

import '../../models/user_profile.dart';
import '../../models/profile_match_result.dart';
import '../../repositories/supabase_recommendation_repository.dart';
import '../../services/recommendation_engine_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../user_profile_screen/user_profile_screen.dart';

/// Screen that allows searching for user profiles and viewing compatibility.
class ProfileSearchScreen extends StatefulWidget {
  /// The current logged-in user profile used for compatibility calculation.
  final UserProfile currentUserProfile;

  const ProfileSearchScreen({super.key, required this.currentUserProfile});

  @override
  State<ProfileSearchScreen> createState() => _ProfileSearchScreenState();
}

class _ProfileSearchScreenState extends State<ProfileSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final RecommendationEngineService _engine =
      const RecommendationEngineService();
  final SupabaseRecommendationRepository _repo =
      const SupabaseRecommendationRepository();

  // Suggestions (affinity-sorted, shown when query is empty)
  List<ProfileMatchResult> _suggestions = [];
  bool _loadingSuggestions = false;
  bool _suggestionsLoaded = false;

  // Search results
  List<ProfileMatchResult> _searchResults = [];
  bool _isSearching = false;
  String _query = '';

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onQueryChanged);
    _loadSuggestions();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Load affinity-sorted suggestions ──────────────────────────────────────

  Future<void> _loadSuggestions() async {
    if (_suggestionsLoaded) return;
    setState(() => _loadingSuggestions = true);
    try {
      final results = await _repo.fetchRecommendations(
        currentUser: widget.currentUserProfile,
        limit: 30,
      );
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _loadingSuggestions = false;
        _suggestionsLoaded = true;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingSuggestions = false);
    }
  }

  // ── Search by name or interest ─────────────────────────────────────────────

  void _onQueryChanged() {
    final q = _searchController.text.trim();
    if (q == _query) return;
    setState(() => _query = q);

    _debounce?.cancel();
    if (q.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    if (q.trim().isEmpty) return;
    setState(() => _isSearching = true);
    try {
      final uid = SupabaseService.instance.currentUserId;
      final qLower = q.trim().toLowerCase();

      // Fetch from DB: search by name, username, or hyperfocus/interest
      final byName = await SupabaseService.instance.searchUsers(q.trim());

      // Also search by hyperfocus/interest via a separate query
      List<Map<String, dynamic>> byInterest = [];
      try {
        final data = await SupabaseService.instance.client
            .from('user_profiles')
            .select(
              'id, full_name, username, avatar_url, bio, neurodiv_type, '
              'hyperfocuses, interests, communication_styles, values_and_ideas, '
              'communication_preferences',
            )
            .or('hyperfocuses.cs.{"$q"},interests.cs.{"$q"}')
            .neq('id', uid ?? '')
            .limit(20);
        byInterest = List<Map<String, dynamic>>.from(data);
      } catch (_) {
        // Fallback: filter from suggestions by interest match
        byInterest = [];
      }

      // Merge and deduplicate
      final seen = <String>{};
      final merged = <Map<String, dynamic>>[];
      for (final p in [...byName, ...byInterest]) {
        final id = p['id'] as String? ?? '';
        if (id.isNotEmpty && id != uid && seen.add(id)) {
          merged.add(p);
        }
      }

      // Convert to UserProfile and score against current user
      final candidates = merged
          .map((row) => _mapRowToUserProfile(row))
          .toList();
      final scored = _engine.getRecommendedProfiles(
        currentUser: widget.currentUserProfile,
        candidateProfiles: candidates,
        limit: 50,
      );

      // Attach raw DB data for display (username, neurodiv_type, etc.)
      final rawById = {for (final r in merged) r['id'] as String: r};
      final enriched = scored.map((result) {
        final raw = rawById[result.profile.id];
        if (raw == null) return result;
        return _ProfileMatchResultWithRaw(result: result, raw: raw);
      }).toList();

      // Also include name/username matches that scored 0 (still relevant)
      // Sort: first by score desc, then alphabetically
      enriched.sort((a, b) {
        final aScore = a is _ProfileMatchResultWithRaw
            ? a.matchScore
            : (a).matchScore;
        final bScore = b is _ProfileMatchResultWithRaw
            ? b.matchScore
            : (b).matchScore;
        return bScore.compareTo(aScore);
      });

      if (!mounted) return;
      setState(() {
        _searchResults = enriched.cast<ProfileMatchResult>();
        _isSearching = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  UserProfile _mapRowToUserProfile(Map<String, dynamic> row) {
    // ── Neurotypes ──────────────────────────────────────────────────────────
    List<Neurotype> neurotypes = [];
    final ntRaw = row['neurodiv_type'];
    final ntList = ntRaw is List
        ? ntRaw.map((e) => e.toString().toLowerCase().trim()).toList()
        : [((ntRaw as String?) ?? '').toLowerCase().trim()];

    const ntMap = {
      'tdah': Neurotype.adhd,
      'adhd': Neurotype.adhd,
      'tea': Neurotype.asd,
      'asd': Neurotype.asd,
      'autismo': Neurotype.asd,
      'dislexia': Neurotype.dyslexia,
      'dyslexia': Neurotype.dyslexia,
      'superdotacao': Neurotype.giftedHighAbility,
      'superdotação': Neurotype.giftedHighAbility,
      'gifted': Neurotype.giftedHighAbility,
      'discalculia': Neurotype.dyscalculia,
      'dyscalculia': Neurotype.dyscalculia,
      'tourette': Neurotype.tourette,
      'toc': Neurotype.anxiety,
      'anxiety': Neurotype.anxiety,
      'ansiedade': Neurotype.anxiety,
      'depressao': Neurotype.depression,
      'depressão': Neurotype.depression,
      'depression': Neurotype.depression,
      'bipolar': Neurotype.bipolar,
      'neurotipico': Neurotype.neurotypical,
      'neurotípico': Neurotype.neurotypical,
      'neurotypical': Neurotype.neurotypical,
      'outro': Neurotype.neurotypical,
      'other': Neurotype.neurotypical,
    };

    for (final nt in ntList) {
      if (nt.isNotEmpty && ntMap.containsKey(nt)) {
        neurotypes.add(ntMap[nt]!);
      }
    }

    // ── Helper to parse string lists from DB ────────────────────────────────
    List<String> parseList(String key) {
      final raw = row[key];
      if (raw is List) return raw.map((e) => e.toString()).toList();
      if (raw is String && raw.isNotEmpty) return [raw];
      return [];
    }

    // ── Communication styles ────────────────────────────────────────────────
    // DB stores communication_styles and communication_preferences as text arrays
    const commStyleMap = {
      'texto_curto': CommunicationStyle.shortText,
      'short_text': CommunicationStyle.shortText,
      'texto_longo': CommunicationStyle.longText,
      'long_text': CommunicationStyle.longText,
      'audio': CommunicationStyle.audio,
      'video': CommunicationStyle.video,
      'mensagens_diretas': CommunicationStyle.directMessages,
      'direct_messages': CommunicationStyle.directMessages,
      'mensagens_assincronas': CommunicationStyle.asyncMessages,
      'async_messages': CommunicationStyle.asyncMessages,
      'emojis': CommunicationStyle.emojiHeavy,
      'emoji_heavy': CommunicationStyle.emojiHeavy,
      'formal': CommunicationStyle.formalTone,
      'formal_tone': CommunicationStyle.formalTone,
      'informal': CommunicationStyle.informalTone,
      'informal_tone': CommunicationStyle.informalTone,
    };

    final rawCommStyles = [
      ...parseList('communication_styles'),
      ...parseList('communication_preferences'),
    ];
    final communicationStyles = rawCommStyles
        .map((s) => commStyleMap[s.toLowerCase().trim()])
        .whereType<CommunicationStyle>()
        .toSet()
        .toList();

    // ── Hyperfocus + interests ──────────────────────────────────────────────
    final hyperfocusInterests =
        parseList('hyperfocuses') + parseList('interests');

    // ── Values and ideas ────────────────────────────────────────────────────
    final valuesAndIdeas = parseList('values_and_ideas');

    return UserProfile(
      id: row['id'] as String? ?? '',
      displayName: row['full_name'] as String? ?? 'Usuário',
      avatarUrl: row['avatar_url'] as String?,
      bio: row['bio'] as String?,
      neurotypes: neurotypes,
      hyperfocusInterests: hyperfocusInterests,
      communicationStyles: communicationStyles,
      valuesAndIdeas: valuesAndIdeas,
    );
  }

  void _openProfile(Map<String, dynamic> raw) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userData: {
            'id': raw['id'] ?? '',
            'name': raw['full_name'] ?? 'Usuário',
            'username': '@${raw['username'] ?? ''}',
            'avatarUrl': raw['avatar_url'] ?? '',
            'avatarSemantic': '${raw['full_name'] ?? 'Usuário'} foto de perfil',
            'bio': raw['bio'] ?? '',
            'neurodivType': raw['neurodiv_type'] ?? '',
            'hyperfocuses':
                (raw['hyperfocuses'] as List?)
                    ?.map((h) => {'name': h.toString(), 'color': 0xFF4A90D9})
                    .toList() ??
                [],
            'interests': (raw['interests'] as List?)?.cast<String>() ?? [],
            'friendsCount': 0,
            'postsCount': 0,
            'compatScore': 0,
            'isMe': false,
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    const floatingNavHeight = 80.0;
    final listBottomPadding = floatingNavHeight + bottomPadding + 16.0;

    final bool showSearch = _query.isNotEmpty;
    final bool showSuggestions = _query.isEmpty;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Buscar Perfis', style: theme.textTheme.headlineSmall),
        centerTitle: false,
      ),
      body: Column(
        children: [
          // ── Search bar ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              autofocus: false,
              decoration: InputDecoration(
                hintText: 'Buscar por nome, interesse...',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: AppTheme.primary,
                  size: 22,
                ),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _searchFocus.unfocus();
                        },
                      )
                    : null,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14.0),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),

          // ── Content ─────────────────────────────────────────────────────
          Expanded(
            child: showSearch
                ? _buildSearchResults(theme, listBottomPadding)
                : _buildSuggestions(theme, listBottomPadding),
          ),
        ],
      ),
    );
  }

  // ── Search results view ──────────────────────────────────────────────────

  Widget _buildSearchResults(ThemeData theme, double bottomPadding) {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    if (_searchResults.isEmpty) {
      return _buildEmptySearch(theme);
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPadding),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final result = _searchResults[index];
        final raw = result is _ProfileMatchResultWithRaw
            ? result.raw
            : _profileToRaw(result.profile);
        return _AffinityProfileCard(
          result: result is _ProfileMatchResultWithRaw ? result : result,
          raw: raw,
          currentUser: widget.currentUserProfile,
          onTap: () => _openProfile(raw),
          highlightQuery: _query,
        );
      },
    );
  }

  // ── Suggestions view ─────────────────────────────────────────────────────

  Widget _buildSuggestions(ThemeData theme, double bottomPadding) {
    if (_loadingSuggestions) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppTheme.primary),
            const SizedBox(height: 12),
            Text(
              'Calculando afinidades...',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_suggestions.isEmpty) {
      return _buildEmptyState(theme);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Sugestões por Afinidade',
                style: GoogleFonts.inter(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '${_suggestions.length} perfis',
                style: GoogleFonts.inter(
                  fontSize: 10.sp,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
            itemCount: _suggestions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final result = _suggestions[index];
              final raw = _profileToRaw(result.profile);
              return _AffinityProfileCard(
                result: result,
                raw: raw,
                currentUser: widget.currentUserProfile,
                onTap: () => _openProfile(raw),
                rank: index + 1,
              );
            },
          ),
        ),
      ],
    );
  }

  Map<String, dynamic> _profileToRaw(UserProfile p) => {
    'id': p.id,
    'full_name': p.displayName,
    'avatar_url': p.avatarUrl ?? '',
    'bio': p.bio ?? '',
    'neurodiv_type': p.neurotypes.isNotEmpty ? p.neurotypes.first.name : '',
    'hyperfocuses': p.hyperfocusInterests,
    'interests': <String>[],
  };

  Widget _buildEmptySearch(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_search_rounded,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'Nenhum perfil encontrado para "$_query"',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_search_rounded,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'Digite para buscar perfis',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal wrapper to carry raw DB data alongside a ProfileMatchResult
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileMatchResultWithRaw extends ProfileMatchResult {
  final Map<String, dynamic> raw;

  _ProfileMatchResultWithRaw({
    required ProfileMatchResult result,
    required this.raw,
  }) : super(
         profile: result.profile,
         matchScore: result.matchScore,
         interestsScore: result.interestsScore,
         valuesScore: result.valuesScore,
         neurotypesScore: result.neurotypesScore,
         communicationScore: result.communicationScore,
         aiInsight: result.aiInsight,
         aiRefined: result.aiRefined,
       );
}

// ─────────────────────────────────────────────────────────────────────────────
// Affinity Profile Card
// ─────────────────────────────────────────────────────────────────────────────

class _AffinityProfileCard extends StatelessWidget {
  final ProfileMatchResult result;
  final Map<String, dynamic> raw;
  final UserProfile currentUser;
  final VoidCallback onTap;
  final int? rank;
  final String highlightQuery;

  const _AffinityProfileCard({
    required this.result,
    required this.raw,
    required this.currentUser,
    required this.onTap,
    this.rank,
    this.highlightQuery = '',
  });

  Color _scoreColor(int pct) {
    if (pct >= 75) return AppTheme.success;
    if (pct >= 50) return AppTheme.warning;
    if (pct >= 25) return AppTheme.primary;
    return AppTheme.error;
  }

  String _scoreLabel(int pct) {
    if (pct >= 85) return 'Altíssima Sintonia ✨';
    if (pct >= 70) return 'Boa Compatibilidade 💚';
    if (pct >= 50) return 'Compatibilidade Moderada 🌱';
    if (pct >= 25) return 'Baixa Compatibilidade';
    return 'Pouca Afinidade';
  }

  String _neurotypeName(Neurotype n) {
    const names = {
      Neurotype.adhd: 'TDAH',
      Neurotype.asd: 'TEA',
      Neurotype.dyslexia: 'Dislexia',
      Neurotype.giftedHighAbility: 'AH/SD',
      Neurotype.dyscalculia: 'Discalculia',
      Neurotype.dyspraxia: 'Dispraxia',
      Neurotype.tourette: 'Tourette',
      Neurotype.anxiety: 'Ansiedade',
      Neurotype.depression: 'Depressão',
      Neurotype.bipolar: 'Bipolar',
      Neurotype.neurotypical: 'Neurotípico',
    };
    return names[n] ?? n.name;
  }

  List<String> _commonInterests() {
    final a = currentUser.hyperfocusInterests
        .map((e) => e.toLowerCase().trim())
        .toSet();
    final b = result.profile.hyperfocusInterests
        .map((e) => e.toLowerCase().trim())
        .toSet();
    return a.intersection(b).take(3).toList();
  }

  List<String> _commonNeurotypes() {
    final a = currentUser.neurotypes.toSet();
    final b = result.profile.neurotypes.toSet();
    return a.intersection(b).map(_neurotypeName).take(2).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = raw['full_name'] as String? ?? result.profile.displayName;
    final username = raw['username'] as String? ?? '';
    final avatarUrl =
        raw['avatar_url'] as String? ?? result.profile.avatarUrl ?? '';
    final bio = raw['bio'] as String? ?? result.profile.bio ?? '';
    final neurodivType = raw['neurodiv_type'] as String? ?? '';
    final pct = result.matchPercentage;
    final color = _scoreColor(pct);
    final commonInterests = _commonInterests();
    final commonNeuro = _commonNeurotypes();
    final hasCommonPoints =
        commonInterests.isNotEmpty || commonNeuro.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16.0),
          border: pct >= 70
              ? Border.all(color: color.withAlpha(80), width: 1.2)
              : null,
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar + rank badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppTheme.primaryContainer,
                  backgroundImage: avatarUrl.isNotEmpty
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: avatarUrl.isEmpty
                      ? Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: GoogleFonts.inter(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14.sp,
                          ),
                        )
                      : null,
                ),
                if (rank != null && rank! <= 3)
                  Positioned(
                    bottom: -4,
                    right: -4,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: rank == 1
                            ? const Color(0xFFFFD700)
                            : rank == 2
                            ? const Color(0xFFC0C0C0)
                            : const Color(0xFFCD7F32),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.scaffoldBackgroundColor,
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$rank',
                          style: GoogleFonts.inter(
                            fontSize: 8.sp,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + score badge
                  Row(
                    children: [
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
                      // Affinity score pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: color.withAlpha(30),
                          borderRadius: BorderRadius.circular(20.0),
                          border: Border.all(color: color.withAlpha(100)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.favorite_rounded,
                              size: 10,
                              color: color,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '$pct%',
                              style: GoogleFonts.inter(
                                fontSize: 10.sp,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Username + neurodiv
                  Row(
                    children: [
                      if (username.isNotEmpty) ...[
                        Text(
                          '@$username',
                          style: GoogleFonts.inter(
                            fontSize: 10.sp,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (neurodivType.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.teaColor.withAlpha(25),
                            borderRadius: BorderRadius.circular(6.0),
                          ),
                          child: Text(
                            neurodivType.toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 8.sp,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.teaColor,
                            ),
                          ),
                        ),
                    ],
                  ),

                  // Bio
                  if (bio.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      bio,
                      style: GoogleFonts.inter(
                        fontSize: 10.sp,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  // Common points
                  if (hasCommonPoints) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (commonNeuro.isNotEmpty)
                          ...commonNeuro.map(
                            (n) => _CommonChip(
                              label: n,
                              color: AppTheme.teaColor,
                              icon: Icons.psychology_rounded,
                            ),
                          ),
                        ...commonInterests.map(
                          (i) => _CommonChip(
                            label: i,
                            color: AppTheme.secondary,
                            icon: Icons.bolt_rounded,
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Score label for high matches
                  if (pct >= 50) ...[
                    const SizedBox(height: 4),
                    Text(
                      _scoreLabel(pct),
                      style: GoogleFonts.inter(
                        fontSize: 9.sp,
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Common point chip
// ─────────────────────────────────────────────────────────────────────────────

class _CommonChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _CommonChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 9.sp,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
