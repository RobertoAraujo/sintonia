import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io' if (dart.library.io) 'dart:io';
import 'package:flutter/foundation.dart';

import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';

class CreateGroupScreen extends StatefulWidget {
  final void Function(Map<String, dynamic>) onGroupCreated;

  const CreateGroupScreen({required this.onGroupCreated, super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _imageUrlCtrl = TextEditingController();

  XFile? _pickedImageFile;
  bool _isUploadingImage = false;

  final List<String> _allTags = [
    'TDAH',
    'TEA',
    'Dislexia',
    'Música',
    'Astronomia',
    'Arte',
    'Jogos',
    'Pets',
    'Leitura',
    'Culinária',
    'Esportes',
    'Tecnologia',
    'Natureza',
    'Cinema',
    'Fotografia',
  ];

  final Set<String> _selectedTags = {};
  String _privacy = 'Público';
  bool _isCreating = false;

  final List<String> _coverImages = [
    'https://images.pexels.com/photos/1169754/pexels-photo-1169754.jpeg',
    'https://images.pexels.com/photos/1108099/pexels-photo-1108099.jpeg',
    'https://images.pexels.com/photos/3184418/pexels-photo-3184418.jpeg',
    'https://images.pexels.com/photos/1181671/pexels-photo-1181671.jpeg',
    'https://images.pixabay.com/photo/2016/11/29/09/32/concept-1868728_1280.jpg',
    'https://images.unsplash.com/photo-1522071820081-009f0129c71c',
  ];

  int _selectedCoverIndex = 0;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _imageUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImageFromGallery() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (image != null) {
      setState(() {
        _pickedImageFile = image;
      });
    }
  }

  Future<String?> _uploadPickedImage() async {
    if (_pickedImageFile == null) return null;
    try {
      setState(() => _isUploadingImage = true);
      final supabase = SupabaseService.instance.client;
      final userId = supabase.auth.currentUser?.id ?? 'unknown';
      final fileName =
          'group_covers/${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = await _pickedImageFile!.readAsBytes();
      await supabase.storage
          .from('posts')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(contentType: 'image/jpeg', upsert: true),
          );
      final publicUrl = supabase.storage.from('posts').getPublicUrl(fileName);
      return publicUrl;
    } catch (e) {
      debugPrint('Erro ao fazer upload da imagem: $e');
      return null;
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  void _createGroup() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTags.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Selecione ao menos uma categoria/tag'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    setState(() => _isCreating = true);

    String coverUrl = _coverImages[_selectedCoverIndex];

    if (_pickedImageFile != null) {
      final uploadedUrl = await _uploadPickedImage();
      if (uploadedUrl != null) {
        coverUrl = uploadedUrl;
      }
    }

    final success = await SupabaseService.instance.createGroup(
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty
          ? 'Grupo criado por você'
          : _descCtrl.text.trim(),
      tags: _selectedTags.toList(),
      isPublic: _privacy == 'Público',
      avatarUrl: coverUrl,
    );

    if (!mounted) return;
    setState(() => _isCreating = false);

    if (success) {
      final newGroup = {
        'id': '',
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty
            ? 'Grupo criado por você'
            : _descCtrl.text.trim(),
        'members': 1,
        'imageUrl': coverUrl,
        'imageSemantic': 'Imagem de capa do grupo ${_nameCtrl.text.trim()}',
        'tags': _selectedTags.toList(),
        'privacy': _privacy,
        'isMember': true,
        'isOwner': true,
      };
      widget.onGroupCreated(newGroup);
      Navigator.of(context).pop(newGroup);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Erro ao criar grupo. Tente novamente.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Criar Grupo',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _isCreating
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: _createGroup,
                    child: Text(
                      'Criar',
                      style: GoogleFonts.manrope(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: [
            // Cover image picker
            _buildSectionLabel(theme, 'Imagem de Capa', Icons.image_rounded),
            const SizedBox(height: 12),
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _coverImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final isSelected =
                      _selectedCoverIndex == i && _pickedImageFile == null;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _selectedCoverIndex = i;
                      _pickedImageFile = null;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 140,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primary
                              : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppTheme.primary.withAlpha(80),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : [],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              _coverImages[i],
                              fit: BoxFit.cover,
                              semanticLabel: 'Opção de capa ${i + 1}',
                            ),
                            if (isSelected)
                              Container(
                                color: AppTheme.primary.withAlpha(60),
                                child: const Center(
                                  child: Icon(
                                    Icons.check_circle_rounded,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            // Gallery picker button (replaces URL text field)
            _pickedImageFile != null
                ? Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: kIsWeb
                            ? Image.network(
                                _pickedImageFile!.path,
                                height: 120,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                semanticLabel: 'Imagem selecionada da galeria',
                              )
                            : Image.file(
                                File(_pickedImageFile!.path),
                                height: 120,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                semanticLabel: 'Imagem selecionada da galeria',
                              ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: () => setState(() => _pickedImageFile = null),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(160),
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
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: _pickImageFromGallery,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(160),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.photo_library_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Trocar',
                                  style: GoogleFonts.manrope(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : OutlinedButton.icon(
                    onPressed: _pickImageFromGallery,
                    icon: const Icon(Icons.photo_library_rounded),
                    label: Text(
                      'Exportar da Galeria',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: BorderSide(color: AppTheme.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 16,
                      ),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),

            const SizedBox(height: 24),

            // Group name
            _buildSectionLabel(theme, 'Nome do Grupo *', Icons.group_rounded),
            const SizedBox(height: 10),
            TextFormField(
              controller: _nameCtrl,
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Informe o nome do grupo'
                  : null,
              decoration: InputDecoration(
                hintText: 'Ex: TDAH Criativo, Pets & Astronomia...',
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Description
            _buildSectionLabel(
              theme,
              'Descrição / Objetivos',
              Icons.description_outlined,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText:
                    'Descreva o propósito do grupo, quem pode participar e o que será compartilhado...',
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),

            const SizedBox(height: 20),

            // Category tags
            _buildSectionLabel(
              theme,
              'Categorias / Tags *',
              Icons.label_rounded,
            ),
            const SizedBox(height: 4),
            Text(
              'Selecione ao menos uma categoria',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allTags.map((tag) {
                final isSelected = _selectedTags.contains(tag);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedTags.remove(tag);
                      } else {
                        _selectedTags.add(tag);
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primary
                            : theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected) ...[
                          const Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          tag,
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // Privacy
            _buildSectionLabel(
              theme,
              'Privacidade',
              Icons.lock_outline_rounded,
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: ['Público', 'Privado', 'Somente Convidados']
                    .map(
                      (option) => RadioListTile<String>(
                        value: option,
                        groupValue: _privacy,
                        onChanged: (v) => setState(() => _privacy = v!),
                        title: Text(
                          option,
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          option == 'Público'
                              ? 'Qualquer pessoa pode encontrar e participar'
                              : option == 'Privado'
                              ? 'Qualquer pessoa pode encontrar, mas precisa solicitar'
                              : 'Apenas pessoas convidadas podem entrar',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        activeColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),

            const SizedBox(height: 32),

            // Create button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isCreating ? null : _createGroup,
                icon: _isCreating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.group_add_rounded),
                label: Text(
                  _isCreating ? 'Criando...' : 'Criar Grupo',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(ThemeData theme, String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
