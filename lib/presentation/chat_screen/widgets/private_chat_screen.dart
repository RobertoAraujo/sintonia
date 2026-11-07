import 'dart:async';
import 'dart:io' if (dart.library.io) 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/app_export.dart';
import '../../../services/supabase_service.dart';
import '../../../services/twilio_call_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_scaffold.dart';
import '../../../widgets/report_content_dialog.dart';
import '../../../widgets/user_avatar_widget.dart';
import '../../call_screen/twilio_call_screen.dart';
import '../../user_profile_screen/user_profile_screen.dart';
import './conversation_starters_widget.dart';

/// Full-screen real-time private chat using Supabase Realtime stream.
/// Uses StreamBuilder so messages appear instantly without manual polling.
class PrivateChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUserId;
  final String otherUserName;
  final String otherUserAvatar;
  final String otherUserAvatarSemantic;

  const PrivateChatScreen({
    super.key,
    required this.chatId,
    required this.otherUserId,
    required this.otherUserName,
    required this.otherUserAvatar,
    required this.otherUserAvatarSemantic,
  });

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  late final Stream<List<Map<String, dynamic>>> _messagesStream;

  bool _isSending = false;
  int _previousMessageCount = 0;
  bool _hasInitialScrolled = false;

  // Recipient enriched data
  String _recipientName = '';
  String _recipientAvatar = '';
  String? _recipientPetPhotoUrl;
  bool _isLoadingRecipient = false;

  // Online presence & typing
  bool _isRecipientOnline = false;
  bool _isRecipientTyping = false;
  RealtimeChannel? _presenceChannel;
  RealtimeChannel? _profileChannel;
  Timer? _onlineStatusTimer;
  DateTime? _recipientLastSeen;

  // Typing debounce
  Timer? _typingTimer;
  bool _iAmTyping = false;

  // Input bar state
  bool _showEmojiPicker = false;
  bool _isRecording = false;
  final ImagePicker _imagePicker = ImagePicker();

  String get _myId => SupabaseService.instance.currentUserId ?? '';

  bool _isUploadingMedia = false;
  AudioRecorder? _audioRecorder;
  String? _recordingPath;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;

  // Search state
  bool _showSearch = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _allMessages = [];

  // Read receipts toggle
  bool _showReadReceipts = true;

  static const String _readReceiptsPrefKey = 'show_read_receipts';

  // ── Block state ────────────────────────────────────────────────────────────
  bool _isBlocked = false; // true if either side has blocked the other
  bool _isCheckingBlock = true;

  // ── Gemini conversation starters ───────────────────────────────────────────
  bool _startersDismissed = false;

  @override
  void initState() {
    super.initState();
    _recipientName = widget.otherUserName;
    _recipientAvatar = widget.otherUserAvatar;

    _messagesStream = SupabaseService.instance.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', widget.chatId)
        .order('created_at', ascending: true)
        .map((rows) => rows.cast<Map<String, dynamic>>());

    _markAsRead();
    _loadReadReceiptsPref();

    _fetchRecipientProfile();
    _checkBlockStatus();

    _subscribePresence();
    _subscribeProfileChanges();

    _fetchRecipientOnlineStatus();

    _onlineStatusTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _fetchRecipientOnlineStatus();
    });

    chatKeyboardVisibleNotifier.value = true;
  }

  Future<void> _loadReadReceiptsPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _showReadReceipts = prefs.getBool(_readReceiptsPrefKey) ?? true;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleReadReceipts() async {
    final newValue = !_showReadReceipts;
    setState(() => _showReadReceipts = newValue);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_readReceiptsPrefKey, newValue);
    } catch (_) {}
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _onlineStatusTimer?.cancel();
    _presenceChannel?.unsubscribe();
    _profileChannel?.unsubscribe();
    _inputFocusNode.dispose();
    // Restore bottom nav bar when leaving private chat
    chatKeyboardVisibleNotifier.value = false;
    _scrollCtrl.dispose();
    _audioRecorder?.dispose();
    _recordingTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Directly query last_seen for the recipient and update online status.
  Future<void> _fetchRecipientOnlineStatus() async {
    try {
      final rows = await SupabaseService.instance.client
          .from('user_profiles')
          .select('last_seen')
          .eq('id', widget.otherUserId)
          .limit(1);
      if (!mounted) return;
      final list = rows as List;
      if (list.isEmpty) return;
      final lastSeenRaw = list.first['last_seen'];
      final isOnline = _isLastSeenOnline(lastSeenRaw);
      DateTime? lastSeenDt;
      if (lastSeenRaw != null) {
        try {
          lastSeenDt = DateTime.parse(lastSeenRaw as String).toLocal();
        } catch (_) {}
      }
      debugPrint(
        'PrivateChatScreen: initial last_seen=$lastSeenRaw isOnline=$isOnline',
      );
      setState(() {
        _isRecipientOnline = isOnline;
        _recipientLastSeen = lastSeenDt;
      });
    } catch (e) {
      debugPrint('PrivateChatScreen: _fetchRecipientOnlineStatus error: $e');
    }
  }

  /// Returns true if [lastSeenRaw] (ISO string or null) is within 35 seconds.
  bool _isLastSeenOnline(dynamic lastSeenRaw) {
    if (lastSeenRaw == null) return false;
    try {
      final lastSeen = DateTime.parse(lastSeenRaw as String).toLocal();
      return DateTime.now().difference(lastSeen).inSeconds <= 35;
    } catch (_) {
      return false;
    }
  }

  // ── Presence & Typing ─────────────────────────────────────────────────────

  void _subscribePresence() {
    // Use a per-chat channel ONLY for typing indicators.
    // Online/offline status is handled by GlobalPresenceService.
    final channelName = 'chat_presence_${widget.chatId}';
    _presenceChannel = SupabaseService.instance.client.channel(channelName);

    _presenceChannel!
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final senderId = payload['user_id'] as String?;
            if (senderId != null && senderId != _myId) {
              final isTyping = payload['is_typing'] as bool? ?? false;
              if (mounted) {
                setState(() => _isRecipientTyping = isTyping);
              }
              // Auto-clear typing after 4 seconds if no update
              if (isTyping) {
                Future.delayed(const Duration(seconds: 4), () {
                  if (mounted) setState(() => _isRecipientTyping = false);
                });
              }
            }
          },
        )
        .subscribe();
  }

  /// Subscribe to user_profiles Realtime changes for the recipient.
  /// Updates avatar/name AND online status (via last_seen) instantly.
  void _subscribeProfileChanges() {
    _profileChannel = SupabaseService.instance.client
        .channel('profile_changes_${widget.otherUserId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'user_profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.otherUserId,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            if (record.isEmpty || !mounted) return;

            // Update avatar and name
            final newAvatar = record['avatar_url'] as String? ?? '';
            final newName = (record['full_name'] as String?)?.isNotEmpty == true
                ? record['full_name'] as String
                : (record['username'] as String? ?? _recipientName);

            // Update online status from last_seen
            final lastSeenRaw = record['last_seen'];
            final isOnline = _isLastSeenOnline(lastSeenRaw);
            DateTime? lastSeenDt;
            if (lastSeenRaw != null) {
              try {
                lastSeenDt = DateTime.parse(lastSeenRaw as String).toLocal();
              } catch (_) {}
            }
            debugPrint(
              'Realtime profile update -> $newName | last_seen=$lastSeenRaw isOnline=$isOnline',
            );

            setState(() {
              _recipientAvatar = newAvatar;
              _recipientName = newName;
              _isRecipientOnline = isOnline;
              _recipientLastSeen = lastSeenDt;
            });
          },
        )
        .subscribe((status, [error]) {
          debugPrint(
            'PrivateChatScreen: profile channel status=$status error=$error',
          );
        });
  }

  void _onInputChanged(String value) {
    setState(() {});
    final isTyping = value.trim().isNotEmpty;
    if (isTyping != _iAmTyping) {
      _iAmTyping = isTyping;
      _broadcastTyping(isTyping);
    }
    if (isTyping) {
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        _iAmTyping = false;
        _broadcastTyping(false);
      });
    }
  }

  void _broadcastTyping(bool isTyping) {
    _presenceChannel?.sendBroadcastMessage(
      event: 'typing',
      payload: {'user_id': _myId, 'is_typing': isTyping},
    );
  }

  // ── Profile loading ───────────────────────────────────────────────────────

  Future<void> _fetchRecipientProfile() async {
    setState(() => _isLoadingRecipient = true);
    try {
      final profile = await SupabaseService.instance.client
          .from('user_profiles')
          .select('id, full_name, username, avatar_url, active_pet_id')
          .eq('id', widget.otherUserId)
          .maybeSingle();
      if (profile != null && mounted) {
        final name = (profile['full_name'] as String?)?.isNotEmpty == true
            ? profile['full_name'] as String
            : (profile['username'] as String? ?? 'Usuário');
        final avatarUrl = profile['avatar_url'] as String? ?? '';
        debugPrint('DEBUG CHAT -> Usuário: $name | AvatarURL: $avatarUrl');
        setState(() {
          _recipientName = name;
          _recipientAvatar = avatarUrl;
          _isLoadingRecipient = false;
        });
        final activePetId = profile['active_pet_id'] as String?;
        if (activePetId != null) _fetchPetPhoto(activePetId);
      } else {
        if (mounted) setState(() => _isLoadingRecipient = false);
      }
    } catch (e) {
      debugPrint('_fetchRecipientProfile error: $e');
      if (mounted) setState(() => _isLoadingRecipient = false);
    }
  }

  Future<void> _fetchRecipientPet() async {
    try {
      final profile = await SupabaseService.instance.client
          .from('user_profiles')
          .select('active_pet_id')
          .eq('id', widget.otherUserId)
          .maybeSingle();
      if (profile != null) {
        final activePetId = profile['active_pet_id'] as String?;
        if (activePetId != null) _fetchPetPhoto(activePetId);
      }
    } catch (_) {}
  }

  Future<void> _fetchPetPhoto(String petId) async {
    try {
      final pet = await SupabaseService.instance.client
          .from('pets')
          .select('photo_url')
          .eq('id', petId)
          .maybeSingle();
      if (pet != null && mounted) {
        final photoUrl = pet['photo_url'] as String?;
        if (photoUrl != null && photoUrl.isNotEmpty) {
          setState(() => _recipientPetPhotoUrl = photoUrl);
        }
      }
    } catch (_) {}
  }

  void _navigateToRecipientProfile() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => UserProfileScreen(
          userData: {
            'id': widget.otherUserId,
            'name': _recipientName,
            'avatarUrl': _recipientAvatar,
            'avatarSemantic': 'Foto de $_recipientName',
            'username': '',
            'bio': '',
            'neurodivType': '',
            'hyperfocuses': [],
            'interests': [],
            'friendsCount': 0,
            'postsCount': 0,
            'compatScore': 0,
            'isMe': false,
          },
        ),
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

  // ── Gemini conversation starters ─────────────────────────────────────────

  /// Show starters when the chat is empty, or the last message is > 24h old.
  bool _shouldShowStarters(List<Map<String, dynamic>> messages) {
    if (_startersDismissed || _isBlocked || _isCheckingBlock) return false;
    if (_inputCtrl.text.trim().isNotEmpty) return false;
    if (messages.isEmpty) return true;
    try {
      final last = DateTime.parse(
        messages.last['created_at'] as String,
      ).toLocal();
      return DateTime.now().difference(last).inHours >= 24;
    } catch (_) {
      return false;
    }
  }

  Widget _buildStartersCard() {
    return ConversationStartersWidget(
      friendId: widget.otherUserId,
      friendName: _recipientName.isNotEmpty
          ? _recipientName.split(' ').first
          : 'seu amigo',
      onDismiss: () => setState(() => _startersDismissed = true),
      onSelected: (text) {
        setState(() {
          _inputCtrl.text = text;
          _inputCtrl.selection = TextSelection.fromPosition(
            TextPosition(offset: text.length),
          );
          _startersDismissed = true;
        });
        _inputFocusNode.requestFocus();
      },
    );
  }

  // ── Send message ─────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _isSending) return;

    // Session guard — ensure user is authenticated before sending
    final currentUser = SupabaseService.instance.currentUser;
    if (currentUser == null || currentUser.id.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sessão expirada. Faça login novamente.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final senderId = currentUser.id;

    // Stop typing indicator
    _typingTimer?.cancel();
    _iAmTyping = false;
    _broadcastTyping(false);

    setState(() {
      _inputCtrl.clear();
      _isSending = true;
    });

    try {
      await SupabaseService.instance.client.from('messages').insert({
        'conversation_id': widget.chatId,
        'sender_id': senderId,
        'content': text,
        'is_read': false,
      });
    } catch (e) {
      debugPrint('_sendMessage error: $e');
      if (mounted) {
        // Restore the text so user can retry
        _inputCtrl.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Falha ao enviar mensagem. Tente novamente.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade600,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // ── Mark messages as read ─────────────────────────────────────────────────

  Future<void> _markAsRead() async {
    try {
      await SupabaseService.instance.client
          .from('messages')
          .update({'is_read': true})
          .eq('conversation_id', widget.chatId)
          .eq('sender_id', widget.otherUserId)
          .eq('is_read', false);
    } catch (_) {}
  }

  // ── Media Upload ──────────────────────────────────────────────────────────

  Future<String?> _uploadToStorage(
    List<int> bytes,
    String fileName,
    String contentType,
  ) async {
    try {
      final path = 'chat/${widget.chatId}/$fileName';
      await SupabaseService.instance.client.storage
          .from('chat-media')
          .uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );
      final url = SupabaseService.instance.client.storage
          .from('chat-media')
          .getPublicUrl(path);
      return url;
    } catch (e) {
      debugPrint('_uploadToStorage error: $e');
      return null;
    }
  }

  Future<void> _sendMediaMessage(
    String mediaUrl,
    String messageType, {
    String content = '',
  }) async {
    final currentUser = SupabaseService.instance.currentUser;
    if (currentUser == null) return;
    try {
      await SupabaseService.instance.client.from('messages').insert({
        'conversation_id': widget.chatId,
        'sender_id': currentUser.id,
        'content': content,
        'message_type': messageType,
        'media_url': mediaUrl,
        'is_read': false,
      });
    } catch (e) {
      debugPrint('_sendMediaMessage error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Falha ao enviar mídia. Tente novamente.'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Image / Video Picking ─────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? file = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1280,
      );
      if (file == null || !mounted) return;

      setState(() => _isUploadingMedia = true);
      _showUploadingSnackbar('Enviando imagem...');

      final bytes = await file.readAsBytes();
      final ext = file.name.split('.').last.toLowerCase();
      final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';

      final url = await _uploadToStorage(bytes, fileName, contentType);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (url != null) {
        await _sendMediaMessage(url, 'image');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Falha ao enviar imagem.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('_pickImage error: $e');
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    } finally {
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? file = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      if (file == null || !mounted) return;

      setState(() => _isUploadingMedia = true);
      _showUploadingSnackbar('Enviando vídeo...');

      final bytes = await file.readAsBytes();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';

      final url = await _uploadToStorage(bytes, fileName, 'video/mp4');
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (url != null) {
        await _sendMediaMessage(url, 'image', content: '🎥 Vídeo');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Falha ao enviar vídeo.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('_pickVideo error: $e');
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    } finally {
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }

  // ── Audio Recording ───────────────────────────────────────────────────────

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      _audioRecorder ??= AudioRecorder();
      final hasPermission = await _audioRecorder!.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Permissão de microfone necessária para gravar áudio.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      String path;
      if (kIsWeb) {
        path = 'recording_${DateTime.now().millisecondsSinceEpoch}.webm';
        await _audioRecorder!.start(
          const RecordConfig(encoder: AudioEncoder.opus),
          path: path,
        );
      } else {
        final dir = await getTemporaryDirectory();
        path =
            '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder!.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
          path: path,
        );
      }

      _recordingPath = path;
      _recordingDuration = Duration.zero;
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _recordingDuration += const Duration(seconds: 1));
        }
      });

      setState(() => _isRecording = true);
    } catch (e) {
      debugPrint('_startRecording error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível iniciar a gravação.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      _recordingTimer?.cancel();
      _recordingTimer = null;
      final path = await _audioRecorder?.stop();
      setState(() => _isRecording = false);

      if (path == null || !mounted) return;

      setState(() => _isUploadingMedia = true);
      _showUploadingSnackbar('Enviando áudio...');

      List<int> bytes;
      if (kIsWeb) {
        // On web, path is a blob URL — read via XFile
        final xfile = XFile(path);
        bytes = await xfile.readAsBytes();
      } else {
        final file = File(path);
        bytes = await file.readAsBytes();
      }

      final ext = kIsWeb ? 'webm' : 'm4a';
      final contentType = kIsWeb ? 'audio/webm' : 'audio/m4a';
      final fileName = 'audio_${DateTime.now().millisecondsSinceEpoch}.$ext';

      final url = await _uploadToStorage(bytes, fileName, contentType);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (url != null) {
        final secs = _recordingDuration.inSeconds;
        final durStr =
            '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}';
        await _sendMediaMessage(url, 'audio', content: '🎤 Áudio ($durStr)');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Falha ao enviar áudio.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('_stopRecording error: $e');
      if (mounted) setState(() => _isRecording = false);
    } finally {
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }

  void _cancelRecording() async {
    try {
      _recordingTimer?.cancel();
      _recordingTimer = null;
      await _audioRecorder?.stop();
    } catch (_) {}
    if (mounted) setState(() => _isRecording = false);
  }

  void _showUploadingSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 30),
        backgroundColor: AppTheme.primary,
      ),
    );
  }

  void _showFilePlaceholder() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Selecione um arquivo para enviar'),
        backgroundColor: AppTheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Search ────────────────────────────────────────────────────────────────

  void _onSearchChanged(String query, List<Map<String, dynamic>> messages) {
    setState(() => _searchQuery = query);
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    final q = query.toLowerCase();
    final results = messages.where((m) {
      final text = (m['content'] as String? ?? '').toLowerCase();
      return text.contains(q);
    }).toList();
    setState(() => _searchResults = results);
  }

  void _scrollToMessage(String messageId, List<Map<String, dynamic>> messages) {
    final idx = messages.indexWhere((m) => m['id']?.toString() == messageId);
    if (idx == -1 || !_scrollCtrl.hasClients) return;

    // In a reversed ListView, item at original index `idx` is at reversed index (messages.length - 1 - idx)
    final reversedIdx = messages.length - 1 - idx;
    // Estimate item height ~60px
    const itemHeight = 60.0;
    final offset = (reversedIdx * itemHeight).clamp(
      0.0,
      _scrollCtrl.position.maxScrollExtent,
    );
    _scrollCtrl.animateTo(
      offset,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    setState(() => _showSearch = false);
  }

  void _showCallDialog(bool isVideo) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isVideo ? Icons.videocam_rounded : Icons.call_rounded,
              color: AppTheme.primary,
            ),
            const SizedBox(width: 8),
            Text(isVideo ? 'Chamada de Vídeo' : 'Chamada de Voz'),
          ],
        ),
        content: Text(
          isVideo
              ? 'Iniciar chamada de vídeo com $_recipientName?'
              : 'Iniciar chamada de voz com $_recipientName?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              _initiateCall(isVideo);
            },
            child: Text(isVideo ? 'Ligar Vídeo' : 'Ligar'),
          ),
        ],
      ),
    );
  }

  Future<void> _initiateCall(bool isVideo) async {
    final callType = isVideo ? 'video' : 'voice';
    final roomName =
        'room_${widget.chatId}_${DateTime.now().millisecondsSinceEpoch}';

    try {
      await TwilioCallService.instance.sendCallInvitation(
        chatId: widget.chatId,
        callerId: _myId,
        callerName: _recipientName,
        callerAvatar: _recipientAvatar,
        calleeId: widget.otherUserId,
        roomName: roomName,
        callType: callType,
      );
    } catch (e) {
      debugPrint('sendCallInvitation error: $e');
    }

    if (!mounted) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => TwilioCallScreen(
          chatId: widget.chatId,
          roomName: roomName,
          callType: callType,
          otherUserId: widget.otherUserId,
          otherUserName: _recipientName,
          otherUserAvatar: _recipientAvatar,
        ),
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  // ── Block check ───────────────────────────────────────────────────────────

  Future<void> _checkBlockStatus() async {
    final myId = SupabaseService.instance.currentUserId;
    final otherId = widget.otherUserId;
    if (myId == null || myId.isEmpty) {
      if (mounted) setState(() => _isCheckingBlock = false);
      return;
    }
    try {
      // Check both directions: I blocked them OR they blocked me
      final results = await SupabaseService.instance.client
          .from('blocked_users')
          .select('id')
          .or(
            'and(blocker_id.eq.$myId,blocked_user_id.eq.$otherId),and(blocker_id.eq.$otherId,blocked_user_id.eq.$myId)',
          );
      if (mounted) {
        setState(() {
          _isBlocked = (results as List).isNotEmpty;
          _isCheckingBlock = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isCheckingBlock = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatTime(String? createdAt) {
    if (createdAt == null) return '';
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  String _formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) return 'Offline';
    final now = DateTime.now();
    final diff = now.difference(lastSeen);
    if (diff.inSeconds < 60) {
      return 'Visto por último: agora pouco';
    } else if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return 'Visto por último: há ${m}min';
    } else if (diff.inHours < 24) {
      final h = diff.inHours;
      return 'Visto por último: há ${h}h';
    } else {
      final d = diff.inDays;
      return 'Visto por último: há ${d}d';
    }
  }

  String _statusText() {
    if (_isRecipientOnline) return 'Online';
    // Always show "Visto por último" when last_seen timestamp exists
    if (_recipientLastSeen != null) return _formatLastSeen(_recipientLastSeen);
    return 'Offline';
  }

  void _scrollToBottom({bool instant = false}) {
    // Use a robust retry approach: attempt scroll multiple times over 500ms
    // to ensure the ListView is fully laid out before scrolling
    void attemptScroll(int retriesLeft) {
      if (!mounted) return;
      if (_scrollCtrl.hasClients && _scrollCtrl.position.maxScrollExtent >= 0) {
        if (instant) {
          _scrollCtrl.jumpTo(0);
        } else {
          _scrollCtrl.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      } else if (retriesLeft > 0) {
        Future.delayed(const Duration(milliseconds: 80), () {
          attemptScroll(retriesLeft - 1);
        });
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      attemptScroll(8); // retry up to 8 times (~640ms total)
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Show blocked screen — chat is unavailable
    if (!_isCheckingBlock && _isBlocked) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.colorScheme.surface,
          elevation: 0,
          leading: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: theme.colorScheme.onSurface,
            ),
          ),
          title: Text(
            _recipientName.isNotEmpty ? _recipientName : 'Conversa',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: theme.colorScheme.outlineVariant),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.block_rounded,
                  size: 72,
                  color: theme.colorScheme.error.withAlpha(179),
                ),
                const SizedBox(height: 24),
                Text(
                  'Conversa indisponível',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Não é possível enviar ou receber mensagens nesta conversa.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: theme.colorScheme.onSurface,
          ),
        ),
        title: GestureDetector(
          onTap: _navigateToRecipientProfile,
          child: Row(
            children: [
              // Avatar with online dot + pet badge
              Stack(
                clipBehavior: Clip.none,
                children: [
                  UserAvatar(
                    avatarUrl: _recipientAvatar.isNotEmpty
                        ? _recipientAvatar
                        : null,
                    displayName: _recipientName,
                    radius: 18,
                  ),
                  // Online presence dot
                  if (_isRecipientOnline)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: AppTheme.success,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.surface,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  // Pet badge
                  if (_recipientPetPhotoUrl != null)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.surface,
                            width: 1.5,
                          ),
                        ),
                        child: ClipOval(
                          child: Image.network(
                            _recipientPetPhotoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.pets_rounded,
                              size: 10,
                              color: Colors.brown,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _isLoadingRecipient
                        ? Container(
                            width: 100,
                            height: 14,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.outlineVariant.withAlpha(
                                80,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          )
                        : Text(
                            _recipientName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                    // Typing or online status
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _isRecipientTyping
                          ? _TypingIndicator(key: const ValueKey('typing'))
                          : Text(
                              key: const ValueKey('status'),
                              _statusText(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: _isRecipientOnline
                                    ? AppTheme.success
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: theme.colorScheme.outlineVariant),
        ),
        actions: [
          // TODO: Habilitar quando o recurso de chamadas for lançado
          // IconButton(
          //   onPressed: () => _showCallDialog(true),
          //   icon: Icon(
          //     Icons.videocam_rounded,
          //     color: theme.colorScheme.onSurface,
          //     size: 22,
          //   ),
          //   tooltip: 'Chamada de vídeo',
          // ),
          // IconButton(
          //   onPressed: () => _showCallDialog(false),
          //   icon: Icon(
          //     Icons.call_rounded,
          //     color: theme.colorScheme.onSurface,
          //     size: 22,
          //   ),
          //   tooltip: 'Chamada de voz',
          // ),
          IconButton(
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchCtrl.clear();
                  _searchResults = [];
                }
              });
            },
            icon: Icon(
              _showSearch ? Icons.search_off_rounded : Icons.search_rounded,
              color: _showSearch
                  ? AppTheme.primary
                  : theme.colorScheme.onSurface,
              size: 22,
            ),
            tooltip: 'Pesquisar mensagens',
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert_rounded,
              color: theme.colorScheme.onSurface,
              size: 22,
            ),
            onSelected: (value) {
              if (value == 'report') {
                showReportDialog(
                  context,
                  contentType: 'profile',
                  reportedUserId: widget.otherUserId,
                );
              } else if (value == 'toggle_receipts') {
                _toggleReadReceipts();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                value: 'toggle_receipts',
                child: Row(
                  children: [
                    Icon(
                      _showReadReceipts
                          ? Icons.done_all_rounded
                          : Icons.remove_done_rounded,
                      color: _showReadReceipts
                          ? AppTheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _showReadReceipts
                          ? 'Desativar confirmação de leitura'
                          : 'Ativar confirmação de leitura',
                    ),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'report',
                child: Row(
                  children: [
                    Icon(Icons.flag_outlined, color: Colors.red),
                    SizedBox(width: 12),
                    Text(
                      'Denunciar usuário',
                      style: TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _messagesStream,
        builder: (context, snapshot) {
          final messages = snapshot.data ?? [];
          _allMessages = messages;

          if (messages.length > _previousMessageCount) {
            _previousMessageCount = messages.length;
            if (!_hasInitialScrolled) {
              _hasInitialScrolled = true;
              _scrollToBottom(instant: true);
            } else {
              _scrollToBottom();
            }
            if (messages.isNotEmpty) _markAsRead();
          }

          return Stack(
            children: [
              Column(
                children: [
                  // ── Messages list ────────────────────────────────────────
                  Expanded(
                    child: () {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (messages.isEmpty) {
                        return SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 48,
                                color: theme.colorScheme.outlineVariant,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Nenhuma mensagem ainda.\nDiga olá! 👋',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_shouldShowStarters(messages))
                                _buildStartersCard(),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        controller: _scrollCtrl,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (_, i) => _buildBubble(
                          theme,
                          messages[messages.length - 1 - i],
                        ),
                      );
                    }(),
                  ),

                  // ── Gemini starters for stale (old) chats ────────────────
                  if (messages.isNotEmpty && _shouldShowStarters(messages))
                    _buildStartersCard(),

                  // ── Input bar ────────────────────────────────────────────
                  _buildInputBar(theme),
                ],
              ),

              // ── Search panel overlay ─────────────────────────────────────
              if (_showSearch)
                Positioned(
                  top: 0,
                  right: 0,
                  width: MediaQuery.of(context).size.width * 0.85,
                  bottom: 0,
                  child: _SearchPanel(
                    controller: _searchCtrl,
                    searchQuery: _searchQuery,
                    results: _searchResults,
                    allMessages: messages,
                    onChanged: (q) => _onSearchChanged(q, messages),
                    onResultTap: (msgId) => _scrollToMessage(msgId, messages),
                    onClose: () {
                      setState(() {
                        _showSearch = false;
                        _searchCtrl.clear();
                        _searchQuery = '';
                        _searchResults = [];
                      });
                    },
                    theme: theme,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBubble(ThemeData theme, Map<String, dynamic> row) {
    final senderId = row['sender_id'] as String?;
    final isMe = senderId == _myId;
    final text = row['content'] as String? ?? '';
    final time = _formatTime(row['created_at']?.toString());
    final isRead = row['is_read'] as bool? ?? false;
    final messageType = row['message_type'] as String? ?? 'text';
    final mediaUrl = row['media_url'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            UserAvatar(
              avatarUrl: _recipientAvatar.isNotEmpty ? _recipientAvatar : null,
              displayName: _recipientName,
              radius: 12,
            ),
            const SizedBox(width: 6),
          ],
          Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  // Image bubble
                  if (messageType == 'image' && mediaUrl.isNotEmpty)
                    _ImageBubble(mediaUrl: mediaUrl, isMe: isMe, theme: theme),
                  // Audio bubble
                  if (messageType == 'audio' && mediaUrl.isNotEmpty)
                    _AudioBubble(
                      mediaUrl: mediaUrl,
                      isMe: isMe,
                      theme: theme,
                      label: text.isNotEmpty ? text : '🎤 Áudio',
                    ),
                  // Text bubble (shown for text type, or as caption for media)
                  if (messageType == 'text' ||
                      (messageType != 'audio' &&
                          messageType != 'image' &&
                          text.isNotEmpty))
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isMe
                            ? AppTheme.primary
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(isMe ? 18 : 4),
                          bottomRight: Radius.circular(isMe ? 4 : 18),
                        ),
                      ),
                      child: Text(
                        text,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isMe
                              ? Colors.white
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        time,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isMe
                              ? Colors.white.withAlpha(180)
                              : theme.colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                      if (isMe && _showReadReceipts) ...[
                        const SizedBox(width: 4),
                        Icon(
                          isRead ? Icons.done_all_rounded : Icons.done_rounded,
                          size: 12,
                          color: isRead
                              ? Colors.lightBlueAccent
                              : Colors.white.withAlpha(180),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Emoji picker panel
          if (_showEmojiPicker)
            Container(
              height: 250,
              color: theme.colorScheme.surface,
              child: _EmojiPickerPanel(
                onEmojiSelected: (emoji) {
                  final text = _inputCtrl.text;
                  final sel = _inputCtrl.selection;
                  final newText = text.replaceRange(
                    sel.start < 0 ? text.length : sel.start,
                    sel.end < 0 ? text.length : sel.end,
                    emoji,
                  );
                  _inputCtrl.value = TextEditingValue(
                    text: newText,
                    selection: TextSelection.collapsed(
                      offset:
                          (sel.start < 0 ? text.length : sel.start) +
                          emoji.length,
                    ),
                  );
                  _onInputChanged(newText);
                },
              ),
            ),
          // Recording indicator bar
          if (_isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.red.shade50,
              child: Row(
                children: [
                  const Icon(Icons.mic_rounded, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Gravando... ${_recordingDuration.inMinutes.toString().padLeft(2, '0')}:${(_recordingDuration.inSeconds % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _cancelRecording,
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Emoji button
                _InputActionBtn(
                  icon: _showEmojiPicker
                      ? Icons.keyboard_rounded
                      : Icons.emoji_emotions_outlined,
                  color: _showEmojiPicker
                      ? AppTheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  onTap: () {
                    setState(() => _showEmojiPicker = !_showEmojiPicker);
                    if (_showEmojiPicker) {
                      FocusScope.of(context).unfocus();
                    }
                  },
                ),
                // Attachment button
                _InputActionBtn(
                  icon: Icons.attach_file_rounded,
                  color: _isUploadingMedia
                      ? AppTheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  onTap: _isUploadingMedia ? () {} : _showAttachmentOptions,
                ),
                // Text input
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (_showEmojiPicker) {
                        setState(() => _showEmojiPicker = false);
                      }
                    },
                    child: TextField(
                      controller: _inputCtrl,
                      focusNode: _inputFocusNode,
                      onChanged: _onInputChanged,
                      onSubmitted: (_) => _sendMessage(),
                      onTap: () {
                        if (_showEmojiPicker) {
                          setState(() => _showEmojiPicker = false);
                        }
                      },
                      textInputAction: TextInputAction.send,
                      maxLines: 4,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: _isRecording
                            ? 'Gravando áudio...'
                            : 'Digite uma mensagem',
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Send / mic button
                _inputCtrl.text.trim().isNotEmpty
                    ? GestureDetector(
                        onTap: _isSending ? null : _sendMessage,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: _isSending
                              ? const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.send_rounded,
                                  size: 20,
                                  color: Colors.white,
                                ),
                        ),
                      )
                    : GestureDetector(
                        onTap: _isUploadingMedia ? null : _toggleRecording,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _isRecording
                                ? Colors.red
                                : theme.colorScheme.surfaceContainerHighest,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isRecording
                                ? Icons.stop_rounded
                                : Icons.mic_rounded,
                            size: 20,
                            color: _isRecording
                                ? Colors.white
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _AttachOption(
                      icon: Icons.photo_library_rounded,
                      label: 'Galeria',
                      color: Colors.purple,
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickImage(ImageSource.gallery);
                      },
                    ),
                    _AttachOption(
                      icon: Icons.camera_alt_rounded,
                      label: 'Câmera',
                      color: Colors.blue,
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickImage(ImageSource.camera);
                      },
                    ),
                    _AttachOption(
                      icon: Icons.videocam_rounded,
                      label: 'Vídeo',
                      color: Colors.red,
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickVideo();
                      },
                    ),
                    _AttachOption(
                      icon: Icons.insert_drive_file_rounded,
                      label: 'Arquivo',
                      color: Colors.orange,
                      onTap: () {
                        Navigator.pop(ctx);
                        _showFilePlaceholder();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

// ── Image bubble widget ───────────────────────────────────────────────────────

class _ImageBubble extends StatelessWidget {
  final String mediaUrl;
  final bool isMe;
  final ThemeData theme;

  const _ImageBubble({
    required this.mediaUrl,
    required this.isMe,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(18),
        topRight: const Radius.circular(18),
        bottomLeft: Radius.circular(isMe ? 18 : 4),
        bottomRight: Radius.circular(isMe ? 4 : 18),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260, maxHeight: 320),
        child: Image.network(
          mediaUrl,
          fit: BoxFit.cover,
          semanticLabel: 'Imagem enviada na conversa',
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              width: 200,
              height: 160,
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
          errorBuilder: (_, __, ___) => Container(
            width: 200,
            height: 100,
            color: theme.colorScheme.surfaceContainerHighest,
            child: const Center(
              child: Icon(Icons.broken_image_rounded, color: Colors.grey),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Audio bubble widget ───────────────────────────────────────────────────────

class _AudioBubble extends StatefulWidget {
  final String mediaUrl;
  final bool isMe;
  final ThemeData theme;
  final String label;

  const _AudioBubble({
    required this.mediaUrl,
    required this.isMe,
    required this.theme,
    required this.label,
  });

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  late final AudioPlayer _player;
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _player.durationStream.listen((dur) {
      if (mounted && dur != null) setState(() => _duration = dur);
    });
    _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          if (state.processingState == ProcessingState.completed) {
            _isPlaying = false;
            _position = Duration.zero;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
      return;
    }
    setState(() => _isLoading = true);
    try {
      if (_position == Duration.zero ||
          _player.processingState == ProcessingState.completed) {
        await _player.setUrl(widget.mediaUrl);
      }
      await _player.play();
    } catch (e) {
      debugPrint('_AudioBubble play error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isMe
        ? AppTheme.primary
        : widget.theme.colorScheme.surfaceContainerHighest;
    final fgColor = widget.isMe
        ? Colors.white
        : widget.theme.colorScheme.onSurface;
    final maxDur = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final curPos = _position.inMilliseconds.toDouble().clamp(0.0, maxDur);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(widget.isMe ? 18 : 4),
          bottomRight: Radius.circular(widget.isMe ? 4 : 18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: fgColor.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: _isLoading
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: fgColor,
                      ),
                    )
                  : Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: fgColor,
                      size: 22,
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: SliderComponentShape.noOverlay,
                    activeTrackColor: fgColor,
                    inactiveTrackColor: fgColor.withAlpha(60),
                    thumbColor: fgColor,
                  ),
                  child: Slider(
                    value: curPos,
                    min: 0,
                    max: maxDur,
                    onChanged: (v) async {
                      await _player.seek(Duration(milliseconds: v.toInt()));
                    },
                  ),
                ),
              ),
              Text(
                '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                style: TextStyle(fontSize: 10, color: fgColor.withAlpha(180)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Input action button ───────────────────────────────────────────────────────

class _InputActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _InputActionBtn({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}

// ── Attachment option ─────────────────────────────────────────────────────────

class _AttachOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Emoji picker panel ────────────────────────────────────────────────────────

class _EmojiPickerPanel extends StatelessWidget {
  final void Function(String emoji) onEmojiSelected;

  const _EmojiPickerPanel({required this.onEmojiSelected});

  static const List<String> _emojis = [
    '😀',
    '😂',
    '🥰',
    '😍',
    '🤩',
    '😎',
    '🥳',
    '😊',
    '😇',
    '🤗',
    '😅',
    '😆',
    '😋',
    '😛',
    '😜',
    '🤪',
    '😝',
    '🤑',
    '🤭',
    '🤫',
    '🤔',
    '😐',
    '😑',
    '😶',
    '😏',
    '😒',
    '🙄',
    '😬',
    '🤥',
    '😌',
    '😔',
    '😪',
    '🤤',
    '😴',
    '😷',
    '🤒',
    '🤕',
    '🤢',
    '🤧',
    '🥵',
    '🥶',
    '🥴',
    '😵',
    '🤯',
    '🤠',
    '🥸',
    '😈',
    '👿',
    '💀',
    '💩',
    '🤡',
    '👹',
    '👺',
    '👻',
    '👽',
    '👾',
    '🤖',
    '😺',
    '😸',
    '😹',
    '❤️',
    '🧡',
    '💛',
    '💚',
    '💙',
    '💜',
    '🖤',
    '🤍',
    '🤎',
    '💔',
    '❣️',
    '💕',
    '💞',
    '💓',
    '💗',
    '💖',
    '💘',
    '💝',
    '💟',
    '☮️',
    '👍',
    '👎',
    '👏',
    '🙌',
    '🤝',
    '🤜',
    '🤛',
    '✊',
    '👊',
    '🤚',
    '✋',
    '🖐️',
    '👋',
    '🤙',
    '💪',
    '🦾',
    '🖕',
    '✌️',
    '🤞',
    '🤟',
    '🎉',
    '🎊',
    '🎈',
    '🎁',
    '🎀',
    '🎗️',
    '🎟️',
    '🎫',
    '🏆',
    '🥇',
    '⭐',
    '🌟',
    '✨',
    '💫',
    '🔥',
    '💥',
    '❄️',
    '🌈',
    '☀️',
    '🌙',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(height: 1, color: theme.colorScheme.outlineVariant),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 10,
              childAspectRatio: 1,
            ),
            itemCount: _emojis.length,
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => onEmojiSelected(_emojis[i]),
              child: Center(
                child: Text(_emojis[i], style: const TextStyle(fontSize: 22)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Search panel ─────────────────────────────────────────────────────────────

class _SearchPanel extends StatelessWidget {
  final TextEditingController controller;
  final String searchQuery;
  final List<Map<String, dynamic>> results;
  final List<Map<String, dynamic>> allMessages;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onResultTap;
  final VoidCallback onClose;
  final ThemeData theme;

  const _SearchPanel({
    required this.controller,
    required this.searchQuery,
    required this.results,
    required this.allMessages,
    required this.onChanged,
    required this.onResultTap,
    required this.onClose,
    required this.theme,
  });

  String _formatDate(String? createdAt) {
    if (createdAt == null) return '';
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(40),
            blurRadius: 12,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: onClose,
                    child: Icon(
                      Icons.close_rounded,
                      color: theme.colorScheme.onSurface,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Pesquisar mensagens',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            // Search field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppTheme.primary.withAlpha(120),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 12),
                      child: Icon(Icons.search_rounded, size: 18),
                    ),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        onChanged: onChanged,
                        style: theme.textTheme.bodyMedium,
                        decoration: InputDecoration(
                          hintText: 'Pesquisar...',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    if (searchQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          controller.clear();
                          onChanged('');
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            // Results
            Expanded(
              child: searchQuery.isEmpty
                  ? Center(
                      child: Text(
                        'Digite para pesquisar',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : results.isEmpty
                  ? Center(
                      child: Text(
                        'Nenhuma mensagem encontrada',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: results.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        indent: 16,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      itemBuilder: (_, i) {
                        final msg = results[i];
                        final msgId = msg['id']?.toString() ?? '';
                        final text = msg['content'] as String? ?? '';
                        final date = _formatDate(msg['created_at']?.toString());
                        final query = searchQuery.toLowerCase();
                        final lowerText = text.toLowerCase();
                        final matchIdx = lowerText.indexOf(query);

                        return InkWell(
                          onTap: () => onResultTap(msgId),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  date,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                matchIdx >= 0
                                    ? RichText(
                                        text: TextSpan(
                                          style: theme.textTheme.bodyMedium,
                                          children: [
                                            if (matchIdx > 0)
                                              TextSpan(
                                                text: text.substring(
                                                  0,
                                                  matchIdx,
                                                ),
                                              ),
                                            TextSpan(
                                              text: text.substring(
                                                matchIdx,
                                                matchIdx + query.length,
                                              ),
                                              style: TextStyle(
                                                color: AppTheme.primary,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            if (matchIdx + query.length <
                                                text.length)
                                              TextSpan(
                                                text: text.substring(
                                                  matchIdx + query.length,
                                                ),
                                              ),
                                          ],
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : Text(
                                        text,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium,
                                      ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Typing indicator widget ───────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({super.key});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Digitando',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppTheme.success,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(width: 3),
        ...List.generate(3, (i) {
          final start = i / 3;
          final end = (i + 1) / 3;
          final anim = CurvedAnimation(
            parent: _ctrl,
            curve: Interval(start, end, curve: Curves.easeInOut),
          );
          return AnimatedBuilder(
            animation: anim,
            builder: (_, __) => Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: AppTheme.success.withAlpha(
                  (100 + (anim.value * 155)).toInt(),
                ),
                shape: BoxShape.circle,
              ),
              transform: Matrix4.translationValues(0, -2 * anim.value, 0),
            ),
          );
        }),
      ],
    );
  }
}
