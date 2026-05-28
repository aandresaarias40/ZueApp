import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/bloc/auth_bloc.dart';
import '../../../trips/bloc/trip_bloc.dart';
import '../../../../services/trip_service.dart';
import '../../../../services/driver_service.dart';

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
  String _selectedVehicleType = AppConstants.vehicleCar; // 'car' o 'moto'

  final TripService _tripService = TripService();
  final DriverService _driverService = DriverService();

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

          final fare = _tripService.estimateFare(distanceKm,
              vehicleType: _selectedVehicleType);

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
      // Verificar disponibilidad de conductores antes de crear el viaje
      final nearbyDrivers = await _driverService.getNearbyDrivers(
        lat: _originPosition!.latitude,
        lng: _originPosition!.longitude,
        vehicleType: _selectedVehicleType,
      );

      if (!mounted) return;

      if (nearbyDrivers.isEmpty) {
        setState(() => _isRequesting = false);
        _showNoDriversDialog();
        return;
      }

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
            requestedVehicleType: _selectedVehicleType,
          ));
    } catch (_) {
      // Si falla la consulta de conductores, continuar igual para no bloquear
      // al pasajero por un error de red en la validación previa.
      if (!mounted) return;
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
            requestedVehicleType: _selectedVehicleType,
          ));
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  void _showNoDriversDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.directions_car_outlined, color: AppTheme.warningColor),
            SizedBox(width: 10),
            Text('Sin conductores disponibles'),
          ],
        ),
        content: const Text(
          'No hay conductores disponibles en tu zona en este momento.\n\n'
          'Intenta de nuevo en unos minutos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _requestTrip();
            },
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
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

              const SizedBox(height: 20),

              // ── Selector tipo de vehículo ─────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tipo de servicio',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // Opción Carro
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedVehicleType = AppConstants.vehicleCar;
                              // Recalcular tarifa si ya hay distancia
                              if (_estimatedDistance != null) {
                                _estimatedFare = _tripService.estimateFare(
                                  _estimatedDistance!,
                                  vehicleType: AppConstants.vehicleCar,
                                );
                              }
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 8),
                            decoration: BoxDecoration(
                              color: _selectedVehicleType ==
                                      AppConstants.vehicleCar
                                  ? AppTheme.primaryColor
                                  : AppTheme.backgroundColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _selectedVehicleType ==
                                        AppConstants.vehicleCar
                                    ? AppTheme.primaryColor
                                    : AppTheme.dividerColor,
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.directions_car_rounded,
                                  size: 28,
                                  color: _selectedVehicleType ==
                                          AppConstants.vehicleCar
                                      ? Colors.white
                                      : AppTheme.textSecondary,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Carro',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _selectedVehicleType ==
                                            AppConstants.vehicleCar
                                        ? Colors.white
                                        : AppTheme.textPrimary,
                                  ),
                                ),
                                Text(
                                  'Desde \$${AppConstants.minimumFare.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _selectedVehicleType ==
                                            AppConstants.vehicleCar
                                        ? Colors.white70
                                        : AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Opción Moto
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedVehicleType = AppConstants.vehicleMoto;
                              // Recalcular tarifa si ya hay distancia
                              if (_estimatedDistance != null) {
                                _estimatedFare = _tripService.estimateFare(
                                  _estimatedDistance!,
                                  vehicleType: AppConstants.vehicleMoto,
                                );
                              }
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 8),
                            decoration: BoxDecoration(
                              color: _selectedVehicleType ==
                                      AppConstants.vehicleMoto
                                  ? AppTheme.primaryColor
                                  : AppTheme.backgroundColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _selectedVehicleType ==
                                        AppConstants.vehicleMoto
                                    ? AppTheme.primaryColor
                                    : AppTheme.dividerColor,
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.two_wheeler_rounded,
                                  size: 28,
                                  color: _selectedVehicleType ==
                                          AppConstants.vehicleMoto
                                      ? Colors.white
                                      : AppTheme.textSecondary,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Moto',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _selectedVehicleType ==
                                            AppConstants.vehicleMoto
                                        ? Colors.white
                                        : AppTheme.textPrimary,
                                  ),
                                ),
                                Text(
                                  'Desde \$${AppConstants.motoMinimumFare.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _selectedVehicleType ==
                                            AppConstants.vehicleMoto
                                        ? Colors.white70
                                        : AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),

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
