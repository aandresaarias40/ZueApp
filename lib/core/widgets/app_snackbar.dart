import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Tipo de notificación, define color e ícono del SnackBar.
enum _SnackType { error, success, warning, info }

/// Helper para mostrar SnackBars con un diseño consistente en toda la app:
/// tarjeta oscura redondeada, ícono a color según el tipo, márgenes y
/// comportamiento flotante. Reemplaza los bloques de color planos.
///
/// Uso:
///   AppSnackBar.error(context, 'Correo o contraseña incorrectos.');
///   AppSnackBar.success(context, '¡Pago aprobado!');
///   AppSnackBar.warning(context, 'El viaje fue cancelado');
///   AppSnackBar.info(context, 'Cargando datos...');
class AppSnackBar {
  AppSnackBar._();

  static void error(BuildContext context, String message) =>
      _show(context, message, _SnackType.error);

  static void success(BuildContext context, String message) =>
      _show(context, message, _SnackType.success);

  static void warning(BuildContext context, String message) =>
      _show(context, message, _SnackType.warning);

  static void info(BuildContext context, String message) =>
      _show(context, message, _SnackType.info);

  static void _show(BuildContext context, String message, _SnackType type) {
    final (Color accent, IconData icon) = switch (type) {
      _SnackType.error => (AppTheme.errorColor, Icons.error_outline_rounded),
      _SnackType.success => (
          AppTheme.successColor,
          Icons.check_circle_outline_rounded
        ),
      _SnackType.warning => (
          AppTheme.warningColor,
          Icons.warning_amber_rounded
        ),
      _SnackType.info => (AppTheme.primaryColor, Icons.info_outline_rounded),
    };

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.textPrimary,
          behavior: SnackBarBehavior.floating,
          elevation: 4,
          duration: const Duration(seconds: 4),
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }
}
