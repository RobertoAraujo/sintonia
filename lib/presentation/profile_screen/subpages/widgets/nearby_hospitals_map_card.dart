import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../services/location_service.dart';
import '../../../../services/nearby_emergency_service.dart';

class NearbyHospitalsMapCard extends StatefulWidget {
  const NearbyHospitalsMapCard({super.key});

  @override
  State<NearbyHospitalsMapCard> createState() => _NearbyHospitalsMapCardState();
}

class _NearbyHospitalsMapCardState extends State<NearbyHospitalsMapCard> {
  static const _refreshInterval = Duration(seconds: 60);
  static const _refetchDistanceMeters = 300.0;

  final MapController _mapController = MapController();
  Position? _currentPosition;
  LatLng? _lastFetchOrigin;
  List<EmergencyPlace> _places = [];
  bool _isLoading = true;
  bool _isFetching = false;
  bool _fetchFailed = false;
  EmergencyPlace? _selected;
  StreamSubscription<Position>? _positionSub;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLocation() async {
    setState(() => _isLoading = true);
    final pos = await LocationService.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      _currentPosition = pos;
      _isLoading = false;
    });
    if (pos != null) {
      _fetchPlaces(force: true);
      _startRealtime();
    }
  }

  void _startRealtime() {
    _positionSub?.cancel();
    _refreshTimer?.cancel();

    _positionSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 25,
          ),
        ).listen((pos) {
          if (!mounted) return;
          setState(() => _currentPosition = pos);
          final origin = LatLng(pos.latitude, pos.longitude);
          final last = _lastFetchOrigin;
          if (last == null ||
              NearbyEmergencyService.metersBetween(last, origin) >
                  _refetchDistanceMeters) {
            _fetchPlaces(force: true);
          }
        }, onError: (_) {});

    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      _fetchPlaces(force: true);
    });
  }

  Future<void> _fetchPlaces({bool force = false}) async {
    final pos = _currentPosition;
    if (pos == null || _isFetching) return;
    if (!force && _places.isNotEmpty) return;
    setState(() {
      _isFetching = true;
      _fetchFailed = false;
    });
    try {
      final result = await NearbyEmergencyService.fetchNearby(
        pos.latitude,
        pos.longitude,
      );
      if (!mounted) return;
      setState(() {
        _places = result;
        _lastFetchOrigin = LatLng(pos.latitude, pos.longitude);
        _isFetching = false;
        if (_selected != null && !result.any((p) => p.id == _selected!.id)) {
          _selected = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isFetching = false;
        _fetchFailed = _places.isEmpty;
      });
    }
  }

  Future<void> _openHospitalSearch(double lat, double lng) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/hospital+pronto+socorro/@$lat,$lng,14z',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openRouteTo(EmergencyPlace place) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${place.position.latitude},${place.position.longitude}&travelmode=driving',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Color _colorFor(EmergencyPlaceType type) {
    switch (type) {
      case EmergencyPlaceType.hospital:
        return const Color(0xFFDC2626);
      case EmergencyPlaceType.clinic:
        return const Color(0xFF16A34A);
      case EmergencyPlaceType.fireStation:
        return const Color(0xFFEA580C);
    }
  }

  IconData _iconFor(EmergencyPlaceType type) {
    switch (type) {
      case EmergencyPlaceType.hospital:
        return Icons.local_hospital_rounded;
      case EmergencyPlaceType.clinic:
        return Icons.medical_services_rounded;
      case EmergencyPlaceType.fireStation:
        return Icons.local_fire_department_rounded;
    }
  }

  BoxDecoration get _cardDecoration => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withAlpha(10),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );

  Widget _legendItem(EmergencyPlaceType type, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_iconFor(type), size: 14, color: _colorFor(type)),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 220,
        margin: const EdgeInsets.only(top: 16),
        decoration: _cardDecoration,
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF2563EB)),
        ),
      );
    }

    if (_currentPosition == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.only(top: 16),
        decoration: _cardDecoration,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.location_off_rounded,
              color: Color(0xFF64748B),
              size: 36,
            ),
            const SizedBox(height: 10),
            const Text(
              'Localização desativada',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Ative a localização para visualizar hospitais, postos médicos e bombeiros próximos.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              icon: const Icon(
                Icons.my_location_rounded,
                color: Colors.white,
                size: 18,
              ),
              label: const Text(
                'Ativar Localização',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: _loadLocation,
            ),
          ],
        ),
      );
    }

    final userCoord = LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );

    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
            child: Row(
              children: [
                const Icon(
                  Icons.local_hospital_rounded,
                  color: Color(0xFF2563EB),
                  size: 22,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Hospitais e UPAs Próximos',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _openHospitalSearch(
                    userCoord.latitude,
                    userCoord.longitude,
                  ),
                  child: const Text(
                    'Ver todos',
                    style: TextStyle(color: Color(0xFF2563EB), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _legendItem(EmergencyPlaceType.hospital, 'Hospitais'),
                _legendItem(EmergencyPlaceType.clinic, 'Postos médicos'),
                _legendItem(EmergencyPlaceType.fireStation, 'Bombeiros'),
                if (_isFetching)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF2563EB),
                    ),
                  ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: _selected == null
                ? const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  )
                : BorderRadius.zero,
            child: SizedBox(
              height: 220,
              width: double.infinity,
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: userCoord,
                      initialZoom: 14.0,
                      onTap: (_, __) => setState(() => _selected = null),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.sintonia.app',
                      ),
                      MarkerLayer(
                        markers: [
                          ..._places.map(
                            (p) => Marker(
                              point: p.position,
                              width: 36,
                              height: 36,
                              child: GestureDetector(
                                onTap: () => setState(() => _selected = p),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _colorFor(p.type),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withAlpha(60),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    _iconFor(p.type),
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Marker(
                            point: userCoord,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.my_location_rounded,
                              color: Color(0xFF2563EB),
                              size: 28,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_fetchFailed)
                    Positioned(
                      top: 8,
                      left: 8,
                      right: 8,
                      child: Material(
                        color: Colors.white.withAlpha(235),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Não foi possível carregar as unidades.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => _fetchPlaces(force: true),
                                child: const Text('Tentar de novo'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (!_fetchFailed && !_isFetching && _places.isEmpty)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(235),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Nenhuma unidade encontrada em 5 km.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: FloatingActionButton.extended(
                      heroTag: 'maps_route_btn',
                      backgroundColor: const Color(0xFF2563EB),
                      elevation: 3,
                      icon: const Icon(
                        Icons.directions_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      label: const Text(
                        'Abrir Rotas',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      onPressed: () => _selected != null
                          ? _openRouteTo(_selected!)
                          : _places.isNotEmpty
                          ? _openRouteTo(_places.first)
                          : _openHospitalSearch(
                              userCoord.latitude,
                              userCoord.longitude,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_selected != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _iconFor(_selected!.type),
                    color: _colorFor(_selected!.type),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selected!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        Text(
                          '${_selected!.typeLabel} • ${_selected!.distanceLabel}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
