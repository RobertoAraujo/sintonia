import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

enum EmergencyPlaceType { hospital, clinic, fireStation }

class EmergencyPlace {
  final String id;
  final String name;
  final EmergencyPlaceType type;
  final LatLng position;
  final double distanceMeters;

  const EmergencyPlace({
    required this.id,
    required this.name,
    required this.type,
    required this.position,
    required this.distanceMeters,
  });

  String get typeLabel {
    switch (type) {
      case EmergencyPlaceType.hospital:
        return 'Hospital';
      case EmergencyPlaceType.clinic:
        return 'Posto médico';
      case EmergencyPlaceType.fireStation:
        return 'Bombeiros';
    }
  }

  String get distanceLabel => distanceMeters < 1000
      ? '${distanceMeters.round()} m'
      : '${(distanceMeters / 1000).toStringAsFixed(1)} km';
}

class NearbyEmergencyService {
  static const List<String> _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'User-Agent': 'SintonIA/1.0 (com.sintonia.app)'},
    ),
  );

  static Future<List<EmergencyPlace>> fetchNearby(
    double lat,
    double lng, {
    int radiusMeters = 5000,
  }) async {
    final query =
        '''
[out:json][timeout:20];
(
  nwr["amenity"="hospital"](around:$radiusMeters,$lat,$lng);
  nwr["amenity"="clinic"](around:$radiusMeters,$lat,$lng);
  nwr["amenity"="doctors"](around:$radiusMeters,$lat,$lng);
  nwr["healthcare"="centre"](around:$radiusMeters,$lat,$lng);
  nwr["amenity"="fire_station"](around:$radiusMeters,$lat,$lng);
);
out center 80;
''';

    Object? lastError;
    for (final url in _endpoints) {
      try {
        final res = await _dio.post(
          url,
          data: 'data=${Uri.encodeQueryComponent(query)}',
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
        final data = res.data;
        if (data is Map && data['elements'] is List) {
          return _parse(data['elements'] as List, lat, lng);
        }
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('Falha ao buscar unidades próximas: $lastError');
  }

  static List<EmergencyPlace> _parse(List elements, double lat, double lng) {
    final origin = LatLng(lat, lng);
    const distance = Distance();
    final places = <EmergencyPlace>[];
    final seen = <String>{};

    for (final el in elements) {
      if (el is! Map) continue;
      final tags = (el['tags'] as Map?) ?? {};
      double? pLat = (el['lat'] as num?)?.toDouble();
      double? pLng = (el['lon'] as num?)?.toDouble();
      if (pLat == null || pLng == null) {
        final center = el['center'] as Map?;
        pLat = (center?['lat'] as num?)?.toDouble();
        pLng = (center?['lon'] as num?)?.toDouble();
      }
      if (pLat == null || pLng == null) continue;

      EmergencyPlaceType type;
      final amenity = tags['amenity'];
      if (amenity == 'fire_station') {
        type = EmergencyPlaceType.fireStation;
      } else if (amenity == 'hospital') {
        type = EmergencyPlaceType.hospital;
      } else {
        type = EmergencyPlaceType.clinic;
      }

      final fallback = type == EmergencyPlaceType.fireStation
          ? 'Corpo de Bombeiros'
          : type == EmergencyPlaceType.hospital
          ? 'Hospital'
          : 'Posto médico';
      final name = (tags['name'] as String?)?.trim();
      final id = '${el['type']}-${el['id']}';
      if (!seen.add(id)) continue;

      final point = LatLng(pLat, pLng);
      places.add(
        EmergencyPlace(
          id: id,
          name: (name == null || name.isEmpty) ? fallback : name,
          type: type,
          position: point,
          distanceMeters: distance.as(LengthUnit.Meter, origin, point),
        ),
      );
    }

    places.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return places.take(40).toList();
  }

  static double metersBetween(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(h));
  }
}
