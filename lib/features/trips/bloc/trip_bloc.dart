import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/trip_model.dart';
import '../../../services/trip_service.dart';
import '../data/repositories/trip_repository_impl.dart';

// Events
abstract class TripEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class RequestTripEvent extends TripEvent {
  final String passengerId;
  final String passengerName;
  final double originLat;
  final double originLng;
  final String originAddress;
  final double destinationLat;
  final double destinationLng;
  final String destinationAddress;
  final double? estimatedFare;
  final double? estimatedDistance;

  RequestTripEvent({
    required this.passengerId,
    required this.passengerName,
    required this.originLat,
    required this.originLng,
    required this.originAddress,
    required this.destinationLat,
    required this.destinationLng,
    required this.destinationAddress,
    this.estimatedFare,
    this.estimatedDistance,
  });
}

class AcceptTripEvent extends TripEvent {
  final String tripId;
  final String driverId;
  final String driverName;
  final String driverPhone;
  final String vehiclePlate;
  final String vehicleType;

  AcceptTripEvent({
    required this.tripId,
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
    required this.vehiclePlate,
    required this.vehicleType,
  });
}

class WatchTripEvent extends TripEvent {
  final String tripId;
  WatchTripEvent({required this.tripId});
}

class WatchPassengerActiveTripEvent extends TripEvent {
  final String passengerId;
  WatchPassengerActiveTripEvent({required this.passengerId});
}

class WatchPendingTripsEvent extends TripEvent {}

class CancelTripEvent extends TripEvent {
  final String tripId;
  final String? driverId;
  final String reason;
  CancelTripEvent({
    required this.tripId,
    this.driverId,
    required this.reason,
  });
}

class RateTripEvent extends TripEvent {
  final String tripId;
  final String driverId;
  final int rating;
  final String? comment;
  RateTripEvent({
    required this.tripId,
    required this.driverId,
    required this.rating,
    this.comment,
  });
}

class LoadTripHistoryEvent extends TripEvent {
  final String passengerId;
  LoadTripHistoryEvent({required this.passengerId});
}

// States
abstract class TripState extends Equatable {
  @override
  List<Object?> get props => [];
}

class TripInitialState extends TripState {}

class TripLoadingState extends TripState {}

class TripRequestedState extends TripState {
  final TripModel trip;
  TripRequestedState({required this.trip});
  @override
  List<Object?> get props => [trip];
}

class TripActiveState extends TripState {
  final TripModel trip;
  TripActiveState({required this.trip});
  @override
  List<Object?> get props => [trip];
}

class TripAcceptedState extends TripState {
  final TripModel trip;
  TripAcceptedState({required this.trip});
}

class TripCompletedState extends TripState {
  final TripModel trip;
  TripCompletedState({required this.trip});
}

class TripCancelledState extends TripState {}

class TripsListState extends TripState {
  final List<TripModel> trips;
  TripsListState({required this.trips});
  @override
  List<Object?> get props => [trips];
}

class TripHistoryLoadedState extends TripState {
  final List<TripModel> trips;
  TripHistoryLoadedState({required this.trips});
}

class TripErrorState extends TripState {
  final String message;
  TripErrorState({required this.message});
}

// BLoC
class TripBloc extends Bloc<TripEvent, TripState> {
  final TripRepositoryImpl tripRepository;
  final TripService _tripService = TripService();
  StreamSubscription? _tripSubscription;
  StreamSubscription? _pendingTripsSubscription;

  TripBloc({required this.tripRepository}) : super(TripInitialState()) {
    on<RequestTripEvent>(_onRequestTrip);
    on<AcceptTripEvent>(_onAcceptTrip);
    on<WatchTripEvent>(_onWatchTrip);
    on<WatchPassengerActiveTripEvent>(_onWatchPassengerActiveTrip);
    on<WatchPendingTripsEvent>(_onWatchPendingTrips);
    on<CancelTripEvent>(_onCancelTrip);
    on<RateTripEvent>(_onRateTrip);
    on<LoadTripHistoryEvent>(_onLoadHistory);
  }

