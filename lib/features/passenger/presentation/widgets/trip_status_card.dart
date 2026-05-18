import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';

class TripStatusCard extends StatelessWidget {
  final String status;

  const TripStatusCard({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final config = _getStatusConfig(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: config['color'].withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(config['icon'], color: config['color'], size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  config['title'],
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: config['color'],
                  ),
                ),
                Text(
                  config['subtitle'],
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (status == AppConstants.tripStatusRequested)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: config['color'],
              ),
            ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getStatusConfig(String status) {
    switch (status) {
      case AppConstants.tripStatusRequested:
        return {
          'title': 'Buscando conductor...',
          'subtitle': 'Estamos buscando un conductor cerca de ti',
          'icon': Icons.search,
          'color': AppTheme.warningColor,
        };
      case AppConstants.tripStatusAccepted:
        return {
          'title': 'Conductor en camino',
          'subtitle': 'Tu conductor está yendo a recogerte',
          'icon': Icons.directions_car,
          'color': AppTheme.primaryColor,
        };
      case AppConstants.tripStatusInProgress:
        return {
          'title': 'Viaje en curso',
          'subtitle': 'Estás en camino a tu destino',
          'icon': Icons.navigation,
          'color': AppTheme.successColor,
        };
      case AppConstants.tripStatusCompleted:
        return {
          'title': '¡Llegaste!',
          'subtitle': 'Tu viaje ha finalizado exitosamente',
          'icon': Icons.check_circle,
          'color': AppTheme.successColor,
        };
      case AppConstants.tripStatusCancelled:
        return {
          'title': 'Viaje cancelado',
          'subtitle': 'El viaje fue cancelado',
          'icon': Icons.cancel,
          'color': AppTheme.errorColor,
        };
      default:
        return {
          'title': 'En proceso',
          'subtitle': '',
          'icon': Icons.info_outline,
          'color': AppTheme.textSecondary,
        };
    }
  }
}
