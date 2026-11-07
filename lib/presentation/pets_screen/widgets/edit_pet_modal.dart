import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/pet_avatar_notifier.dart';
import '../../../services/pet_service.dart';
import '../../../services/profile_interaction_service.dart';
import '../../../theme/app_theme.dart';

/// Bottom-sheet modal for creating or editing a pet profile.
/// Supports: photo upload (gallery), name, species, breed, age, and role.
class EditPetModal extends StatefulWidget {
  final Map<String, dynamic>? existingPet;
  final String userId;
  final void Function(Map<String, dynamic> updatedPet) onSaved;

  const EditPetModal({
    super.key,
    this.existingPet,
    required this.userId,
    required this.onSaved,
  });

  static Future<void> show(
    BuildContext context, {
    Map<String, dynamic>? existingPet,
    required String userId,
    required void Function(Map<String, dynamic>) onSaved,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditPetModal(
        existingPet: existingPet,
        userId: userId,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<EditPetModal> createState() => _EditPetModalState();
}

class _EditPetModalState extends State<EditPetModal> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _speciesCtrl;
  late final TextEditingController _breedCtrl;
  late final TextEditingController _ageCtrl;
  String _selectedRole = 'pet';
  bool _isSaving = false;
  bool _isUploadingPhoto = false;

  // Current pet photo URL (may be updated after upload)
  String _currentPhotoUrl = '';

  static const List<Map<String, String>> _roles = [
    {'value': 'pet', 'label': 'Pet de Estimação 🐾'},
    {'value': 'emotional_support', 'label': 'Suporte Emocional 💛'},
    {'value': 'assistance_dog', 'label': 'Cão de Assistência 🦺'},
    {'value': 'therapy_animal', 'label': 'Animal de Terapia 🌿'},
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.existingPet;
    _nameCtrl = TextEditingController(text: p?['name'] as String? ?? '');
    _speciesCtrl = TextEditingController(text: p?['species'] as String? ?? '');
    _breedCtrl = TextEditingController(text: p?['breed'] as String? ?? '');
    _ageCtrl = TextEditingController(text: p?['age'] as String? ?? '');
    _currentPhotoUrl = p?['imageUrl'] as String? ?? '';
    _selectedRole = p?['role'] as String? ?? 'pet';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _speciesCtrl.dispose();
    _breedCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  /// Pick image from gallery and upload to Supabase Storage (pets bucket).
  /// Updates pets.photo_url and notifies PetAvatarNotifier.
  Future<void> _pickAndUploadPetImage() async {
    final petId = widget.existingPet?['id'] as String? ?? '';

    // For new pets (no ID yet), just pick and store locally until save
    if (petId.isEmpty) {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (pickedFile == null) return;

      // We'll upload after the pet is created; for now show a local preview
      // by storing the path as a temporary indicator
      setState(() {
        _currentPhotoUrl = pickedFile.path;
      });
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (pickedFile == null) return;

    setState(() => _isUploadingPhoto = true);

    try {
      final fileBytes = await pickedFile.readAsBytes();
      final fileExt = pickedFile.name.split('.').last.toLowerCase();

      final newUrl = await PetService.instance.uploadAndSyncPetPhoto(
        petId: petId,
        imageBytes: fileBytes,
        fileExtension: fileExt,
      );

      if (newUrl != null && mounted) {
        setState(() {
          _currentPhotoUrl = newUrl;
          _isUploadingPhoto = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto do pet atualizada com sucesso! 🐾'),
            backgroundColor: Color(0xFF1B4D3E),
          ),
        );
      } else {
        if (mounted) {
          setState(() => _isUploadingPhoto = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erro ao atualizar foto do pet.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao atualizar foto do pet.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);

    final service = ProfileInteractionService();
    final result = await service.updatePetProfile(
      userId: widget.userId,
      petData: {
        'pet_id': widget.existingPet?['id'] as String? ?? '',
        'name': _nameCtrl.text.trim(),
        'species': _speciesCtrl.text.trim(),
        'breed': _breedCtrl.text.trim(),
        'age': _ageCtrl.text.trim(),
        'role': _selectedRole,
        'photo_url': _currentPhotoUrl,
      },
    );

    setState(() => _isSaving = false);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: result.status == 'success'
            ? AppTheme.primary
            : Colors.red.shade600,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    if (result.status == 'success') {
      final updatedPet = <String, dynamic>{
        'id': result.updatedFields['pet_id'] ?? widget.existingPet?['id'] ?? '',
        'name': _nameCtrl.text.trim(),
        'species': _speciesCtrl.text.trim(),
        'breed': _breedCtrl.text.trim(),
        'age': _ageCtrl.text.trim(),
        'role': _selectedRole,
        'imageUrl': _currentPhotoUrl.isNotEmpty
            ? _currentPhotoUrl
            : (widget.existingPet?['imageUrl'] ?? ''),
        'imageSemantic':
            '${_nameCtrl.text.trim()}, ${_speciesCtrl.text.trim()}',
        'entriesCount': widget.existingPet?['entriesCount'] ?? 0,
        'lastEntry': widget.existingPet?['lastEntry'] ?? '',
      };

      if (_currentPhotoUrl.isNotEmpty) {
        PetAvatarNotifier.instance.updatePetAvatar(_currentPhotoUrl);
      }

      widget.onSaved(updatedPet);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isEditing = widget.existingPet != null;
    final hasPhoto = _currentPhotoUrl.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(top: 60),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isEditing ? 'Editar Pet' : 'Adicionar Pet',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pet photo section
                    Center(
                      child: Stack(
                        children: [
                          GestureDetector(
                            onTap: _isUploadingPhoto
                                ? null
                                : _pickAndUploadPetImage,
                            child: Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFD7E7E3),
                                border: Border.all(
                                  color: AppTheme.primary.withAlpha(77),
                                  width: 2,
                                ),
                              ),
                              child: ClipOval(
                                child: _isUploadingPhoto
                                    ? const Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF1B4D3E),
                                        ),
                                      )
                                    : hasPhoto
                                    ? ((_currentPhotoUrl.startsWith('http'))
                                          ? Image.network(
                                              _currentPhotoUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  const Icon(
                                                    Icons.pets,
                                                    size: 40,
                                                    color: Color(0xFF1B4D3E),
                                                  ),
                                            )
                                          : const Icon(
                                              Icons.pets,
                                              size: 40,
                                              color: Color(0xFF1B4D3E),
                                            ))
                                    : const Icon(
                                        Icons.pets,
                                        size: 40,
                                        color: Color(0xFF1B4D3E),
                                      ),
                              ),
                            ),
                          ),
                          // Camera icon overlay
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _isUploadingPhoto
                                  ? null
                                  : _pickAndUploadPetImage,
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppTheme.primary,
                                  border: Border.all(
                                    color: Colors.white,
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
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        'Alterar Foto do Pet',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Name
                    _buildField(
                      theme,
                      controller: _nameCtrl,
                      label: 'Nome do Pet *',
                      icon: Icons.pets_rounded,
                      validator: (v) =>
                          (v?.trim().isEmpty ?? true) ? 'Informe o nome' : null,
                    ),
                    const SizedBox(height: 12),

                    // Species + Breed row
                    Row(
                      children: [
                        Expanded(
                          child: _buildField(
                            theme,
                            controller: _speciesCtrl,
                            label: 'Espécie',
                            icon: Icons.category_outlined,
                            hint: 'Gato, Cão...',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildField(
                            theme,
                            controller: _breedCtrl,
                            label: 'Raça',
                            icon: Icons.info_outline_rounded,
                            hint: 'Maine Coon...',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Age
                    _buildField(
                      theme,
                      controller: _ageCtrl,
                      label: 'Idade',
                      icon: Icons.cake_outlined,
                      hint: '3 anos',
                    ),
                    const SizedBox(height: 16),

                    // Role selector
                    Text(
                      'Função do Pet',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _roles.map((r) {
                        final isSelected = _selectedRole == r['value'];
                        return ChoiceChip(
                          label: Text(
                            r['label']!,
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected
                                  ? AppTheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (_) =>
                              setState(() => _selectedRole = r['value']!),
                          selectedColor: AppTheme.primaryContainer,
                          backgroundColor: theme.colorScheme.surface,
                          side: BorderSide(
                            color: isSelected
                                ? AppTheme.primary
                                : theme.colorScheme.outlineVariant,
                          ),
                          showCheckmark: false,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    // Save button
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
                            : Text(
                                isEditing
                                    ? 'Salvar Alterações'
                                    : 'Adicionar Pet',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(
    ThemeData theme, {
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    int maxLines = 1,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18, color: AppTheme.primary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        isDense: true,
      ),
      style: theme.textTheme.bodyMedium,
    );
  }
}
