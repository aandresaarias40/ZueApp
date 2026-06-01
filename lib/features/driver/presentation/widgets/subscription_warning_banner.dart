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
    // ── Período de prueba activo ──────────────────────────────────────────
    if (driver.isOnTrial) {
      final days = driver.trialDaysRemaining;
      return _Banner(
        color: AppTheme.primaryColor,
        icon: Icons.redeem_outlined,
        message: days > 1
            ? '¡Período de prueba gratuita! Te quedan $days días sin costo.'
            : '¡Último día de prueba gratuita! Activa tu plan para continuar.',
        actionLabel: 'Ver planes',
        onAction: onRenew,
      );
    }

    // ── Suscripción vencida ───────────────────────────────────────────────
    final isExpired = !driver.isSubscriptionActive;
    final isExpiringSoon =
        driver.isSubscriptionActive && driver.daysUntilExpiry <= 3;

    if (!isExpired && !isExpiringSoon) return const SizedBox.shrink();

    final color   = isExpired ? AppTheme.errorColor : AppTheme.warningColor;
    final icon    = isExpired ? Icons.block : Icons.warning_amber;
    final message = isExpired
        ? 'Tu suscripción ha vencido. No puedes recibir viajes.'
        : 'Tu suscripción vence en ${driver.daysUntilExpiry} día(s). ¡Renueva ahora!';

    return _Banner(
      color: color,
      icon: icon,
      message: message,
      actionLabel: 'Renovar',
      onAction: onRenew,
    );
  }
}

// ── Widget interno reutilizable ───────────────────────────────────────────────

class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _Banner({
    required this.color,
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
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
            onTap: onAction,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                actionLabel,
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
