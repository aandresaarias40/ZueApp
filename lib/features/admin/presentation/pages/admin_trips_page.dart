import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/trip_model.dart';
import '../../../../models/driver_model.dart';
import '../../../../services/trip_service.dart';
import '../../../../services/driver_service.dart';

class AdminTripsPage extends StatefulWidget {
  const AdminTripsPage({super.key});

  @override
  State<AdminTripsPage> createState() => _AdminTripsPageState();
}

class _AdminTripsPageState extends State<AdminTripsPage> {
  final TripService _tripService = TripService();
  final DriverService _driverService = DriverService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Viajes')),
      body: StreamBuilder<List<TripModel>>(
        stream: _tripService.watchAllActiveTrips(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final trips = snapshot.data!;
          if (trips.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.directions_car_outlined,
                      size: 60,
                      color: AppTheme.textSecondary.withOpacity(0.3)),
                  const SizedBox(height: 12),
                  Text('No hay viajes activos',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: trips.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _TripAdminCard(
              trip: trips[i],
              onAssign: () => _showAssignDriverDialog(context, trips[i]),
            ),
          );
        },
      ),
    );
  }

  void _showAssignDriverDialog(BuildContext context, TripModel trip) async {
    final drivers = await _driverService.getNearbyDrivers(
      lat: trip.originLat,
      lng: trip.originLng,
    );

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Asignar conductor',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '${drivers.length} conductor(es) disponible(s) cerca',
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            if (drivers.isEmpty)
              Center(
                child: Text(
                  'No hay conductores disponibles en este momento',
                  style: TextStyle(color: AppTheme.textSecondary),
                  textAlign: TextAlign.center,
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: drivers.length,
                  itemBuilder: (_, i) {
                    final driver = drivers[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            AppTheme.primaryColor.withOpacity(0.1),
                        child: Text(
                          driver.name[0].toUpperCase(),
                          style: const TextStyle(
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      title: Text(driver.name),
                      subtitle: Text(
                          '${driver.vehiclePlate} · ${driver.vehicleType == 'car' ? 'Carro' : 'Moto'}${driver.hasRating ? ' · ⭐ ${driver.rating.toStringAsFixed(1)}' : ''}'),
                      trailing: ElevatedButton(
                        onPressed: () async {
                          await _tripService.manuallyAssignTrip(
                            tripId: trip.id,
                            driverId: driver.id,
                            driverName: driver.name,
                            driverPhone: driver.phone,
                            vehiclePlate: driver.vehiclePlate,
                            vehicleType: driver.vehicleType,
                          );
                          if (mounted) Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(80, 36),
                        ),
                        child: const Text('Asignar'),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TripAdminCard extends StatelessWidget {
  final TripModel trip;
  final VoidCallback onAssign;

  const _TripAdminCard({required this.trip, required this.onAssign});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('h:mm a', 'es_CO');
    final isUnassigned = trip.driverId == null &&
        trip.status == AppConstants.tripStatusRequested;
    final statusLabel = _getStatusLabel(trip.status);
    final statusColor = _getStatusColor(trip.status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUnassigned
              ? AppTheme.warningColor.withOpacity(0.5)
              : AppTheme.dividerColor,
          width: isUnassigned ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                dateFormat.format(trip.createdAt),
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Pasajero
          Row(
            children: [
              const Icon(Icons.person_outline,
                  size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                trip.passengerName,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Ruta
          Text(
            '📍 ${trip.originAddress}',
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '🏁 ${trip.destinationAddress}',
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 12),

          // Conductor o botón asignar
          if (trip.driverName != null)
            Row(
              children: [
                const Icon(Icons.directions_car,
                    size: 16, color: AppTheme.primaryColor),
                const SizedBox(width: 6),
                Text(
                  '${trip.driverName} · ${trip.vehiclePlate}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.primaryColor),
                ),
              ],
            )
          else if (isUnassigned)
            SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton.icon(
                onPressed: onAssign,
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: const Text('Asignar conductor'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.warningColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case AppConstants.tripStatusRequested: return 'Sin asignar';
      case AppConstants.tripStatusAccepted: return 'Asignado';
      case AppConstants.tripStatusInProgress: return 'En curso';
      default: return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case AppConstants.tripStatusRequested: return AppTheme.warningColor;
      case AppConstants.tripStatusAccepted: return AppTheme.primaryColor;
      case AppConstants.tripStatusInProgress: return AppTheme.successColor;
      default: return AppTheme.textSecondary;
    }
  }
}
