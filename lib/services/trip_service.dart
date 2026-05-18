import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/trip_model.dart';
import '../core/constants/app_constants.dart';

class TripService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _trips =>
      _firestore.collection(AppConstants.tripsCollection);

  // Crear solicitud de viaje
  Future<TripModel> createTripRequest({
    required String passengerId,
    required String passengerName,
    required double originLat,
    required double originLng,
    required String originAddress,
    required double destinationLat,
    required double destinationLng,
    required String destinationAddress,
    double? estimatedFare,
    double? estimatedDistance,
  }) async {
    final docRef = _trips.doc();
    final trip = TripModel(
      id: docRef.id,
      passengerId: passengerId,
      passengerName: passengerName,
      originLat: originLat,
      originLng: originLng,
      originAddress: originAddress,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      destinationAddress: destinationAddress,
      status: AppConstants.tripStatusRequested,
      fare: estimatedFare,
      distance: estimatedDistance,
      assignmentType: 'auto',
      createdAt: DateTime.now(),
    );

    await docRef.set(trip.toFirestore());
    return trip;
  }

  // Conductor acepta viaje
  Future<void> acceptTrip({
    required String tripId,
    required String driverId,
    required String driverName,
    required String driverPhone,
    required String vehiclePlate,
    required String vehicleType,
  }) async {
    await _trips.doc(tripId).update({
      'driverId': driverId,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'vehiclePlate': vehiclePlate,
      'vehicleType': vehicleType,
      'status': AppConstants.tripStatusAccepted,
      'acceptedAt': FieldValue.serverTimestamp(),
    });

    // Marcar conductor como ocupado
    await _firestore
        .collection(AppConstants.driversCollection)
        .doc(driverId)
        .update({'status': AppConstants.driverStatusBusy});
  }

  // Conductor inicia el viaje (recogió al pasajero)
  Future<void> startTrip(String tripId) async {
    await _trips.doc(tripId).update({
      'status': AppConstants.tripStatusInProgress,
      'startedAt': FieldValue.serverTimestamp(),
    });
  }

  // Conductor completa el viaje
  Future<void> completeTrip({
    required String tripId,
    required String driverId,
    double? finalFare,
    double? finalDistance,
    int? finalDuration,
  }) async {
    final batch = _firestore.batch();

    batch.update(_trips.doc(tripId), {
      'status': AppConstants.tripStatusCompleted,
      'completedAt': FieldValue.serverTimestamp(),
      if (finalFare != null) 'fare': finalFare,
      if (finalDistance != null) 'distance': finalDistance,
      if (finalDuration != null) 'duration': finalDuration,
    });

    // Liberar conductor
    batch.update(
      _firestore.collection(AppConstants.driversCollection).doc(driverId),
      {'status': AppConstants.driverStatusActive},
    );

    await batch.commit();
  }

  // Cancelar viaje
  Future<void> cancelTrip({
    required String tripId,
    String? driverId,
    required String reason,
  }) async {
    final batch = _firestore.batch();

    batch.update(_trips.doc(tripId), {
      'status': AppConstants.tripStatusCancelled,
      'cancelReason': reason,
      'cancelledAt': FieldValue.serverTimestamp(),
    });

    if (driverId != null) {
      batch.update(
        _firestore.collection(AppConstants.driversCollection).doc(driverId),
        {'status': AppConstants.driverStatusActive},
      );
    }

    await batch.commit();
  }

  // Admin asigna viaje manualmente
  Future<void> manuallyAssignTrip({
    required String tripId,
    required String driverId,
    required String driverName,
    required String driverPhone,
    required String vehiclePlate,
    required String vehicleType,
  }) async {
    await _trips.doc(tripId).update({
      'driverId': driverId,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'vehiclePlate': vehiclePlate,
      'vehicleType': vehicleType,
      'status': AppConstants.tripStatusAccepted,
      'assignmentType': 'manual',
      'acceptedAt': FieldValue.serverTimestamp(),
    });

    await _firestore
        .collection(AppConstants.driversCollection)
        .doc(driverId)
        .update({'status': AppConstants.driverStatusBusy});
  }

  // Calificar viaje (pasajero califica al conductor)
  Future<void> rateTrip({
    required String tripId,
    required String driverId,
    required int rating,
    String? comment,
  }) async {
    await _trips.doc(tripId).update({
      'passengerRating': rating,
      'passengerComment': comment,
    });

    // Actualizar promedio de calificación del conductor
    final driverDoc = await _firestore
        .collection(AppConstants.driversCollection)
        .doc(driverId)
        .get();
    if (driverDoc.exists) {
      final data = driverDoc.data() as Map<String, dynamic>;
      final currentRating = (data['rating'] ?? 5.0).toDouble();
      final totalTrips = (data['totalTrips'] ?? 0) as int;
      final newRating =
          ((currentRating * totalTrips) + rating) / (totalTrips + 1);
      await _firestore
          .collection(AppConstants.driversCollection)
          .doc(driverId)
          .update({'rating': newRating});
    }
  }

  // Stream del viaje activo del pasajero
  Stream<TripModel?> watchPassengerActiveTrip(String passengerId) {
    return _trips
        .where('passengerId', isEqualTo: passengerId)
        .where('status', whereIn: [
          AppConstants.tripStatusRequested,
          AppConstants.tripStatusAccepted,
          AppConstants.tripStatusOnRoute,
          AppConstants.tripStatusInProgress,
        ])
        .limit(1)
        .snapshots()
        .map((snapshot) => snapshot.docs.isEmpty
            ? null
            : TripModel.fromFirestore(snapshot.docs.first));
  }

  // Stream de viajes pendientes para conductor
  Stream<List<TripModel>> watchPendingTrips() {
    return _trips
        .where('status', isEqualTo: AppConstants.tripStatusRequested)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => TripModel.fromFirestore(doc)).toList());
  }

  // Stream del viaje activo del conductor
  Stream<TripModel?> watchDriverActiveTrip(String driverId) {
    return _trips
        .where('driverId', isEqualTo: driverId)
        .where('status', whereIn: [
          AppConstants.tripStatusAccepted,
          AppConstants.tripStatusOnRoute,
          AppConstants.tripStatusInProgress,
        ])
        .limit(1)
        .snapshots()
        .map((snapshot) => snapshot.docs.isEmpty
            ? null
            : TripModel.fromFirestore(snapshot.docs.first));
  }

  // Historial de viajes del pasajero
  Future<List<TripModel>> getPassengerTripHistory(String passengerId) async {
    final snapshot = await _trips
        .where('passengerId', isEqualTo: passengerId)
        .where('status', whereIn: [
          AppConstants.tripStatusCompleted,
          AppConstants.tripStatusCancelled,
        ])
        .orderBy('createdAt', descending: true)
        .limit(AppConstants.pageSize)
        .get();
    return snapshot.docs.map((doc) => TripModel.fromFirestore(doc)).toList();
  }

  // Todos los viajes para admin (tiempo real)
  Stream<List<TripModel>> watchAllActiveTrips() {
    return _trips
        .where('status', whereIn: [
          AppConstants.tripStatusRequested,
          AppConstants.tripStatusAccepted,
          AppConstants.tripStatusInProgress,
        ])
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => TripModel.fromFirestore(doc)).toList());
  }

  // Calcular tarifa estimada (COP)
  double estimateFare(double distanceKm) {
    // Tarifa base: $3.000 COP + $1.200 por km
    const double baseFare = 3000;
    const double perKm = 1200;
    final double fare = baseFare + (distanceKm * perKm);
    return (fare / 100).ceil() * 100.0; // Redondear a centenas
  }
}
