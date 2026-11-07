import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/location_service.dart';

/// A compact emergency card shown in the SintonIA chat when crisis keywords are detected.
class EmergencyActionCard extends StatelessWidget {
  const EmergencyActionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_hospital_rounded,
                  color: Color(0xFF2563EB),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Encontrar hospital com pronto atendimento',
                  style: TextStyle(
                    color: Color(0xFF1E3A8A),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
                elevation: 0,
              ),
              icon: const Icon(
                Icons.directions_rounded,
                color: Colors.white,
                size: 16,
              ),
              label: const Text(
                'Abrir Rota no Google Maps',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: () async {
                final pos = await LocationService.getCurrentPosition();
                if (pos != null) {
                  final uri = Uri.parse(
                    'https://www.google.com/maps/search/hospital+pronto+socorro/@${pos.latitude},${pos.longitude},14z',
                  );
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  // Fallback: open generic hospital search without coordinates
                  final uri = Uri.parse(
                    'https://www.google.com/maps/search/hospital+pronto+socorro',
                  );
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
