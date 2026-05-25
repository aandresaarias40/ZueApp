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
    String requestedVehicleType = AppConstants.vehicleCar,
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
      requestedVehicleType: requestedVehicleType,
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
    // Verificar que el conductor no tenga ya un viaje activo
    final driverDoc = await _firestore
        .collection(AppConstants.driversCollection)
        .doc(driverId)
        .get();

    if (driverDoc.exists) {
      final currentStatus = driverDoc.data()?['status'] as String? ?? '';
      if (currentStatus == AppConstants.driverStatusBusy) {
        throw Exception(
            'Ya tienes un viaje activo. Complétalo antes de aceptar otro.');
      }
    }

    // Verificar que el viaje aún esté disponible (no lo tomó otro conductor)
    final tripDoc = await _trips.doc(tripId).get();
    if (!tripDoc.exists) {
      throw Exception('El viaje ya no está disponible.');
    }
    final tripStatus = (tripDoc.data() as Map<String, dynamic>?)?['status'] as String? ?? '';
    if (tripStatus != AppConstants.tripStatusRequested) {
      throw Exception('Este viaje ya fue tomado por otro conductor.');
    }

    // Aceptar viaje
    await _trips.doc(tripId).set({
      'driverId': driverId,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'vehiclePlate': vehiclePlate,
      'vehicleType': vehicleType,
      'status': AppConstants.tripStatusAccepted,
      'acceptedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Marcar conductor como ocupado
    await _firestore
        .collection(AppConstants.driversCollection)
        .doc(driverId)
        .set({'status': AppConstants.driverStatusBusy}, SetOptions(merge: true));
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

    // Liberar conductor e incrementar contador de viajes
    batch.update(
      _firestore.collection(AppConstants.driversCollection).doc(driverId),
      {
        'status': AppConstants.driverStatusActive,
        'totalTrips': FieldValue.increment(1),
      },
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

  /// Cancela cualquier viaje en estado "requested" del pasajero.
  /// Se llama al cerrar sesión para evitar que el viaje quede en espera
  /// indefinidamente en Firestore.
  Future<void> cancelPendingPassengerTrip({
    required String passengerId,
    String reason = 'Cancelado al cerrar sesión',
  }) async {
    final snapshot = await _trips
        .where('passengerId', isEqualTo: passengerId)
        .where('status', isEqualTo: AppConstants.tripStatusRequested)
        .limit(1)
        .get();

    for (final doc in snapshot.docs) {
      await _trips.doc(doc.id).update({
        'status': AppConstants.tripStatusCancelled,
        'cancelReason': reason,
        'cancelledAt': FieldValue.serverTimestamp(),
      });
    }
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

    // Actualizar promedio de calificación del conductor.
    // Solo se calcula promedio real; el valor 5.0 inicial no se usa como base.
    final driverDoc = await _firestore
        .collection(AppConstants.driversCollection)
        .doc(driverId)
        .get();
    if (driverDoc.exists) {
      final data = driverDoc.data() as Map<String, dynamic>;
      final totalTrips = (data['totalTrips'] ?? 0) as int;
      // ratedTrips: cuántos viajes ya tienen calificación acumulada en rating
      final ratedTrips = (data['ratedTrips'] ?? 0) as int;
      final currentRating = ratedTrips > 0
          ? (data['rating'] ?? 0.0).toDouble()
          : 0.0; // ignorar el 5.0 por defecto si aún no hay calificaciones
      final newRating =
          ((currentRating * ratedTrips) + rating) / (ratedTrips + 1);
      await _firestore
          .collection(AppConstants.driversCollection)
          .doc(driverId)
          .update({
        'rating': newRating,
        'ratedTrips': ratedTrips + 1,
      });
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

  // Obtener un viaje por ID una sola vez
  Future<TripModel?> fetchTripById(String tripId) async {
    final doc = await _trips.doc(tripId).get();
    return doc.exists ? TripModel.fromFirestore(doc) : null;
  }

  // Stream de un viaje específico por su ID (para el pasajero en tracking)
  Stream<TripModel?> watchTripById(String tripId) {
    return _trips
        .doc(tripId)
        .snapshots()
        .map((doc) => doc.exists ? TripModel.fromFirestore(doc) : null);
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
  // Nota: se evita orderBy compuesto para no requerir índice manual en Firestore.
  // El ordenamiento se hace en memoria después de obtener los datos.
  Future<List<TripModel>> getPassengerTripHistory(String passengerId) async {
    final snapshot = await _trips
        .where('passengerId', isEqualTo: passengerId)
        .where('status', whereIn: [
          AppConstants.tripStatusCompleted,
          AppConstants.tripStatusCancelled,
        ])
        .limit(AppConstants.pageSize)
        .get();
    final trips = snapshot.docs
        .map((doc) => TripModel.fromFirestore(doc))
        .toList();
    trips.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return trips;
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

  // Calcular tarifa estimada (COP) — Tarifas de Fusagasugá
  // [vehicleType] puede ser AppConstants.vehicleCar o AppConstants.vehicleMoto
  double estimateFare(double distanceKm,
      {String vehicleType = AppConstants.vehicleCar}) {
    if (vehicleType == AppConstants.vehicleMoto) {
      // Moto: tarifa fija $4.500 para rutas < 6 km
      if (distanceKm < AppConstants.minimumFareDistanceKm) {
        return AppConstants.motoMinimumFare;
      }
      // Moto: tarifa base $1.500 + $600 por km
      final double fare =
          AppConstants.motoBaseFare + (distanceKm * AppConstants.motoPerKmRate);
      return (fare / 100).ceil() * 100.0;
    }
    // Carro: tarifa fija $8.000 para rutas < 6 km (tarifa oficial Fusagasugá)
    if (distanceKm < AppConstants.minimumFareDistanceKm) {
      return AppConstants.minimumFare;
    }
    // Carro: tarifa base $3.000 + $1.200 por km
    final double fare =
        AppConstants.carBaseFare + (distanceKm * AppConstants.carPerKmRate);
    return (fare / 100).ceil() * 100.0; // Redondear a centenas
  }
}
