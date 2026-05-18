import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/driver_model.dart';
import '../models/user_model.dart';
import '../core/constants/app_constants.dart';

class DriverService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _drivers =>
      _firestore.collection(AppConstants.driversCollection);

  CollectionReference get _users =>
      _firestore.collection(AppConstants.usersCollection);

  // ─────────────────────────────────────────────────────────────────────────
  // Obtener conductor por ID.
  // Si no existe en la colección "drivers", lo construye desde "users"
  // y crea el documento en "drivers" automáticamente.
  // ─────────────────────────────────────────────────────────────────────────
  Future<DriverModel> getDriverById(String driverId) async {
    // 1. Buscar en la colección drivers
    final driverDoc = await _drivers.doc(driverId).get();
    if (driverDoc.exists) {
      return DriverModel.fromFirestore(driverDoc);
    }

    // 2. Fallback: construir desde la colección users
    final userDoc = await _users.doc(driverId).get();
    if (!userDoc.exists) {
      throw Exception('Usuario no encontrado');
    }

    final user = UserModel.fromFirestore(userDoc);

    // Crear un DriverModel básico desde los datos del usuario
    final driver = DriverModel(
      id: driverId,
      userId: driverId,
      name: user.name,
      email: user.email,
      phone: user.phone,
      photoUrl: user.photoUrl,
      vehicleType: AppConstants.vehicleCar,
      vehiclePlate: '',
      vehicleModel: '',
      vehicleColor: '',
      licenseNumber: '',
      status: AppConstants.driverStatusInactive,
      isOnline: false,
      subscriptionPlan: AppConstants.planWeekly,
      subscriptionStatus: 'pending',
      createdAt: user.createdAt,
    );

    // 3. Persistir el documento en "drivers" para futuras consultas
    await _drivers.doc(driverId).set(driver.toFirestore());

    return driver;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stream en tiempo real del conductor
  // ─────────────────────────────────────────────────────────────────────────
  Stream<DriverModel> watchDriver(String driverId) {
    return _drivers.doc(driverId).snapshots().asyncMap((doc) async {
      if (doc.exists) return DriverModel.fromFirestore(doc);
      // Si aún no existe el documento, lo creamos
      return getDriverById(driverId);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Actualizar ubicación — usa set+merge para no fallar si no existe el doc
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> updateDriverLocation({
    required String driverId,
    required double lat,
    required double lng,
  }) async {
    await _drivers.doc(driverId).set(
      {
        'currentLat': lat,
        'currentLng': lng,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Cambiar estado online/offline — usa set+merge
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> setDriverOnlineStatus({
    required String driverId,
    required bool isOnline,
    required bool canWork,
  }) async {
    if (!canWork && isOnline) {
      throw Exception(
          'No puedes conectarte. Tu suscripción está vencida o suspendida.');
    }
    await _drivers.doc(driverId).set(
      {
        'isOnline': isOnline,
        'status': isOnline
            ? AppConstants.driverStatusActive
            : AppConstants.driverStatusInactive,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Actualizar datos del perfil del conductor (vehículo, etc.)
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> updateDriverProfile({
    required String driverId,
    String? vehicleType,
    String? vehiclePlate,
    String? vehicleModel,
    String? vehicleColor,
    String? licenseNumber,
    String? subscriptionPlan,
  }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (vehicleType != null) data['vehicleType'] = vehicleType;
    if (vehiclePlate != null) data['vehiclePlate'] = vehiclePlate;
    if (vehicleModel != null) data['vehicleModel'] = vehicleModel;
    if (vehicleColor != null) data['vehicleColor'] = vehicleColor;
    if (licenseNumber != null) data['licenseNumber'] = licenseNumber;
    if (subscriptionPlan != null) data['subscriptionPlan'] = subscriptionPlan;

    await _drivers.doc(driverId).set(data, SetOptions(merge: true));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Conductores cercanos disponibles
  // ─────────────────────────────────────────────────────────────────────────
  Future<List<DriverModel>> getNearbyDrivers({
    required double lat,
    required double lng,
    String? vehicleType,
  }) async {
    Query query = _drivers
        .where('isOnline', isEqualTo: true)
        .where('status', isEqualTo: AppConstants.driverStatusActive);

    if (vehicleType != null) {
      query = query.where('vehicleType', isEqualTo: vehicleType);
    }

    final snapshot = await query.get();
    final drivers = snapshot.docs
        .map((doc) => DriverModel.fromFirestore(doc))
        .toList();

    return drivers.where((driver) {
      if (driver.currentLat == null || driver.currentLng == null) return false;
      final distance = _calculateDistance(
        lat, lng, driver.currentLat!, driver.currentLng!,
      );
      return distance <= AppConstants.maxDriverSearchRadius;
    }).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Todos los conductores (para admin)
  // ─────────────────────────────────────────────────────────────────────────
  Stream<List<DriverModel>> watchAllDrivers() {
    return _drivers
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => DriverModel.fromFirestore(doc))
            .toList());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Suspender conductor
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> suspendDriver(String driverId, String reason) async {
    await _drivers.doc(driverId).set(
      {
        'status': AppConstants.driverStatusSuspended,
        'isOnline': false,
        'subscriptionStatus': 'expired',
        'suspensionReason': reason,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Reactivar conductor
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> reactivateDriver(String driverId) async {
    await _drivers.doc(driverId).set(
      {
        'status': AppConstants.driverStatusInactive,
        'suspensionReason': null,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Distancia Haversine simplificada (metros)
  // ─────────────────────────────────────────────────────────────────────────
  double _calculateDistance(
      double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371000;
    final double dLat = _toRadians(lat2 - lat1);
    final double dLng = _toRadians(lng2 - lng1);
    final double a = (dLat / 2) * (dLat / 2) +
        _toRadians(lat1) *
            _toRadians(lat2) *
            (dLng / 2) *
            (dLng / 2);
    return earthRadius * 2 * (a < 1 ? a : 1);
  }

  double _toRadians(double degrees) => degrees * 3.14159265358979 / 180;
}
