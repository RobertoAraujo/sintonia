import 'dart:io' if (dart.library.io) 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/avatar_notifier.dart';
import '../../../services/pet_avatar_notifier.dart';
import '../../../services/pet_service.dart';
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
  final TextEditingController _petSpeciesBreedController =
      TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  bool _isUploadingPet = false;

  String _currentAvatarUrl = '';
  String _currentPetPhotoUrl = '';
  String _petId = '';

  // Role dropdown — maps display label → DB enum value
  static const Map<String, String> _roleOptions = {
    'Pet': 'pet',
    'Suporte Emocional': 'suporte_emocional',
    'Cão de Assistência': 'cao_assistencia',
    'Animal de Terapia': 'animal_terapia',
  };
  String _selectedRoleKey = 'Pet'; // display label

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
    _petSpeciesBreedController.dispose();
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
          // Combine species + breed into one field
          final species = (pet['species'] as String?) ?? '';
          final breed = (pet['breed'] as String?) ?? '';
          _petSpeciesBreedController.text = breed.isNotEmpty
              ? '$species - $breed'
              : species;
          // Map DB enum value back to display label
          final dbRole = (pet['role'] as String?) ?? 'pet';
          _selectedRoleKey = _roleOptions.entries
              .firstWhere(
                (e) => e.value == dbRole,
                orElse: () => _roleOptions.entries.first,
              )
              .key;
          _currentPetPhotoUrl = pet['photo_url'] ?? '';
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _pickUserImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (image == null) {
      // Force a rebuild to recover from black screen after picker dismissal
      if (mounted) setState(() {});
      return;
    }
    if (!mounted) return;
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
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (image == null) {
      // Force a rebuild to recover from black screen after picker dismissal
      if (mounted) setState(() {});
      return;
    }
    if (!mounted) return;
    setState(() {
      _petImageFile = image;
      _isUploadingPet = true;
    });
    try {
      final bytes = await image.readAsBytes();
      final ext = image.name.split('.').last.toLowerCase();
      final safeExt = ['jpg', 'jpeg', 'png', 'webp'].contains(ext)
          ? ext
          : 'jpg';

      String? url;

      if (_petId.isNotEmpty) {
        // Use PetService which uploads to 'pets' bucket and syncs DB
        url = await PetService.instance.uploadAndSyncPetPhoto(
          petId: _petId,
          imageBytes: bytes,
          fileExtension: safeExt,
        );
      } else {
        // No pet yet — upload to pets bucket without DB sync (will be saved on _save)
        url = await _uploadPetPhotoToBucket(bytes, safeExt);
      }

      if (url != null && mounted) {
        setState(() {
          _currentPetPhotoUrl = url!;
          _isUploadingPet = false;
        });
        PetAvatarNotifier.instance.updatePetAvatar(url);
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

  /// Uploads pet photo to the 'pets' bucket without updating DB (used when pet doesn't exist yet).
  Future<String?> _uploadPetPhotoToBucket(
    List<int> imageBytes,
    String fileExtension,
  ) async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return null;
    try {
      final safeExt = ['jpg', 'jpeg', 'png', 'webp'].contains(fileExtension)
          ? fileExtension
          : 'jpg';
      final storagePath =
          '$uid/pet_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
      final mimeType = (safeExt == 'jpg' || safeExt == 'jpeg')
          ? 'image/jpeg'
          : 'image/$safeExt';
      await SupabaseService.instance.client.storage
          .from('pets')
          .uploadBinary(
            storagePath,
            Uint8List.fromList(imageBytes),
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          );
      final baseUrl = SupabaseService.instance.client.storage
          .from('pets')
          .getPublicUrl(storagePath);
      return '$baseUrl?v=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      debugPrint('_uploadPetPhotoToBucket error: $e');
      return null;
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

    // 1. Save user profile name
    final profileSuccess = await SupabaseService.instance.updateUserProfile({
      'full_name': name,
    });

    // 2. Parse species / breed from combined field
    final speciesBreedText = _petSpeciesBreedController.text.trim();
    final parts = speciesBreedText.split(' - ');
    final species = parts.isNotEmpty ? parts.first.trim() : '';
    final breed = parts.length > 1 ? parts.sublist(1).join(' - ').trim() : '';

    // 3. Map selected role label to DB enum value
    final roleDbValue = _roleOptions[_selectedRoleKey] ?? 'pet';

    final petName = _petNameController.text.trim();

    if (_petId.isNotEmpty) {
      // Update existing pet
      await SupabaseService.instance.updatePet(_petId, {
        'name': petName,
        'species': species,
        'breed': breed,
        'role': roleDbValue,
        if (_currentPetPhotoUrl.isNotEmpty) 'photo_url': _currentPetPhotoUrl,
        'photo_semantic': 'Foto do pet $petName',
      });
    } else if (petName.isNotEmpty) {
      // Create new pet if name was provided
      final newPet = await SupabaseService.instance.createPet(
        name: petName,
        species: species.isNotEmpty ? species : 'Não informado',
        breed: breed,
        role: roleDbValue,
        photoUrl: _currentPetPhotoUrl,
        photoSemantic: 'Foto do pet $petName',
      );
      if (newPet != null) {
        final newPetId = newPet['id'] as String?;
        if (newPetId != null) {
          _petId = newPetId;
          // Set as active pet
          await SupabaseService.instance.setActivePet(newPetId);
        }
      }
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
    if (_petImageFile == null && _currentPetPhotoUrl.isEmpty) return;
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
                          '${_petSpeciesBreedController.text} • $_selectedRoleKey',
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
                            controller: _petSpeciesBreedController,
                            label: "Espécie / Raça",
                            icon: Icons.category_outlined,
                          ),
                          const SizedBox(height: 10),
                          // Role dropdown
                          DropdownButtonFormField<String>(
                            initialValue: _selectedRoleKey,
                            decoration: InputDecoration(
                              labelText: 'Função',
                              prefixIcon: const Icon(
                                Icons.favorite_outline_rounded,
                              ),
                              filled: true,
                              fillColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: AppTheme.primary,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            items: _roleOptions.keys
                                .map(
                                  (label) => DropdownMenuItem(
                                    value: label,
                                    child: Text(label),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedRoleKey = val);
                              }
                            },
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
