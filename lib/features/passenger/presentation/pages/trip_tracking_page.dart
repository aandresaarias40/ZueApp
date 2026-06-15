import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../models/trip_model.dart';
import '../../../trips/bloc/trip_bloc.dart';
import '../widgets/trip_status_card.dart';
import '../widgets/driver_info_card.dart';
import '../widgets/rating_dialog.dart';

class TripTrackingPage extends StatefulWidget {
  final String tripId;
  const TripTrackingPage({super.key, required this.tripId});

  @override
  State<TripTrackingPage> createState() => _TripTrackingPageState();
}

class _TripTrackingPageState extends State<TripTrackingPage> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};

  // Timeout: cancela automáticamente si el viaje lleva más de 5 min sin conductor
  static const _timeoutDuration = Duration(minutes: 5);
  Timer? _timeoutTimer;
  bool _timeoutDialogShown = false;

  @override
  void initState() {
    super.initState();
    context.read<TripBloc>().add(WatchTripEvent(tripId: widget.tripId));
    _startTimeoutTimer();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _startTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_timeoutDuration, _onTimeout);
  }

  void _cancelTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  void _onTimeout() {
    if (!mounted || _timeoutDialogShown) return;
    _timeoutDialogShown = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.timer_off_outlined, color: AppTheme.warningColor),
            SizedBox(width: 10),
            Text('Sin respuesta'),
          ],
        ),
        content: const Text(
          'No encontramos un conductor disponible en los últimos 5 minutos.\n\n'
          'Tu solicitud ha sido cancelada sin costo.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<TripBloc>().add(CancelTripEvent(
                    tripId: widget.tripId,
                    reason: 'Timeout: sin conductor en 5 minutos',
                  ));
              context.go(AppRoutes.passengerHome);
            },
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocConsumer<TripBloc, TripState>(
        listener: (context, state) {
          // Cuando el conductor acepta, el timeout ya no aplica
          if (state is TripAcceptedState || state is TripActiveState) {
            _cancelTimeoutTimer();
          }
          if (state is TripCompletedState) {
            // Mostrar diálogo de calificación
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => RatingDialog(
                driverName: state.trip.driverName ?? 'Conductor',
                onRated: (rating, comment) {
                  context.read<TripBloc>().add(RateTripEvent(
                        tripId: state.trip.id,
                        driverId: state.trip.driverId!,
                        rating: rating,
                        comment: comment,
                      ));
                  context.go(AppRoutes.passengerHome);
                },
              ),
            );
          } else if (state is TripCancelledState) {
            AppSnackBar.warning(context, 'El viaje fue cancelado');
            context.go(AppRoutes.passengerHome);
          }
        },
        builder: (context, state) {
          // Mientras el stream se establece, puede llegar TripRequestedState
          // desde la pantalla anterior. Usamos ese trip si está disponible.
          final TripModel? tripData = state is TripActiveState
              ? state.trip
              : state is TripRequestedState
                  ? state.trip
                  : null;

          if (tripData == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final trip = tripData;
          _updateMarkers(trip);

          return Stack(
            children: [
              // Mapa
              GoogleMap(
                onMapCreated: (controller) {
                  _mapController = controller;
                  _centerMap(trip);
                },
                initialCameraPosition: CameraPosition(
                  target: LatLng(trip.originLat, trip.originLng),
                  zoom: 14,
                ),
                markers: _markers,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
              ),

              // Botón atrás (sólo visible en estados post-aceptación)
              if (trip.status != AppConstants.tripStatusRequested)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () => context.go(AppRoutes.passengerHome),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Panel de información del viaje
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24)),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x15000000),
                        blurRadius: 20,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Indicador de arrastre
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.dividerColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),

                      // Estado del viaje
                      TripStatusCard(status: trip.status),
                      const SizedBox(height: 16),

                      // Info del conductor (si fue asignado)
                      if (trip.driverId != null)
                        DriverInfoCard(trip: trip),

                      // Detalles del viaje
                      const SizedBox(height: 16),
                      _TripRouteInfo(trip: trip),

                      if (trip.fare != null) ...[
                        const SizedBox(height: 12),
                        _FareInfo(fare: trip.fare!),
                      ],

                      // Botón cancelar — prominente cuando se está buscando conductor
                      if (trip.status == AppConstants.tripStatusRequested) ...[
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton.icon(
                            onPressed: () => _showCancelDialog(context, trip),
                            icon: const Icon(
                              Icons.cancel_outlined,
                              color: AppTheme.errorColor,
                            ),
                            label: const Text(
                              'Cancelar búsqueda',
                              style: TextStyle(
                                color: AppTheme.errorColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: AppTheme.errorColor,
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Puedes cancelar sin costo mientras buscamos conductor',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
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

  void _updateMarkers(TripModel trip) {
    _markers.clear();
    _markers.add(Marker(
      markerId: const MarkerId('origin'),
      position: LatLng(trip.originLat, trip.originLng),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: const InfoWindow(title: 'Origen'),
    ));
    _markers.add(Marker(
      markerId: const MarkerId('destination'),
      position: LatLng(trip.destinationLat, trip.destinationLng),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: const InfoWindow(title: 'Destino'),
    ));
  }

  void _centerMap(TripModel trip) {
    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            trip.originLat < trip.destinationLat
                ? trip.originLat
                : trip.destinationLat,
            trip.originLng < trip.destinationLng
                ? trip.originLng
                : trip.destinationLng,
          ),
          northeast: LatLng(
            trip.originLat > trip.destinationLat
                ? trip.originLat
                : trip.destinationLat,
            trip.originLng > trip.destinationLng
                ? trip.originLng
                : trip.destinationLng,
          ),
        ),
        80,
      ),
    );
  }

  void _showCancelDialog(BuildContext context, TripModel trip) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar viaje'),
        content: const Text(
            '¿Estás seguro de que deseas cancelar este viaje?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<TripBloc>().add(CancelTripEvent(
                    tripId: trip.id,
                    driverId: trip.driverId,
                    reason: 'Cancelado por pasajero',
                  ));
            },
            style: TextButton.styleFrom(
                foregroundColor: AppTheme.errorColor),
            child: const Text('Cancelar viaje'),
          ),
        ],
      ),
    );
  }
}

class _TripRouteInfo extends StatelessWidget {
  final TripModel trip;
  const _TripRouteInfo({required this.trip});

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
              const Icon(Icons.circle,
                  size: 12, color: AppTheme.successColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  trip.originAddress,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(left: 5),
            child: Column(
              children: [
                SizedBox(height: 2),
                Icon(Icons.more_vert,
                    size: 16, color: AppTheme.textSecondary),
                SizedBox(height: 2),
              ],
            ),
          ),
          Row(
            children: [
              const Icon(Icons.location_on,
                  size: 14, color: AppTheme.errorColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  trip.destinationAddress,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FareInfo extends StatelessWidget {
  final double fare;
  const _FareInfo({required this.fare});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Tarifa estimada',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          Text(
            '\$${fare.toStringAsFixed(0)} COP',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}
