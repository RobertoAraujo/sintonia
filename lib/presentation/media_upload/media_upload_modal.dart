import 'dart:io' if (dart.library.io) 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/media_processing_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';

/// A bottom-sheet modal that lets the user pick an image and either
/// update their profile picture or create a new feed post.
class MediaUploadModal extends StatefulWidget {
  final MediaActionType initialAction;
  final Map<String, dynamic> currentUser;

  /// Called when a profile picture update succeeds — passes the new image URL.
  final void Function(String newAvatarUrl)? onProfilePictureUpdated;

  /// Called when a feed post is created — passes the new post map.
  final void Function(Map<String, dynamic> newPost)? onFeedPostCreated;

  const MediaUploadModal({
    super.key,
    required this.initialAction,
    required this.currentUser,
    this.onProfilePictureUpdated,
    this.onFeedPostCreated,
  });

  @override
  State<MediaUploadModal> createState() => _MediaUploadModalState();
}

class _MediaUploadModalState extends State<MediaUploadModal> {
  late MediaActionType _selectedAction;
  XFile? _pickedFile;
  final TextEditingController _captionCtrl = TextEditingController();
  final TextEditingController _tagsCtrl = TextEditingController();
  bool _isProcessing = false;
  String? _previewUrl;

  final _picker = ImagePicker();
  final _service = MediaProcessingService();

  // Predefined sensitivity tag options.
  static const List<String> _sensitivityOptions = [
    'Luzes Fortes',
    'Contraste Alto',
    'Conteúdo Intenso',
    'Padrão Visual',
    'Cores Vibrantes',
  ];
  final Set<String> _selectedSensitivityTags = {};

