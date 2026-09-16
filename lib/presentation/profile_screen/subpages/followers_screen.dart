import 'package:flutter/material.dart';

import '../../../core/app_export.dart';
import '../../../services/supabase_service.dart';
import '../../../theme/app_theme.dart';
import '../../user_profile_screen/user_profile_screen.dart';

class FollowersScreen extends StatefulWidget {
  final int friendsCount;
  const FollowersScreen({super.key, required this.friendsCount});

  @override
  State<FollowersScreen> createState() => _FollowersScreenState();
}

class _FollowersScreenState extends State<FollowersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  final List<Map<String, dynamic>> _friends = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadFriends();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
          'username': '@${friend['username'] ?? ''}',
          'avatarUrl': friend['avatar_url'] ?? '',
          'neurodivType': friend['neurodiv_type'] ?? '',
          'isFollowingBack': true,
        };
      }).toList();
      setState(() {
        _friends
          ..clear()
          ..addAll(mapped);
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openProfile(String userId) {
    SupabaseService.instance.fetchUserProfile(userId).then((profile) {
      if (!mounted) return;
      final userData = profile != null
          ? {
              'id': profile['id'] ?? userId,
              'name': profile['full_name'] ?? 'Usuário',
              'username': '@${profile['username'] ?? ''}',
              'bio': profile['bio'] ?? '',
              'neurodivType': profile['neurodiv_type'] ?? '',
              'avatarUrl': profile['avatar_url'] ?? '',
              'avatarSemantic': 'Foto de ${profile['full_name'] ?? 'Usuário'}',
              'hyperfocuses': [],
              'interests': [],
              'friendsCount': 0,
              'postsCount': 0,
              'compatScore': 0,
              'isMe': false,
            }
          : {
              'id': userId,
              'name': 'Usuário',
              'avatarUrl': '',
              'avatarSemantic': '',
            };
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UserProfileScreen(userData: userData),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('${_friends.length} Conexões'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(text: 'Seguidores'),
            Tab(text: 'Seguindo'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(theme, _friends),
                _buildList(
                  theme,
                  _friends.where((f) => f['isFollowingBack'] == true).toList(),
                ),
              ],
            ),
    );
  }

  Widget _buildList(ThemeData theme, List<Map<String, dynamic>> users) {
    if (users.isEmpty) {
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
              'Nenhuma conexão ainda',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: users.length,
      itemBuilder: (_, i) {
        final user = users[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 6,
            ),
            onTap: () => _openProfile(user['id'] as String),
            leading: CircleAvatar(
              radius: 24,
              backgroundImage: (user['avatarUrl'] as String).isNotEmpty
                  ? NetworkImage(user['avatarUrl'] as String)
                  : null,
              backgroundColor: AppTheme.primaryContainer,
              child: (user['avatarUrl'] as String).isEmpty
                  ? Text(
                      (user['name'] as String)[0].toUpperCase(),
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
            ),
            title: Text(
              user['name'] as String,
              style: theme.textTheme.titleSmall,
            ),
            subtitle: Text(
              user['username'] as String,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: user['isFollowingBack'] == true
                ? OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                    ),
                    child: const Text(
                      'Seguindo',
                      style: TextStyle(fontSize: 12),
                    ),
                  )
                : FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                    ),
                    child: const Text('Seguir', style: TextStyle(fontSize: 12)),
                  ),
          ),
        );
      },
    );
  }
}