  @override
  Future<void> close() {
    _tripSubscription?.cancel();
    _pendingTripsSubscription?.cancel();
    return super.close();
  }

  Future<void> _onRequestTrip(
      RequestTripEvent event, Emitter<TripState> emit) async {
    emit(TripLoadingState());
    try {
      final trip = await _tripService.createTripRequest(
        passengerId: event.passengerId,
        passengerName: event.passengerName,
        originLat: event.originLat,
        originLng: event.originLng,
        originAddress: event.originAddress,
        destinationLat: event.destinationLat,
        destinationLng: event.destinationLng,
        destinationAddress: event.destinationAddress,
        estimatedFare: event.estimatedFare,
        estimatedDistance: event.estimatedDistance,
      );
      emit(TripRequestedState(trip: trip));
    } catch (e) {
      emit(TripErrorState(message: e.toString()));
    }
  }

  Future<void> _onAcceptTrip(
      AcceptTripEvent event, Emitter<TripState> emit) async {
    try {
      await _tripService.acceptTrip(
        tripId: event.tripId,
        driverId: event.driverId,
        driverName: event.driverName,
        driverPhone: event.driverPhone,
        vehiclePlate: event.vehiclePlate,
        vehicleType: event.vehicleType,
      );
      // Obtener el viaje actualizado y emitir estado aceptado
      final trip = await _tripService.fetchTripById(event.tripId);
      if (trip != null) {
        emit(TripAcceptedState(trip: trip));
      }
    } catch (e) {
      emit(TripErrorState(message: e.toString()));
    }
  }

  Future<void> _onWatchTrip(
      WatchTripEvent event, Emitter<TripState> emit) async {
    await _tripSubscription?.cancel();
    await emit.forEach(
      _tripService.watchTripById(event.tripId),
      onData: (trip) {
        if (trip == null) return TripInitialState();
        if (trip.status == AppConstants.tripStatusCompleted) {
          return TripCompletedState(trip: trip);
        }
        if (trip.status == AppConstants.tripStatusCancelled) {
          return TripCancelledState();
        }
        return TripActiveState(trip: trip);
      },
    );
  }

  Future<void> _onWatchPassengerActiveTrip(
      WatchPassengerActiveTripEvent event,
      Emitter<TripState> emit) async {
    await emit.forEach(
      _tripService.watchPassengerActiveTrip(event.passengerId),
      onData: (trip) {
        if (trip == null) return TripInitialState();
        return TripActiveState(trip: trip);
      },
    );
  }

  Future<void> _onWatchPendingTrips(
      WatchPendingTripsEvent event, Emitter<TripState> emit) async {
    await emit.forEach(
      _tripService.watchPendingTrips(),
      onData: (trips) => TripsListState(trips: trips),
    );
  }

  Future<void> _onCancelTrip(
      CancelTripEvent event, Emitter<TripState> emit) async {
    try {
      await _tripService.cancelTrip(
        tripId: event.tripId,
        driverId: event.driverId,
        reason: event.reason,
      );
      emit(TripCancelledState());
    } catch (e) {
      emit(TripErrorState(message: e.toString()));
    }
  }

  Future<void> _onRateTrip(
      RateTripEvent event, Emitter<TripState> emit) async {
    try {
      await _tripService.rateTrip(
        tripId: event.tripId,
        driverId: event.driverId,
        rating: event.rating,
        comment: event.comment,
      );
    } catch (_) {}
  }

  Future<void> _onLoadHistory(
      LoadTripHistoryEvent event, Emitter<TripState> emit) async {
    emit(TripLoadingState());
    try {
      final trips =
          await _tripService.getPassengerTripHistory(event.passengerId);
      emit(TripHistoryLoadedState(trips: trips));
    } catch (e) {
      emit(TripErrorState(message: e.toString()));
    }
  }
}
