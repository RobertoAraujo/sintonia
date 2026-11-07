import 'package:flutter/material.dart';
import '../../../services/supabase_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/custom_image_widget.dart';
import '../../chat_screen/widgets/private_chat_screen.dart';
import '../../user_profile_screen/user_profile_screen.dart';

/// Modal/page that shows the friends list of a given user.
/// Can be pushed as a full page or shown as a bottom sheet.
class FriendsListPage extends StatefulWidget {
  final String userId;
  final String userName;

  const FriendsListPage({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<FriendsListPage> createState() => _FriendsListPageState();
}

class _FriendsListPageState extends State<FriendsListPage> {
  List<Map<String, dynamic>> _friends = [];
  bool _isLoading = true;
  String? _error;
  final Set<String> _startingChat = {};

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final uid = widget.userId;
      // Fetch accepted friendships involving this user
      final rows = await SupabaseService.instance.client
          .from('friendships')
          .select(
            'id, requester_id, addressee_id, '
            'requester:user_profiles!requester_id(id, full_name, username, avatar_url, neurodiv_type), '
            'addressee:user_profiles!addressee_id(id, full_name, username, avatar_url, neurodiv_type)',
          )
          .or('requester_id.eq.$uid,addressee_id.eq.$uid')
          .eq('status', 'accepted')
          .order('created_at', ascending: false);

      final friends = (rows as List).map((r) {
        final isRequester = r['requester_id'] == uid;
        final friend = isRequester
            ? r['addressee'] as Map<String, dynamic>? ?? {}
            : r['requester'] as Map<String, dynamic>? ?? {};
        return {
          'id': friend['id'] ?? '',
          'name': friend['full_name'] ?? 'Usuário',
          'username': friend['username'] ?? '',
          'avatarUrl': friend['avatar_url'] ?? '',
          'neurodivType': friend['neurodiv_type'] ?? '',
        };
      }).toList();

      if (mounted) {
        setState(() {
          _friends = friends;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Não foi possível carregar a lista de amigos.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _startConversation(Map<String, dynamic> friend) async {
    final friendId = friend['id'] as String? ?? '';
    if (friendId.isEmpty) return;

    setState(() => _startingChat.add(friendId));
    try {
      final convId = await SupabaseService.instance
          .createOrGetDirectConversation(friendId);
      if (!mounted) return;
      if (convId != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PrivateChatScreen(
              chatId: convId,
              otherUserId: friendId,
              otherUserName: friend['name'] as String? ?? 'Usuário',
              otherUserAvatar: friend['avatarUrl'] as String? ?? '',
              otherUserAvatarSemantic: 'Foto de ${friend['name']}',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível iniciar a conversa.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível iniciar a conversa.')),
        );
      }
    } finally {
      if (mounted) setState(() => _startingChat.remove(friendId));
    }
  }

  Widget _buildAvatar(Map<String, dynamic> friend, double size) {
    final avatarUrl = friend['avatarUrl'] as String? ?? '';
    final name = friend['name'] as String? ?? 'U';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    if (avatarUrl.isNotEmpty &&
        (avatarUrl.startsWith('http://') || avatarUrl.startsWith('https://'))) {
      return ClipOval(
        child: CustomImageWidget(
          imageUrl: avatarUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          semanticLabel: 'Foto de $name',
        ),
      );
    }
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppTheme.primary.withAlpha(40),
      child: Text(
        initial,
        style: TextStyle(
          color: AppTheme.primary,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.38,
        ),
      ),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUid = SupabaseService.instance.currentUserId ?? '';
    final isOwnProfile = widget.userId == currentUid;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isOwnProfile ? 'Meus Amigos' : 'Amigos de ${widget.userName}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (!_isLoading)
              Text(
                '${_friends.length} amigo${_friends.length != 1 ? 's' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _loadFriends,
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            )
          : _friends.isEmpty
          ? Center(
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
                    'Nenhum amigo ainda',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _friends.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 72, endIndent: 16),
              itemBuilder: (context, index) {
                final friend = _friends[index];
                final neurodivType = friend['neurodivType'] as String? ?? '';
                final friendId = friend['id'] as String? ?? '';
                final isStarting = _startingChat.contains(friendId);
                // Show chat button only when viewing own profile
                final showChatButton = isOwnProfile && friendId != currentUid;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => UserProfileScreen(
                            userData: {
                              'id': friend['id'],
                              'name': friend['name'],
                              'username': friend['username'],
                              'avatarUrl': friend['avatarUrl'],
                              'neurodivType': neurodivType,
                            },
                          ),
                        ),
                      );
                    },
                    child: _buildAvatar(friend, 48),
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          friend['name'] as String? ?? 'Usuário',
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (neurodivType.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
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
                    ],
                  ),
                  subtitle:
                      friend['username'] != null &&
                          (friend['username'] as String).isNotEmpty
                      ? Text(
                          '@${friend['username']}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      : null,
                  trailing: showChatButton
                      ? isStarting
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.primary,
                                ),
                              )
                            : Tooltip(
                                message: 'Iniciar conversa',
                                child: IconButton(
                                  onPressed: () => _startConversation(friend),
                                  icon: Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    color: AppTheme.primary,
                                    size: 22,
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: AppTheme.primary.withAlpha(
                                      20,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              )
                      : null,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => UserProfileScreen(
                          userData: {
                            'id': friend['id'],
                            'name': friend['name'],
                            'username': friend['username'],
                            'avatarUrl': friend['avatarUrl'],
                            'neurodivType': neurodivType,
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
