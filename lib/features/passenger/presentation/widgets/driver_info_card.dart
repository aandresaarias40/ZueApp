import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/trip_model.dart';

class DriverInfoCard extends StatelessWidget {
  final TripModel trip;

  const DriverInfoCard({super.key, required this.trip});

  /// Limpia el número dejando solo dígitos y lo normaliza a formato colombiano
  /// para WhatsApp: +57XXXXXXXXXX
  String _waNumber(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    // Si ya tiene código de país (57 + 10 dígitos = 12)
    if (digits.length == 12 && digits.startsWith('57')) return digits;
    // Si tiene 10 dígitos (número local colombiano)
    if (digits.length == 10) return '57$digits';
    return digits;
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _whatsapp(String phone) async {
    final number = _waNumber(phone);
    final uri = Uri.parse('https://wa.me/$number');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = trip.driverPhone;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        children: [
          // Avatar del conductor
          CircleAvatar(
            radius: 26,
            backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
            child: const Icon(
              Icons.person,
              color: AppTheme.primaryColor,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),

          // Info del conductor
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.driverName ?? 'Conductor',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        trip.vehiclePlate ?? '-',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryColor,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      trip.vehicleType == 'moto'
                          ? Icons.two_wheeler
                          : Icons.directions_car,
                      size: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Botones de contacto (solo cuando hay teléfono)
          if (phone != null) ...[
            // WhatsApp
            _ContactButton(
              color: const Color(0xFF25D366),
              icon: Icons.chat,
              onTap: () => _whatsapp(phone),
              tooltip: 'WhatsApp',
            ),
            const SizedBox(width: 8),
            // Llamada
            _ContactButton(
              color: AppTheme.successColor,
              icon: Icons.call,
              onTap: () => _call(phone),
              tooltip: 'Llamar',
            ),
          ],
        ],
      ),
    );
  }
}

class _ContactButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _ContactButton({
    required this.color,
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}
