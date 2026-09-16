import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../../core/app_export.dart';
import '../../../services/user_settings_service.dart';
import '../../../theme/app_theme.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<Map<String, dynamic>> _blockedUsers = [];
  bool _isLoading = true;
  final Set<String> _unblockingIds = {};

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    setState(() => _isLoading = true);
    final users = await UserSettingsService.instance.fetchBlockedUsers();
    if (mounted) {
      setState(() {
        _blockedUsers = users;
        _isLoading = false;
      });
    }
  }

  Future<void> _unblockUser(String blockedUserId, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
        ),
        title: const Text('Desbloquear usuário?'),
        content: Text(
          'Deseja desbloquear $displayName? Ele poderá ver seu perfil e enviar mensagens novamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
            ),
            child: const Text(
              'Desbloquear',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _unblockingIds.add(blockedUserId));
    final success = await UserSettingsService.instance.unblockUser(
      blockedUserId,
    );
    if (mounted) {
      setState(() {
        _unblockingIds.remove(blockedUserId);
        if (success) {
          _blockedUsers.removeWhere(
            (u) => u['blocked_user_id'] == blockedUserId,
          );
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? '$displayName foi desbloqueado.'
                : 'Erro ao desbloquear. Tente novamente.',
          ),
          backgroundColor: success ? AppTheme.primary : AppTheme.error,
          behavior: SnackBarBehavior.floating,
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
    final bg = theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Usuários Bloqueados',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _blockedUsers.isEmpty
          ? _buildEmptyState(context)
          : RefreshIndicator(
              onRefresh: _loadBlockedUsers,
              color: AppTheme.primary,
              child: ListView.builder(
                padding: EdgeInsets.symmetric(
                  horizontal: 4.w,
                  vertical: 1.h,
                ).copyWith(bottom: 10.h),
                itemCount: _blockedUsers.length,
                itemBuilder: (context, index) {
                  final item = _blockedUsers[index];
                  final profile =
                      item['user_profiles'] as Map<String, dynamic>?;
                  final blockedUserId =
                      item['blocked_user_id'] as String? ?? '';
                  final fullName =
                      profile?['full_name'] as String? ?? 'Usuário';
                  final username = profile?['username'] as String? ?? '';
                  final avatarUrl = profile?['avatar_url'] as String?;
                  final isUnblocking = _unblockingIds.contains(blockedUserId);

                  return Container(
                    margin: EdgeInsets.only(bottom: 1.h),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withAlpha(120),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(8),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 3.w,
                        vertical: 1.5.h,
                      ),
                      child: Row(
                        children: [
                          // Avatar
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: AppTheme.primary.withAlpha(30),
                            backgroundImage:
                                avatarUrl != null && avatarUrl.isNotEmpty
                                ? CachedNetworkImageProvider(avatarUrl)
                                : null,
                            child: avatarUrl == null || avatarUrl.isEmpty
                                ? Text(
                                    fullName.isNotEmpty
                                        ? fullName[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14.sp,
                                    ),
                                  )
                                : null,
                          ),
                          SizedBox(width: 3.w),
                          // Name & username
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  fullName,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.sp,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (username.isNotEmpty)
                                  Text(
                                    '@$username',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontSize: 11.sp,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          // Unblock button
                          isUnblocking
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : TextButton(
                                  onPressed: () =>
                                      _unblockUser(blockedUserId, fullName),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppTheme.primary,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 2.w,
                                      vertical: 0.5.h,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10.0),
                                      side: BorderSide(
                                        color: AppTheme.primary.withAlpha(120),
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    'Desbloquear',
                                    style: TextStyle(
                                      fontSize: 11.sp,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20.w,
              height: 20.w,
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.block_rounded,
                size: 10.w,
                color: AppTheme.primary.withAlpha(120),
              ),
            ),
            SizedBox(height: 2.h),
            Text(
              'Nenhum usuário bloqueado',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 15.sp,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 0.8.h),
            Text(
              'Quando você bloquear alguém, o usuário aparecerá aqui e você poderá gerenciar os bloqueios.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12.sp,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
