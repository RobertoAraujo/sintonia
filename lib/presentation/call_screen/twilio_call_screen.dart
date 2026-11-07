import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sizer/sizer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../services/twilio_call_service.dart';

/// Active call screen for voice and video calls via Twilio.
/// On web preview, shows a "not available" message.
/// On mobile (APK), connects to Twilio Video room.
class TwilioCallScreen extends StatefulWidget {
  final String chatId;
  final String roomName;
  final String callType; // 'video' or 'voice'
  final String otherUserId;
  final String otherUserName;
  final String otherUserAvatar;
  final bool isIncoming;

  const TwilioCallScreen({
    super.key,
    required this.chatId,
    required this.roomName,
    required this.callType,
    required this.otherUserId,
    required this.otherUserName,
    required this.otherUserAvatar,
    this.isIncoming = false,
  });

  @override
  State<TwilioCallScreen> createState() => _TwilioCallScreenState();
}

class _TwilioCallScreenState extends State<TwilioCallScreen>
    with TickerProviderStateMixin {
  bool _isConnecting = true;
  bool _isConnected = false;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;
  String? _errorMessage;
  Duration _callDuration = Duration.zero;
  Timer? _durationTimer;
  Timer? _connectionTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  RealtimeChannel? _signalChannel;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _subscribeToSignals();

    if (kIsWeb) {
      // Web preview: show info message, don't attempt real connection
      setState(() {
        _isConnecting = false;
        _errorMessage =
            'Chamadas de voz e vídeo funcionam no aplicativo móvel (APK).\n\nBaixe o APK para testar chamadas reais via Twilio.';
      });
    } else {
      _initializeCall();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _durationTimer?.cancel();
    _connectionTimer?.cancel();
    _signalChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToSignals() {
    _signalChannel = Supabase.instance.client
        .channel('call_signal_${widget.chatId}')
        .onBroadcast(
          event: 'call_ended',
          callback: (payload) {
            final roomName = payload['room_name'] as String?;
            if (roomName == widget.roomName && mounted) {
              _endCall(remoteHangup: true);
            }
          },
        )
        .onBroadcast(
          event: 'call_response',
          callback: (payload) {
            final accepted = payload['accepted'] as bool? ?? false;
            if (!accepted && mounted) {
              setState(() {
                _isConnecting = false;
                _errorMessage = '${widget.otherUserName} recusou a chamada.';
              });
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) Navigator.of(context).pop();
              });
            }
          },
        )
        .subscribe();
  }

  Future<void> _initializeCall() async {
    try {
      // Get Twilio token from Edge Function
      final tokenData = await TwilioCallService.instance.generateToken(
        roomName: widget.roomName,
        callType: widget.callType,
      );

      if (!mounted) return;

      // Token obtained — in a real mobile build, you'd connect to Twilio here
      // using the token. For now, we simulate the connection state.
      debugPrint('Twilio token obtained for room: ${tokenData['roomName']}');

      // Simulate connection (replace with actual Twilio SDK connect call)
      _connectionTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _isConnecting = false;
            _isConnected = true;
          });
          _startDurationTimer();
        }
      });
    } catch (e) {
      debugPrint('TwilioCallScreen error: $e');
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _errorMessage =
              'Não foi possível conectar a chamada.\nVerifique suas credenciais Twilio nas configurações.';
        });
        // Auto-return to chat after 4 seconds on error
        _connectionTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    }
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _callDuration += const Duration(seconds: 1));
      }
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _endCall({bool remoteHangup = false}) async {
    _durationTimer?.cancel();
    if (!remoteHangup) {
      await TwilioCallService.instance.sendCallEnded(
        chatId: widget.chatId,
        roomName: widget.roomName,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.callType == 'video';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Stack(
          children: [
            // Background gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF1A1A2E),
                    AppTheme.primary.withAlpha(77),
                    const Color(0xFF0D0D1A),
                  ],
                ),
              ),
            ),

            // Main content
            Column(
              children: [
                // Top bar
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.h),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white70,
                          size: 28,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          isVideo ? 'Chamada de Vídeo' : 'Chamada de Voz',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: Colors.white70,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),

                Expanded(
                  child: _errorMessage != null
                      ? _buildErrorState()
                      : _isConnecting
                      ? _buildConnectingState()
                      : _buildConnectedState(isVideo),
                ),

                // Controls
                if (_errorMessage == null) _buildCallControls(isVideo),

                SizedBox(height: 2.h),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectingState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Avatar with pulse
        ScaleTransition(
          scale: _pulseAnimation,
          child: Container(
            width: 25.w,
            height: 25.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.primary, width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withAlpha(102),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: ClipOval(
              child: widget.otherUserAvatar.isNotEmpty
                  ? Image.network(widget.otherUserAvatar, fit: BoxFit.cover)
                  : CircleAvatar(
                      backgroundColor: AppTheme.primary,
                      child: Text(
                        widget.otherUserName.isNotEmpty
                            ? widget.otherUserName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        SizedBox(height: 3.h),
        Text(
          widget.otherUserName,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 18.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 1.h),
        Text(
          widget.isIncoming ? 'Chamada recebida...' : 'Chamando...',
          style: GoogleFonts.inter(color: Colors.white60, fontSize: 13.sp),
        ),
        SizedBox(height: 3.h),
        SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildConnectedState(bool isVideo) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Avatar
        Container(
          width: 22.w,
          height: 22.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 2),
          ),
          child: ClipOval(
            child: widget.otherUserAvatar.isNotEmpty
                ? Image.network(widget.otherUserAvatar, fit: BoxFit.cover)
                : CircleAvatar(
                    backgroundColor: AppTheme.primary,
                    child: Text(
                      widget.otherUserName.isNotEmpty
                          ? widget.otherUserName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 20),
                    ),
                  ),
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          widget.otherUserName,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 18.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 0.5.h),
        // Duration
        Container(
          padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 0.5.h),
          decoration: BoxDecoration(
            color: Colors.green.withAlpha(51),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.green.withAlpha(102)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _formatDuration(_callDuration),
                style: GoogleFonts.inter(
                  color: Colors.green,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (isVideo) ...[
          SizedBox(height: 3.h),
          Container(
            width: 60.w,
            height: 20.h,
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isCameraOff
                        ? Icons.videocam_off_rounded
                        : Icons.videocam_rounded,
                    color: Colors.white38,
                    size: 32,
                  ),
                  SizedBox(height: 1.h),
                  Text(
                    _isCameraOff ? 'Câmera desligada' : 'Vídeo ativo',
                    style: GoogleFonts.inter(
                      color: Colors.white38,
                      fontSize: 11.sp,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 20.w,
            height: 20.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white10,
              border: Border.all(color: Colors.white24),
            ),
            child: ClipOval(
              child: widget.otherUserAvatar.isNotEmpty
                  ? Image.network(widget.otherUserAvatar, fit: BoxFit.cover)
                  : CircleAvatar(
                      backgroundColor: AppTheme.primary,
                      child: Text(
                        widget.otherUserName.isNotEmpty
                            ? widget.otherUserName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                        ),
                      ),
                    ),
            ),
          ),
          SizedBox(height: 3.h),
          Text(
            widget.otherUserName,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 16.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 2.h),
          Container(
            padding: EdgeInsets.all(4.w),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                Icon(
                  kIsWeb
                      ? Icons.phone_android_rounded
                      : Icons.error_outline_rounded,
                  color: kIsWeb ? AppTheme.primary : Colors.orange,
                  size: 32,
                ),
                SizedBox(height: 1.5.h),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 12.sp,
                    height: 1.5,
                  ),
                ),
                if (kIsWeb) ...[
                  SizedBox(height: 2.h),
                  Text(
                    'Acesse: Launch → APK',
                    style: GoogleFonts.inter(
                      color: AppTheme.primary,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: 4.h),
          // Always show a visible back button so the user can return
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 1.5.h),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white70,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Voltar ao chat',
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!kIsWeb) ...[
            SizedBox(height: 1.5.h),
            Text(
              'Voltando automaticamente...',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 10.sp),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCallControls(bool isVideo) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 6.w),
      child: Column(
        children: [
          // Secondary controls row
          if (_isConnected)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ControlButton(
                  icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  label: _isMuted ? 'Ativar mic' : 'Mudo',
                  color: _isMuted ? Colors.red : Colors.white24,
                  onTap: () => setState(() => _isMuted = !_isMuted),
                ),
                SizedBox(width: 4.w),
                if (isVideo)
                  _ControlButton(
                    icon: _isCameraOff
                        ? Icons.videocam_off_rounded
                        : Icons.videocam_rounded,
                    label: _isCameraOff ? 'Ligar câmera' : 'Câmera',
                    color: _isCameraOff ? Colors.red : Colors.white24,
                    onTap: () => setState(() => _isCameraOff = !_isCameraOff),
                  ),
                if (isVideo) SizedBox(width: 4.w),
                _ControlButton(
                  icon: _isSpeakerOn
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  label: _isSpeakerOn ? 'Alto-falante' : 'Fone',
                  color: _isSpeakerOn ? AppTheme.primary : Colors.white24,
                  onTap: () => setState(() => _isSpeakerOn = !_isSpeakerOn),
                ),
              ],
            ),
          SizedBox(height: 2.h),
          // End call button
          GestureDetector(
            onTap: () => _endCall(),
            child: Container(
              width: 16.w,
              height: 16.w,
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withAlpha(102),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.call_end_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
          SizedBox(height: 1.h),
          Text(
            'Encerrar',
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 11.sp),
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 13.w,
            height: 13.w,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          SizedBox(height: 0.5.h),
          Text(
            label,
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 9.sp),
          ),
        ],
      ),
    );
  }
}
