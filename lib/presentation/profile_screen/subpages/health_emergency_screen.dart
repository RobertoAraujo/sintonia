import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/aiIntegrations/chat_completion_service.dart';
import './widgets/nearby_hospitals_map_card.dart';

class HealthEmergencyScreen extends ConsumerStatefulWidget {
  const HealthEmergencyScreen({super.key});

  @override
  ConsumerState<HealthEmergencyScreen> createState() =>
      _HealthEmergencyScreenState();
}

class _HealthEmergencyScreenState extends ConsumerState<HealthEmergencyScreen> {
  String? _aiTip;
  bool _loadingTip = true;

  @override
  void initState() {
    super.initState();
    _loadAiTip();
  }

  Future<void> _loadAiTip() async {
    try {
      final response = await getChatCompletion(
        'GEMINI',
        'gemini/gemini-3.7-flash',
        [
          {
            'role': 'system',
            'content':
                'Você é um assistente de saúde para pessoas neurodivergentes. '
                'Forneça dicas curtas, práticas e acolhedoras. Nunca diagnostique.',
          },
          {
            'role': 'user',
            'content':
                'Dê UMA dica rápida (máx 2 frases) sobre como pessoas neurodivergentes podem se preparar para uma emergência médica. '
                'Seja prático e acolhedor. Use 1 emoji.',
          },
        ],
        parameters: {'temperature': 0.6, 'max_tokens': 100},
      );
      final tip =
          response['choices']?[0]?['message']?['content'] as String? ?? '';
      if (mounted && tip.isNotEmpty) {
        setState(() {
          _aiTip = tip.trim();
          _loadingTip = false;
        });
      } else {
        if (mounted) setState(() => _loadingTip = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTip = false);
    }
  }

  Future<void> _makeCall(BuildContext context, String number) async {
    final Uri launchUri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível iniciar a chamada para o número $number.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Saúde & Emergência 🩺',
          style: TextStyle(
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: const BackButton(color: Color(0xFF1E293B)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Banner de Orientação
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Color(0xFF2563EB)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Se estiver a sentir-se mal ou em perigo imediato, toque num dos botões abaixo para ligar instantaneamente para os serviços de emergência.',
                    style: TextStyle(
                      color: Color(0xFF1E3A8A),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // SintonIA AI Tip Card
          _buildAiTipCard(),

          const SizedBox(height: 16),

          // 1. SAMU (192)
          _buildEmergencyCard(
            context: context,
            title: 'SAMU',
            subtitle: 'Atendimento Médico de Urgência',
            number: '192',
            description:
                'Para crises agudas, convulsões, desmaios e emergências graves.',
            icon: Icons.medical_services_rounded,
            cardColor: const Color(0xFFDC2626),
          ),
          const SizedBox(height: 16),

          // 2. Bombeiros (193)
          _buildEmergencyCard(
            context: context,
            title: 'Corpo de Bombeiros',
            subtitle: 'Resgate e Socorro',
            number: '193',
            description: 'Resgate em acidentes, socorro físico e traumas.',
            icon: Icons.local_fire_department_rounded,
            cardColor: const Color(0xFFEA580C),
          ),
          const SizedBox(height: 16),

          // 3. CVV (188)
          _buildEmergencyCard(
            context: context,
            title: 'CVV',
            subtitle: 'Centro de Valorização da Vida',
            number: '188',
            description:
                'Apoio emocional confidencial e gratuito, disponível 24 horas.',
            icon: Icons.favorite_outline_rounded,
            cardColor: const Color(0xFF9333EA),
          ),
          const SizedBox(height: 16),

          // Mini Mapa — Hospitais e UPAs Próximos
          const NearbyHospitalsMapCard(),

          const SizedBox(height: 32),

          // Rodapé informativo
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_outline, size: 16, color: Color(0xFF64748B)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Esta secção é privada e visível apenas para você.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildAiTipCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withAlpha(50),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('✨', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dica da SintonIA',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                _loadingTip
                    ? Row(
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.white.withAlpha(180),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Carregando dica...',
                            style: TextStyle(
                              color: Colors.white.withAlpha(180),
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        _aiTip ??
                            'Mantenha uma lista de medicamentos e contatos de emergência sempre acessível. 📋',
                        style: TextStyle(
                          color: Colors.white.withAlpha(230),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String number,
    required String description,
    required IconData icon,
    required Color cardColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: cardColor.withAlpha(31),
                  radius: 26,
                  child: Icon(icon, color: cardColor, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: cardColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(
                  Icons.phone_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                label: Text(
                  'Ligar para $number',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                onPressed: () => _makeCall(context, number),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
