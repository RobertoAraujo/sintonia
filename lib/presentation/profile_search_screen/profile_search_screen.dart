import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sizer/sizer.dart';

import '../../models/user_profile.dart';
import '../../models/profile_match_result.dart';
import '../../services/recommendation_engine_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_image_widget.dart';
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

  List<Map<String, dynamic>> _allProfiles = [];
  List<Map<String, dynamic>> _filteredProfiles = [];
  bool _isLoading = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _searchProfiles(String q) async {
    if (q.trim().isEmpty) {
      setState(() {
        _filteredProfiles = [];
        _isLoading = false;
      });
      return;
    }
    setState(() => _isLoading = true);
    try {
      final results = await SupabaseService.instance.searchUsers(q.trim());
      if (!mounted) return;
      final uid = SupabaseService.instance.currentUserId;
      final filtered = results.where((u) => u['id'] != uid).toList();
      setState(() {
        _allProfiles = filtered;
        _filteredProfiles = filtered;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onQueryChanged() {
    final q = _searchController.text.trim().toLowerCase();
    if (q == _query) return;
    setState(() => _query = q);
    _searchProfiles(q);
  }

  void _openProfile(Map<String, dynamic> profile) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userData: {
            'id': profile['id'] ?? '',
            'name': profile['full_name'] ?? 'Usuário',
            'username': '@${profile['username'] ?? ''}',
            'avatarUrl': profile['avatar_url'] ?? '',
            'avatarSemantic':
                '${profile['full_name'] ?? 'Usuário'} foto de perfil',
            'bio': profile['bio'] ?? '',
            'neurodivType': profile['neurodiv_type'] ?? '',
            'hyperfocuses':
                (profile['hyperfocuses'] as List?)
                    ?.map(
                      (h) => {
                        'name': h['name'] ?? '',
                        'color': h['color'] ?? 0xFF4A90D9,
                      },
                    )
                    .toList() ??
                [],
            'interests': (profile['interests'] as List?)?.cast<String>() ?? [],
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
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              autofocus: true,
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
                          _searchFocus.requestFocus();
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
          // Results
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  )
                : _filteredProfiles.isEmpty
                ? _buildEmpty(theme)
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, listBottomPadding),
                    itemCount: _filteredProfiles.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 60),
                    itemBuilder: (context, index) {
                      final profile = _filteredProfiles[index];
                      return _SupabaseProfileTile(
                        profile: profile,
                        onTap: () => _openProfile(profile),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
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
            _query.isEmpty
                ? 'Digite para buscar perfis'
                : 'Nenhum perfil encontrado para "$_query"',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SupabaseProfileTile extends StatelessWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onTap;

  const _SupabaseProfileTile({required this.profile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = profile['full_name'] as String? ?? 'Usuário';
    final username = profile['username'] as String? ?? '';
    final avatarUrl = profile['avatar_url'] as String? ?? '';
    final bio = profile['bio'] as String? ?? '';
    final neurodivType = profile['neurodiv_type'] as String? ?? '';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppTheme.primaryContainer,
        backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
        child: avatarUrl.isEmpty
            ? Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              )
            : null,
      ),
      title: Text(
        name,
        style: theme.textTheme.titleSmall,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (username.isNotEmpty)
            Text(
              '@$username',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.primary,
              ),
            ),
          if (bio.isNotEmpty)
            Text(
              bio,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      trailing: neurodivType.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                neurodivType,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile detail page with full compatibility breakdown
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileDetailSheet extends StatelessWidget {
  final ProfileMatchResult result;
  final UserProfile currentUser;
  final RecommendationEngineService engine;

  const _ProfileDetailSheet({
    required this.result,
    required this.currentUser,
    required this.engine,
  });

  Color _compatColor(int pct) {
    if (pct >= 75) return AppTheme.success;
    if (pct >= 50) return AppTheme.warning;
    return AppTheme.error;
  }

  String _compatLabel(int pct) {
    if (pct >= 85) return 'Altíssima Sintonia ✨';
    if (pct >= 70) return 'Boa Compatibilidade 💚';
    if (pct >= 50) return 'Compatibilidade Moderada 🌱';
    return 'Baixa Compatibilidade';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = result.profile;
    final pct = result.matchPercentage;
    final color = _compatColor(pct);

    // Recalculate full breakdown
    final fullResult = _buildFullResult();

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          profile.displayName,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 15.sp,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar
            CircleAvatar(
              radius: 44,
              backgroundColor: AppTheme.primaryContainer,
              child: ClipOval(
                child: profile.avatarUrl != null
                    ? CustomImageWidget(
                        imageUrl: profile.avatarUrl!,
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                        semanticLabel: '${profile.displayName} foto de perfil',
                      )
                    : Text(
                        profile.displayName.isNotEmpty
                            ? profile.displayName[0].toUpperCase()
                            : '?',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                          fontSize: 22.sp,
                        ),
                      ),
              ),
            ),
            SizedBox(height: 1.5.h),
            Text(
              profile.displayName,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 16.sp,
                color: theme.colorScheme.onSurface,
              ),
            ),
            if (profile.bio != null) ...[
              SizedBox(height: 0.5.h),
              Text(
                profile.bio!,
                style: GoogleFonts.inter(
                  fontSize: 12.sp,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            SizedBox(height: 2.5.h),

            // Compatibility ring card
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 2.5.h, horizontal: 5.w),
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                borderRadius: BorderRadius.circular(20.0),
                border: Border.all(color: color.withAlpha(77), width: 1.5),
              ),
              child: Column(
                children: [
                  Text(
                    'Compatibilidade com você',
                    style: GoogleFonts.inter(
                      fontSize: 12.sp,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 1.h),
                  _CompatibilityRing(percent: pct, color: color),
                  SizedBox(height: 1.h),
                  Text(
                    _compatLabel(pct),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.sp,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 2.h),

            // Breakdown
            _buildBreakdownCard(theme, fullResult),
            SizedBox(height: 2.h),

            // Interests chips
            if (profile.hyperfocusInterests.isNotEmpty) ...[
              _buildSection(
                theme,
                title: 'Hiperfocos',
                icon: Icons.bolt_rounded,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: profile.hyperfocusInterests
                      .map((i) => _chip(theme, i, AppTheme.secondary))
                      .toList(),
                ),
              ),
              SizedBox(height: 1.5.h),
            ],

            // Values chips
            if (profile.valuesAndIdeas.isNotEmpty) ...[
              _buildSection(
                theme,
                title: 'Valores & Ideias',
                icon: Icons.favorite_border_rounded,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: profile.valuesAndIdeas
                      .map((v) => _chip(theme, v, AppTheme.primary))
                      .toList(),
                ),
              ),
              SizedBox(height: 1.5.h),
            ],

            // Neurotypes
            if (profile.neurotypes.isNotEmpty) ...[
              _buildSection(
                theme,
                title: 'Neurotipo',
                icon: Icons.psychology_rounded,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: profile.neurotypes
                      .map(
                        (n) =>
                            _chip(theme, _neurotypeName(n), AppTheme.teaColor),
                      )
                      .toList(),
                ),
              ),
              SizedBox(height: 2.h),
            ],
          ],
        ),
      ),
    );
  }

  ProfileMatchResult _buildFullResult() {
    // Recalculate with full breakdown
    final a = currentUser;
    final b = result.profile;

    double jaccard<T>(Set<T> setA, Set<T> setB) {
      if (setA.isEmpty && setB.isEmpty) return 0.0;
      final inter = setA.intersection(setB).length;
      final union = setA.union(setB).length;
      return union == 0 ? 0.0 : inter / union;
    }

    final interests = jaccard(
      a.hyperfocusInterests.map((e) => e.toLowerCase().trim()).toSet(),
      b.hyperfocusInterests.map((e) => e.toLowerCase().trim()).toSet(),
    );
    final values = jaccard(
      a.valuesAndIdeas.map((e) => e.toLowerCase().trim()).toSet(),
      b.valuesAndIdeas.map((e) => e.toLowerCase().trim()).toSet(),
    );
    final neuro = jaccard(a.neurotypes.toSet(), b.neurotypes.toSet());
    final comm = jaccard(
      a.communicationStyles.toSet(),
      b.communicationStyles.toSet(),
    );

    final score =
        (interests * 0.40) + (values * 0.35) + (neuro * 0.15) + (comm * 0.10);

    return ProfileMatchResult(
      profile: b,
      matchScore: score.clamp(0.0, 1.0),
      interestsScore: interests,
      valuesScore: values,
      neurotypesScore: neuro,
      communicationScore: comm,
    );
  }

  Widget _buildBreakdownCard(ThemeData theme, ProfileMatchResult r) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Detalhes da Compatibilidade',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 13.sp,
              color: theme.colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 1.5.h),
          _breakdownRow(
            theme,
            'Hiperfocos',
            r.interestsScore,
            '40%',
            AppTheme.secondary,
          ),
          SizedBox(height: 1.h),
          _breakdownRow(
            theme,
            'Valores & Ideias',
            r.valuesScore,
            '35%',
            AppTheme.primary,
          ),
          SizedBox(height: 1.h),
          _breakdownRow(
            theme,
            'Neurotipo',
            r.neurotypesScore,
            '15%',
            AppTheme.teaColor,
          ),
          SizedBox(height: 1.h),
          _breakdownRow(
            theme,
            'Comunicação',
            r.communicationScore,
            '10%',
            AppTheme.tdahColor,
          ),
        ],
      ),
    );
  }

  Widget _breakdownRow(
    ThemeData theme,
    String label,
    double score,
    String weight,
    Color color,
  ) {
    final pct = (score * 100).round();
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11.sp,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4.0),
            child: LinearProgressIndicator(
              value: score.clamp(0.0, 1.0),
              backgroundColor: color.withAlpha(40),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            '$pct%',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 11.sp,
              color: color,
            ),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          weight,
          style: GoogleFonts.inter(
            fontSize: 10.sp,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildSection(
    ThemeData theme, {
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.primary),
            const SizedBox(width: 6),
            Text(
              title,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 12.sp,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        SizedBox(height: 0.8.h),
        child,
      ],
    );
  }

  Widget _chip(ThemeData theme, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(color: color.withAlpha(77)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10.sp,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated compatibility ring
// ─────────────────────────────────────────────────────────────────────────────

class _CompatibilityRing extends StatefulWidget {
  final int percent;
  final Color color;

  const _CompatibilityRing({required this.percent, required this.color});

  @override
  State<_CompatibilityRing> createState() => _CompatibilityRingState();
}

class _CompatibilityRingState extends State<_CompatibilityRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim = Tween<double>(
      begin: 0,
      end: widget.percent / 100,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => SizedBox(
        width: 110,
        height: 110,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 110,
              height: 110,
              child: CircularProgressIndicator(
                value: _anim.value,
                strokeWidth: 10,
                backgroundColor: widget.color.withAlpha(40),
                valueColor: AlwaysStoppedAnimation<Color>(widget.color),
                strokeCap: StrokeCap.round,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(_anim.value * 100).round()}%',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 18.sp,
                    color: widget.color,
                  ),
                ),
                Text(
                  'sintonia',
                  style: GoogleFonts.inter(
                    fontSize: 9.sp,
                    color: widget.color.withAlpha(180),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
