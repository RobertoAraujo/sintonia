import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dio/dio.dart';

import './avatar_notifier.dart';
import '../core/services/aiIntegrations/chat_completion_service.dart';

class SupabaseService {
  static SupabaseService? _instance;
  static SupabaseService get instance => _instance ??= SupabaseService._();

  SupabaseService._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  // Initialize Supabase - call this in main()
  static Future<void> initialize() async {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw Exception(
        'SUPABASE_URL and SUPABASE_ANON_KEY must be defined using --dart-define.',
      );
    }
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        // Use implicit flow on web to avoid CORS/preflight issues with PKCE
        // Use PKCE on mobile for better security
        authFlowType: kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.info,
      ),
    );
  }

  // Get Supabase client
  SupabaseClient get client => Supabase.instance.client;

  // Current authenticated user
  User? get currentUser => client.auth.currentUser;
  String? get currentUserId => client.auth.currentUser?.id;
  bool get isAuthenticated => client.auth.currentUser != null;

  // ─────────────────────────────────────────────────────────────
  // AUTH
  // ─────────────────────────────────────────────────────────────

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? fullName,
    String? username,
  }) async {
    // Completely different approach: use dio to call Supabase Auth REST API directly.
    // This bypasses the SDK's internal fetch/XMLHttpRequest mechanism that causes
    // "Failed to fetch" / "AuthRetryableFetchException" errors on web.
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: supabaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            'apikey': supabaseAnonKey,
            'Content-Type': 'application/json',
          },
        ),
      );

      final response = await dio.post(
        '/auth/v1/signup',
        data: {
          'email': email,
          'password': password,
          'data': {
            if (fullName != null) 'full_name': fullName,
            if (username != null) 'username': username,
          },
        },
      );

      final body = response.data as Map<String, dynamic>;

      // Parse user from response
      final userJson = body['user'] as Map<String, dynamic>?;
      final sessionJson = body['session'] as Map<String, dynamic>?;

      if (userJson == null) {
        throw AuthException('Não foi possível criar a conta. Tente novamente.');
      }

      // If we got a session from the direct call, set it in the Supabase client
      if (sessionJson != null) {
        final accessToken = sessionJson['access_token'] as String?;
        final refreshToken = sessionJson['refresh_token'] as String?;
        if (accessToken != null && refreshToken != null) {
          try {
            await client.auth.setSession(accessToken);
          } catch (_) {
            // setSession may fail if token format differs — fall back to signIn
          }
        }
      }

      // Fall back to the SDK signUp to get a proper AuthResponse object
      // Now that we know the network works via dio, the SDK call should also work.
      // If the direct call succeeded but SDK still fails, sign in instead.
      try {
        return await client.auth.signUp(
          email: email,
          password: password,
          data: {
            if (fullName != null) 'full_name': fullName,
            if (username != null) 'username': username,
          },
        );
      } catch (sdkErr) {
        // SDK failed but dio succeeded — try signing in to get a proper session
        debugPrint(
          'SDK signUp failed after dio success, trying signIn: $sdkErr',
        );
        try {
          return await client.auth.signInWithPassword(
            email: email,
            password: password,
          );
        } catch (signInErr) {
          // Account was created (dio succeeded), user needs to confirm email or retry login
          debugPrint('signIn after dio signup also failed: $signInErr');
          // Return a minimal response indicating success without session
          // by re-throwing the original SDK error so the caller can handle it
          rethrow;
        }
      }
    } on DioException catch (dioErr) {
      debugPrint('Dio signUp error: ${dioErr.type} — ${dioErr.message}');
      final responseData = dioErr.response?.data;
      if (responseData is Map) {
        final msg =
            responseData['msg'] ??
            responseData['message'] ??
            responseData['error_description'] ??
            '';
        final code = responseData['error_code'] ?? responseData['code'] ?? '';
        if (msg.toString().contains('already registered') ||
            code.toString().contains('user_already_exists')) {
          throw AuthException('User already registered');
        }
        if (msg.toString().isNotEmpty) {
          throw AuthException(msg.toString());
        }
      }
      // Network-level failure — rethrow as a recognizable error
      throw AuthException('Failed to fetch');
    }
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await client.auth.signOut();
  }

  Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  // ─────────────────────────────────────────────────────────────
  // AUTH SECURITY — User Existence Check, 2FA, Session Management
  // ─────────────────────────────────────────────────────────────

  /// Checks if a user account exists for the given email.
  /// Returns true if the account exists, false otherwise.
  /// This prevents auto-creation of accounts during login.
  Future<bool> checkIfUserExists(String email) async {
    try {
      // Query user_profiles by email to check existence
      final data = await client
          .from('user_profiles')
          .select('id')
          .eq('email', email.trim().toLowerCase())
          .maybeSingle();
      return data != null;
    } catch (e) {
      debugPrint('checkIfUserExists error: $e');
      // On error, allow the login attempt to proceed (signIn will fail with proper error)
      return true;
    }
  }

  /// Sends a 2FA verification code to the user's email via edge function.
  Future<void> send2FACode({required String email}) async {
    try {
      final supabaseUrl = SupabaseService.supabaseUrl;
      final anonKey = SupabaseService.supabaseAnonKey;
      final response = await client.functions.invoke(
        'send-2fa-code',
        body: {'email': email},
      );
      if (response.status != 200) {
        throw Exception('Falha ao enviar código 2FA.');
      }
    } catch (e) {
      debugPrint('send2FACode error: $e');
      rethrow;
    }
  }

  /// Verifies a 2FA code for the given email.
  /// Returns true if the code is valid and not expired.
  Future<bool> verify2FACode({
    required String email,
    required String code,
  }) async {
    try {
      final response = await client.functions.invoke(
        'verify-2fa-code',
        body: {'email': email, 'code': code},
      );
      if (response.status == 200) {
        final data = response.data as Map<String, dynamic>?;
        return data?['verified'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('verify2FACode error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // USER PROFILES
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> fetchCurrentUserProfile() async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final data = await client
          .from('user_profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      return data;
    } catch (e) {
      debugPrint('fetchCurrentUserProfile error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchUserProfile(String userId) async {
    try {
      final data = await client
          .from('user_profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      return data;
    } catch (e) {
      debugPrint('fetchUserProfile error: $e');
      return null;
    }
  }

  Future<bool> updateUserProfile(Map<String, dynamic> updates) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      await client.from('user_profiles').update(updates).eq('id', uid);
      return true;
    } catch (e) {
      debugPrint('updateUserProfile error: $e');
      return false;
    }
  }

  /// Uploads image bytes to Supabase Storage bucket 'avatars',
  /// then updates the user's avatar_url in user_profiles.
  /// Returns the public URL on success, or null on failure.
  Future<String?> uploadProfileAvatar(
    List<int> imageBytes,
    String fileExtension,
  ) async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final fileName =
          '$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final mimeType = fileExtension == 'jpg' || fileExtension == 'jpeg'
          ? 'image/jpeg'
          : 'image/$fileExtension';
      await client.storage
          .from('avatars')
          .uploadBinary(
            fileName,
            Uint8List.fromList(imageBytes),
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          );
      // Add cache-busting timestamp so CachedNetworkImage always fetches fresh
      final baseUrl = client.storage.from('avatars').getPublicUrl(fileName);
      final publicUrl = '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
      // Update avatar_url in user_profiles
      await client
          .from('user_profiles')
          .update({'avatar_url': publicUrl})
          .eq('id', uid);
      // Notify all listeners about the new avatar URL
      AvatarNotifier.instance.updateAvatar(publicUrl);
      return publicUrl;
    } catch (e) {
      debugPrint('uploadProfileAvatar error: $e');
      return null;
    }
  }

  /// Uploads pet photo bytes to Supabase Storage bucket 'avatars' (pets/ subfolder).
  /// Returns the public URL on success, or null on failure.
  Future<String?> uploadPetPhoto(
    List<int> imageBytes,
    String fileExtension,
  ) async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final safeExt = ['jpg', 'jpeg', 'png', 'webp'].contains(fileExtension)
          ? fileExtension
          : 'jpg';
      final fileName =
          '$uid/pets/pet_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
      final mimeType = safeExt == 'jpg' || safeExt == 'jpeg'
          ? 'image/jpeg'
          : 'image/$safeExt';
      await client.storage
          .from('avatars')
          .uploadBinary(
            fileName,
            Uint8List.fromList(imageBytes),
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          );
      final baseUrl = client.storage.from('avatars').getPublicUrl(fileName);
      final publicUrl = '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
      return publicUrl;
    } catch (e) {
      debugPrint('uploadPetPhoto error: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    // Require at least 1 character
    if (query.trim().isEmpty) return [];
    // Sanitize: limit query length
    final safeQuery = query.trim().substring(
      0,
      query.trim().length.clamp(0, 50),
    );
    try {
      final data = await client
          .from('user_profiles')
          .select(
            'id, full_name, username, avatar_url, bio, neurodiv_type, '
            'hyperfocuses, interests, communication_styles, values_and_ideas, '
            'communication_preferences',
          )
          .or('full_name.ilike.%$safeQuery%,username.ilike.%$safeQuery%')
          .limit(20);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('searchUsers error: $e');
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────
  // POSTS
  // ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchFeedPosts({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final data = await client
          .from('posts')
          .select('*, author:user_profiles!author_id(*)')
          .eq('is_published', true)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('fetchFeedPosts error: $e');
      return [];
    }
  }

  /// Fetch a single post with author details by post ID (used by realtime callbacks)
  Future<Map<String, dynamic>?> fetchSinglePost(String postId) async {
    try {
      final data = await client
          .from('posts')
          .select('*, author:user_profiles!author_id(*)')
          .eq('id', postId)
          .eq('is_published', true)
          .maybeSingle();
      return data;
    } catch (e) {
      debugPrint('fetchSinglePost error: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> fetchUserPosts(String userId) async {
    try {
      final data = await client
          .from('posts')
          .select()
          .eq('author_id', userId)
          .eq('is_published', true)
          .neq('post_type', 'diary')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('fetchUserPosts error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> createPost({
    required String content,
    String? imageUrl,
    String? imageSemantic,
    List<String> hyperfocusTags = const [],
    String postType = 'post',
  }) async {
    final uid = currentUserId;
    if (uid == null) return null;
    // Input validation — allow image-only posts (empty caption is OK when imageUrl is present)
    final trimmedContent = content.trim();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    if (trimmedContent.isEmpty && !hasImage) return null;
    if (trimmedContent.length > 2000) return null;
    try {
      final data = await client
          .from('posts')
          .insert({
            'author_id': uid,
            if (trimmedContent.isNotEmpty) 'content': trimmedContent,
            if (hasImage) 'image_url': imageUrl,
            if (imageSemantic != null && imageSemantic.isNotEmpty)
              'image_semantic': imageSemantic,
            'hyperfocus_tags': hyperfocusTags,
            'post_type': postType,
          })
          .select()
          .single();
      return data;
    } catch (e) {
      debugPrint('createPost error: $e');
      return null;
    }
  }

  /// Uploads image bytes to Supabase Storage bucket 'posts',
  /// Returns the public URL on success, or null on failure.
  Future<String?> uploadPostImage(
    List<int> imageBytes,
    String fileExtension,
  ) async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final safeExt =
          ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(fileExtension)
          ? fileExtension
          : 'jpg';
      final fileName =
          '$uid/post_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
      final mimeType = safeExt == 'jpg' || safeExt == 'jpeg'
          ? 'image/jpeg'
          : 'image/$safeExt';
      await client.storage
          .from('posts')
          .uploadBinary(
            fileName,
            Uint8List.fromList(imageBytes),
            fileOptions: FileOptions(contentType: mimeType, upsert: false),
          );
      final publicUrl = client.storage.from('posts').getPublicUrl(fileName);
      return publicUrl;
    } catch (e) {
      debugPrint('uploadPostImage error: $e');
      return null;
    }
  }

  /// Syncs a published post image to the user_photos gallery table.
  Future<void> syncPostToUserPhotos({
    required String postId,
    required String photoUrl,
    String caption = '',
  }) async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      await client.from('user_photos').insert({
        'user_id': uid,
        'post_id': postId,
        'photo_url': photoUrl,
        'caption': caption,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('syncPostToUserPhotos error: $e');
    }
  }

  /// Fetches the photo gallery for a given user (or current user if null).
  Future<List<Map<String, dynamic>>> fetchUserPhotos([String? userId]) async {
    final uid = userId ?? currentUserId;
    if (uid == null) return [];
    try {
      final data = await client
          .from('user_photos')
          .select('id, photo_url, caption, post_id, created_at')
          .eq('user_id', uid)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('fetchUserPhotos error: $e');
      return [];
    }
  }

  /// Fetch saved posts for the current user, mapped for the profile grid.
  Future<List<Map<String, dynamic>>> fetchSavedPostsMapped() async {
    final uid = currentUserId;
    if (uid == null) return [];
    try {
      final data = await client
          .from('saved_posts')
          .select('*, post:posts!post_id(*)')
          .eq('user_id', uid)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data).map((row) {
        final p = row['post'] as Map<String, dynamic>? ?? {};
        return {
          'id': p['id'] ?? '',
          'imageUrl': (p['image_url'] as String?)?.isNotEmpty == true
              ? p['image_url']
              : null,
          'semanticLabel': p['image_semantic'] ?? '',
          'likes': p['likes_count'] ?? 0,
          'hasImage': (p['image_url'] as String?)?.isNotEmpty == true,
          'content': p['content'] ?? '',
        };
      }).toList();
    } catch (e) {
      debugPrint('fetchSavedPostsMapped error: $e');
      return [];
    }
  }

  Future<bool> deletePost(String postId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      await client.from('posts').delete().eq('id', postId).eq('author_id', uid);
      return true;
    } catch (e) {
      debugPrint('deletePost error: $e');
      return false;
    }
  }

  Future<bool> updatePost(
    String postId, {
    required String content,
    required String visibility,
    String? imageUrl,
  }) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      final Map<String, dynamic> updates = {
        'content': content,
        'visibility': visibility,
      };
      if (imageUrl != null) updates['image_url'] = imageUrl;
      await client
          .from('posts')
          .update(updates)
          .eq('id', postId)
          .eq('author_id', uid);

      // Insert a post_edit notification so the author sees the edit in their notification center
      try {
        final profile = await client
            .from('user_profiles')
            .select('full_name, username')
            .eq('id', uid)
            .maybeSingle();
        final actorName = (profile?['full_name'] as String?)?.isNotEmpty == true
            ? profile!['full_name'] as String
            : (profile?['username'] as String? ?? 'Você');
        await client.from('notifications').insert({
          'recipient_id': uid,
          'actor_id': uid,
          'type': 'post_edit',
          'title': 'Publicação editada',
          'body': '$actorName editou uma publicação.',
          'reference_id': postId,
          'is_read': false,
        });
      } catch (notifErr) {
        debugPrint('updatePost notification error (non-fatal): $notifErr');
      }

      return true;
    } catch (e) {
      debugPrint('updatePost error: $e');
      // Fallback: try updating only content if visibility column doesn't exist yet
      try {
        await client
            .from('posts')
            .update({'content': content})
            .eq('id', postId)
            .eq('author_id', uid);
        return true;
      } catch (e2) {
        debugPrint('updatePost fallback error: $e2');
        return false;
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // POST LIKES
  // ─────────────────────────────────────────────────────────────

  Future<bool> likePost(String postId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      await client.from('post_likes').insert({
        'post_id': postId,
        'user_id': uid,
      });
      return true;
    } catch (e) {
      debugPrint('likePost error: $e');
      return false;
    }
  }

  Future<bool> unlikePost(String postId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      await client
          .from('post_likes')
          .delete()
          .eq('post_id', postId)
          .eq('user_id', uid);
      return true;
    } catch (e) {
      debugPrint('unlikePost error: $e');
      return false;
    }
  }

  Future<bool> isPostLiked(String postId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      final data = await client
          .from('post_likes')
          .select('id')
          .eq('post_id', postId)
          .eq('user_id', uid)
          .maybeSingle();
      return data != null;
    } catch (e) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // POST COMMENTS
  // ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchPostComments(String postId) async {
    try {
      final data = await client
          .from('post_comments')
          .select('*, author:user_profiles!author_id(*)')
          .eq('post_id', postId)
          .eq('is_visible', true)
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('fetchPostComments error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> addComment({
    required String postId,
    required String content,
  }) async {
    final uid = currentUserId;
    if (uid == null) return null;
    // Input validation
    final trimmedContent = content.trim();
    if (trimmedContent.isEmpty || trimmedContent.length > 500) return null;
    try {
      final data = await client
          .from('post_comments')
          .insert({
            'post_id': postId,
            'author_id': uid,
            'content': trimmedContent,
          })
          .select('*, author:user_profiles!author_id(*)')
          .single();
      return data;
    } catch (e) {
      debugPrint('addComment error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // POST SHARES
  // ─────────────────────────────────────────────────────────────

  Future<bool> sharePost(String postId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      await client.from('post_shares').upsert({
        'post_id': postId,
        'user_id': uid,
      });
      return true;
    } catch (e) {
      debugPrint('sharePost error: $e');
      return false;
    }
  }

  /// Fetch liked post IDs for the current user from a given list of post IDs.
  Future<Set<String>> fetchLikedPostIds(List<String> postIds) async {
    final uid = currentUserId;
    if (uid == null || postIds.isEmpty) return {};
    try {
      final data = await client
          .from('post_likes')
          .select('post_id')
          .eq('user_id', uid)
          .inFilter('post_id', postIds);
      return {
        for (final row in List<Map<String, dynamic>>.from(data))
          row['post_id'] as String,
      };
    } catch (e) {
      debugPrint('fetchLikedPostIds error: $e');
      return {};
    }
  }

  /// Fetch saved post IDs for the current user from a given list of post IDs.
  Future<Set<String>> fetchSavedPostIds(List<String> postIds) async {
    final uid = currentUserId;
    if (uid == null || postIds.isEmpty) return {};
    try {
      final data = await client
          .from('saved_posts')
          .select('post_id')
          .eq('user_id', uid)
          .inFilter('post_id', postIds);
      return {
        for (final row in List<Map<String, dynamic>>.from(data))
          row['post_id'] as String,
      };
    } catch (e) {
      debugPrint('fetchSavedPostIds error: $e');
      return {};
    }
  }

  // ─────────────────────────────────────────────────────────────
  // SAVED POSTS
  // ─────────────────────────────────────────────────────────────

  Future<bool> savePost(String postId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      await client.from('saved_posts').insert({
        'user_id': uid,
        'post_id': postId,
      });
      return true;
    } catch (e) {
      debugPrint('savePost error: $e');
      return false;
    }
  }

  Future<bool> unsavePost(String postId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      await client
          .from('saved_posts')
          .delete()
          .eq('user_id', uid)
          .eq('post_id', postId);
      return true;
    } catch (e) {
      debugPrint('unsavePost error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchSavedPosts() async {
    final uid = currentUserId;
    if (uid == null) return [];
    try {
      final data = await client
          .from('saved_posts')
          .select('*, post:posts!post_id(*, author:user_profiles!author_id(*))')
          .eq('user_id', uid)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('fetchSavedPosts error: $e');
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PETS
  // ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchUserPets(String userId) async {
    try {
      final data = await client
          .from('pets')
          .select()
          .eq('owner_id', userId)
          .eq('is_active', true)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('fetchUserPets error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> createPet({
    required String name,
    required String species,
    String breed = '',
    String age = '',
    String role = 'pet',
    String photoUrl = '',
    String photoSemantic = '',
  }) async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final data = await client
          .from('pets')
          .insert({
            'owner_id': uid,
            'name': name,
            'species': species,
            'breed': breed,
            'age': age,
            'role': role,
            'photo_url': photoUrl,
            'photo_semantic': photoSemantic,
          })
          .select()
          .single();
      return data;
    } catch (e) {
      debugPrint('createPet error: $e');
      return null;
    }
  }

  Future<bool> updatePet(String petId, Map<String, dynamic> updates) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      await client
          .from('pets')
          .update(updates)
          .eq('id', petId)
          .eq('owner_id', uid);
      return true;
    } catch (e) {
      debugPrint('updatePet error: $e');
      return false;
    }
  }

  Future<bool> deletePet(String petId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      await client
          .from('pets')
          .update({'is_active': false})
          .eq('id', petId)
          .eq('owner_id', uid);
      return true;
    } catch (e) {
      debugPrint('deletePet error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ACTIVE PET BADGE
  // ─────────────────────────────────────────────────────────────

  /// Fetches the current user's profile joined with their active pet data.
  /// Returns a map with profile fields plus an 'activePet' sub-map containing
  /// id, name, photoUrl, and thumbnailUrl (with cache-busting ?v= param).
  Future<Map<String, dynamic>?> fetchProfileWithActivePet() async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final data = await client
          .from('user_profiles')
          .select('*, active_pet:pets!active_pet_id(id, name, photo_url)')
          .eq('id', uid)
          .maybeSingle();
      if (data == null) return null;

      final petRow = data['active_pet'] as Map<String, dynamic>?;
      Map<String, dynamic>? activePet;
      if (petRow != null) {
        final rawUrl = (petRow['photo_url'] as String?) ?? '';
        final cacheBust = DateTime.now().millisecondsSinceEpoch;
        final photoUrl = rawUrl.isNotEmpty ? '$rawUrl?v=$cacheBust' : '';
        activePet = {
          'id': petRow['id'] as String? ?? '',
          'name': petRow['name'] as String? ?? '',
          'photoUrl': photoUrl,
          'thumbnailUrl': photoUrl,
        };
      }

      return {...data, 'activePet': activePet};
    } catch (e) {
      debugPrint('fetchProfileWithActivePet error: $e');
      return null;
    }
  }

  /// Sets the active pet for the current user.
  /// The pet must belong to the current user (ownership validated by RLS).
  Future<bool> setActivePet(String petId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      // Validate ownership: pet must belong to current user
      final pet = await client
          .from('pets')
          .select('id')
          .eq('id', petId)
          .eq('owner_id', uid)
          .eq('is_active', true)
          .maybeSingle();
      if (pet == null) return false;

      await client
          .from('user_profiles')
          .update({'active_pet_id': petId})
          .eq('id', uid);
      return true;
    } catch (e) {
      debugPrint('setActivePet error: $e');
      return false;
    }
  }

  /// Updates a pet's photo URL with cache-busting and syncs active_pet_id
  /// if this pet is the user's active pet.
  Future<String?> updatePetPhotoWithCacheBust(
    String petId,
    List<int> imageBytes,
    String fileExtension,
  ) async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      // Validate ownership
      final pet = await client
          .from('pets')
          .select('id, owner_id')
          .eq('id', petId)
          .eq('owner_id', uid)
          .maybeSingle();
      if (pet == null) return null;

      // Upload photo
      final newUrl = await uploadPetPhoto(imageBytes, fileExtension);
      if (newUrl == null) return null;

      // Update pet photo_url in DB
      await client
          .from('pets')
          .update({'photo_url': newUrl})
          .eq('id', petId)
          .eq('owner_id', uid);

      // Add cache-busting query string for immediate UI refresh
      final cacheBustUrl = '$newUrl?v=${DateTime.now().millisecondsSinceEpoch}';
      return cacheBustUrl;
    } catch (e) {
      debugPrint('updatePetPhotoWithCacheBust error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PET DIARY
  // ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchPetDiaryFeed({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final data = await client
          .from('pet_diary_entries')
          .select('*, owner:user_profiles!owner_id(*), pet:pets!pet_id(*)')
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('fetchPetDiaryFeed error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> addPetDiaryEntry({
    required String petId,
    required String entryText,
    String imageUrl = '',
    String imageSemantic = '',
  }) async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final data = await client
          .from('pet_diary_entries')
          .insert({
            'pet_id': petId,
            'owner_id': uid,
            'entry_text': entryText,
            'image_url': imageUrl,
            'image_semantic': imageSemantic,
          })
          .select()
          .single();
      return data;
    } catch (e) {
      debugPrint('addPetDiaryEntry error: $e');
      return null;
    }
  }

  Future<bool> likeDiaryEntry(String entryId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      await client.from('pet_diary_likes').insert({
        'entry_id': entryId,
        'user_id': uid,
      });
      return true;
    } catch (e) {
      debugPrint('likeDiaryEntry error: $e');
      return false;
    }
  }

  Future<bool> unlikeDiaryEntry(String entryId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      await client
          .from('pet_diary_likes')
          .delete()
          .eq('entry_id', entryId)
          .eq('user_id', uid);
      return true;
    } catch (e) {
      debugPrint('unlikeDiaryEntry error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // FRIENDSHIPS
  // ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchFriends() async {
    final uid = currentUserId;
    if (uid == null) return [];
    try {
      final data = await client
          .from('friendships')
          .select(
            '*, requester:user_profiles!requester_id(*), addressee:user_profiles!addressee_id(*)',
          )
          .or('requester_id.eq.$uid,addressee_id.eq.$uid')
          .eq('status', 'accepted');
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('fetchFriends error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchFriendRequests() async {
    final uid = currentUserId;
    if (uid == null) return [];
    try {
      final data = await client
          .from('friendships')
          .select('*, requester:user_profiles!requester_id(*)')
          .eq('addressee_id', uid)
          .eq('status', 'pending');
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('fetchFriendRequests error: $e');
      return [];
    }
  }

  Future<bool> sendFriendRequest(String addresseeId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      await client.from('friendships').insert({
        'requester_id': uid,
        'addressee_id': addresseeId,
        'status': 'pending',
      });
      // Insert notification for the addressee (belt-and-suspenders alongside DB trigger)
      try {
        final profile = await fetchCurrentUserProfile();
        final requesterName =
            (profile?['full_name'] as String?)?.isNotEmpty == true
            ? profile!['full_name'] as String
            : (profile?['username'] as String? ?? 'Alguém');
        await client.from('notifications').insert({
          'recipient_id': addresseeId,
          'actor_id': uid,
          'type': 'friend_request',
          'title': 'Nova solicitação de amizade',
          'body': '$requesterName quer se conectar com você!',
          'is_read': false,
        });
      } catch (notifError) {
        // Non-critical — notification failure should not block the request
        debugPrint('sendFriendRequest notification error: $notifError');
      }
      return true;
    } catch (e) {
      debugPrint('sendFriendRequest error: $e');
      return false;
    }
  }

  Future<bool> acceptFriendRequest(String friendshipId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      await client
          .from('friendships')
          .update({'status': 'accepted'})
          .eq('id', friendshipId)
          .eq('addressee_id', uid);
      return true;
    } catch (e) {
      debugPrint('acceptFriendRequest error: $e');
      return false;
    }
  }

  Future<bool> declineFriendRequest(String friendshipId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      await client
          .from('friendships')
          .delete()
          .eq('id', friendshipId)
          .eq('addressee_id', uid);
      return true;
    } catch (e) {
      debugPrint('declineFriendRequest error: $e');
      return false;
    }
  }

  /// Returns the friendship status between the current user and [otherUserId].
  /// Possible values: 'accepted', 'pending', 'pending_received', or null (no relation).
  Future<String?> checkFriendshipStatus(String otherUserId) async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final data = await client
          .from('friendships')
          .select('id, status, requester_id, addressee_id')
          .or(
            'and(requester_id.eq.$uid,addressee_id.eq.$otherUserId),and(requester_id.eq.$otherUserId,addressee_id.eq.$uid)',
          )
          .maybeSingle();
      if (data == null) return null;
      final status = data['status'] as String?;
      if (status == 'accepted') return 'accepted';
      if (status == 'pending') {
        // Distinguish: did I send it or did they?
        if (data['requester_id'] == uid) return 'pending_sent';
        return 'pending_received';
      }
      return status;
    } catch (e) {
      debugPrint('checkFriendshipStatus error: $e');
      return null;
    }
  }

  /// Returns true if the current user and [otherUserId] are accepted friends.
  Future<bool> areFriends(String otherUserId) async {
    final status = await checkFriendshipStatus(otherUserId);
    return status == 'accepted';
  }

  /// Removes an accepted friendship between the current user and [otherUserId].
  Future<bool> removeFriend(String otherUserId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      await client
          .from('friendships')
          .delete()
          .or(
            'and(requester_id.eq.$uid,addressee_id.eq.$otherUserId),and(requester_id.eq.$otherUserId,addressee_id.eq.$uid)',
          );
      return true;
    } catch (e) {
      debugPrint('removeFriend error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // CONVERSATIONS & MESSAGES
  // ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchConversations() async {
    final uid = currentUserId;
    if (uid == null) return [];
    try {
      // Step 1: Fetch all conversation_participants rows for this user
      final participantRows = await client
          .from('conversation_participants')
          .select(
            'conversation_id, unread_count, conversation:conversations!conversation_id(*)',
          )
          .eq('user_id', uid)
          .order('conversation_id');

      if (participantRows.isEmpty) return [];

      // Step 2: Collect all conversation IDs for direct (non-group) chats
      final convIds = participantRows
          .map((r) => r['conversation_id'] as String?)
          .whereType<String>()
          .toList();

      // Step 3: Batch-fetch all OTHER participants for these conversations
      // Use SECURITY DEFINER RPC to bypass RLS and always get co-participants
      List<Map<String, dynamic>> otherParticipants = [];
      try {
        final rpcResult = await client.rpc(
          'get_conversation_participants',
          params: {'conv_ids': convIds},
        );
        otherParticipants = (rpcResult as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
      } catch (_) {
        // Fallback to direct query if RPC not available
        try {
          otherParticipants = await client
              .from('conversation_participants')
              .select('conversation_id, user_id')
              .inFilter('conversation_id', convIds)
              .neq('user_id', uid);
        } catch (_) {}
      }

      // Step 4: Collect unique other user IDs
      final otherUserIds = otherParticipants
          .map((r) => r['user_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      // Step 5: Batch-fetch profiles for all other users in one query
      Map<String, Map<String, dynamic>> profilesById = {};
      if (otherUserIds.isNotEmpty) {
        final profiles = await client
            .from('user_profiles')
            .select('id, full_name, username, avatar_url')
            .inFilter('id', otherUserIds);
        for (final p in profiles) {
          final id = p['id'] as String?;
          if (id != null) profilesById[id] = Map<String, dynamic>.from(p);
        }
      }

      // Step 6: Build a map of conversationId -> otherUserId
      final Map<String, String> convToOtherUser = {};
      for (final op in otherParticipants) {
        final convId = op['conversation_id'] as String?;
        final userId = op['user_id'] as String?;
        if (convId != null && userId != null) {
          convToOtherUser[convId] = userId;
        }
      }

      // Step 6b: For conversations where RLS blocked reading other participants,
      // fall back to finding the other user from the messages table
      final missingConvIds = convIds.where((id) {
        final conv = participantRows.firstWhere(
          (r) => r['conversation_id'] == id,
          orElse: () => {},
        );
        final convData = conv['conversation'] as Map<String, dynamic>? ?? {};
        final isGroup = convData['is_group'] as bool? ?? false;
        return !isGroup && !convToOtherUser.containsKey(id);
      }).toList();

      if (missingConvIds.isNotEmpty) {
        try {
          // Find the other sender in messages for these conversations
          final msgRows = await client
              .from('messages')
              .select('conversation_id, sender_id')
              .inFilter('conversation_id', missingConvIds)
              .neq('sender_id', uid)
              .limit(missingConvIds.length * 2);

          for (final msg in msgRows) {
            final convId = msg['conversation_id'] as String?;
            final senderId = msg['sender_id'] as String?;
            if (convId != null &&
                senderId != null &&
                !convToOtherUser.containsKey(convId)) {
              convToOtherUser[convId] = senderId;
              if (!otherUserIds.contains(senderId)) {
                otherUserIds.add(senderId);
              }
            }
          }

          // Fetch profiles for newly discovered user IDs
          final newIds = convToOtherUser.values
              .where((id) => !profilesById.containsKey(id))
              .toSet()
              .toList();
          if (newIds.isNotEmpty) {
            final newProfiles = await client
                .from('user_profiles')
                .select('id, full_name, username, avatar_url')
                .inFilter('id', newIds);
            for (final p in newProfiles) {
              final id = p['id'] as String?;
              if (id != null) profilesById[id] = Map<String, dynamic>.from(p);
            }
          }
        } catch (e) {
          debugPrint('fetchConversations fallback error: $e');
        }
      }

      // Step 7: Enrich each participantRow with the other user's profile
      final enriched = <Map<String, dynamic>>[];
      for (final row in participantRows) {
        final convId = row['conversation_id'] as String?;
        final conv = row['conversation'] as Map<String, dynamic>? ?? {};
        final isGroup = conv['is_group'] as bool? ?? false;

        String? otherUserId;
        String otherName = 'Conversa';
        String otherAvatarUrl = '';

        if (!isGroup && convId != null) {
          otherUserId = convToOtherUser[convId];
          if (otherUserId != null) {
            final profile = profilesById[otherUserId];
            if (profile != null) {
              otherName = (profile['full_name'] as String?)?.isNotEmpty == true
                  ? profile['full_name'] as String
                  : (profile['username'] as String? ?? 'Usuário');
              final rawAvatar = profile['avatar_url'] as String? ?? '';
              // Resolve partial storage paths to full public URLs
              if (rawAvatar.isNotEmpty &&
                  !rawAvatar.startsWith('http://') &&
                  !rawAvatar.startsWith('https://')) {
                try {
                  otherAvatarUrl = client.storage
                      .from('avatars')
                      .getPublicUrl(rawAvatar);
                } catch (_) {
                  otherAvatarUrl = rawAvatar;
                }
              } else {
                otherAvatarUrl = rawAvatar;
              }
            }
          }
        } else if (isGroup) {
          otherName =
              conv['group_name'] as String? ??
              conv['name'] as String? ??
              'Grupo';
          otherAvatarUrl =
              conv['group_image_url'] as String? ??
              conv['avatar_url'] as String? ??
              '';
        }

        enriched.add({
          ...row,
          '_otherUserId': otherUserId,
          '_otherName': otherName,
          '_otherAvatarUrl': otherAvatarUrl,
        });
      }

      return enriched;
    } catch (e) {
      debugPrint('fetchConversations error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchMessages(
    String conversationId,
  ) async {
    try {
      final data = await client
          .from('messages')
          .select('*, sender:user_profiles!sender_id(*)')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('fetchMessages error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> sendMessage({
    required String conversationId,
    required String content,
    String messageType = 'text',
  }) async {
    final uid = currentUserId;
    if (uid == null) return null;
    // Input validation
    final trimmedContent = content.trim();
    if (trimmedContent.isEmpty || trimmedContent.length > 4000) return null;
    try {
      final data = await client
          .from('messages')
          .insert({
            'conversation_id': conversationId,
            'sender_id': uid,
            'content': trimmedContent,
            'message_type': messageType,
          })
          .select('*, sender:user_profiles!sender_id(*)')
          .single();
      return data;
    } catch (e) {
      debugPrint('sendMessage error: $e');
      return null;
    }
  }

  Future<String?> createOrGetDirectConversation(String otherUserId) async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      // Use the SECURITY DEFINER RPC function which bypasses RLS for participant inserts
      final result = await client.rpc(
        'create_direct_conversation',
        params: {'other_user_id': otherUserId},
      );
      if (result != null) {
        return result as String;
      }
      return null;
    } catch (e) {
      debugPrint(
        'createOrGetDirectConversation rpc error: $e — falling back to manual',
      );
      // Fallback: manual approach
      try {
        // Check if conversation already exists
        final myConvs = await client
            .from('conversation_participants')
            .select('conversation_id')
            .eq('user_id', uid);

        final myConvIds = (myConvs as List)
            .map((r) => r['conversation_id'] as String)
            .toList();

        if (myConvIds.isNotEmpty) {
          final existing = await client
              .from('conversation_participants')
              .select('conversation_id')
              .eq('user_id', otherUserId)
              .inFilter('conversation_id', myConvIds)
              .maybeSingle();

          if (existing != null) {
            return existing['conversation_id'] as String;
          }
        }

        // Create new conversation
        final conv = await client
            .from('conversations')
            .insert({'is_group': false})
            .select()
            .single();

        final convId = conv['id'] as String;

        // Insert own participant row first
        await client.from('conversation_participants').insert({
          'conversation_id': convId,
          'user_id': uid,
          'unread_count': 0,
        });

        // Insert other participant row separately
        await client.from('conversation_participants').insert({
          'conversation_id': convId,
          'user_id': otherUserId,
          'unread_count': 0,
        });

        return convId;
      } catch (fallbackError) {
        debugPrint(
          'createOrGetDirectConversation fallback error: $fallbackError',
        );
        return null;
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // GROUPS
  // ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchGroups() async {
    try {
      final data = await client
          .from('groups')
          .select('*, creator:user_profiles!creator_id(*)')
          .eq('is_public', true)
          .order('members_count', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('fetchGroups error: $e');
      return [];
    }
  }

  Future<bool> joinGroup(String groupId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      await client.from('group_members').insert({
        'group_id': groupId,
        'user_id': uid,
      });
      // Use rpc to safely increment counter server-side
      await client.rpc(
        'increment_group_members',
        params: {'group_id_param': groupId},
      );
      return true;
    } catch (e) {
      debugPrint('joinGroup error: $e');
      return false;
    }
  }

  Future<bool> leaveGroup(String groupId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      await client
          .from('group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', uid);
      await client.rpc(
        'decrement_group_members',
        params: {'group_id_param': groupId},
      );
      return true;
    } catch (e) {
      debugPrint('leaveGroup error: $e');
      return false;
    }
  }

  Future<bool> isGroupMember(String groupId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      final data = await client
          .from('group_members')
          .select('id')
          .eq('group_id', groupId)
          .eq('user_id', uid)
          .maybeSingle();
      return data != null;
    } catch (e) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchGroupPosts(String groupId) async {
    try {
      final data = await client
          .from('group_posts')
          .select(
            '*, author:user_profiles!author_id(id, full_name, username, avatar_url)',
          )
          .eq('group_id', groupId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('fetchGroupPosts error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> createGroupPost({
    required String groupId,
    required String content,
    String? imageUrl,
  }) async {
    final uid = currentUserId;
    if (uid == null) return null;
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;
    try {
      final data = await client
          .from('group_posts')
          .insert({
            'group_id': groupId,
            'author_id': uid,
            'content': trimmed,
            if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
          })
          .select(
            '*, author:user_profiles!author_id(id, full_name, username, avatar_url)',
          )
          .single();
      return data;
    } catch (e) {
      debugPrint('createGroupPost error: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> fetchGroupMembers(String groupId) async {
    try {
      final data = await client
          .from('group_members')
          .select(
            '*, member:user_profiles!user_id(id, full_name, username, avatar_url, neurodiv_type)',
          )
          .eq('group_id', groupId);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('fetchGroupMembers error: $e');
      return [];
    }
  }

  Future<bool> createGroup({
    required String name,
    required String description,
    required List<String> tags,
    required bool isPublic,
    String? avatarUrl,
  }) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      final data = await client
          .from('groups')
          .insert({
            'creator_id': uid,
            'name': name.trim(),
            'description': description.trim(),
            'hyperfocus_tags': tags,
            'is_public': isPublic,
            if (avatarUrl != null && avatarUrl.isNotEmpty)
              'cover_url': avatarUrl,
            'members_count': 1,
          })
          .select('id')
          .single();
      final groupId = data['id'] as String;
      // Auto-join creator
      await client.from('group_members').insert({
        'group_id': groupId,
        'user_id': uid,
        'is_admin': true,
      });
      return true;
    } catch (e) {
      debugPrint('createGroup error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // STORIES
  // ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchActiveStories() async {
    try {
      final data = await client
          .from('stories')
          .select('*, author:user_profiles!author_id(*)')
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('fetchActiveStories error: $e');
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────
  // USER DIARY
  // ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchUserPublicDiaryEntries(
    String targetUserId,
  ) async {
    try {
      final uid = currentUserId;
      final data = await client
          .from('user_diary_entries')
          .select()
          .eq('user_id', targetUserId)
          .order('created_at', ascending: false);
      // RLS handles filtering: owner sees all, friends see friends_only, public sees is_private=false
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('fetchUserPublicDiaryEntries error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchDiaryEntries() async {
    final uid = currentUserId;
    if (uid == null) return [];
    try {
      final data = await client
          .from('user_diary_entries')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('fetchDiaryEntries error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> addDiaryEntry({
    required String content,
    String title = '',
    String mood = '',
    List<String> tags = const [],
    bool isPrivate = true,
    bool friendsOnly = true,
  }) async {
    final uid = currentUserId;
    if (uid == null) return null;
    // Input validation
    final trimmedContent = content.trim();
    if (trimmedContent.isEmpty || trimmedContent.length > 10000) return null;
    try {
      final data = await client
          .from('user_diary_entries')
          .insert({
            'user_id': uid,
            'title': title.trim().substring(
              0,
              title.trim().length.clamp(0, 200),
            ),
            'content': trimmedContent,
            'mood': mood,
            'tags': tags,
            'is_private': isPrivate,
            'friends_only': friendsOnly,
          })
          .select()
          .single();
      return data;
    } catch (e) {
      debugPrint('addDiaryEntry error: $e');
      return null;
    }
  }

  Future<bool> updateDiaryEntryVisibility({
    required String entryId,
    required bool isPrivate,
    required bool friendsOnly,
  }) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      await client
          .from('user_diary_entries')
          .update({'is_private': isPrivate, 'friends_only': friendsOnly})
          .eq('id', entryId)
          .eq('user_id', uid);
      return true;
    } catch (e) {
      debugPrint('updateDiaryEntryVisibility error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // REAL-TIME SUBSCRIPTIONS
  // ─────────────────────────────────────────────────────────────

  /// Subscribe to new posts in the feed
  RealtimeChannel subscribeToFeedPosts({
    required void Function(Map<String, dynamic> newPost) onNewPost,
  }) {
    return client
        .channel('public:posts')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'posts',
          callback: (payload) => onNewPost(payload.newRecord),
        )
        .subscribe();
  }

  /// Subscribe to messages in a conversation
  RealtimeChannel subscribeToMessages({
    required String conversationId,
    required void Function(Map<String, dynamic> newMessage) onNewMessage,
  }) {
    return client
        .channel('messages:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) => onNewMessage(payload.newRecord),
        )
        .subscribe();
  }

  /// Subscribe to post likes changes
  RealtimeChannel subscribeToPostLikes({
    required String postId,
    required void Function(PostgresChangePayload payload) onLikeChange,
  }) {
    return client
        .channel('post_likes:$postId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'post_likes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'post_id',
            value: postId,
          ),
          callback: onLikeChange,
        )
        .subscribe();
  }

  /// Subscribe to post comments
  RealtimeChannel subscribeToPostComments({
    required String postId,
    required void Function(Map<String, dynamic> newComment) onNewComment,
  }) {
    return client
        .channel('post_comments:$postId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'post_comments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'post_id',
            value: postId,
          ),
          callback: (payload) => onNewComment(payload.newRecord),
        )
        .subscribe();
  }

  /// Subscribe to friend requests
  RealtimeChannel subscribeToFriendRequests({
    required void Function(Map<String, dynamic> request) onNewRequest,
  }) {
    final uid = currentUserId;
    if (uid == null) {
      return client.channel('noop').subscribe();
    }
    return client
        .channel('friendships:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'friendships',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'addressee_id',
            value: uid,
          ),
          callback: (payload) => onNewRequest(payload.newRecord),
        )
        .subscribe();
  }

  /// Subscribe to pet diary entries
  RealtimeChannel subscribeToPetDiaryFeed({
    required void Function(Map<String, dynamic> newEntry) onNewEntry,
  }) {
    return client
        .channel('public:pet_diary_entries')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'pet_diary_entries',
          callback: (payload) => onNewEntry(payload.newRecord),
        )
        .subscribe();
  }

  // ─────────────────────────────────────────────────────────────
  // SINTONIA AI SESSIONS
  // ─────────────────────────────────────────────────────────────

  /// Fetch the last 100 messages for the current user from sintonia_ai_sessions
  Future<List<Map<String, dynamic>>> fetchSintoniaHistory({
    int limit = 100,
  }) async {
    final uid = currentUserId;
    if (uid == null) return [];
    try {
      final data = await client
          .from('sintonia_ai_sessions')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: true)
          .limit(limit);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('fetchSintoniaHistory error: $e');
      return [];
    }
  }

  /// Persist a single message (user or assistant) to sintonia_ai_sessions
  Future<void> saveSintoniaMessage({
    required String role,
    required String content,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;
    // Security: validate role and content
    if (role != 'user' && role != 'assistant') return;
    final trimmed = content.trim();
    if (trimmed.isEmpty || trimmed.length > 4000) return;
    try {
      await client.from('sintonia_ai_sessions').insert({
        'user_id': uid,
        'role': role,
        'content': trimmed,
      });
    } catch (e) {
      debugPrint('saveSintoniaMessage error: $e');
    }
  }

  /// Delete all SintonIA messages for the current user
  Future<void> clearSintoniaHistory() async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      await client.from('sintonia_ai_sessions').delete().eq('user_id', uid);
    } catch (e) {
      debugPrint('clearSintoniaHistory error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // SECURITY HELPERS
  // ─────────────────────────────────────────────────────────────

  /// Sanitize a text input: trim, limit length, strip null bytes
  static String sanitizeText(String input, {int maxLength = 2000}) {
    return input
        .trim()
        .replaceAll('\\x00', '')
        .substring(0, input.trim().length.clamp(0, maxLength));
  }

  /// Validate that a UUID string is well-formed before using in queries
  static bool isValidUuid(String? value) {
    if (value == null || value.isEmpty) return false;
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuidRegex.hasMatch(value);
  }

  // ─────────────────────────────────────────────────────────────
  // ADMIN / REPORTS (used by admin_dashboard_screen)
  // ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchReports({
    String? status,
    int limit = 50,
  }) async {
    try {
      var query = client
          .from('reports')
          .select(
            '*, reporter:user_profiles!reporter_id(id, full_name, avatar_url), '
            'reported_user:user_profiles!reported_user_id(id, full_name)',
          );
      if (status != null) {
        query = query.eq('status', status);
      }
      final data = await query
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('fetchReports error: $e');
      return [];
    }
  }

  Future<bool> updateReportStatus(String reportId, String newStatus) async {
    final uid = currentUserId;
    if (uid == null) return false;
    if (!isValidUuid(reportId)) return false;
    try {
      await client
          .from('reports')
          .update({'status': newStatus, 'reviewed_by': uid})
          .eq('id', reportId);
      return true;
    } catch (e) {
      debugPrint('updateReportStatus error: $e');
      return false;
    }
  }

  Future<Map<String, int>> fetchAdminKpis() async {
    try {
      final usersResp = await client
          .from('user_profiles')
          .select('id')
          .count(CountOption.exact);
      final postsResp = await client
          .from('posts')
          .select('id')
          .eq('is_published', true)
          .count(CountOption.exact);
      final reportsResp = await client
          .from('reports')
          .select('id')
          .eq('status', 'open')
          .count(CountOption.exact);
      final groupsResp = await client
          .from('groups')
          .select('id')
          .count(CountOption.exact);
      return {
        'users': usersResp.count ?? 0,
        'posts': postsResp.count ?? 0,
        'openReports': reportsResp.count ?? 0,
        'groups': groupsResp.count ?? 0,
      };
    } catch (e) {
      debugPrint('fetchAdminKpis error: $e');
      return {'users': 0, 'posts': 0, 'openReports': 0, 'groups': 0};
    }
  }

  void unsubscribe(RealtimeChannel channel) {
    channel.unsubscribe();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONTENT MODERATION & REPORTS
  // ─────────────────────────────────────────────────────────────────────────

  /// Submit a content report to the reports table.
  /// Supports post reports (reported_post_id) and user reports (reported_user_id).
  /// After inserting the report, sends an in-app notification to the post author
  /// (the DB trigger also handles this, but we do it here as belt-and-suspenders).
  Future<void> submitReport({
    String? reportedUserId,
    required String contentType,
    String? contentId,
    required String reason,
    String? details,
    String? postAuthorId,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;

    // Map reason string to report_reason enum value
    final reasonEnum = _mapReasonToEnum(reason);

    try {
      final Map<String, dynamic> payload = {
        'reporter_id': uid,
        'status': 'pending',
        'reason': reasonEnum,
        if (details != null && details.isNotEmpty) 'description': details,
        'deadline_at': DateTime.now()
            .add(const Duration(hours: 24))
            .toIso8601String(),
      };

      if (contentType == 'post' && contentId != null) {
        payload['reported_post_id'] = contentId;
        if (reportedUserId != null) {
          payload['reported_user_id'] = reportedUserId;
        }
      } else if (contentType == 'comment' && contentId != null) {
        payload['reported_comment_id'] = contentId;
        if (reportedUserId != null) {
          payload['reported_user_id'] = reportedUserId;
        }
      } else if (contentType == 'profile' && reportedUserId != null) {
        payload['reported_user_id'] = reportedUserId;
      }

      await client.from('reports').insert(payload);

      // Belt-and-suspenders: also send notification directly if we have the author id
      // (DB trigger trg_notify_author_on_report handles this automatically too)
      if (contentType == 'post' && contentId != null) {
        final authorId = postAuthorId ?? await _fetchPostAuthorId(contentId);
        if (authorId != null && authorId != uid) {
          try {
            await client.from('notifications').insert({
              'recipient_id': authorId,
              'actor_id': uid,
              'type': 'report',
              'title': '⚠️ Sua publicação foi denunciada',
              'body':
                  'Uma denúncia foi registrada em sua publicação. Você tem 24 horas para editar ou remover o conteúdo. Caso contrário, ele será removido automaticamente.',
              'reference_id': contentId,
              'is_read': false,
            });
          } catch (notifError) {
            debugPrint('submitReport notification error: $notifError');
          }
        }
      }
    } catch (e) {
      debugPrint('submitReport error: $e');
      rethrow;
    }
  }

  /// Maps human-readable reason strings to report_reason enum values.
  String _mapReasonToEnum(String reason) {
    switch (reason.toLowerCase()) {
      case 'discurso de ódio ou discriminação':
        return 'hate_speech';
      case 'assédio, bullying ou ameaças':
        return 'harassment';
      case 'conteúdo explícito ou sexualmente inadequado':
        return 'inappropriate_content';
      case 'spam, fraude ou perfil falso':
        return 'spam';
      default:
        return 'other';
    }
  }

  /// Fetches the author_id of a post by its ID.
  Future<String?> _fetchPostAuthorId(String postId) async {
    try {
      final data = await client
          .from('posts')
          .select('author_id')
          .eq('id', postId)
          .maybeSingle();
      return data?['author_id'] as String?;
    } catch (e) {
      debugPrint('_fetchPostAuthorId error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SINTONIA AI
  // ─────────────────────────────────────────────────────────────────────────

  /// Calls the AI chat completion Lambda to get a SintonIA AI response.
  /// Returns the AI reply text, or null if the call fails.
  Future<String?> callSintoniaAI(String userMessage) async {
    try {
      final response = await getChatCompletion(
        'GEMINI',
        'gemini/gemini-3.7-flash',
        [
          {
            'role': 'system',
            'content':
                'Você é SintonIA, uma IA empática e acolhedora especializada em apoiar pessoas neurodivergentes. '
                'Responda sempre em português brasileiro, com empatia, clareza e sem julgamentos.',
          },
          {'role': 'user', 'content': userMessage},
        ],
        parameters: {'max_tokens': 500},
      );
      return response['choices']?[0]?['message']?['content'] as String?;
    } catch (e) {
      debugPrint('callSintoniaAI error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // LGPD — Consent Logging & Data Export (Art. 7, 8, 18)
  // ─────────────────────────────────────────────────────────────

  /// Logs a consent event to the consent_logs table.
  /// [consentType] — 'terms', 'privacy_policy', 'sensitive_data', etc.
  /// [accepted] — true = accepted, false = revoked.
  Future<void> logConsent({
    required String consentType,
    bool accepted = true,
    String? ipAddress,
    String? userAgent,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      await client.from('consent_logs').insert({
        'user_id': uid,
        'consent_type': consentType,
        'accepted': accepted,
        if (ipAddress != null) 'ip_address': ipAddress,
        if (userAgent != null) 'user_agent': userAgent,
        'accepted_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('logConsent error: $e');
    }
  }

  /// Exports all personal data for the current user (LGPD Art. 18).
  /// Returns a JSON map with profile, posts, friendships, notifications, etc.
  Future<Map<String, dynamic>?> exportUserData() async {
    try {
      final result = await client.rpc('export_user_data');
      if (result == null) return null;
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      debugPrint('exportUserData error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COMPATIBILITY ENGINE (Gemini via Lambda + user_matches persistence)
  // ─────────────────────────────────────────────────────────────────────────

  /// Compares two user profiles using the Gemini AI (via Lambda) and saves
  /// the resulting compatibility score to the [user_matches] table.
  ///
  /// Returns the score (0–100). Falls back to the local Supabase RPC
  /// [calculate_compatibility] if the Lambda call fails.
  Future<int> calculateAndSaveMatchScore({
    required String currentUserId,
    required String targetUserId,
  }) async {
    // 1. Fetch both profiles
    Map<String, dynamic>? userA;
    Map<String, dynamic>? userB;
    try {
      userA = await client
          .from('user_profiles')
          .select('id, full_name, neurodiv_type, hyperfocuses, interests')
          .eq('id', currentUserId)
          .maybeSingle();
      userB = await client
          .from('user_profiles')
          .select('id, full_name, neurodiv_type, hyperfocuses, interests')
          .eq('id', targetUserId)
          .maybeSingle();
    } catch (e) {
      debugPrint('calculateAndSaveMatchScore fetch error: $e');
    }

    int score = 50;

    // 2. Try Gemini via Lambda for AI-powered score
    try {
      if (userA != null && userB != null) {
        final neuroA = userA['neurodiv_type'] ?? 'não informado';
        final neuroB = userB['neurodiv_type'] ?? 'não informado';
        final hyperfocusA = (userA['hyperfocuses'] as List?)?.join(', ') ?? '';
        final hyperfocusB = (userB['hyperfocuses'] as List?)?.join(', ') ?? '';
        final interestsA = (userA['interests'] as List?)?.join(', ') ?? '';
        final interestsB = (userB['interests'] as List?)?.join(', ') ?? '';

        final prompt =
            'Compare esses dois perfis neurodivergentes e retorne APENAS um número inteiro de 0 a 100 '
            'indicando a porcentagem de compatibilidade social e de interesses:\n'
            'Usuário 1: Tipo neurodivergente: $neuroA, Hiperfocos: $hyperfocusA, Interesses: $interestsA\n'
            'Usuário 2: Tipo neurodivergente: $neuroB, Hiperfocos: $hyperfocusB, Interesses: $interestsB\n'
            'Responda SOMENTE com o número, sem texto adicional.';

        final response = await getChatCompletion(
          'GEMINI',
          'gemini/gemini-3.7-flash',
          [
            {'role': 'user', 'content': prompt},
          ],
          parameters: {'max_tokens': 10},
        );
        final text =
            response['choices']?[0]?['message']?['content'] as String? ?? '';
        final cleaned = text.replaceAll(RegExp(r'[^0-9]'), '');
        final parsed = int.tryParse(cleaned);
        if (parsed != null) {
          score = parsed.clamp(0, 100);
        }
      }
    } catch (e) {
      debugPrint(
        'calculateAndSaveMatchScore Lambda error: $e — falling back to RPC',
      );
      // Fallback: use local Supabase RPC
      try {
        final result = await client.rpc(
          'calculate_compatibility',
          params: {'user_a_id': currentUserId, 'user_b_id': targetUserId},
        );
        score = (result as int?) ?? 50;
      } catch (rpcErr) {
        debugPrint('calculateAndSaveMatchScore RPC fallback error: $rpcErr');
      }
    }

    // 3. Persist to user_matches
    try {
      await client.from('user_matches').upsert({
        'user_id_1': currentUserId,
        'user_id_2': targetUserId,
        'compatibility_score': score,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id_1,user_id_2');
    } catch (e) {
      debugPrint('calculateAndSaveMatchScore upsert error: $e');
    }

    return score;
  }
}
