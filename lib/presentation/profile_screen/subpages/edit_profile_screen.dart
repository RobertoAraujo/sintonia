import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/app_export.dart';
import '../../../services/supabase_service.dart';
import '../../../theme/app_theme.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> profileData;
  final void Function(Map<String, dynamic>) onSave;

  const EditProfileScreen({
    super.key,
    required this.profileData,
    required this.onSave,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _bioCtrl;
  late TextEditingController _petNameCtrl;
  late TextEditingController _usernameCtrl;
  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  String? _localAvatarUrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
      text: widget.profileData['name'] as String? ?? '',
    );
    _bioCtrl = TextEditingController(
      text: widget.profileData['bio'] as String? ?? '',
    );
    _petNameCtrl = TextEditingController(
      text: widget.profileData['petName'] as String? ?? '',
    );
    _usernameCtrl = TextEditingController(
      text: widget.profileData['username'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _petNameCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadAvatar() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (picked == null) return;

      setState(() => _isUploadingAvatar = true);

      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final safeExt = ['jpg', 'jpeg', 'png', 'webp'].contains(ext)
          ? ext
          : 'jpg';

      final url = await SupabaseService.instance.uploadProfileAvatar(
        bytes,
        safeExt,
      );

      if (!mounted) return;
      if (url != null) {
        setState(() {
          _localAvatarUrl = url;
          _isUploadingAvatar = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Foto atualizada! ✨'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      } else {
        setState(() => _isUploadingAvatar = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Erro ao enviar foto. Tente novamente.'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Não foi possível acessar a galeria.'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    if (name.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Nome não pode estar vazio.'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
      return;
    }
    setState(() => _isSaving = true);
    final updates = <String, dynamic>{
      'full_name': name,
      'username': username.isNotEmpty
          ? username.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '')
          : null,
      'bio': _bioCtrl.text.trim(),
    };
    updates.removeWhere((_, v) => v == null);
    final success = await SupabaseService.instance.updateUserProfile(updates);
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (success) {
      widget.onSave({
        'name': name,
        'bio': _bioCtrl.text.trim(),
        'petName': _petNameCtrl.text.trim().isEmpty
            ? null
            : _petNameCtrl.text.trim(),
        'username': username,
        if (_localAvatarUrl != null) 'avatarUrl': _localAvatarUrl,
      });
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Perfil atualizado! ✨'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Erro ao salvar perfil. Tente novamente.'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentAvatarUrl =
        _localAvatarUrl ?? (widget.profileData['avatarUrl'] as String? ?? '');

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Editar Perfil'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Salvar',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            Center(
              child: Stack(
                children: [
                  _isUploadingAvatar
                      ? CircleAvatar(
                          radius: 52,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          child: const CircularProgressIndicator(),
                        )
                      : CircleAvatar(
                          radius: 52,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          backgroundImage: currentAvatarUrl.isNotEmpty
                              ? NetworkImage(currentAvatarUrl)
                              : null,
                          child: currentAvatarUrl.isEmpty
                              ? Icon(
                                  Icons.person_rounded,
                                  size: 48,
                                  color: theme.colorScheme.onSurfaceVariant,
                                )
                              : null,
                        ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: _isUploadingAvatar ? null : _pickAndUploadAvatar,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.surface,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _isUploadingAvatar ? null : _pickAndUploadAvatar,
                child: const Text(
                  'Alterar foto de perfil',
                  style: TextStyle(color: AppTheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 24),

            _SectionLabel('Informações Pessoais'),
            const SizedBox(height: 12),
            _buildField(
              theme,
              'Nome completo',
              _nameCtrl,
              Icons.person_outline_rounded,
            ),
            const SizedBox(height: 12),
            _buildField(
              theme,
              'Nome de usuário',
              _usernameCtrl,
              Icons.alternate_email_rounded,
            ),
            const SizedBox(height: 12),
            _buildField(
              theme,
              'Bio',
              _bioCtrl,
              Icons.info_outline_rounded,
              maxLines: 3,
            ),

            const SizedBox(height: 24),
            _SectionLabel('Meu Pet'),
            const SizedBox(height: 12),

            Row(
              children: [
                if (widget.profileData['petAvatarUrl'] != null)
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: NetworkImage(
                      widget.profileData['petAvatarUrl'] as String,
                    ),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildField(
                    theme,
                    'Nome do pet',
                    _petNameCtrl,
                    Icons.pets_rounded,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            _SectionLabel('Neurodivergência'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  [
                    'TEA',
                    'TDAH',
                    'Dislexia',
                    'Tourette',
                    'Outra',
                    'Prefiro não informar',
                  ].map((type) {
                    final isSelected =
                        widget.profileData['neurodivType'] == type;
                    return FilterChip(
                      label: Text(type),
                      selected: isSelected,
                      onSelected: (_) {},
                      selectedColor: AppTheme.primaryContainer,
                      checkmarkColor: AppTheme.primary,
                    );
                  }).toList(),
            ),

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Salvar Alterações'),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
    ThemeData theme,
    String label,
    TextEditingController ctrl,
    IconData icon, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
