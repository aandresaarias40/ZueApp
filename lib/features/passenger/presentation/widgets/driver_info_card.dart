import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/trip_model.dart';

class DriverInfoCard extends StatelessWidget {
  final TripModel trip;

  const DriverInfoCard({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
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

          // Botón llamar
          if (trip.driverPhone != null)
            GestureDetector(
              onTap: () =>
                  launchUrl(Uri.parse('tel:${trip.driverPhone}')),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.successColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.call, color: Colors.white, size: 20),
              ),
            ),
        ],
      ),
    );
  }
}
