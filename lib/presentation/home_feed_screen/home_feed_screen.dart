import 'dart:io' if (dart.library.io) 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_export.dart';
import '../../core/services/aiIntegrations/chat_completion_service.dart';
import '../../models/user_profile.dart';
import '../../services/avatar_notifier.dart';
import '../../services/media_permission_service.dart';
import '../../services/media_processing_service.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../../services/user_settings_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/share_helper.dart';
import '../../widgets/app_scaffold.dart' show registerGlobalPostModal;
import '../media_upload/media_upload_modal.dart';
import '../profile_search_screen/profile_search_screen.dart';
import '../user_profile_screen/user_profile_screen.dart';
import './widgets/post_card_widget.dart';
import './widgets/status_strip_widget.dart';

// Global callback so the navigation-level post modal can add posts to the feed
void Function(Map<String, dynamic>)? globalAddPostCallback;

class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen>
    with WidgetsBindingObserver {
  bool _isLoading = false;
  bool _isLoadingPosts = true;
  String? _postsError;
  dynamic _feedSubscription;

  Map<String, dynamic>? _currentUserProfile;

  // Dynamic greeting & quote from Gemini
  String _dynamicSaudacao = '';
  String _dynamicQuote = '';
  bool _isLoadingQuote = false;

  final List<Map<String, dynamic>> _statusList = [];
  final List<Map<String, dynamic>> _postsMaps = [];

  // Notification bell state
  int _notificationUnreadCount = 0;
  bool _notifyMessages = true;
  bool _notifyFriendships = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Listen to avatar changes from any screen
    AvatarNotifier.instance.addListener(_onAvatarChanged);
    // Listen to notification changes
    NotificationService.instance.addListener(_onNotificationsChanged);
    // Register the create post callback globally so AppNavigation can trigger it
    WidgetsBinding.instance.addPostFrameCallback((_) {
      registerGlobalPostModal(_openCreatePostModal);
      // Register global add-post callback for the nav-level modal
      globalAddPostCallback = (post) {
        if (mounted) setState(() => _postsMaps.insert(0, post));
      };
    });
    _loadCurrentUser();
    _loadFeedPosts();
    _loadStories();
    _subscribeToFeed();
    _initNotifications();
    _loadDynamicGreeting();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AvatarNotifier.instance.removeListener(_onAvatarChanged);
    NotificationService.instance.removeListener(_onNotificationsChanged);
    NotificationService.instance.unsubscribeRealtime();
    if (_feedSubscription != null) {
      SupabaseService.instance.unsubscribe(_feedSubscription!);
    }
    super.dispose();
  }

  void _onNotificationsChanged() {
    if (!mounted) return;
    setState(() {
      _notificationUnreadCount = NotificationService.instance.unreadCount;
    });
  }

  Future<void> _initNotifications() async {
    // Load user settings to check notification preferences
    final settings = await UserSettingsService.instance.fetchSettings();
    if (mounted) {
      setState(() {
        _notifyMessages = settings['notify_messages'] as bool? ?? true;
        _notifyFriendships = settings['notify_friendships'] as bool? ?? true;
      });
    }
    // Fetch and subscribe to notifications
    await NotificationService.instance.fetchNotifications();
    NotificationService.instance.subscribeRealtime();
    if (mounted) {
      setState(() {
        _notificationUnreadCount = NotificationService.instance.unreadCount;
      });
    }
  }

  void _onAvatarChanged() {
    if (!mounted) return;
    final newUrl = AvatarNotifier.instance.value;
    setState(() {
      // Update current user profile map
      if (_currentUserProfile != null) {
        _currentUserProfile = {..._currentUserProfile!, 'avatar_url': newUrl};
      }
      // Update "Você" entry in stories strip
      final meIdx = _statusList.indexWhere((s) => s['isMe'] == true);
      if (meIdx != -1) {
        _statusList[meIdx] = {..._statusList[meIdx], 'imageUrl': newUrl};
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshCurrentUserAvatar();
    }
  }

  /// Refreshes only the current user's profile data (avatar) without reloading all posts.
  Future<void> _refreshCurrentUserAvatar() async {
    final profile = await SupabaseService.instance.fetchCurrentUserProfile();
    if (mounted && profile != null) {
      final newAvatarUrl = profile['avatar_url'] as String? ?? '';
      final oldAvatarUrl = _currentUserProfile?['avatar_url'] as String? ?? '';
      if (newAvatarUrl != oldAvatarUrl) {
        setState(() {
          _currentUserProfile = profile;
          // Update "Você" entry in stories strip
          final meIdx = _statusList.indexWhere((s) => s['isMe'] == true);
          if (meIdx != -1) {
            _statusList[meIdx] = {
              ..._statusList[meIdx],
              'imageUrl': newAvatarUrl,
            };
          }
        });
      }
    }
  }

  Future<void> _loadDynamicGreeting() async {
    if (_isLoadingQuote) return;
    setState(() => _isLoadingQuote = true);

    // Compute local greeting as fallback
    final hora = DateTime.now().hour;
    final String fallbackSaudacao;
    if (hora >= 5 && hora < 12) {
      fallbackSaudacao = 'Bom dia,';
    } else if (hora >= 12 && hora < 18) {
      fallbackSaudacao = 'Boa tarde,';
    } else {
      fallbackSaudacao = 'Boa noite,';
    }

    // Fallback quotes in case AI is unavailable
    const fallbackQuotes = [
      'O coração do homem determina o seu caminho, mas o Senhor lhe dirige os passos.',
      'Guardes o teu coração com toda a diligência, porque dele procedem as fontes da vida.',
      'A resposta branda desvia o furor, mas a palavra dura suscita a ira.',
      'Como a água reflete o rosto, assim o coração do homem reflete quem ele é.',
      'Melhor é o bom nome do que as muitas riquezas, e o favor é melhor do que a prata e o ouro.',
      'Espera no Senhor, tem bom ânimo, e ele fortalecerá o teu coração.',
      'A verdadeira sabedoria consiste no conhecimento de quem realmente somos e no entendimento das coisas do alto.',
      'O contentamento não vem de ter tudo o que se deseja, mas de confiar naquilo que é providenciado.',
      'Um coração humilde é a base sobre a qual todas as outras virtudes se sustentam.',
      'O tempo é breve e a eternidade é longa; viva cada momento com intenção e propósito.',
      'A paz interior não é a ausência de dificuldades, mas a presença de uma firmeza inabalável.',
      'A gratidão altera a perspectiva da vida e transforma deveres comuns em momentos de alegria.',
      'Nenhuma circunstância externa tem o poder de perturbar a mente que repousa em convicções sólidas.',
    ];

    try {
      final systemPrompt =
          'Você é um gerador de reflexões diárias elegantes e anônimas. '
          'Gere uma saudação e uma frase de reflexão profunda baseada no horário informado. '
          'Use EXCLUSIVAMENTE textos fiéis à Bíblia de Genebra ou frases de grandes teólogos Calvinistas e Puritanos '
          '(João Calvino, John Owen, Thomas Watson, Jeremiah Burroughs, Richard Sibbes, Jonathan Edwards, Charles Spurgeon, J.C. Ryle, Martyn Lloyd-Jones). '
          'NUNCA inclua nome do livro, capítulo, versículo ou nome do autor. '
          'As frases devem soar como sabedoria profunda e reflexão interior. '
          'Alterne temas: sabedoria, paz interior, paciência, prudência, humildade, firmeza de caráter, gratidão, tempo. '
          'Responda APENAS em JSON válido no formato: {"saudacao": "<saudação>", "frase": "<texto da frase>"}';

      final userPrompt =
          'Hora atual: $hora. '
          'Regras de saudação: 05-11h = "Bom dia,", 12-17h = "Boa tarde,", 18-04h = "Boa noite,". '
          'Gere uma frase inédita e variada. Responda apenas com o JSON.';

      final response = await getChatCompletion(
        'GEMINI',
        'gemini/gemini-3.7-flash',
        [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        parameters: {
          'temperature': 0.9,
          'max_tokens': 200,
          'response_format': {'type': 'json_object'},
        },
      );

      final content =
          response['choices']?[0]?['message']?['content'] as String? ?? '';

      if (content.isNotEmpty) {
        // Parse JSON response
        final jsonStart = content.indexOf('{');
        final jsonEnd = content.lastIndexOf('}');
        if (jsonStart != -1 && jsonEnd != -1) {
          final jsonStr = content.substring(jsonStart, jsonEnd + 1);
          // Simple manual parse to avoid dart:convert import issues
          final saudacaoMatch = RegExp(
            r'"saudacao"\s*:\s*"([^"]+)"',
          ).firstMatch(jsonStr);
          final fraseMatch = RegExp(
            r'"frase"\s*:\s*"([^"]+)"',
          ).firstMatch(jsonStr);

          final saudacao = saudacaoMatch?.group(1) ?? fallbackSaudacao;
          final frase = fraseMatch?.group(1) ?? '';

          if (mounted && frase.isNotEmpty) {
            setState(() {
              _dynamicSaudacao = saudacao;
              _dynamicQuote = frase;
              _isLoadingQuote = false;
            });
            return;
          }
        }
      }
    } catch (_) {
      // Fall through to fallback
    }

    // Use fallback if AI fails
    if (mounted) {
      final dayOfYear = DateTime.now()
          .difference(DateTime(DateTime.now().year))
          .inDays;
      setState(() {
        _dynamicSaudacao = fallbackSaudacao;
        _dynamicQuote = fallbackQuotes[dayOfYear % fallbackQuotes.length];
        _isLoadingQuote = false;
      });
    }
  }

  Future<void> _loadCurrentUser() async {
    final profile = await SupabaseService.instance.fetchCurrentUserProfile();
    if (mounted && profile != null) {
      setState(() => _currentUserProfile = profile);
    }
  }

  Future<void> _loadStories() async {
    try {
      final stories = await SupabaseService.instance.fetchActiveStories();
      if (!mounted) return;
      final uid = SupabaseService.instance.currentUserId;
      final mapped = <Map<String, dynamic>>[];
      // Add "me" entry first
      if (_currentUserProfile != null || uid != null) {
        mapped.add({
          'id': 'me',
          'userId': uid ?? '',
          'name': 'Você',
          'imageUrl': _currentUserProfile?['avatar_url'] ?? '',
          'isMe': true,
          'hasStory': false,
          'semanticLabel': 'Sua foto de perfil',
        });
      }
      for (final s in stories) {
        final author = s['author'] as Map<String, dynamic>? ?? {};
        if (author['id'] == uid) continue;
        mapped.add({
          'id': s['id'] ?? '',
          'userId': s['author_id'] ?? '',
          'name': (author['full_name'] as String? ?? 'Usuário')
              .split(' ')
              .first,
          'imageUrl': author['avatar_url'] ?? '',
          'isMe': false,
          'hasStory': true,
          'semanticLabel': 'Foto de ${author['full_name'] ?? 'Usuário'}',
        });
      }
      if (mounted) {
        setState(
          () => _statusList
            ..clear()
            ..addAll(mapped),
        );
      }
    } catch (_) {}
  }

  Future<void> _loadFeedPosts() async {
    setState(() {
      _isLoadingPosts = true;
      _postsError = null;
    });
    try {
      final posts = await SupabaseService.instance.fetchFeedPosts(limit: 20);
      if (mounted) {
        final postIds = posts
            .map((p) => p['id'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toList();
        final likedIds = await SupabaseService.instance.fetchLikedPostIds(
          postIds,
        );
        final mapped = posts.map((p) {
          final author = p['author'] as Map<String, dynamic>? ?? {};
          final postId = p['id'] as String? ?? '';
          return {
            'id': postId,
            'authorId': p['author_id'] ?? '',
            'authorName': author['full_name'] ?? 'Usuário',
            'authorImage': author['avatar_url'] ?? '',
            'authorImageSemantic':
                'Foto de perfil de ${author['full_name'] ?? 'Usuário'}',
            'neurodivType': author['neurodiv_type'] ?? '',
            'hyperfocusTags':
                (p['hyperfocus_tags'] as List?)?.cast<String>() ?? [],
            'content': p['content'] ?? '',
            'imageUrl': (p['image_url'] as String?)?.isNotEmpty == true
                ? p['image_url']
                : null,
            'imageSemantic': p['image_semantic'] ?? '',
            'likes': p['likes_count'] ?? 0,
            'comments': p['comments_count'] ?? 0,
            'saves': 0,
            'timeAgo': _timeAgo(p['created_at']),
            'isLiked': likedIds.contains(postId),
            'isSaved': false,
          };
        }).toList();
        if (mounted) {
          setState(() {
            _postsMaps
              ..clear()
              ..addAll(mapped);
            _isLoadingPosts = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _postsError = e.toString();
          _isLoadingPosts = false;
        });
      }
    }
  }

  void _subscribeToFeed() {
    _feedSubscription = SupabaseService.instance.subscribeToFeedPosts(
      onNewPost: (newPost) async {
        if (!mounted) return;
        final postId = newPost['id'] as String?;
        if (postId == null) return;

        // Skip posts authored by the current user (already added optimistically)
        final currentUid = SupabaseService.instance.currentUserId;
        final authorId = newPost['author_id'] as String?;
        if (authorId != null && authorId == currentUid) return;

        // Avoid duplicates
        if (_postsMaps.any((p) => p['id'] == postId)) return;

        // Fetch full post with author details
        final fullPost = await SupabaseService.instance.fetchSinglePost(postId);
        if (!mounted || fullPost == null) return;

        final author = fullPost['author'] as Map<String, dynamic>? ?? {};
        final mapped = {
          'id': fullPost['id'] ?? '',
          'authorId': fullPost['author_id'] ?? '',
          'authorName': author['full_name'] ?? 'Usuário',
          'authorImage': author['avatar_url'] ?? '',
          'authorImageSemantic':
              'Foto de perfil de ${author['full_name'] ?? 'Usuário'}',
          'neurodivType': author['neurodiv_type'] ?? '',
          'hyperfocusTags':
              (fullPost['hyperfocus_tags'] as List?)?.cast<String>() ?? [],
          'content': fullPost['content'] ?? '',
          'imageUrl': (fullPost['image_url'] as String?)?.isNotEmpty == true
              ? fullPost['image_url']
              : null,
          'imageSemantic': fullPost['image_semantic'] ?? '',
          'likes': fullPost['likes_count'] ?? 0,
          'comments': fullPost['comments_count'] ?? 0,
          'saves': 0,
          'timeAgo': 'Agora',
          'isLiked': false,
          'isSaved': false,
        };
        setState(() => _postsMaps.insert(0, mapped));
      },
    );
  }

  String _timeAgo(dynamic createdAt) {
    if (createdAt == null) return '';
    try {
      final dt = DateTime.parse(createdAt.toString()).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}min atrás';
      if (diff.inHours < 24) return '${diff.inHours}h atrás';
      return '${diff.inDays}d atrás';
    } catch (_) {
      return '';
    }
  }

  Future<void> _handleRefresh() async {
    setState(() => _isLoading = true);
    await _loadFeedPosts();
    await _loadStories();
    setState(() => _isLoading = false);
  }

  void _toggleLike(String postId) {
    final idx = _postsMaps.indexWhere((p) => p['id'] == postId);
    if (idx == -1) return;
    final isLiked = _postsMaps[idx]['isLiked'] as bool;
    setState(() {
      _postsMaps[idx]['isLiked'] = !isLiked;
      _postsMaps[idx]['likes'] =
          (_postsMaps[idx]['likes'] as int) + (isLiked ? -1 : 1);
    });
    if (isLiked) {
      SupabaseService.instance.unlikePost(postId);
    } else {
      SupabaseService.instance.likePost(postId);
    }
  }

  void _toggleSave(String postId) {
    final idx = _postsMaps.indexWhere((p) => p['id'] == postId);
    if (idx == -1) return;
    final isSaved = _postsMaps[idx]['isSaved'] as bool;
    setState(() {
      _postsMaps[idx]['isSaved'] = !isSaved;
    });
    if (isSaved) {
      SupabaseService.instance.unsavePost(postId);
    } else {
      SupabaseService.instance.savePost(postId);
    }
  }

  void _openCreatePostModal() {
    final me =
        _currentUserProfile ??
        {'id': SupabaseService.instance.currentUserId ?? '', 'name': 'Você'};
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MediaUploadModal(
        initialAction: MediaActionType.createFeedPost,
        currentUser: me,
        onFeedPostCreated: (newPost) {
          if (mounted) setState(() => _postsMaps.insert(0, newPost));
        },
      ),
    );
  }

  void _openComments(String postId) {
    final post = _postsMaps.firstWhere((p) => p['id'] == postId);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      builder: (_) => _CommentsModal(
        post: post,
        currentUserProfile: _currentUserProfile,
        onCommentAdded: () {
          final idx = _postsMaps.indexWhere((p) => p['id'] == postId);
          if (idx != -1 && mounted) {
            setState(() {
              _postsMaps[idx]['comments'] =
                  (_postsMaps[idx]['comments'] as int) + 1;
            });
          }
        },
      ),
    );
  }

  void _sharePost(Map<String, dynamic> post) {
    ShareHelper.sharePost(
      postId: post['id'] as String,
      authorName: post['authorName'] as String? ?? 'Usuário',
      postContentText: post['content'] as String?,
    );
  }

  Future<void> _deletePost(String postId) async {
    final success = await SupabaseService.instance.deletePost(postId);
    if (success && mounted) {
      setState(() => _postsMaps.removeWhere((p) => p['id'] == postId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Publicação excluída.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade400,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  void _openUserProfile(String authorId) {
    // Fetch user profile from Supabase and open profile screen
    SupabaseService.instance.fetchUserProfile(authorId).then((profile) {
      if (!mounted) return;
      final userData = profile != null
          ? {
              'id': profile['id'] ?? authorId,
              'name': profile['full_name'] ?? 'Usuário',
              'username': '@${profile['username'] ?? ''}',
              'bio': profile['bio'] ?? '',
              'neurodivType': profile['neurodiv_type'] ?? '',
              'avatarUrl': profile['avatar_url'] ?? '',
              'avatarSemantic':
                  'Foto de perfil de ${profile['full_name'] ?? 'Usuário'}',
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
              'interests':
                  (profile['interests'] as List?)?.cast<String>() ?? [],
              'friendsCount': 0,
              'postsCount': 0,
              'compatScore': 0,
              'isMe': profile['id'] == SupabaseService.instance.currentUserId,
            }
          : {
              'id': authorId,
              'name': 'Usuário',
              'avatarUrl': '',
              'avatarSemantic': '',
            };
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, animation, __) =>
              UserProfileScreen(userData: userData),
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

  void _openStatusViewer(Map<String, dynamic> status) {
    if (status['isMe'] == true) {
      _showAddStatusModal();
    } else {
      _showStatusViewModal(status);
    }
  }

  void _showAddStatusModal() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          bool isPosting = false;
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppTheme.primary, AppTheme.secondary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.add_circle_outline_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Criar Status',
                              style: Theme.of(ctx).textTheme.titleLarge,
                            ),
                            Text(
                              'Compartilhe um momento com seus amigos',
                              style: Theme.of(ctx).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      ctx,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: ctrl,
                    maxLines: 4,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'O que está acontecendo? ✨',
                      filled: true,
                      fillColor: Theme.of(
                        ctx,
                      ).colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: isPosting
                          ? null
                          : () {
                              if (ctrl.text.trim().isEmpty) return;
                              final statusText = ctrl.text.trim();
                              Navigator.pop(ctx);
                              setState(() {
                                _statusList[0]['hasStatus'] = true;
                                _statusList[0]['statusText'] = statusText;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Status publicado! 🌟'),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: AppTheme.primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.send_rounded),
                      label: const Text(
                        'Publicar Status',
                        style: TextStyle(
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
          );
        },
      ),
    );
  }

  void _showNotificationsSheet() {
    // Mark all as read when opening the sheet
    final notifService = NotificationService.instance;
    final notifications = notifService.notifications;
    final unreadCount = notifService.unreadCount;

    // Mark all unread as read
    for (final n in notifications.where((n) => !n.isRead)) {
      notifService.markAsRead(n.id);
    }
    if (mounted) setState(() => _notificationUnreadCount = 0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, scrollController) => Container(
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.notifications_rounded,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Notificações',
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      if (unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withAlpha(20),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            '$unreadCount novas',
                            style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                              color: Colors.red,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: notifications.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.notifications_none_rounded,
                                size: 48,
                                color: Theme.of(ctx).colorScheme.outlineVariant,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Nenhuma notificação ainda',
                                style: Theme.of(ctx).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        ctx,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: notifications.length,
                          itemBuilder: (_, i) {
                            final n = notifications[i];
                            final isRead = n.isRead;
                            final iconData = _notifIcon(n.type);
                            final iconColor = _notifColor(n.type);
                            final timeStr = _timeAgo(
                              n.createdAt.toIso8601String(),
                            );
                            return Container(
                              color: isRead
                                  ? Colors.transparent
                                  : AppTheme.primary.withAlpha(8),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 6,
                                ),
                                leading: Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 24,
                                      backgroundImage:
                                          n.actorAvatarUrl != null &&
                                              n.actorAvatarUrl!.isNotEmpty
                                          ? NetworkImage(n.actorAvatarUrl!)
                                          : null,
                                      backgroundColor:
                                          AppTheme.primaryContainer,
                                      child:
                                          n.actorAvatarUrl == null ||
                                              n.actorAvatarUrl!.isEmpty
                                          ? Text(
                                              (n.actorName ?? 'U')[0]
                                                  .toUpperCase(),
                                              style: const TextStyle(
                                                color: AppTheme.primary,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            )
                                          : null,
                                    ),
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: iconColor,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Theme.of(
                                              ctx,
                                            ).colorScheme.surface,
                                            width: 2,
                                          ),
                                        ),
                                        child: Icon(
                                          iconData,
                                          size: 11,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                title: Text(
                                  n.title,
                                  style: Theme.of(ctx).textTheme.bodyMedium
                                      ?.copyWith(
                                        fontWeight: isRead
                                            ? FontWeight.w400
                                            : FontWeight.w700,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (n.body.isNotEmpty)
                                      Text(
                                        n.body,
                                        style: Theme.of(ctx).textTheme.bodySmall
                                            ?.copyWith(
                                              color: Theme.of(
                                                ctx,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    const SizedBox(height: 2),
                                    Text(
                                      timeStr,
                                      style: Theme.of(ctx).textTheme.labelSmall
                                          ?.copyWith(
                                            color: isRead
                                                ? Theme.of(
                                                    ctx,
                                                  ).colorScheme.onSurfaceVariant
                                                : AppTheme.primary,
                                            fontWeight: isRead
                                                ? FontWeight.w400
                                                : FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                                trailing: isRead
                                    ? null
                                    : Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: AppTheme.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                onTap: () => Navigator.pop(ctx),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _notifIcon(NotificationType type) {
    switch (type) {
      case NotificationType.like:
        return Icons.favorite_rounded;
      case NotificationType.comment:
        return Icons.chat_bubble_rounded;
      case NotificationType.friendRequest:
      case NotificationType.friendAccepted:
        return Icons.person_add_rounded;
      case NotificationType.message:
        return Icons.message_rounded;
    }
  }

  Color _notifColor(NotificationType type) {
    switch (type) {
      case NotificationType.like:
        return Colors.red;
      case NotificationType.comment:
        return AppTheme.primary;
      case NotificationType.friendRequest:
      case NotificationType.friendAccepted:
        return AppTheme.secondary;
      case NotificationType.message:
        return Colors.orange;
    }
  }

  void _showStatusViewModal(Map<String, dynamic> status) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primary.withAlpha(220),
                AppTheme.secondary.withAlpha(200),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundImage: NetworkImage(status['imageUrl'] as String),
              ),
              const SizedBox(height: 12),
              Text(
                status['name'] as String,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '🌟 Está aproveitando o dia!',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Fechar',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    // With extendBody: true, padding.bottom already includes the full nav bar height.
    final listBottomPadding = bottomPadding + 24.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          color: AppTheme.primary,
          child: CustomScrollView(
            slivers: [
              // App Bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _dynamicSaudacao.isNotEmpty
                                  ? _dynamicSaudacao
                                  : (DateTime.now().hour >= 5 &&
                                            DateTime.now().hour < 12
                                        ? 'Bom dia,'
                                        : DateTime.now().hour < 18
                                        ? 'Boa tarde,'
                                        : 'Boa noite,'),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              '${(_currentUserProfile?['full_name'] as String? ?? 'Olá').split(' ').first} ✨',
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 6),
                            _isLoadingQuote
                                ? Container(
                                    height: 12,
                                    width: 220,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.onSurfaceVariant
                                          .withAlpha(38),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  )
                                : Text(
                                    _dynamicQuote.isNotEmpty
                                        ? '"$_dynamicQuote"'
                                        : '',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontStyle: FontStyle.italic,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          final profile = _currentUserProfile;
                          final uid =
                              SupabaseService.instance.currentUserId ?? '';
                          final currentUserProfile = UserProfile(
                            id: uid,
                            displayName:
                                profile?['full_name'] as String? ?? 'Você',
                            avatarUrl: profile?['avatar_url'] as String?,
                            bio: profile?['bio'] as String?,
                            neurotypes: [Neurotype.asd],
                            hyperfocusInterests:
                                (profile?['hyperfocuses'] as List?)
                                    ?.map((h) => h['name'] as String? ?? '')
                                    .toList() ??
                                [],
                            communicationStyles: [
                              CommunicationStyle.shortText,
                              CommunicationStyle.asyncMessages,
                            ],
                            valuesAndIdeas: const [
                              'neurodiversidade',
                              'inclusão',
                            ],
                          );
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ProfileSearchScreen(
                                currentUserProfile: currentUserProfile,
                              ),
                            ),
                          );
                        },
                        icon: Icon(
                          Icons.person_search_rounded,
                          color: theme.colorScheme.onSurface,
                          size: 26,
                        ),
                        tooltip: 'Buscar Perfis',
                      ),
                      IconButton(
                        onPressed: () => _showNotificationsSheet(),
                        icon: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              _notificationUnreadCount > 0
                                  ? Icons.notifications_rounded
                                  : Icons.notifications_outlined,
                              color: theme.colorScheme.onSurface,
                              size: 26,
                            ),
                            if (_notificationUnreadCount > 0)
                              Positioned(
                                right: -2,
                                top: -2,
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minWidth: 16,
                                    minHeight: 16,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: theme.colorScheme.surface,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Text(
                                    _notificationUnreadCount > 99
                                        ? '99+'
                                        : '$_notificationUnreadCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Status Strip
              SliverToBoxAdapter(
                child: StatusStripWidget(
                  statusList: _statusList,
                  onStatusTap: _openStatusViewer,
                  onPostStatus: _showAddStatusModal,
                ),
              ),

              // Feed Posts
              if (_isLoading || _isLoadingPosts)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.zero,
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      if (index == _postsMaps.length) {
                        return SizedBox(height: listBottomPadding);
                      }
                      final post = _postsMaps[index];
                      return PostCardWidget(
                        post: post,
                        onLike: () => _toggleLike(post['id'] as String),
                        onComment: () => _openComments(post['id'] as String),
                        onShare: () => _sharePost(post),
                        onSave: () => _toggleSave(post['id'] as String),
                        onAuthorTap: () =>
                            _openUserProfile(post['authorId'] as String),
                        onDelete:
                            (post['authorId'] as String?) ==
                                SupabaseService.instance.currentUserId
                            ? () => _deletePost(post['id'] as String)
                            : null,
                      );
                    }, childCount: _postsMaps.length + 1),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Create Post Modal ────────────────────────────────────────────────────────
class _CreatePostModal extends StatefulWidget {
  final void Function(Map<String, dynamic>) onPost;
  const _CreatePostModal({required this.onPost});

  @override
  State<_CreatePostModal> createState() => _CreatePostModalState();
}

class _CreatePostModalState extends State<_CreatePostModal> {
  final _textCtrl = TextEditingController();
  String _visibility = 'Todos';
  bool _isPosting = false;

  XFile? _selectedMedia;
  bool _isVideo = false;

  final _picker = ImagePicker();

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickMedia({
    required bool isVideo,
    required ImageSource source,
  }) async {
    try {
      final allowed = await MediaPermissionService.request(
        camera: source == ImageSource.camera,
        video: isVideo,
      );
      if (!allowed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permissão de fotos/câmera negada.')),
          );
        }
        return;
      }
      XFile? file;
      if (isVideo) {
        file = await _picker.pickVideo(
          source: source,
          maxDuration: const Duration(minutes: 5),
        );
      } else {
        file = await _picker.pickImage(source: source, imageQuality: 85);
      }
      if (file != null) {
        setState(() {
          _selectedMedia = file;
          _isVideo = isVideo;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível acessar a mídia: $e')),
        );
      }
    }
  }

  void _showMediaSourceSheet({required bool isVideo}) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text(
                isVideo
                    ? 'Importar Vídeo da Galeria'
                    : 'Importar Foto da Galeria',
              ),
              onTap: () {
                Navigator.pop(context);
                _pickMedia(isVideo: isVideo, source: ImageSource.gallery);
              },
            ),
            if (!kIsWeb)
              ListTile(
                leading: Icon(
                  isVideo ? Icons.videocam_rounded : Icons.camera_alt_rounded,
                ),
                title: Text(isVideo ? 'Gravar Vídeo' : 'Tirar Foto'),
                onTap: () {
                  Navigator.pop(context);
                  _pickMedia(isVideo: isVideo, source: ImageSource.camera);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _removeMedia() {
    setState(() {
      _selectedMedia = null;
      _isVideo = false;
    });
  }

  Future<void> _submit() async {
    if (_textCtrl.text.trim().isEmpty) return;
    setState(() => _isPosting = true);
    await Future.delayed(const Duration(milliseconds: 600));
    final now = DateTime.now();
    widget.onPost({
      'id': 'new_${now.millisecondsSinceEpoch}',
      'authorId': 'u1',
      'authorName': 'Amara Osei',
      'authorImage':
          'https://img.rocket.new/generatedImages/rocket_gen_img_10a397da6-1772094815227.png',
      'authorImageSemantic':
          'Amara Osei, jovem mulher com cabelo natural sorrindo',
      'neurodivType': 'TEA',
      'hyperfocusTags': ['Astronomia'],
      'content': _textCtrl.text.trim(),
      'imageUrl': (_selectedMedia != null && !_isVideo)
          ? _selectedMedia!.path
          : null,
      'localImageFile': (_selectedMedia != null && !_isVideo)
          ? _selectedMedia!.path
          : null,
      'localVideoFile': (_selectedMedia != null && _isVideo)
          ? _selectedMedia!.path
          : null,
      'imageSemantic': 'Imagem do post',
      'likes': 0,
      'comments': 0,
      'saves': 0,
      'timeAgo': 'Agora',
      'isLiked': false,
      'isSaved': false,
    });
    if (mounted) Navigator.pop(context);
  }

  Widget _buildMediaPreview(ThemeData theme) {
    if (_selectedMedia == null) return const SizedBox.shrink();

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 180,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          clipBehavior: Clip.antiAlias,
          child: _isVideo
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.play_circle_fill_rounded,
                        size: 56,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Vídeo selecionado',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _selectedMedia!.name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                )
              : kIsWeb
              ? Image.network(
                  _selectedMedia!.path,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 180,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_rounded, size: 48),
                  ),
                )
              : Image.file(
                  File(_selectedMedia!.path),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 180,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_rounded, size: 48),
                  ),
                ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: _removeMedia,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(153),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundImage: const NetworkImage(
                          'https://img.rocket.new/generatedImages/rocket_gen_img_10a397da6-1772094815227.png',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Amara Osei',
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(
                              'Publicando para: $_visibility',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            builder: (_) => Column(
                              mainAxisSize: MainAxisSize.min,
                              children: ['Todos', 'Amigos', 'Somente eu']
                                  .map(
                                    (v) => ListTile(
                                      title: Text(v),
                                      leading: Radio<String>(
                                        value: v,
                                        groupValue: _visibility,
                                        onChanged: (val) {
                                          setState(() => _visibility = val!);
                                          Navigator.pop(context);
                                        },
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          );
                        },
                        child: const Icon(Icons.public_rounded, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _textCtrl,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'O que está passando pela sua cabeça? 💭',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Media preview
                  _buildMediaPreview(theme),
                  // Media action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _showMediaSourceSheet(isVideo: false),
                          icon: const Icon(
                            Icons.photo_library_rounded,
                            size: 18,
                          ),
                          label: const Text(
                            'Foto',
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.primary,
                            side: BorderSide(
                              color: theme.colorScheme.primary.withAlpha(128),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showMediaSourceSheet(isVideo: true),
                          icon: const Icon(Icons.videocam_rounded, size: 18),
                          label: const Text(
                            'Vídeo',
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.secondary,
                            side: BorderSide(
                              color: theme.colorScheme.secondary.withAlpha(128),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.emoji_emotions_outlined),
                        tooltip: 'Emoji',
                        style: IconButton.styleFrom(
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isPosting ? null : _submit,
                      icon: _isPosting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.book_rounded),
                      label: Text(
                        _isPosting ? 'Publicando...' : 'Publicar no Diário',
                        style: const TextStyle(
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
          ],
        ),
      ),
    );
  }
}

// ─── Comments Modal ───────────────────────────────────────────────────────────
class _CommentsModal extends StatefulWidget {
  final Map<String, dynamic> post;
  final Map<String, dynamic>? currentUserProfile;
  final VoidCallback onCommentAdded;

  const _CommentsModal({
    required this.post,
    required this.currentUserProfile,
    required this.onCommentAdded,
  });

  @override
  State<_CommentsModal> createState() => _CommentsModalState();
}

class _CommentsModalState extends State<_CommentsModal> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<Map<String, dynamic>> _comments = [];
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    final postId = widget.post['id'] as String? ?? '';
    if (postId.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final data = await SupabaseService.instance.fetchPostComments(postId);
      if (!mounted) return;
      final mapped = data.map((c) {
        final author = c['author'] as Map<String, dynamic>? ?? {};
        return {
          'id': c['id'] ?? '',
          'authorName': author['full_name'] ?? 'Usuário',
          'authorAvatar': author['avatar_url'] ?? '',
          'text': c['content'] ?? '',
          'time': _timeAgo(c['created_at']),
        };
      }).toList();
      setState(() {
        _comments
          ..clear()
          ..addAll(mapped);
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _timeAgo(dynamic createdAt) {
    if (createdAt == null) return '';
    try {
      final dt = DateTime.parse(createdAt.toString()).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}min';
      if (diff.inHours < 24) return '${diff.inHours}h';
      return '${diff.inDays}d';
    } catch (_) {
      return '';
    }
  }

  Future<void> _sendComment() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    final postId = widget.post['id'] as String? ?? '';
    final result = await SupabaseService.instance.addComment(
      postId: postId,
      content: text,
    );
    if (!mounted) return;
    if (result != null) {
      final author = result['author'] as Map<String, dynamic>? ?? {};
      final newComment = {
        'id': result['id'] ?? '',
        'authorName':
            author['full_name'] ??
            widget.currentUserProfile?['full_name'] ??
            'Você',
        'authorAvatar':
            author['avatar_url'] ??
            widget.currentUserProfile?['avatar_url'] ??
            '',
        'text': result['content'] ?? text,
        'time': 'Agora',
      };
      setState(() {
        _comments.add(newComment);
        _ctrl.clear();
        _isSending = false;
      });
      widget.onCommentAdded();
      // Scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } else {
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível enviar o comentário.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.only(
        bottom: keyboardHeight > 0 ? keyboardHeight : bottomPadding,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.72,
        ),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text('Comentários', style: theme.textTheme.titleMedium),
            ),
            const Divider(height: 1),
            // Comments list
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.primary,
                        strokeWidth: 2,
                      ),
                    )
                  : _comments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 40,
                            color: theme.colorScheme.onSurfaceVariant.withAlpha(
                              100,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Seja o primeiro a comentar!',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.all(16),
                      itemCount: _comments.length,
                      itemBuilder: (_, i) {
                        final c = _comments[i];
                        final avatarUrl = c['authorAvatar'] as String? ?? '';
                        final authorName = c['authorName'] as String? ?? 'U';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              avatarUrl.isNotEmpty
                                  ? CircleAvatar(
                                      radius: 16,
                                      backgroundImage: NetworkImage(avatarUrl),
                                    )
                                  : CircleAvatar(
                                      radius: 16,
                                      backgroundColor:
                                          AppTheme.primaryContainer,
                                      child: Text(
                                        authorName.isNotEmpty
                                            ? authorName[0].toUpperCase()
                                            : 'U',
                                        style: const TextStyle(
                                          color: AppTheme.primary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      authorName,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      c['text'] as String? ?? '',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                c['time'] as String? ?? '',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            // Input row — always pinned above keyboard/nav bar
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                children: [
                  // Current user avatar
                  () {
                    final avatarUrl =
                        widget.currentUserProfile?['avatar_url'] as String? ??
                        '';
                    final name =
                        widget.currentUserProfile?['full_name'] as String? ??
                        'V';
                    return avatarUrl.isNotEmpty
                        ? CircleAvatar(
                            radius: 16,
                            backgroundImage: NetworkImage(avatarUrl),
                          )
                        : CircleAvatar(
                            radius: 16,
                            backgroundColor: AppTheme.primaryContainer,
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'V',
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          );
                  }(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendComment(),
                      decoration: InputDecoration(
                        hintText: 'Adicionar comentário...',
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _isSending
                      ? const SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                        )
                      : IconButton(
                          onPressed: _sendComment,
                          icon: const Icon(Icons.send_rounded),
                          style: IconButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
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
}
