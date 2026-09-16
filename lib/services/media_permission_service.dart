import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class MediaPermissionService {
  const MediaPermissionService._();

  static Future<bool> request({required bool camera, bool video = false}) async {
    if (kIsWeb) return true;

    final permission = camera
        ? Permission.camera
        : video
        ? Permission.videos
        : Permission.photos;
    final status = await permission.request();
    return status.isGranted || status.isLimited;
  }
}