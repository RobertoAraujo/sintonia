import 'dart:io' if (dart.library.io) 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/avatar_notifier.dart';
import '../../../services/media_permission_service.dart';
import '../../../services/supabase_service.dart';
import '../../../theme/app_theme.dart';

class EditProfileAndFeedScreen extends StatefulWidget {
  const EditProfileAndFeedScreen({super.key});

  @override
  State<EditProfileAndFeedScreen> createState() =>
      _EditProfileAndFeedScreenState();
}

class _EditProfileAndFeedScreenState extends State<EditProfileAndFeedScreen> {
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _petNameController = TextEditingController();
  final TextEditingController _petBreedController = TextEditingController();
  final TextEditingController _petRoleController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  bool _isUploadingPet = false;

  String _currentAvatarUrl = '';
  String _currentPetPhotoUrl = '';
  String _petId = '';

  XFile? _userImageFile;
  XFile? _petImageFile;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _petNameController.dispose();
    _petBreedController.dispose();
    _petRoleController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final profile = await SupabaseService.instance.fetchCurrentUserProfile();
      if (profile != null && mounted) {
        _nameController.text = profile['full_name'] ?? '';
        _currentAvatarUrl = profile['avatar_url'] ?? '';
      }

      final uid = SupabaseService.instance.currentUserId;
      if (uid != null) {
        final pets = await SupabaseService.instance.fetchUserPets(uid);
        if (pets.isNotEmpty && mounted) {
          final pet = pets.first;
          _petId = pet['id'] ?? '';
          _petNameController.text = pet['name'] ?? '';
          _petBreedController.text =
              '${pet['species'] ?? ''}${(pet['breed'] as String?)?.isNotEmpty == true ? ' - ${pet['breed']}' : ''}';
          _petRoleController.text = pet['role'] ?? '';
          _currentPetPhotoUrl = pet['photo_url'] ?? '';
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _pickUserImage() async {
    if (!await MediaPermissionService.request(camera: false)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissão para acessar fotos negada.')),
        );
      }
      return;
    }
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (image == null || !mounted) return;
    setState(() {
      _userImageFile = image;
      _isUploadingAvatar = true;
    });
    try {
      final bytes = await image.readAsBytes();
      final ext = image.name.split('.').last.toLowerCase();
      final url = await SupabaseService.instance.uploadProfileAvatar(
        bytes,
        ext,
      );
      if (url != null && mounted) {
        setState(() {
          _currentAvatarUrl = url;
          _isUploadingAvatar = false;
        });
        AvatarNotifier.instance.updateAvatar(url);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Foto de perfil atualizada! ✨'),
              backgroundColor: AppTheme.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      } else {
        if (mounted) setState(() => _isUploadingAvatar = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _pickPetImage() async {
    if (!await MediaPermissionService.request(camera: false)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissão para acessar fotos negada.')),
        );
      }
      return;
    }
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (image == null || !mounted) return;
    setState(() {
      _petImageFile = image;
      _isUploadingPet = true;
    });
    try {
      final bytes = await image.readAsBytes();
      final ext = image.name.split('.').last.toLowerCase();
      final url = await SupabaseService.instance.uploadPetPhoto(bytes, ext);
      if (url != null && mounted) {
        setState(() {
          _currentPetPhotoUrl = url;
          _isUploadingPet = false;
        });
        // Persist pet photo url if pet exists
        if (_petId.isNotEmpty) {
          await SupabaseService.instance.updatePet(_petId, {
            'photo_url': url,
            'photo_semantic': 'Foto do pet ${_petNameController.text}',
          });
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Foto do pet atualizada! 🐾'),
              backgroundColor: AppTheme.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      } else {
        if (mounted) setState(() => _isUploadingPet = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isUploadingPet = false);
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
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
      return;
    }
    setState(() => _isSaving = true);
    final profileSuccess = await SupabaseService.instance.updateUserProfile({
      'full_name': name,
    });

    // Update pet data if pet exists
    if (_petId.isNotEmpty) {
      final breedParts = _petBreedController.text.trim().split(' - ');
      final species = breedParts.isNotEmpty ? breedParts.first.trim() : '';
      final breed = breedParts.length > 1
          ? breedParts.sublist(1).join(' - ').trim()
          : '';
      await SupabaseService.instance.updatePet(_petId, {
        'name': _petNameController.text.trim(),
        'species': species,
        'breed': breed,
        'role': _petRoleController.text.trim(),
      });
    }

    if (!mounted) return;
    setState(() => _isSaving = false);
    if (profileSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Perfil atualizado! ✨'),
          backgroundColor: AppTheme.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Erro ao salvar. Tente novamente.'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Widget _buildUserAvatar() {
    if (_isUploadingAvatar) {
      return const CircleAvatar(
        radius: 50,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_userImageFile != null) {
      if (kIsWeb) {
        return CircleAvatar(
          radius: 50,
          backgroundImage: NetworkImage(_userImageFile!.path),
        );
      } else {
        return CircleAvatar(
          radius: 50,
          backgroundImage: FileImage(File(_userImageFile!.path)),
        );
      }
    }
    if (_currentAvatarUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 50,
        backgroundImage: NetworkImage(_currentAvatarUrl),
      );
    }
    return const CircleAvatar(
      radius: 50,
      child: Icon(Icons.person_rounded, size: 44),
    );
  }

  Widget _buildPetImage() {
    if (_isUploadingPet) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_petImageFile != null) {
      if (kIsWeb) {
        return Image.network(_petImageFile!.path, fit: BoxFit.cover);
      } else {
        return Image.file(File(_petImageFile!.path), fit: BoxFit.cover);
      }
    }
    if (_currentPetPhotoUrl.isNotEmpty) {
      return Image.network(_currentPetPhotoUrl, fit: BoxFit.cover);
    }
    return const Center(
      child: Icon(Icons.pets_rounded, size: 48, color: Colors.grey),
    );
  }

  void _showPetImageZoom() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.black.withAlpha(235),
          insetPadding: const EdgeInsets.all(10),
          child: Stack(
            alignment: Alignment.center,
            children: [
              InteractiveViewer(
                child: _petImageFile != null
                    ? (kIsWeb
                          ? Image.network(
                              _petImageFile!.path,
                              fit: BoxFit.contain,
                            )
                          : Image.file(
                              File(_petImageFile!.path),
                              fit: BoxFit.contain,
                            ))
                    : (_currentPetPhotoUrl.isNotEmpty
                          ? Image.network(
                              _currentPetPhotoUrl,
                              fit: BoxFit.contain,
                            )
                          : const Icon(
                              Icons.pets_rounded,
                              size: 80,
                              color: Colors.white,
                            )),
              ),
              Positioned(
                top: 20,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              if (_petNameController.text.isNotEmpty)
                Positioned(
                  bottom: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(153),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _petNameController.text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "${_petBreedController.text} • ${_petRoleController.text}",
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        title: const Text(
          "Editar Perfil",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Salvar',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- SEÇÃO: FOTO E DADOS DO USUÁRIO ---
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                        width: 0.8,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Sua Foto de Perfil",
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(child: _buildUserAvatar()),
                          const SizedBox(height: 10),
                          Center(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _isUploadingAvatar
                                  ? null
                                  : _pickUserImage,
                              icon: const Icon(
                                Icons.photo_library_outlined,
                                size: 16,
                              ),
                              label: const Text("Alterar Foto de Perfil"),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _buildTextField(
                            theme,
                            controller: _nameController,
                            label: "Seu Nome",
                            icon: Icons.person_outline_rounded,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // --- SEÇÃO: DADOS E FOTO DO PET DE APOIO ---
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                        width: 0.8,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('🐾', style: TextStyle(fontSize: 18)),
                              const SizedBox(width: 6),
                              Text(
                                "Meu Pet de Apoio",
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: _showPetImageZoom,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                height: 180,
                                width: double.infinity,
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                child: _buildPetImage(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.zoom_in_rounded,
                                  size: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "Toque na foto para ampliar",
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _isUploadingPet ? null : _pickPetImage,
                              icon: const Icon(
                                Icons.photo_library_outlined,
                                size: 16,
                              ),
                              label: const Text("Alterar Foto do Pet"),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _buildTextField(
                            theme,
                            controller: _petNameController,
                            label: "Nome do Pet",
                            icon: Icons.pets_rounded,
                          ),
                          const SizedBox(height: 10),
                          _buildTextField(
                            theme,
                            controller: _petBreedController,
                            label: "Espécie / Raça",
                            icon: Icons.category_outlined,
                          ),
                          const SizedBox(height: 10),
                          _buildTextField(
                            theme,
                            controller: _petRoleController,
                            label: "Função (ex: Suporte Emocional)",
                            icon: Icons.favorite_outline_rounded,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTextField(
    ThemeData theme, {
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
      ),
    );
  }
}
