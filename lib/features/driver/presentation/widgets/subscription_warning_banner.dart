import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/driver_model.dart';

class SubscriptionWarningBanner extends StatelessWidget {
  final DriverModel driver;
  final VoidCallback onRenew;

  const SubscriptionWarningBanner({
    super.key,
    required this.driver,
    required this.onRenew,
  });

  @override
  Widget build(BuildContext context) {
    final isExpired = !driver.isSubscriptionActive;
    final isExpiringSoon =
        driver.isSubscriptionActive && driver.daysUntilExpiry <= 3;

    if (!isExpired && !isExpiringSoon) return const SizedBox.shrink();

    final color = isExpired ? AppTheme.errorColor : AppTheme.warningColor;
    final icon = isExpired ? Icons.block : Icons.warning_amber;
    final message = isExpired
        ? 'Tu suscripción ha vencido. No puedes recibir viajes.'
        : 'Tu suscripción vence en ${driver.daysUntilExpiry} día(s). ¡Renueva ahora!';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          GestureDetector(
            onTap: onRenew,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Renovar',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
