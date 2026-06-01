import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/trip_model.dart';
import '../../../../services/trip_service.dart';
import '../../../auth/bloc/auth_bloc.dart';
import '../../../trips/bloc/trip_bloc.dart';

class DriverActiveTripPage extends StatefulWidget {
  final String tripId;
  const DriverActiveTripPage({super.key, required this.tripId});

  @override
  State<DriverActiveTripPage> createState() => _DriverActiveTripPageState();
}

class _DriverActiveTripPageState extends State<DriverActiveTripPage> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  bool _isActionLoading = false;
  final TripService _tripService = TripService();

  @override
  void initState() {
    super.initState();
    // Escuchar cambios del viaje en tiempo real
    context.read<TripBloc>().add(WatchTripEvent(tripId: widget.tripId));
  }

  Future<void> _startTrip() async {
    setState(() => _isActionLoading = true);
    try {
      await _tripService.startTrip(widget.tripId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppTheme.errorColor,
        ));
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _completeTrip(TripModel trip) async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticatedState) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Completar viaje'),
        content: const Text('¿Confirmas que el pasajero llegó a su destino?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sí, completar')),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    setState(() => _isActionLoading = true);
    try {
      await _tripService.completeTrip(
        tripId: widget.tripId,
        driverId: authState.user.id,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppTheme.errorColor,
        ));
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _cancelTrip() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticatedState) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar viaje'),
        content: const Text('¿Estás seguro de que deseas cancelar este viaje?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Cancelar viaje'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    context.read<TripBloc>().add(CancelTripEvent(
          tripId: widget.tripId,
          driverId: authState.user.id,
          reason: 'Cancelado por conductor',
        ));
  }

  void _updateMarkers(TripModel trip) {
    _markers
      ..clear()
      ..add(Marker(
        markerId: const MarkerId('origin'),
        position: LatLng(trip.originLat, trip.originLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Punto de recogida'),
      ))
      ..add(Marker(
        markerId: const MarkerId('destination'),
        position: LatLng(trip.destinationLat, trip.destinationLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Destino'),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocConsumer<TripBloc, TripState>(
        listener: (context, state) {
          if (state is TripCancelledState) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Viaje cancelado'),
              backgroundColor: AppTheme.warningColor,
            ));
            context.go(AppRoutes.driverHome);
          } else if (state is TripCompletedState) {
            _showTripCompletedDialog(state.trip);
          }
        },
        builder: (context, state) {
          final TripModel? tripData = state is TripActiveState
              ? state.trip
              : state is TripAcceptedState
                  ? state.trip
                  : null;

          if (tripData == null) {
            return const Center(child: CircularProgressIndicator());
          }

          _updateMarkers(tripData);

          return Stack(
            children: [
              // Mapa
              GoogleMap(
                onMapCreated: (c) {
                  _mapController = c;
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLngBounds(
                      LatLngBounds(
                        southwest: LatLng(
                          tripData.originLat < tripData.destinationLat
                              ? tripData.originLat
                              : tripData.destinationLat,
                          tripData.originLng < tripData.destinationLng
                              ? tripData.originLng
                              : tripData.destinationLng,
                        ),
                        northeast: LatLng(
                          tripData.originLat > tripData.destinationLat
                              ? tripData.originLat
                              : tripData.destinationLat,
                          tripData.originLng > tripData.destinationLng
                              ? tripData.originLng
                              : tripData.destinationLng,
                        ),
                      ),
                      80,
                    ),
                  );
                },
                initialCameraPosition: CameraPosition(
                  target: LatLng(tripData.originLat, tripData.originLng),
                  zoom: 14,
                ),
                markers: _markers,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
              ),

              // Panel inferior
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24)),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x18000000),
                        blurRadius: 20,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: AppTheme.dividerColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // Estado
                      _StatusBadge(status: tripData.status),
                      const SizedBox(height: 16),

                      // Info pasajero
                      Row(
                        children: [
                          const CircleAvatar(
                            radius: 22,
                            backgroundColor: Color(0xFFF0F4FF),
                            child: Icon(Icons.person,
                                color: AppTheme.primaryColor),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tripData.passengerName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Text('Pasajero',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary)),
                              ],
                            ),
                          ),
                          if (tripData.fare != null)
                            Text(
                              '\$${tripData.fare!.toStringAsFixed(0)} COP',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Ruta
                      _RouteInfo(trip: tripData),
                      const SizedBox(height: 20),

                      // Botones de acción
                      if (_isActionLoading)
                        const CircularProgressIndicator()
                      else
                        _ActionButtons(
                          status: tripData.status,
                          onStart: _startTrip,
                          onComplete: () => _completeTrip(tripData),
                          onCancel: _cancelTrip,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showTripCompletedDialog(TripModel trip) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.successColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle,
                  color: AppTheme.successColor, size: 44),
            ),
            const SizedBox(height: 16),
            const Text('¡Viaje completado!',
                style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (trip.fare != null)
              Text(
                '\$${trip.fare!.toStringAsFixed(0)} COP',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryColor,
                ),
              ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go(AppRoutes.driverHome);
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(160, 48),
            ),
            child: const Text('Volver al inicio'),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final config = _config(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: (config['color'] as Color).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(config['icon'] as IconData,
              color: config['color'] as Color, size: 18),
          const SizedBox(width: 8),
          Text(
            config['label'] as String,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: config['color'] as Color,
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _config(String status) {
    switch (status) {
      case AppConstants.tripStatusAccepted:
        return {
          'label': 'Ve al punto de recogida',
          'icon': Icons.navigation,
          'color': AppTheme.primaryColor,
        };
      case AppConstants.tripStatusInProgress:
        return {
          'label': 'Viaje en curso',
          'icon': Icons.drive_eta,
          'color': AppTheme.successColor,
        };
      default:
        return {
          'label': 'Viaje activo',
          'icon': Icons.directions_car,
          'color': AppTheme.primaryColor,
        };
    }
  }
}

class _RouteInfo extends StatelessWidget {
  final TripModel trip;
  const _RouteInfo({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.circle, size: 10, color: AppTheme.successColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(trip.originAddress,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.more_vert, size: 14, color: AppTheme.textSecondary),
          ),
          Row(
            children: [
              const Icon(Icons.location_on, size: 12, color: AppTheme.errorColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(trip.destinationAddress,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final String status;
  final VoidCallback onStart;
  final VoidCallback onComplete;
  final VoidCallback onCancel;

  const _ActionButtons({
    required this.status,
    required this.onStart,
    required this.onComplete,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    if (status == AppConstants.tripStatusAccepted) {
      // El conductor va a recoger al pasajero
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Iniciar viaje (recogí al pasajero)'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.close, color: AppTheme.errorColor),
              label: const Text('Cancelar viaje'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.errorColor,
                side: const BorderSide(color: AppTheme.errorColor),
              ),
            ),
          ),
        ],
      );
    } else if (status == AppConstants.tripStatusInProgress) {
      // El viaje está en curso
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: onComplete,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Completar viaje'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.successColor,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