  @override
  void initState() {
    super.initState();
    _selectedAction = widget.initialAction;
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    // ── Contextual permission request (only when user triggers the action) ──
    if (!kIsWeb) {
      Permission permission;
      if (source == ImageSource.camera) {
        permission = Permission.camera;
      } else {
        permission = Permission.photos;
      }
      final status = await permission.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                source == ImageSource.camera
                    ? 'Permissão de câmera negada. Ative nas configurações do dispositivo.'
                    : 'Permissão de galeria negada. Ative nas configurações do dispositivo.',
              ),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Configurações',
                textColor: Colors.white,
                onPressed: () => openAppSettings(),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        return;
      }
    }
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1920,
      );
      if (file != null) {
        // Validate file size (max 5 MB)
        final bytes = await file.readAsBytes();
        if (bytes.length > 5 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Imagem muito grande. Máximo 5 MB.'),
                backgroundColor: Colors.red.shade400,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          }
          return;
        }
        setState(() {
          _pickedFile = file;
          _previewUrl = file.path;
        });
        // Auto-submit immediately when updating profile picture
        if (_selectedAction == MediaActionType.updateProfilePicture) {
          await _submit();
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Não foi possível acessar a galeria.'),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (_pickedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Por favor, selecione uma imagem primeiro. 📸'),
          backgroundColor: AppTheme.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    if (_selectedAction == MediaActionType.createFeedPost &&
        _captionCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Adicione uma legenda para a publicação. ✍️'),
          backgroundColor: AppTheme.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    if (_selectedAction == MediaActionType.updateProfilePicture) {
      // Upload directly to Supabase Storage
      try {
        final bytes = await _pickedFile!.readAsBytes();
        final ext = _pickedFile!.name.split('.').last.toLowerCase();
        final safeExt = ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext)
            ? ext
            : 'jpg';
        final publicUrl = await SupabaseService.instance.uploadProfileAvatar(
          bytes,
          safeExt,
        );

        if (!mounted) return;
        setState(() => _isProcessing = false);

        if (publicUrl != null) {
          Navigator.of(context).pop();
          widget.onProfilePictureUpdated?.call(publicUrl);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Foto de perfil atualizada com sucesso! ✨',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              backgroundColor: AppTheme.primary,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Não foi possível atualizar a foto. Tente novamente.',
              ),
              backgroundColor: Colors.red.shade400,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Erro ao enviar foto. Tente novamente.'),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
      return;
    }

    // Feed post path — upload image to Supabase Storage, then save post to DB
    setState(() => _isProcessing = true);

    try {
      // 1. Upload image to Supabase Storage
      final bytes = await _pickedFile!.readAsBytes();
      final ext = _pickedFile!.name.split('.').last.toLowerCase();
      final safeExt = ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext)
          ? ext
          : 'jpg';

      String? uploadedImageUrl;
      if (bytes.isNotEmpty) {
        uploadedImageUrl = await SupabaseService.instance.uploadPostImage(
          bytes,
          safeExt,
        );
      }

      // 2. Extract tags
      final captionTags = _extractHashtags(_captionCtrl.text);
      final allTags = {...captionTags, ..._selectedSensitivityTags}.toList();

      // 3. Detect sensory content for semantic label
      final hasSensory = _service.detectSensoryContent(
        _captionCtrl.text.trim(),
        _selectedSensitivityTags.toList(),
      );
      final imageSemantic = uploadedImageUrl != null
          ? (hasSensory
                ? '⚠️ Conteúdo sensorial — ${_captionCtrl.text.trim()}'
                : 'Imagem publicada pelo usuário: ${_captionCtrl.text.trim()}')
          : '';

      // 4. Save post to Supabase DB
      final savedPost = await SupabaseService.instance.createPost(
        content: _captionCtrl.text.trim(),
        imageUrl: uploadedImageUrl,
        imageSemantic: imageSemantic,
        hyperfocusTags: allTags,
      );

      if (!mounted) return;
      setState(() => _isProcessing = false);

      if (savedPost != null) {
        // Sync to user_photos gallery if image was uploaded
        if (uploadedImageUrl != null && uploadedImageUrl.isNotEmpty) {
          await SupabaseService.instance.syncPostToUserPhotos(
            postId: savedPost['id'] as String,
            photoUrl: uploadedImageUrl,
            caption: _captionCtrl.text.trim(),
          );
        }

        Navigator.of(context).pop();

        // Build the post map for immediate UI update
        final currentUser = widget.currentUser;
        final postMap = {
          'id': savedPost['id'] ?? '',
          'authorId': currentUser['id'] ?? '',
          'authorName': currentUser['name'] ?? 'Usuário',
          'authorImage': currentUser['avatarUrl'] ?? '',
          'authorImageSemantic':
              currentUser['avatarSemantic'] ?? 'Avatar do usuário',
          'neurodivType': currentUser['neurodivType'] ?? '',
          'hyperfocusTags': allTags,
          'content': _captionCtrl.text.trim(),
          'imageUrl': uploadedImageUrl,
          'imageSemantic': imageSemantic,
          'likes': 0,
          'comments': 0,
          'saves': 0,
          'timeAgo': 'agora',
          'isLiked': false,
          'isSaved': false,
          'sensoryWarning': hasSensory,
          // For profile grid
          'semanticLabel': imageSemantic,
          'hasImage': uploadedImageUrl != null && uploadedImageUrl.isNotEmpty,
        };
        widget.onFeedPostCreated?.call(postMap);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hasSensory
                        ? 'Publicação compartilhada! ⚠️ Aviso sensorial adicionado.'
                        : 'Sua publicação foi compartilhada no Feed e no seu Perfil! 🎉',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.primary,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Não foi possível publicar. Tente novamente.'),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Erro ao publicar. Tente novamente.'),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  List<String> _extractHashtags(String text) {
    final regex = RegExp(r'#(\w+)');
    return regex
        .allMatches(text)
        .map((m) => m.group(1) ?? '')
        .where((t) => t.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isPost = _selectedAction == MediaActionType.createFeedPost;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
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
                          color: theme.colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Header
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppTheme.primary, AppTheme.secondary],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.add_photo_alternate_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Adicionar Mídia',
                                style: theme.textTheme.titleLarge,
                              ),
                              Text(
                                'Foto de perfil ou publicação no feed',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Action toggle
                    Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          _ActionToggleButton(
                            label: 'Foto de Perfil',
                            icon: Icons.account_circle_rounded,
                            isSelected:
                                _selectedAction ==
                                MediaActionType.updateProfilePicture,
                            onTap: () => setState(
                              () => _selectedAction =
                                  MediaActionType.updateProfilePicture,
                            ),
                          ),
                          _ActionToggleButton(
                            label: 'Publicação',
                            icon: Icons.photo_library_rounded,
                            isSelected:
                                _selectedAction ==
                                MediaActionType.createFeedPost,
                            onTap: () => setState(
                              () => _selectedAction =
                                  MediaActionType.createFeedPost,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Image picker area
                    GestureDetector(
                      onTap: () => _showPickerOptions(),
                      child: Container(
                        height: 180,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: _pickedFile != null
                                ? AppTheme.primary.withAlpha(120)
                                : theme.colorScheme.outlineVariant,
                            width: 1.5,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _pickedFile == null
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_photo_alternate_outlined,
                                    size: 40,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Toque para selecionar uma foto',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Galeria ou câmera',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant
                                          .withAlpha(160),
                                    ),
                                  ),
                                ],
                              )
                            : Stack(
                                fit: StackFit.expand,
                                children: [
                                  kIsWeb
                                      ? Image.network(
                                          _previewUrl!,
                                          fit: BoxFit.cover,
                                        )
                                      : Image.file(
                                          File(_previewUrl!),
                                          fit: BoxFit.cover,
                                        ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: GestureDetector(
                                      onTap: () => setState(() {
                                        _pickedFile = null;
                                        _previewUrl = null;
                                      }),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.close_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 8,
                                    right: 8,
                                    child: GestureDetector(
                                      onTap: _showPickerOptions,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.edit_rounded,
                                              color: Colors.white,
                                              size: 14,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              'Trocar',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
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
                    const SizedBox(height: 16),

                    // Gallery upload button (only for feed posts)
                    if (isPost)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isProcessing
                              ? null
                              : () => _pickImage(ImageSource.gallery),
                          icon: const Icon(
                            Icons.photo_library_rounded,
                            size: 20,
                          ),
                          label: const Text(
                            'Subir Fotos da Galeria',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            side: BorderSide(
                              color: AppTheme.primary.withAlpha(180),
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),

                    if (isPost) const SizedBox(height: 16),

                    // Caption (only for feed posts)
                    if (isPost) ...[
                      TextField(
                        controller: _captionCtrl,
                        maxLines: 3,
                        maxLength: 500,
                        decoration: InputDecoration(
                          hintText:
                              'Escreva uma legenda... use #hashtags para hiperfocos ✨',
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(14),
                          counterStyle: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Sensitivity tags
                      Text(
                        'Marcações de Sensibilidade (opcional)',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _sensitivityOptions.map((tag) {
                          final selected = _selectedSensitivityTags.contains(
                            tag,
                          );
                          return FilterChip(
                            label: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 12,
                                color: selected
                                    ? Colors.white
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                            selected: selected,
                            onSelected: (val) {
                              setState(() {
                                if (val) {
                                  _selectedSensitivityTags.add(tag);
                                } else {
                                  _selectedSensitivityTags.remove(tag);
                                }
                              });
                            },
                            selectedColor: AppTheme.primary,
                            checkmarkColor: Colors.white,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                            side: BorderSide(
                              color: selected
                                  ? AppTheme.primary
                                  : theme.colorScheme.outlineVariant,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // Sensory warning preview
                      if (_selectedSensitivityTags.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withAlpha(20),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.orange.withAlpha(80),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Um aviso de filtro sensorial será adicionado automaticamente ao seu post.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.orange.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // Sticky submit button — always visible at the bottom
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isProcessing ? null : _submit,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          isPost
                              ? Icons.send_rounded
                              : Icons.check_circle_rounded,
                          size: 20,
                        ),
                  label: Text(
                    _isProcessing
                        ? 'Processando...'
                        : isPost
                        ? 'Publicar no Feed'
                        : 'Atualizar Foto de Perfil',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    disabledBackgroundColor: AppTheme.primary.withAlpha(100),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPickerOptions() {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Selecionar Imagem',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.photo_library_rounded,
                    color: AppTheme.primary,
                  ),
                ),
                title: const Text('Galeria de Fotos'),
                subtitle: const Text('Escolha uma foto existente'),
                onTap: () {
                  Navigator.pop(dialogContext);
                  _pickImage(ImageSource.gallery);
                },
              ),
              if (!kIsWeb)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.secondary.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: AppTheme.secondary,
                    ),
                  ),
                  title: const Text('Câmera'),
                  subtitle: const Text('Tire uma nova foto'),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _pickImage(ImageSource.camera);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Helper widget ────────────────────────────────────────────────────────────

class _ActionToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ActionToggleButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? Colors.white
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
