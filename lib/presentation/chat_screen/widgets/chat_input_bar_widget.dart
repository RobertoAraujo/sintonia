import 'package:flutter/material.dart';

import '../../../core/app_export.dart';
import '../../../theme/app_theme.dart';

class ChatInputBarWidget extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const ChatInputBarWidget({
    super.key,
    required this.controller,
    required this.onSend,
  });

  @override
  State<ChatInputBarWidget> createState() => _ChatInputBarWidgetState();
}

class _ChatInputBarWidgetState extends State<ChatInputBarWidget>
    with SingleTickerProviderStateMixin {
  bool _hasText = false;
  bool _isFocused = false;
  late AnimationController _sendBtnCtrl;
  late Animation<double> _sendBtnScale;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _sendBtnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _sendBtnScale = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _sendBtnCtrl, curve: Curves.elasticOut));
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
      if (hasText) {
        _sendBtnCtrl.forward();
      } else {
        _sendBtnCtrl.reverse();
      }
    }
  }

  void _onFocusChanged() {
    setState(() => _isFocused = _focusNode.hasFocus);
  }

  void _handleSend() {
    if (!_hasText) return;
    widget.onSend();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _sendBtnCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: _isFocused
                ? AppTheme.primary.withAlpha(80)
                : theme.colorScheme.outlineVariant,
            width: _isFocused ? 1.5 : 1.0,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Attachment button
          _IconBtn(
            icon: Icons.add_circle_outline_rounded,
            color: theme.colorScheme.onSurfaceVariant,
            onTap: () {},
          ),
          const SizedBox(width: 4),

          // Text input container
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _isFocused
                      ? AppTheme.primary.withAlpha(100)
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 4,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _handleSend(),
                      decoration: InputDecoration(
                        hintText: 'Escreva uma mensagem...',
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  _IconBtn(
                    icon: Icons.sentiment_satisfied_alt_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                    onTap: () {},
                    padding: const EdgeInsets.only(right: 4, bottom: 4),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Send / mic button
          AnimatedBuilder(
            animation: _sendBtnScale,
            builder: (context, _) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Mic button (shown when no text)
                  Opacity(
                    opacity: (1.0 - _sendBtnScale.value).clamp(0.0, 1.0),
                    child: _SendCircleBtn(
                      color: theme.colorScheme.surfaceContainerHighest,
                      iconColor: theme.colorScheme.onSurfaceVariant,
                      icon: Icons.mic_rounded,
                      onTap: () {},
                    ),
                  ),
                  // Send button (shown when has text)
                  Transform.scale(
                    scale: _sendBtnScale.value,
                    child: _SendCircleBtn(
                      color: AppTheme.primary,
                      iconColor: Colors.white,
                      icon: Icons.send_rounded,
                      onTap: _handleSend,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final EdgeInsets? padding;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(6),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}

class _SendCircleBtn extends StatefulWidget {
  final Color color;
  final Color iconColor;
  final IconData icon;
  final VoidCallback onTap;

  const _SendCircleBtn({
    required this.color,
    required this.iconColor,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_SendCircleBtn> createState() => _SendCircleBtnState();
}

class _SendCircleBtnState extends State<_SendCircleBtn>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.85,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
          child: Icon(widget.icon, color: widget.iconColor, size: 20),
        ),
      ),
    );
  }
}
