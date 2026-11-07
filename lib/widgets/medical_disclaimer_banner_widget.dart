import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

/// Reusable medical disclaimer banner for Google Play health content compliance.
/// Shows a prominent warning that SintonIA does NOT replace professional care.
class MedicalDisclaimerBannerWidget extends StatelessWidget {
  /// When true, shows a compact single-line version (for chat header).
  final bool compact;

  const MedicalDisclaimerBannerWidget({super.key, this.compact = false});

  Future<void> _callNumber(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (compact) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        color: const Color(0xFFFFF3CD),
        child: Row(
          children: [
            const Icon(
              Icons.health_and_safety_outlined,
              color: Color(0xFF856404),
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'A SintonIA NÃO substitui acompanhamento médico ou psicológico profissional.',
                style: GoogleFonts.nunitoSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF856404),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF856404).withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.health_and_safety_outlined,
                  color: Color(0xFF856404),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '⚠️ Aviso Médico Importante',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF856404),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'O SintonIA é uma rede social de acolhimento e suporte comunitário. '
            'Nenhum recurso do aplicativo, incluindo a assistente virtual (IA), '
            'substitui consultas, diagnósticos ou tratamentos médicos, psicológicos '
            'ou psiquiátricos profissionais.',
            style: GoogleFonts.nunitoSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF856404),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Em caso de crise de saúde mental, busque ajuda imediatamente:',
            style: GoogleFonts.nunitoSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF856404),
            ),
          ),
          const SizedBox(height: 10),
          _EmergencyCallTile(
            icon: Icons.phone_outlined,
            title: 'CVV — Centro de Valorização da Vida',
            subtitle: '24h por dia, gratuito',
            number: '188',
            buttonColor: const Color(0xFF2E7D32),
            onTap: () => _callNumber('188'),
          ),
          const SizedBox(height: 8),
          _EmergencyCallTile(
            icon: Icons.add_box_outlined,
            title: 'SAMU — Serviço de Atendimento Móvel',
            subtitle: 'Emergências médicas',
            number: '192',
            buttonColor: const Color(0xFFC62828),
            onTap: () => _callNumber('192'),
          ),
          const SizedBox(height: 8),
          _EmergencyCallTile(
            icon: Icons.local_fire_department_outlined,
            title: 'Bombeiros / Emergência Geral',
            subtitle: 'Situações de risco de vida',
            number: '193',
            buttonColor: const Color(0xFFE65100),
            onTap: () => _callNumber('193'),
          ),
        ],
      ),
    );
  }
}

class _EmergencyCallTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String number;
  final Color buttonColor;
  final VoidCallback onTap;

  const _EmergencyCallTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.number,
    required this.buttonColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(180),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFFD700).withAlpha(120)),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF856404), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF4A3700),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF856404),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: buttonColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    number,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
