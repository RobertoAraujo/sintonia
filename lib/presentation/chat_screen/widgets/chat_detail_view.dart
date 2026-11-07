import 'dart:async';
import 'dart:io' if (dart.library.io) 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../core/app_export.dart';
import '../../../services/offline_message_queue.dart';
import '../../../services/supabase_service.dart';
import '../../../widgets/app_scaffold.dart';
import '../../user_profile_screen/user_profile_screen.dart';

class ChatDetailView extends StatefulWidget {
  final Map<String, dynamic> conversation;
  final VoidCallback onBack;
  final VoidCallback? onAvatarTap;

  const ChatDetailView({
    super.key,
    required this.conversation,
    required this.onBack,
    this.onAvatarTap,
  });

  @override
  State<ChatDetailView> createState() => _ChatDetailViewState();
}

class _ChatDetailViewState extends State<ChatDetailView> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _menuButtonKey = GlobalKey();
  bool _isTyping = false;
  bool _isLoading = true;
  bool _isSending = false;
  bool _isOffline = false;
  bool _isFriend = true;
  bool _isCheckingFriendship = false;

  // Recipient profile data (may be enriched after fetch)
  String _recipientName = '';
  String _recipientAvatar = '';
  String? _recipientPetPhotoUrl;
  bool _isLoadingRecipient = false;

  // Input bar extras
  bool _showEmojiPicker = false;
  bool _isRecording = false;
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUploadingMedia = false;
  AudioRecorder? _audioRecorder;
  String? _recordingPath;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;

  final List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _realtimeChannel;

  // Search state
  bool _showSearch = false;
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];

  String get _conversationId => widget.conversation['id'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _recipientName = widget.conversation['name'] as String? ?? 'Conversa';
    _recipientAvatar = widget.conversation['imageUrl'] as String? ?? '';
    _loadMessages();
    _subscribeToMessages();
    _loadPendingOfflineMessages();
    _checkFriendship();
    // Always fetch the recipient profile to ensure avatar_url and name are
    // up-to-date. This fixes the missing avatar bug.
    _fetchRecipientProfile();
    // Hide bottom nav bar while inside chat detail view
    chatKeyboardVisibleNotifier.value = true;
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _audioRecorder?.dispose();
    _recordingTimer?.cancel();
    _searchCtrl.dispose();
    // Restore bottom nav bar when leaving chat detail view
    chatKeyboardVisibleNotifier.value = false;
    super.dispose();
  }

  /// Fetch the recipient's full profile from Supabase if name is generic/missing.
  Future<void> _fetchRecipientProfile() async {
    final otherUserId = widget.conversation['userId'] as String?;
    if (otherUserId == null) return;
    setState(() => _isLoadingRecipient = true);
    try {
      final profile = await SupabaseService.instance.client
          .from('user_profiles')
          .select('id, full_name, username, avatar_url, active_pet_id')
          .eq('id', otherUserId)
          .maybeSingle();
      if (profile != null && mounted) {
        final name = (profile['full_name'] as String?)?.isNotEmpty == true
            ? profile['full_name'] as String
            : (profile['username'] as String? ?? 'Usuário');
        final avatarUrl = profile['avatar_url'] as String? ?? '';
        debugPrint(
          'DEBUG CHAT_DETAIL -> Usuário: $name | AvatarURL: $avatarUrl',
        );
        setState(() {
          _recipientName = name;
          _recipientAvatar = avatarUrl;
          _isLoadingRecipient = false;
        });
        // Fetch pet badge
        final activePetId = profile['active_pet_id'] as String?;
        if (activePetId != null) {
          _fetchPetPhoto(activePetId);
        }
      } else {
        if (mounted) setState(() => _isLoadingRecipient = false);
      }
    } catch (e) {
      debugPrint('_fetchRecipientProfile error: $e');
      if (mounted) setState(() => _isLoadingRecipient = false);
    }
  }

  /// Fetch pet photo for badge when profile name is already known.
  Future<void> _fetchRecipientPet() async {
    final otherUserId = widget.conversation['userId'] as String?;
    if (otherUserId == null) return;
    try {
      final profile = await SupabaseService.instance.client
          .from('user_profiles')
          .select('active_pet_id')
          .eq('id', otherUserId)
          .maybeSingle();
      if (profile != null) {
        final activePetId = profile['active_pet_id'] as String?;
        if (activePetId != null) {
          _fetchPetPhoto(activePetId);
        }
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
    final otherUserId = widget.conversation['userId'] as String?;
    if (otherUserId == null) {
      widget.onAvatarTap?.call();
      return;
    }
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => UserProfileScreen(
          userData: {
            'id': otherUserId,
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

  /// Check if the other user in this conversation is a friend.
  Future<void> _checkFriendship() async {
    final otherUserId = widget.conversation['userId'] as String?;
    final myId = SupabaseService.instance.currentUserId;
    // Groups or self-chats are always allowed
    if (otherUserId == null ||
        otherUserId == myId ||
        widget.conversation['isGroup'] == true) {
      return;
    }
    setState(() => _isCheckingFriendship = true);
    try {
      final friends = await SupabaseService.instance.areFriends(otherUserId);
      if (mounted) {
        setState(() {
          _isFriend = friends;
          _isCheckingFriendship = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isCheckingFriendship = false);
    }
  }

  /// Load any messages that were queued while offline and show them in the UI.
  Future<void> _loadPendingOfflineMessages() async {
    if (_conversationId.isEmpty) return;
    final pending = await OfflineMessageQueue.instance
        .getPendingForConversation(_conversationId);
    if (!mounted || pending.isEmpty) return;
    final uid = SupabaseService.instance.currentUserId;
    final now = DateTime.now();
    setState(() {
      for (final msg in pending) {
        // Avoid duplicates if already shown
        if (_messages.any((m) => m['id'] == msg.localId)) continue;
        _messages.add({
          'id': msg.localId,
          'isMe': true,
          'text': msg.content,
          'time':
              '${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}',
          'status': 'pending',
        });
      }
    });
    if (pending.isNotEmpty) _scrollToBottom();
  }

  Future<void> _loadMessages() async {
    if (_conversationId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final rows = await SupabaseService.instance.fetchMessages(
        _conversationId,
      );
      if (!mounted) return;
      final uid = SupabaseService.instance.currentUserId;
      final mapped = rows.map((row) => _mapRow(row, uid)).toList();
      setState(() {
        _messages
          ..clear()
          ..addAll(mapped);
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeToMessages() {
    if (_conversationId.isEmpty) return;
    final uid = SupabaseService.instance.currentUserId;

    _realtimeChannel = SupabaseService.instance.client
        .channel('messages:$_conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: _conversationId,
          ),
          callback: (payload) async {
            final newRecord = payload.newRecord;
            if (newRecord.isEmpty) return;

            final senderId = newRecord['sender_id'] as String?;

            if (senderId == uid) {
              // This is our own message arriving via realtime — it was synced
              // from the offline queue by ConnectivitySyncService.
              // Replace any matching 'pending' message in the list, or add if new.
              final content = newRecord['content'] as String?;
              if (!mounted) return;
              setState(() {
                // Find a pending message with the same content to replace
                final idx = _messages.lastIndexWhere(
                  (m) => m['status'] == 'pending' && m['text'] == content,
                );
                if (idx != -1) {
                  final uid2 = SupabaseService.instance.currentUserId;
                  final realMsg = _mapRow(newRecord, uid2);
                  realMsg['status'] = 'read';
                  _messages[idx] = realMsg;
                }
                // If not found as pending, it was already handled optimistically — skip
              });
              return;
            }

            // Incoming message from another user
            Map<String, dynamic>? senderProfile;
            try {
              senderProfile = await SupabaseService.instance.fetchUserProfile(
                senderId ?? '',
              );
            } catch (_) {}

            final enriched = Map<String, dynamic>.from(newRecord);
            if (senderProfile != null) enriched['sender'] = senderProfile;

            if (!mounted) return;
            setState(() => _messages.add(_mapRow(enriched, uid)));
            _scrollToBottom();
          },
        )
        .subscribe();
  }

  Map<String, dynamic> _mapRow(Map<String, dynamic> row, String? uid) {
    final sender = row['sender'] as Map<String, dynamic>?;
    final senderId = row['sender_id'] as String? ?? sender?['id'] as String?;
    final isMe = senderId == uid;
    final createdAt = row['created_at'];
    String time = '';
    if (createdAt != null) {
      try {
        final dt = DateTime.parse(createdAt.toString()).toLocal();
        time =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }
    return {
      'id': row['id'] ?? '',
      'isMe': isMe,
      'text': row['content'] ?? '',
      'time': time,
      'status': 'read',
      'messageType': row['message_type'] ?? 'text',
      'mediaUrl': row['media_url'] ?? '',
    };
  }

  Future<void> _sendMessage() async {
    if (!_isFriend) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Você só pode enviar mensagens para amigos. Envie uma solicitação de amizade primeiro! 💜',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _isSending) return;

    final now = DateTime.now();
    final optimisticId = 'optimistic_${now.millisecondsSinceEpoch}';
    final optimisticMsg = {
      'id': optimisticId,
      'isMe': true,
      'text': text,
      'time':
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      'status': 'sent',
    };

    setState(() {
      _messages.add(optimisticMsg);
      _inputCtrl.clear();
      _isTyping = false;
      _isSending = true;
    });
    _scrollToBottom();

    // Check connectivity before attempting to send
    final connectivityResults = await Connectivity().checkConnectivity();
    final hasConnection = connectivityResults.any(
      (r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet,
    );

    if (!hasConnection) {
      // Queue for later and mark message as pending
      final pending = PendingMessage(
        localId: optimisticId,
        conversationId: _conversationId,
        content: text,
        messageType: 'text',
        createdAt: now,
      );
      await OfflineMessageQueue.instance.enqueue(pending);
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m['id'] == optimisticId);
          if (idx != -1) _messages[idx]['status'] = 'pending';
          _isSending = false;
          _isOffline = true;
        });
      }
      return;
    }

    try {
      final result = await SupabaseService.instance.sendMessage(
        conversationId: _conversationId,
        content: text,
      );
      if (!mounted) return;
      if (result != null) {
        // Replace optimistic message with real one
        final uid = SupabaseService.instance.currentUserId;
        final realMsg = _mapRow(result, uid);
        realMsg['status'] = 'read';
        setState(() {
          final idx = _messages.indexWhere((m) => m['id'] == optimisticId);
          if (idx != -1) _messages[idx] = realMsg;
          _isOffline = false;
        });
      }
    } catch (_) {
      // Network error — queue the message for later
      final pending = PendingMessage(
        localId: optimisticId,
        conversationId: _conversationId,
        content: text,
        messageType: 'text',
        createdAt: now,
      );
      await OfflineMessageQueue.instance.enqueue(pending);
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m['id'] == optimisticId);
          if (idx != -1) _messages[idx]['status'] = 'pending';
          _isOffline = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Search ────────────────────────────────────────────────────────────────

  void _onSearchChanged(String query) {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    final q = query.toLowerCase();
    final results = _messages.where((m) {
      final text = (m['text'] as String? ?? '').toLowerCase();
      return text.contains(q);
    }).toList();
    setState(() => _searchResults = results);
  }

  void _scrollToMessageById(String messageId) {
    final idx = _messages.indexWhere((m) => m['id']?.toString() == messageId);
    if (idx == -1 || !_scrollCtrl.hasClients) return;

    const itemHeight = 60.0;
    final offset = (idx * itemHeight).clamp(
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isVideo
                        ? 'Chamada de vídeo iniciada...'
                        : 'Chamada de voz iniciada...',
                  ),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppTheme.primary,
                ),
              );
            },
            child: Text(isVideo ? 'Ligar Vídeo' : 'Ligar'),
          ),
        ],
      ),
    );
  }

  // ── Input bar ──────────────────────────────────────────────────────────────

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final theme = Theme.of(context);
        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AttachOption(
                icon: Icons.photo_library_rounded,
                label: 'Galeria',
                color: Colors.purple,
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              _AttachOption(
                icon: Icons.camera_alt_rounded,
                label: 'Câmera',
                color: Colors.blue,
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              _AttachOption(
                icon: Icons.videocam_rounded,
                label: 'Vídeo',
                color: Colors.red,
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo();
                },
              ),
              _AttachOption(
                icon: Icons.insert_drive_file_rounded,
                label: 'Arquivo',
                color: Colors.orange,
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _imagePicker.pickImage(
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
      final file = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      if (file == null || !mounted) return;

      setState(() => _isUploadingMedia = true);
      _showUploadingSnackbar('Enviando vídeo...');

      final bytes = await file.readAsBytes();
      final ext = file.name.split('.').last.toLowerCase();
      final contentType = _videoContentType(ext);
      final safeFileName =
          '${DateTime.now().millisecondsSinceEpoch}_video.$ext';

      final url = await _uploadToStorage(bytes, safeFileName, contentType);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (url != null) {
        await _sendMediaMessage(url, 'video', content: '🎥 Vídeo');
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
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Falha ao enviar vídeo.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }

  /// Returns the MIME content type for a given video file extension.
  String _videoContentType(String ext) {
    switch (ext) {
      case 'mp4':
        return 'video/mp4';
      case 'webm':
        return 'video/webm';
      case 'mov':
      case 'qt':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case '3gp':
        return 'video/3gpp';
      case 'mkv':
        return 'video/x-matroska';
      default:
        return 'video/mp4';
    }
  }

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

  // ── Media Upload ──────────────────────────────────────────────────────────

  Future<String?> _uploadToStorage(
    List<int> bytes,
    String fileName,
    String contentType,
  ) async {
    try {
      final path = 'chat/$_conversationId/$fileName';
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
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;
    try {
      await SupabaseService.instance.client.from('messages').insert({
        'conversation_id': _conversationId,
        'sender_id': uid,
        'content': content,
        'message_type': messageType,
        'media_url': mediaUrl,
        'is_read': false,
      });

      if (mounted) {
        final now = DateTime.now();
        final time =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        setState(() {
          _messages.add({
            'id': 'local_${now.millisecondsSinceEpoch}',
            'isMe': true,
            'text': content,
            'time': time,
            'status': 'read',
            'messageType': messageType,
            'mediaUrl': mediaUrl,
          });
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('_sendMediaMessage error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Falha ao enviar mídia.'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conv = widget.conversation;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final navBarOffset = safeBottom + 8.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 12, 4, 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: widget.onBack,
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 18,
                        ),
                      ),
                      GestureDetector(
                        onTap: _navigateToRecipientProfile,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundImage: _recipientAvatar.isNotEmpty
                                  ? NetworkImage(_recipientAvatar)
                                  : null,
                              child: _recipientAvatar.isEmpty
                                  ? const Icon(Icons.person_rounded, size: 20)
                                  : null,
                            ),
                            // Pet badge in bottom-right corner
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
                              )
                            else if (conv['isOnline'] == true)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 10,
                                  height: 10,
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
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: _navigateToRecipientProfile,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _isLoadingRecipient
                                  ? Container(
                                      width: 100,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.outlineVariant
                                            .withAlpha(80),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    )
                                  : Text(
                                      _recipientName,
                                      style: theme.textTheme.titleSmall,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              Text(
                                conv['isOnline'] == true
                                    ? 'Online agora'
                                    : 'Offline',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: conv['isOnline'] == true
                                      ? AppTheme.success
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // TODO: Habilitar quando o recurso de chamadas for lançado
                      // Search button
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
                          _showSearch
                              ? Icons.search_off_rounded
                              : Icons.search_rounded,
                          color: _showSearch
                              ? AppTheme.primary
                              : theme.colorScheme.onSurface,
                          size: 22,
                        ),
                        tooltip: 'Pesquisar mensagens',
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(),
                      ),
                      IconButton(
                        key: _menuButtonKey,
                        onPressed: () {
                          final RenderBox button =
                              _menuButtonKey.currentContext!.findRenderObject()
                                  as RenderBox;
                          final RenderBox overlay =
                              Navigator.of(
                                    context,
                                  ).overlay!.context.findRenderObject()
                                  as RenderBox;
                          final Offset buttonOffset = button.localToGlobal(
                            Offset.zero,
                            ancestor: overlay,
                          );
                          showMenu(
                            context: context,
                            position: RelativeRect.fromLTRB(
                              buttonOffset.dx - 160,
                              buttonOffset.dy + button.size.height,
                              buttonOffset.dx + button.size.width,
                              buttonOffset.dy + button.size.height + 150,
                            ),
                            items: [
                              PopupMenuItem(
                                onTap: () {},
                                child: Row(
                                  children: const [
                                    Icon(Icons.volume_off_outlined),
                                    SizedBox(width: 12),
                                    Text('Silenciar'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                onTap: () {},
                                child: Row(
                                  children: const [
                                    Icon(Icons.block_rounded),
                                    SizedBox(width: 12),
                                    Text('Bloquear'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                onTap: () {},
                                child: Row(
                                  children: const [
                                    Icon(Icons.flag_outlined),
                                    SizedBox(width: 12),
                                    Text('Denunciar'),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                        icon: const Icon(Icons.more_vert_rounded),
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),

                // Messages
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          children: [
                            // Offline banner
                            if (_isOffline)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                  horizontal: 12,
                                ),
                                color: Colors.orange.shade700,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(
                                      Icons.wifi_off_rounded,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Sem conexão — mensagens serão enviadas automaticamente',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            Expanded(
                              child: _messages.isEmpty
                                  ? Center(
                                      child: Text(
                                        'Nenhuma mensagem ainda.\nDiga olá! 👋',
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    )
                                  : ListView.builder(
                                      controller: _scrollCtrl,
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        12,
                                        16,
                                        12,
                                      ),
                                      itemCount: _messages.length,
                                      itemBuilder: (_, i) {
                                        final msg = _messages[i];
                                        final isMe =
                                            msg['isMe'] as bool? ?? false;
                                        return _MessageBubble(
                                          message: msg,
                                          isMe: isMe,
                                          theme: theme,
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                ),

                // Not-friends banner
                if (!_isFriend && !_isCheckingFriendship)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 16,
                    ),
                    color: AppTheme.primary.withAlpha(20),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_rounded,
                          size: 16,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Vocês precisam ser amigos para trocar mensagens.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Input — sits flush above the floating nav bar
                Container(
                  padding: EdgeInsets.only(
                    left: 12,
                    right: 12,
                    top: 8,
                    bottom: bottomInset > 0 ? bottomInset + 8 : navBarOffset,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(
                      top: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Recording indicator
                      if (_isRecording)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.mic_rounded,
                                color: Colors.red,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Gravando... ${_recordingDuration.inMinutes.toString().padLeft(2, '0')}:${(_recordingDuration.inSeconds % 60).toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: _cancelRecording,
                                child: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.red,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Emoji picker panel
                      if (_showEmojiPicker)
                        SizedBox(
                          height: 220,
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
                                      (sel.start < 0
                                          ? text.length
                                          : sel.start) +
                                      emoji.length,
                                ),
                              );
                              setState(() => _isTyping = newText.isNotEmpty);
                            },
                          ),
                        ),
                      Row(
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
                              setState(
                                () => _showEmojiPicker = !_showEmojiPicker,
                              );
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
                            onTap: _isUploadingMedia
                                ? () {}
                                : _showAttachmentOptions,
                          ),
                          // Text input
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                if (_showEmojiPicker) {
                                  setState(() => _showEmojiPicker = false);
                                }
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: _isTyping
                                        ? AppTheme.primary.withAlpha(100)
                                        : Colors.transparent,
                                    width: 1.5,
                                  ),
                                ),
                                child: TextField(
                                  controller: _inputCtrl,
                                  maxLines: 4,
                                  minLines: 1,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  onChanged: (v) =>
                                      setState(() => _isTyping = v.isNotEmpty),
                                  decoration: const InputDecoration(
                                    hintText: 'Mensagem...',
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Send / mic button
                          GestureDetector(
                            onTap: _isTyping ? _sendMessage : _toggleRecording,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: _isRecording
                                    ? Colors.red
                                    : AppTheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isTyping
                                    ? Icons.send_rounded
                                    : (_isRecording
                                          ? Icons.stop_rounded
                                          : Icons.mic_rounded),
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ── Search panel overlay ─────────────────────────────────────
            if (_showSearch)
              Positioned(
                top: 0,
                right: 0,
                width: MediaQuery.of(context).size.width * 0.85,
                bottom: 0,
                child: _ChatSearchPanel(
                  controller: _searchCtrl,
                  results: _searchResults,
                  onChanged: _onSearchChanged,
                  onResultTap: _scrollToMessageById,
                  onClose: () {
                    setState(() {
                      _showSearch = false;
                      _searchCtrl.clear();
                      _searchResults = [];
                    });
                  },
                  theme: theme,
                ),
              ),
          ],
        ),
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
        child: Icon(icon, color: color, size: 24),
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
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface,
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
    '😱',
    '😨',
    '😰',
    '😥',
    '😓',
    '🤯',
    '😤',
    '😠',
    '😡',
    '🤬',
    '💀',
    '☠️',
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
    '😻',
    '😼',
    '😽',
    '🙀',
    '😿',
    '😾',
    '🙈',
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
    '💕',
    '💞',
    '💓',
    '💗',
    '💖',
    '💘',
    '💝',
    '💟',
    '☮️',
    '✌️',
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
    '🖐️',
    '✋',
    '👋',
    '🤙',
    '💪',
    '🦾',
    '🙏',
    '🤲',
    '👐',
    '🫶',
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
    '🔥',
    '💥',
    '✨',
    '⭐',
    '🌟',
    '💫',
    '🌈',
    '☀️',
    '🌙',
    '⚡',
    '🐶',
    '🐱',
    '🐭',
    '🐹',
    '🐰',
    '🦊',
    '🐻',
    '🐼',
    '🐨',
    '🐯',
    '🍕',
    '🍔',
    '🍟',
    '🌮',
    '🌯',
    '🥗',
    '🍜',
    '🍣',
    '🍦',
    '🎂',
    '⚽',
    '🏀',
    '🏈',
    '⚾',
    '🎾',
    '🏐',
    '🏉',
    '🎱',
    '🏓',
    '🏸',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
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
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  final ThemeData theme;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final text = message['text'] as String? ?? '';
    final messageType = message['messageType'] as String? ?? 'text';
    final mediaUrl = message['mediaUrl'] as String? ?? '';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
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
              GestureDetector(
                onTap: () => _openImageOverlay(context, mediaUrl),
                child: ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMe ? 18 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 18),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 260,
                      maxHeight: 320,
                    ),
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
                          child: Icon(
                            Icons.broken_image_rounded,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // Video bubble
            if (messageType == 'video' && mediaUrl.isNotEmpty)
              GestureDetector(
                onTap: () => _openVideoOverlay(context, mediaUrl),
                child: ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMe ? 18 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 18),
                  ),
                  child: Container(
                    width: 220,
                    height: 140,
                    color: Colors.black87,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(
                          Icons.videocam_rounded,
                          color: Colors.white24,
                          size: 64,
                        ),
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(220),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.black87,
                            size: 36,
                          ),
                        ),
                        Positioned(
                          bottom: 8,
                          left: 10,
                          child: Text(
                            '🎥 Vídeo',
                            style: TextStyle(
                              color: Colors.white.withAlpha(200),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Audio bubble
            if (messageType == 'audio' && mediaUrl.isNotEmpty)
              _AudioBubbleDetail(
                mediaUrl: mediaUrl,
                isMe: isMe,
                theme: theme,
                label: text.isNotEmpty ? text : '🎤 Áudio',
              ),
            // Text bubble
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
                  color: isMe ? AppTheme.primary : theme.colorScheme.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMe ? 18 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 18),
                  ),
                  border: isMe
                      ? null
                      : Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isMe ? Colors.white : theme.colorScheme.onSurface,
                    height: 1.4,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message['time'] as String? ?? '',
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe
                        ? Colors.white70
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message['status'] == 'pending'
                        ? Icons.schedule_rounded
                        : message['status'] == 'read'
                        ? Icons.done_all_rounded
                        : Icons.done_rounded,
                    size: 14,
                    color: message['status'] == 'pending'
                        ? Colors.white54
                        : message['status'] == 'read'
                        ? Colors.lightBlueAccent
                        : Colors.white70,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Audio bubble for chat_detail_view ────────────────────────────────────────

class _AudioBubbleDetail extends StatefulWidget {
  final String mediaUrl;
  final bool isMe;
  final ThemeData theme;
  final String label;

  const _AudioBubbleDetail({
    required this.mediaUrl,
    required this.isMe,
    required this.theme,
    required this.label,
  });

  @override
  State<_AudioBubbleDetail> createState() => _AudioBubbleDetailState();
}

class _AudioBubbleDetailState extends State<_AudioBubbleDetail> {
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
      debugPrint('_AudioBubbleDetail play error: $e');
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

// ─── Full-screen Image Overlay ───────────────────────────────────────────────
void _openImageOverlay(BuildContext context, String imageUrl) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withAlpha(230),
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          // Dismiss on tap outside image
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(color: Colors.transparent),
          ),
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                semanticLabel: 'Imagem em tela cheia',
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                },
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(
                    Icons.broken_image_rounded,
                    color: Colors.white54,
                    size: 64,
                  ),
                ),
              ),
            ),
          ),
          // Close button
          Positioned(
            top: 40,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 24),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ─── Full-screen Video Overlay ────────────────────────────────────────────────
void _openVideoOverlay(BuildContext context, String videoUrl) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withAlpha(230),
    builder: (_) => _VideoOverlayDialog(videoUrl: videoUrl),
  );
}

class _VideoOverlayDialog extends StatefulWidget {
  final String videoUrl;
  const _VideoOverlayDialog({required this.videoUrl});

  @override
  State<_VideoOverlayDialog> createState() => _VideoOverlayDialogState();
}

class _VideoOverlayDialogState extends State<_VideoOverlayDialog> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize()
          .then((_) {
            if (mounted) {
              setState(() => _initialized = true);
              _controller.play();
            }
          })
          .catchError((_) {
            if (mounted) setState(() => _hasError = true);
          });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          // Dismiss on tap outside
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(color: Colors.transparent),
          ),
          Center(
            child: _hasError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.white54,
                        size: 64,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Não foi possível reproduzir o vídeo',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () async {
                          final uri = Uri.tryParse(widget.videoUrl);
                          if (uri != null && await canLaunchUrl(uri)) {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        },
                        child: const Text(
                          'Abrir externamente',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  )
                : !_initialized
                ? const CircularProgressIndicator(color: Colors.white)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      ),
                      const SizedBox(height: 8),
                      // Progress bar
                      ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: _controller,
                        builder: (_, value, __) {
                          final pos = value.position.inMilliseconds.toDouble();
                          final dur = value.duration.inMilliseconds.toDouble();
                          return Column(
                            children: [
                              Slider(
                                value: pos.clamp(0, dur > 0 ? dur : 1),
                                min: 0,
                                max: dur > 0 ? dur : 1,
                                activeColor: Colors.white,
                                inactiveColor: Colors.white30,
                                onChanged: (v) => _controller.seekTo(
                                  Duration(milliseconds: v.toInt()),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDur(value.position),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      _formatDur(value.duration),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      // Play/Pause button
                      ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: _controller,
                        builder: (_, value, __) => IconButton(
                          iconSize: 48,
                          icon: Icon(
                            value.isPlaying
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_filled_rounded,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            value.isPlaying
                                ? _controller.pause()
                                : _controller.play();
                          },
                        ),
                      ),
                    ],
                  ),
          ),
          // Close button
          Positioned(
            top: 40,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chat Search Panel ─────────────────────────────────────────────────────────

class _ChatSearchPanel extends StatelessWidget {
  final TextEditingController controller;
  final List<Map<String, dynamic>> results;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onResultTap;
  final VoidCallback onClose;
  final ThemeData theme;

  const _ChatSearchPanel({
    required this.controller,
    required this.results,
    required this.onChanged,
    required this.onResultTap,
    required this.onClose,
    required this.theme,
  });

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
                        decoration: const InputDecoration(
                          hintText: 'Pesquisar...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    if (controller.text.isNotEmpty)
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
              child: controller.text.isEmpty
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
                        final text = msg['text'] as String? ?? '';
                        final time = msg['time'] as String? ?? '';
                        final query = controller.text.toLowerCase();
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
                                if (time.isNotEmpty)
                                  Text(
                                    time,
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
