import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../models/driver_model.dart';
import '../../../services/driver_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Events
// ─────────────────────────────────────────────────────────────────────────────
abstract class DriverEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadDriverEvent extends DriverEvent {
  final String driverId;
  LoadDriverEvent({required this.driverId});
  @override
  List<Object?> get props => [driverId];
}

class ToggleDriverOnlineEvent extends DriverEvent {
  final String driverId;
  final bool isOnline;
  ToggleDriverOnlineEvent({required this.driverId, required this.isOnline});
  @override
  List<Object?> get props => [driverId, isOnline];
}

class UpdateDriverLocationEvent extends DriverEvent {
  final String driverId;
  final double lat;
  final double lng;
  UpdateDriverLocationEvent({
    required this.driverId,
    required this.lat,
    required this.lng,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// States
// ─────────────────────────────────────────────────────────────────────────────
abstract class DriverState extends Equatable {
  @override
  List<Object?> get props => [];
}

class DriverInitialState extends DriverState {}

class DriverLoadingState extends DriverState {}

class DriverLoadedState extends DriverState {
  final DriverModel driver;
  DriverLoadedState({required this.driver});
  @override
  List<Object?> get props => [driver];
}

class DriverErrorState extends DriverState {
  final String message;
  DriverErrorState({required this.message});
  @override
  List<Object?> get props => [message];
}

// ─────────────────────────────────────────────────────────────────────────────
// BLoC
// ─────────────────────────────────────────────────────────────────────────────
class DriverBloc extends Bloc<DriverEvent, DriverState> {
  final DriverService _driverService = DriverService();

  DriverBloc() : super(DriverInitialState()) {
    on<LoadDriverEvent>(_onLoadDriver);
    on<ToggleDriverOnlineEvent>(_onToggleOnline);
    on<UpdateDriverLocationEvent>(_onUpdateLocation);
  }

  // ── Cargar datos del conductor ──────────────────────────────────────────
  Future<void> _onLoadDriver(
      LoadDriverEvent event, Emitter<DriverState> emit) async {
    // Solo mostrar loading si no tenemos datos previos
    if (state is! DriverLoadedState) {
      emit(DriverLoadingState());
    }
    try {
      final driver = await _driverService.getDriverById(event.driverId);
      emit(DriverLoadedState(driver: driver));
    } catch (e) {
      // En caso de error, emitir DriverErrorState con mensaje legible
      emit(DriverErrorState(
        message: e.toString().replaceAll('Exception: ', ''),
      ));
    }
  }

  // ── Cambiar estado online / offline ────────────────────────────────────
  Future<void> _onToggleOnline(
      ToggleDriverOnlineEvent event, Emitter<DriverState> emit) async {
    if (state is! DriverLoadedState) return;
    final currentDriver = (state as DriverLoadedState).driver;
    try {
      await _driverService.setDriverOnlineStatus(
        driverId: event.driverId,
        isOnline: event.isOnline,
        // Si la suscripción está pendiente (nuevo conductor), permitir toggle
        // para que pueda moverse; la restricción real ya está en _toggleOnlineStatus
        canWork: currentDriver.subscriptionStatus == 'pending'
            ? event.isOnline // Si quiere ponerse online y está pending, validar
            : currentDriver.canWork,
      );
      emit(DriverLoadedState(
        driver: currentDriver.copyWith(isOnline: event.isOnline),
      ));
    } catch (e) {
      // Mantener el estado actual y notificar error sin romper la UI
      emit(DriverLoadedState(driver: currentDriver)); // Restaurar estado
      emit(DriverErrorState(
          message: e.toString().replaceAll('Exception: ', '')));
      // Recargar estado correcto
      emit(DriverLoadedState(driver: currentDriver));
    }
  }

  // ── Actualizar ubicación ────────────────────────────────────────────────
  Future<void> _onUpdateLocation(
      UpdateDriverLocationEvent event, Emitter<DriverState> emit) async {
    if (state is! DriverLoadedState) return;
    try {
      await _driverService.updateDriverLocation(
        driverId: event.driverId,
        lat: event.lat,
        lng: event.lng,
      );
      final driver = (state as DriverLoadedState).driver;
      emit(DriverLoadedState(
        driver: driver.copyWith(
          currentLat: event.lat,
          currentLng: event.lng,
        ),
      ));
    } catch (_) {
      // Ignorar errores de ubicación silenciosamente
    }
  }
}
