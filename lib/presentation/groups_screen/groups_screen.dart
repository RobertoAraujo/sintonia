import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_image_widget.dart';
import './create_group_screen.dart';
import './group_detail_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoadingMyGroups = true;
  bool _isLoadingDiscover = true;

  final List<Map<String, dynamic>> _myGroups = [];
  final List<Map<String, dynamic>> _discoverGroups = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadGroups();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    try {
      final rows = await SupabaseService.instance.fetchGroups();
      if (!mounted) return;
      final uid = SupabaseService.instance.currentUserId;

      // Fetch all group_members for current user in one query
      Set<String> memberGroupIds = {};
      if (uid != null) {
        try {
          final memberRows = await SupabaseService.instance.client
              .from('group_members')
              .select('group_id')
              .eq('user_id', uid);
          memberGroupIds = {
            for (final r in List<Map<String, dynamic>>.from(memberRows))
              r['group_id'] as String,
          };
        } catch (_) {}
      }

      final myGroups = <Map<String, dynamic>>[];
      final discoverGroups = <Map<String, dynamic>>[];

      for (final g in rows) {
        final groupId = g['id'] as String? ?? '';
        final isMember =
            memberGroupIds.contains(groupId) || g['creator_id'] == uid;
        final mapped = {
          'id': groupId,
          'name': g['name'] ?? '',
          'description': g['description'] ?? '',
          'members': g['members_count'] ?? 0,
          'imageUrl': g['avatar_url'] ?? '',
          'imageSemantic': 'Imagem do grupo ${g['name'] ?? ''}',
          'tags': (g['tags'] as List?)?.cast<String>() ?? [],
          'privacy': (g['is_public'] as bool? ?? true) ? 'Público' : 'Privado',
          'isMember': isMember,
          'lastActivity': '',
          'creatorId': g['creator_id'] ?? '',
        };
        if (isMember) {
          myGroups.add(mapped);
        } else {
          discoverGroups.add(mapped);
        }
      }

      setState(() {
        _myGroups
          ..clear()
          ..addAll(myGroups);
        _discoverGroups
          ..clear()
          ..addAll(discoverGroups);
        _isLoadingMyGroups = false;
        _isLoadingDiscover = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingMyGroups = false;
          _isLoadingDiscover = false;
        });
      }
    }
  }

  void _openCreateGroup() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => CreateGroupScreen(
          onGroupCreated: (newGroup) {
            setState(() => _myGroups.insert(0, newGroup));
            Future.delayed(const Duration(milliseconds: 300), () {
              if (!mounted) return;
              _openGroupDetail(newGroup);
            });
          },
        ),
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _openGroupDetail(Map<String, dynamic> group) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => GroupDetailScreen(group: group),
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _joinGroup(Map<String, dynamic> group) {
    final groupId = group['id'] as String;
    SupabaseService.instance.joinGroup(groupId).then((success) {
      if (!mounted) return;
      if (success) {
        setState(() {
          _discoverGroups.removeWhere((g) => g['id'] == groupId);
          _myGroups.insert(0, {...group, 'isMember': true});
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Você entrou no grupo ${group['name']}! 🎉'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    });
  }

  void _leaveGroup(Map<String, dynamic> group) {
    final groupId = group['id'] as String;
    SupabaseService.instance.leaveGroup(groupId).then((success) {
      if (!mounted) return;
      if (success) {
        setState(() {
          _myGroups.removeWhere((g) => g['id'] == groupId);
          _discoverGroups.insert(0, {...group, 'isMember': false});
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Você saiu do grupo ${group['name']}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    });
  }

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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Grupos', style: theme.textTheme.headlineSmall),
                        Text(
                          'Comunidades para você',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.search_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.primary.withAlpha(20),
                      foregroundColor: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _openCreateGroup,
                    icon: const Icon(Icons.group_add_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    tooltip: 'Criar Grupo',
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                labelStyle: GoogleFonts.nunitoSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: GoogleFonts.nunitoSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Meus Grupos'),
                        if (_myGroups.isNotEmpty) ...[
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
                                '${_myGroups.length}',
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
                  const Tab(text: 'Descobrir'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _isLoadingMyGroups
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.primary,
                          ),
                        )
                      : _myGroups.isEmpty
                      ? _buildEmptyGroups(theme)
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            12,
                            16,
                            listBottomPadding,
                          ),
                          itemCount: _myGroups.length,
                          itemBuilder: (context, index) =>
                              _buildGroupCard(theme, _myGroups[index], true),
                        ),
                  _isLoadingDiscover
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.primary,
                          ),
                        )
                      : _discoverGroups.isEmpty
                      ? Center(
                          child: Text(
                            'Nenhum grupo para descobrir',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            12,
                            16,
                            listBottomPadding,
                          ),
                          itemCount: _discoverGroups.length,
                          itemBuilder: (context, index) => _buildGroupCard(
                            theme,
                            _discoverGroups[index],
                            false,
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyGroups(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.group_outlined,
            size: 56,
            color: theme.colorScheme.outlineVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'Você ainda não faz parte de nenhum grupo',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openCreateGroup,
            icon: const Icon(Icons.group_add_rounded, size: 18),
            label: const Text('Criar Grupo'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(
    ThemeData theme,
    Map<String, dynamic> group,
    bool isMember,
  ) {
    final tags = (group['tags'] as List?)?.cast<String>() ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () => _openGroupDetail(group),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              (group['imageUrl'] as String).isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: CustomImageWidget(
                        imageUrl: group['imageUrl'] as String,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        semanticLabel: group['imageSemantic'] as String,
                      ),
                    )
                  : Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.group_rounded,
                        color: AppTheme.primary,
                        size: 28,
                      ),
                    ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            group['name'] as String,
                            style: theme.textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (group['privacy'] == 'Privado')
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      group['description'] as String,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.people_outline_rounded,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${group['members']} membros',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        if (!isMember)
                          GestureDetector(
                            onTap: () => _joinGroup(group),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Entrar',
                                style: GoogleFonts.nunitoSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withAlpha(20),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Membro',
                              style: GoogleFonts.nunitoSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: tags
                            .take(3)
                            .map(
                              (tag) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  tag,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: AppTheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
