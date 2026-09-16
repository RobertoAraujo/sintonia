import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import './pet_avatar_notifier.dart';
import './supabase_service.dart';

/// PetService — dedicated service for all pet-related data operations.
///
/// Responsibilities:
///  • Upload a new pet photo to the `avatars` bucket (pets/ subfolder)
///  • Update the `pets.photo_url` column in the database
///  • Apply cache-busting (?v=<timestamp>) to the returned URL so Flutter's
///    image cache is bypassed and the UI refreshes immediately
///  • Broadcast the new URL through [PetAvatarNotifier] for instant UI sync
///  • Fetch the user profile joined with the active pet via the
///    `profile_with_active_pet` view (single DB round-trip)
///  • Set / change the active pet for the current user
class PetService {
  // ── Singleton ──────────────────────────────────────────────
  static PetService? _instance;
  static PetService get instance => _instance ??= PetService._();
  PetService._();

  // ── Helpers ────────────────────────────────────────────────
  SupabaseClient get _client => SupabaseService.instance.client;
  String? get _uid => SupabaseService.instance.currentUserId;

  // ─────────────────────────────────────────────────────────────
  // UPLOAD & UPDATE PET PHOTO
  // ─────────────────────────────────────────────────────────────

  /// Uploads [imageBytes] to the `avatars` bucket under the path
  /// `<userId>/pets/<timestamp>.<ext>`, updates `pets.photo_url`, applies
  /// cache-busting, notifies [PetAvatarNotifier], and returns the final URL.
  ///
  /// Returns `null` if the user is not authenticated, the pet does not belong
  /// to the current user, or any storage / DB operation fails.
  Future<String?> uploadAndSyncPetPhoto({
    required String petId,
    required List<int> imageBytes,
    required String fileExtension,
  }) async {
    final uid = _uid;
    if (uid == null) return null;

    try {
      // 1. Ownership validation — RLS also enforces this, but we fail fast here
      final petRow = await _client
          .from('pets')
          .select('id, owner_id')
          .eq('id', petId)
          .eq('owner_id', uid)
          .maybeSingle();
      if (petRow == null) {
        debugPrint('PetService: pet $petId not found or not owned by $uid');
        return null;
      }

      // 2. Upload to Storage: avatars/<uid>/pets/<timestamp>.<ext>
      final safeExt = ['jpg', 'jpeg', 'png', 'webp'].contains(fileExtension)
          ? fileExtension
          : 'jpg';
      final storagePath =
          '$uid/pets/pet_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
      final mimeType = (safeExt == 'jpg' || safeExt == 'jpeg')
          ? 'image/jpeg'
          : 'image/$safeExt';

      await _client.storage
          .from('avatars')
          .uploadBinary(
            storagePath,
            Uint8List.fromList(imageBytes),
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          );

      // 3. Build the public URL (bucket is public)
      final baseUrl = _client.storage.from('avatars').getPublicUrl(storagePath);

      // 4. Cache-busting: append ?v=<epoch-ms> so CachedNetworkImage always
      //    fetches the latest version instead of serving the stale cached copy.
      final cacheBustUrl =
          '$baseUrl?v=${DateTime.now().millisecondsSinceEpoch}';

      // 5. Persist the new URL in the pets table
      await _client
          .from('pets')
          .update({'photo_url': baseUrl}) // store clean URL in DB
          .eq('id', petId)
          .eq('owner_id', uid);

      // 6. Broadcast to all UI listeners so the badge refreshes instantly
      PetAvatarNotifier.instance.updatePetAvatar(cacheBustUrl);

      debugPrint('PetService: pet photo updated → $cacheBustUrl');
      return cacheBustUrl;
    } catch (e) {
      debugPrint('PetService.uploadAndSyncPetPhoto error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // FETCH PROFILE WITH ACTIVE PET  (single DB round-trip via View)
  // ─────────────────────────────────────────────────────────────

  /// Calls the `get_my_profile_with_pet` RPC (backed by the
  /// `profile_with_active_pet` SQL view) and returns a DTO map with:
  ///
  /// ```
  /// {
  ///   // all user_profiles columns …
  ///   'activePet': {
  ///     'id':           String,
  ///     'name':         String,
  ///     'photoUrl':     String,   // cache-busted URL
  ///     'thumbnailUrl': String,   // same URL (use for badge)
  ///   } | null
  /// }
  /// ```
  Future<Map<String, dynamic>?> fetchProfileWithActivePet() async {
    if (_uid == null) return null;
    try {
      // Use the RPC function backed by the SQL view for a single round-trip
      final rows = await _client.rpc('get_my_profile_with_pet');
      if (rows == null || (rows as List).isEmpty) return null;

      final data = Map<String, dynamic>.from((rows).first as Map);

      // Parse the active_pet JSON column returned by the view
      final petJson = data['active_pet'];
      Map<String, dynamic>? activePet;

      if (petJson != null) {
        final petMap = petJson is Map
            ? Map<String, dynamic>.from(petJson)
            : <String, dynamic>{};
        final rawUrl = (petMap['photo_url'] as String?) ?? '';
        final cacheBust = DateTime.now().millisecondsSinceEpoch;
        final photoUrl = rawUrl.isNotEmpty ? '$rawUrl?v=$cacheBust' : '';
        activePet = {
          'id': petMap['id'] as String? ?? '',
          'name': petMap['name'] as String? ?? '',
          'photoUrl': photoUrl,
          'thumbnailUrl': photoUrl,
        };
      }

      // Remove the raw DB column and replace with the typed DTO
      data.remove('active_pet');
      data['activePet'] = activePet;

      return data;
    } catch (e) {
      debugPrint('PetService.fetchProfileWithActivePet error: $e');
      // Fallback to the direct Supabase join if the RPC is not yet deployed
      return SupabaseService.instance.fetchProfileWithActivePet();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // SET ACTIVE PET
  // ─────────────────────────────────────────────────────────────

  /// Sets [petId] as the current user's active pet (shown in the profile badge).
  /// Validates ownership before writing.  Returns `true` on success.
  Future<bool> setActivePet(String petId) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      // Ownership check
      final pet = await _client
          .from('pets')
          .select('id')
          .eq('id', petId)
          .eq('owner_id', uid)
          .eq('is_active', true)
          .maybeSingle();
      if (pet == null) return false;

      await _client
          .from('user_profiles')
          .update({'active_pet_id': petId})
          .eq('id', uid);
      return true;
    } catch (e) {
      debugPrint('PetService.setActivePet error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // FETCH USER PETS
  // ─────────────────────────────────────────────────────────────

  /// Returns all active pets for [userId].
  Future<List<Map<String, dynamic>>> fetchUserPets(String userId) async {
    try {
      final data = await _client
          .from('pets')
          .select()
          .eq('owner_id', userId)
          .eq('is_active', true)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data as List);
    } catch (e) {
      debugPrint('PetService.fetchUserPets error: $e');
      return [];
    }
  }
}
