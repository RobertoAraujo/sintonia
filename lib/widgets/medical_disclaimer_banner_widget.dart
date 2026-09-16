import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';


/// Reusable medical disclaimer banner for Google Play health content compliance.
/// Shows a prominent warning that SintonIA does NOT replace professional care.
class MedicalDisclaimerBannerWidget extends StatelessWidget {
  /// When true, shows a compact single-line version (for chat header).
  final bool compact;

  const MedicalDisclaimerBannerWidget({super.key, this.compact = false});

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
                  '⚠️ Aviso Importante',
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
            'Nossos recursos e a assistente virtual (IA) NÃO substituem '
            'acompanhamento médico, psicológico ou psiquiátrico profissional.',
            style: GoogleFonts.nunitoSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF856404),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Em caso de crise, ligue para o CVV: 188 (24h, gratuito).',
            style: GoogleFonts.nunitoSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF856404),
            ),
          ),
        ],
      ),
    );
  }
}
