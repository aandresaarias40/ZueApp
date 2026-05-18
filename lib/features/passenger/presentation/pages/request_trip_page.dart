import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/bloc/auth_bloc.dart';
import '../../../trips/bloc/trip_bloc.dart';
import '../../../../services/trip_service.dart';

class RequestTripPage extends StatefulWidget {
  const RequestTripPage({super.key});

  @override
  State<RequestTripPage> createState() => _RequestTripPageState();
}

class _RequestTripPageState extends State<RequestTripPage> {
  final _destinationController = TextEditingController();
  Position? _originPosition;
  String _originAddress = 'Obteniendo ubicación...';
  String _originCity = '';        // Ciudad actual del pasajero
  String _originLocality = '';    // Municipio/barrio para sesgar geocoding
  String _destinationAddress = '';
  double? _destinationLat;
  double? _destinationLng;
  double? _estimatedFare;
  double? _estimatedDistance;
  bool _isSearching = false;
  bool _isRequesting = false;

  final TripService _tripService = TripService();

  @override
  void initState() {
    super.initState();
    _getOriginLocation();
  }

  @override
  void dispose() {
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _getOriginLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      // Guardar posición de inmediato, incluso si geocoding falla
      setState(() => _originPosition = position);

      final placemarks = await placemarkFromCoordinates(
        position.latitude, position.longitude,
      );
      if (!mounted) return;
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final locality = p.locality ?? p.subAdministrativeArea ?? '';
        final adminArea = p.administrativeArea ?? '';
        setState(() {
          _originCity = locality.isNotEmpty ? locality : adminArea;
          _originLocality = locality;
          _originAddress =
              '${p.street ?? ''}, $locality'.trim().replaceAll(RegExp('^,\\s*'), '');
        });
      } else {
        setState(() => _originAddress =
            '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _originAddress = 'No se pudo obtener ubicación');
    }
  }

  Future<void> _searchDestination(String query) async {
    if (query.length < 3) return;
    if (!mounted) return;
    setState(() {
      _isSearching = true;
      _destinationLat = null;
      _destinationLng = null;
      _estimatedFare = null;
      _estimatedDistance = null;
    });
    try {
      final searchQuery = _originCity.isNotEmpty
          ? '$query, $_originCity, Colombia'
          : '$query, Colombia';

      final locations = await locationFromAddress(searchQuery);
      if (!mounted) return;

      if (locations.isNotEmpty) {
        final loc = locations.first;

        if (_originPosition != null) {
          final distanceMeters = Geolocator.distanceBetween(
            _originPosition!.latitude,
            _originPosition!.longitude,
            loc.latitude,
            loc.longitude,
          );
          final distanceKm = distanceMeters / 1000;

          if (distanceKm > 30) {
            if (!mounted) return;
            setState(() => _isSearching = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Destino muy lejos (${distanceKm.toStringAsFixed(0)} km). '
                  'Verifica la dirección.',
                ),
                backgroundColor: AppTheme.warningColor,
                duration: const Duration(seconds: 3),
              ),
            );
            return;
          }

          final placemarks =
              await placemarkFromCoordinates(loc.latitude, loc.longitude);
          if (!mounted) return;

          final p = placemarks.isNotEmpty ? placemarks.first : null;
          final address = p != null
              ? '${p.street ?? ''}, ${p.locality ?? ''}'.trim().replaceAll(RegExp('^,\\s*'), '')
              : query;

          final fare = _tripService.estimateFare(distanceKm);

          setState(() {
            _destinationAddress = address;
            _destinationLat = loc.latitude;
            _destinationLng = loc.longitude;
            _estimatedDistance = distanceKm;
            _estimatedFare = fare;
            _isSearching = false;
          });
        }
      } else {
        if (!mounted) return;
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontró esa dirección. Intenta ser más específico.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSearching = false);
    }
  }

  Future<void> _requestTrip() async {
    if (_originPosition == null || _destinationLat == null) return;
    if (!mounted) return;
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticatedState) return;

    setState(() => _isRequesting = true);
    try {
      context.read<TripBloc>().add(RequestTripEvent(
            passengerId: authState.user.id,
            passengerName: authState.user.name,
            originLat: _originPosition!.latitude,
            originLng: _originPosition!.longitude,
            originAddress: _originAddress,
            destinationLat: _destinationLat!,
            destinationLng: _destinationLng!,
            destinationAddress: _destinationAddress,
            estimatedFare: _estimatedFare,
            estimatedDistance: _estimatedDistance,
          ));
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Solicitar Viaje'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.go(AppRoutes.passengerHome),
        ),
      ),
      body: BlocListener<TripBloc, TripState>(
        listener: (context, state) {
          if (state is TripRequestedState) {
            context.go('/passenger/tracking/${state.trip.id}');
          } else if (state is TripErrorState) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: AppTheme.errorColor,
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Origen
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.dividerColor),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: AppTheme.successColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Origen',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            _originAddress,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.my_location,
                        size: 18, color: AppTheme.primaryColor),
                  ],
                ),
              ),

              const SizedBox(height: 8),
              const Center(
                child: Icon(Icons.more_vert, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 8),

              // Destino
              TextField(
                controller: _destinationController,
                onChanged: _searchDestination,
                decoration: InputDecoration(
                  hintText: 'Ingresa tu destino',
                  prefixIcon: Container(
                    margin: const EdgeInsets.all(12),
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: AppTheme.errorColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  suffixIcon: _isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),

              const SizedBox(height: 24),

              // Resumen del viaje (si hay destino)
              if (_destinationLat != null) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.route,
                              color: AppTheme.primaryColor, size: 22),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Distancia estimada',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary)),
                              Text(
                                '${_estimatedDistance?.toStringAsFixed(1)} km',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('Tarifa estimada',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary)),
                              Text(
                                '\$${_estimatedFare?.toStringAsFixed(0)} COP',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              const Spacer(),

              // Botón confirmar
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _destinationLat == null || _originPosition == null || _isRequesting
                      ? null
                      : _requestTrip,
                  child: _isRequesting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text('Confirmar Viaje'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
