import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_export.dart';
import '../../services/supabase_service.dart';
import './widgets/edit_pet_modal.dart';
import './widgets/pet_card_widget.dart';
import './widgets/pet_diary_entry_widget.dart';

class PetsScreen extends StatefulWidget {
  const PetsScreen({super.key});

  @override
  State<PetsScreen> createState() => _PetsScreenState();
}

class _PetsScreenState extends State<PetsScreen> {
  bool _isLoadingPets = true;
  bool _isLoadingDiary = true;
  RealtimeChannel? _diarySubscription;

  final List<Map<String, dynamic>> _myPetsMaps = [];

  final List<Map<String, dynamic>> _diaryFeedMaps = [];

  @override
  void initState() {
    super.initState();
    _loadPets();
    _loadDiaryFeed();
    _subscribeToDiary();
  }

  @override
  void dispose() {
    if (_diarySubscription != null) {
      SupabaseService.instance.unsubscribe(_diarySubscription!);
    }
    super.dispose();
  }

  Future<void> _loadPets() async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) {
      setState(() => _isLoadingPets = false);
      return;
    }
    try {
      final pets = await SupabaseService.instance.fetchUserPets(uid);
      if (mounted && pets.isNotEmpty) {
        final mapped = pets
            .map(
              (p) => {
                'id': p['id'] ?? '',
                'name': p['name'] ?? '',
                'species': p['species'] ?? '',
                'breed': p['breed'] ?? '',
                'age': p['age'] ?? '',
                'role': p['role'] ?? 'pet',
                'imageUrl': (p['photo_url'] as String?)?.isNotEmpty == true
                    ? p['photo_url']
                    : null,
                'imageSemantic': p['photo_semantic'] ?? '',
                'entriesCount': 0,
                'lastEntry': '',
              },
            )
            .toList();
        setState(() {
          _myPetsMaps.clear();
          _myPetsMaps.addAll(mapped);
          _isLoadingPets = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingPets = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingPets = false);
    }
  }

  Future<void> _loadDiaryFeed() async {
    try {
      final entries = await SupabaseService.instance.fetchPetDiaryFeed(
        limit: 20,
      );
      if (mounted && entries.isNotEmpty) {
        final mapped = entries.map((e) {
          final owner = e['owner'] as Map<String, dynamic>? ?? {};
          final pet = e['pet'] as Map<String, dynamic>? ?? {};
          return {
            'id': e['id'] ?? '',
            'ownerName': owner['full_name'] ?? 'Usuário',
            'ownerImage': owner['avatar_url'] ?? '',
            'ownerImageSemantic': 'Foto de ${owner['full_name'] ?? 'Usuário'}',
            'petName': pet['name'] ?? '',
            'petSpecies': pet['species'] ?? '',
            'entryText': e['entry_text'] ?? '',
            'imageUrl': (e['image_url'] as String?)?.isNotEmpty == true
                ? e['image_url']
                : null,
            'imageSemantic': e['image_semantic'] ?? '',
            'timeAgo': _timeAgo(e['created_at']),
            'likes': e['likes_count'] ?? 0,
            'comments': e['comments_count'] ?? 0,
            'isLiked': false,
          };
        }).toList();
        setState(() {
          _diaryFeedMaps.clear();
          _diaryFeedMaps.addAll(mapped);
          _isLoadingDiary = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingDiary = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingDiary = false);
    }
  }

  void _subscribeToDiary() {
    _diarySubscription = SupabaseService.instance.subscribeToPetDiaryFeed(
      onNewEntry: (newEntry) {
        if (!mounted) return;
        setState(() {
          _diaryFeedMaps.insert(0, {
            'id': newEntry['id'] ?? '',
            'ownerName': 'Novo post',
            'ownerImage': '',
            'ownerImageSemantic': '',
            'petName': '',
            'petSpecies': '',
            'entryText': newEntry['entry_text'] ?? '',
            'imageUrl': null,
            'imageSemantic': '',
            'timeAgo': 'Agora',
            'likes': 0,
            'comments': 0,
            'isLiked': false,
          });
        });
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

  void _toggleDiaryLike(String entryId) {
    final idx = _diaryFeedMaps.indexWhere((e) => e['id'] == entryId);
    if (idx == -1) return;
    final isLiked = _diaryFeedMaps[idx]['isLiked'] as bool;
    setState(() {
      _diaryFeedMaps[idx]['isLiked'] = !isLiked;
      _diaryFeedMaps[idx]['likes'] =
          (_diaryFeedMaps[idx]['likes'] as int) + (isLiked ? -1 : 1);
    });
    if (isLiked) {
      SupabaseService.instance.unlikeDiaryEntry(entryId);
    } else {
      SupabaseService.instance.likeDiaryEntry(entryId);
    }
  }

  void _openAddPet() {
    EditPetModal.show(
      context,
      userId: SupabaseService.instance.currentUserId ?? 'current_user',
      onSaved: (newPet) async {
        // Persist to Supabase
        final created = await SupabaseService.instance.createPet(
          name: newPet['name'] ?? '',
          species: newPet['species'] ?? '',
          breed: newPet['breed'] ?? '',
          age: newPet['age'] ?? '',
          role: newPet['role'] ?? 'pet',
          photoUrl: newPet['imageUrl'] ?? '',
          photoSemantic: newPet['imageSemantic'] ?? '',
        );
        if (created != null) {
          setState(() => _myPetsMaps.add({...newPet, 'id': created['id']}));
        } else {
          setState(() => _myPetsMaps.add(newPet));
        }
      },
    );
  }

  void _openEditPet(Map<String, dynamic> pet) {
    EditPetModal.show(
      context,
      existingPet: pet,
      userId: SupabaseService.instance.currentUserId ?? 'current_user',
      onSaved: (updatedPet) async {
        final petId = pet['id'] as String? ?? '';
        if (petId.isNotEmpty) {
          await SupabaseService.instance.updatePet(petId, {
            'name': updatedPet['name'],
            'species': updatedPet['species'],
            'breed': updatedPet['breed'],
            'age': updatedPet['age'],
            'role': updatedPet['role'],
            'photo_url': updatedPet['imageUrl'] ?? '',
            'photo_semantic': updatedPet['imageSemantic'] ?? '',
          });
        }
        setState(() {
          final idx = _myPetsMaps.indexWhere((p) => p['id'] == pet['id']);
          if (idx != -1) _myPetsMaps[idx] = updatedPet;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    const floatingNavHeight = 80.0;
    final listBottomPadding = floatingNavHeight + bottomPadding + 16.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Pets & Diário',
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: CustomIconWidget(
                        iconName: 'search_rounded',
                        color: theme.colorScheme.onSurface,
                        size: 24,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // My Pets section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Row(
                  children: [
                    Text('Meus Pets', style: theme.textTheme.titleMedium),
                    const Spacer(),
                    TextButton(
                      onPressed: () {},
                      child: Text(
                        'Ver todos',
                        style: TextStyle(color: AppTheme.primary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 160,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // Add pet button
                    GestureDetector(
                      onTap: _openAddPet,
                      child: Container(
                        width: 120,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.primary.withAlpha(102),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withAlpha(26),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.add_rounded,
                                color: AppTheme.primary,
                                size: 24,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Adicionar\nPet',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                    ..._myPetsMaps.map(
                      (pet) => GestureDetector(
                        onLongPress: () => _openEditPet(pet),
                        child: PetCardWidget(pet: pet),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Community diary section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Row(
                  children: [
                    Text(
                      'Diário da Comunidade',
                      style: theme.textTheme.titleMedium,
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.edit_rounded, size: 14),
                      label: const Text(
                        'Escrever',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                if (index == _diaryFeedMaps.length) {
                  return SizedBox(height: listBottomPadding);
                }
                final entry = _diaryFeedMaps[index];
                return PetDiaryEntryWidget(
                  entry: entry,
                  onLike: () => _toggleDiaryLike(entry['id'] as String),
                );
              }, childCount: _diaryFeedMaps.length + 1),
            ),
          ],
        ),
      ),
    );
  }
}
