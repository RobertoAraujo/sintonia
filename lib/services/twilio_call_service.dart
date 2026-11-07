import 'package:supabase_flutter/supabase_flutter.dart';

/// Service to interact with the Twilio Video token Edge Function
/// and manage call signaling via Supabase Realtime.
class TwilioCallService {
  static final TwilioCallService instance = TwilioCallService._();
  TwilioCallService._();

  final _supabase = Supabase.instance.client;

  /// Generates a Twilio Video Access Token for the given room.
  /// Returns a map with {token, identity, roomName} or throws on error.
  Future<Map<String, dynamic>> generateToken({
    required String roomName,
    required String callType, // 'video' or 'voice'
  }) async {
    final response = await _supabase.functions.invoke(
      'twilio-video-token',
      body: {'roomName': roomName, 'callType': callType},
    );

    if (response.status != 200) {
      throw Exception('Failed to get call token: ${response.data}');
    }

    final data = response.data as Map<String, dynamic>;
    return data;
  }

  /// Sends a call invitation signal via Supabase Realtime broadcast.
  Future<void> sendCallInvitation({
    required String chatId,
    required String callerId,
    required String callerName,
    required String callerAvatar,
    required String calleeId,
    required String roomName,
    required String callType,
  }) async {
    final channel = _supabase.channel('call_signal_$chatId');
    channel.subscribe();
    await channel.sendBroadcastMessage(
      event: 'incoming_call',
      payload: {
        'caller_id': callerId,
        'caller_name': callerName,
        'caller_avatar': callerAvatar,
        'callee_id': calleeId,
        'room_name': roomName,
        'call_type': callType,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    await channel.unsubscribe();
  }

  /// Sends a call response (accepted/rejected) signal.
  Future<void> sendCallResponse({
    required String chatId,
    required String userId,
    required String roomName,
    required bool accepted,
  }) async {
    final channel = _supabase.channel('call_signal_$chatId');
    channel.subscribe();
    await channel.sendBroadcastMessage(
      event: 'call_response',
      payload: {
        'user_id': userId,
        'room_name': roomName,
        'accepted': accepted,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    await channel.unsubscribe();
  }

  /// Sends a call ended signal.
  Future<void> sendCallEnded({
    required String chatId,
    required String roomName,
  }) async {
    final channel = _supabase.channel('call_signal_$chatId');
    channel.subscribe();
    await channel.sendBroadcastMessage(
      event: 'call_ended',
      payload: {
        'room_name': roomName,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    await channel.unsubscribe();
  }
}
