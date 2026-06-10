import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/driver_model.dart';
import '../models/user_model.dart';
import '../core/constants/app_constants.dart';
import 'location_telemetry_service.dart';

class DriverService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocationTelemetryService _telemetry = LocationTelemetryService();

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
      cedula: '',
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
  // Actualizar ubicación
  //
  // Si redisEnabled = true (app_constants.dart):
  //   • Escribe a Redis (hot path, ~1-5 ms) — para el mapa de pasajeros.
  //   • Escribe a Firestore cada 30 s (slow path, persistencia).
  //
  // Si redisEnabled = false:
  //   • Escribe directo a Firestore (comportamiento original).
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> updateDriverLocation({
    required String driverId,
    required double lat,
    required double lng,
  }) async {
    await _telemetry.updateDriverPosition(
      driverId: driverId,
      lat: lat,
      lng: lng,
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
  // Conductores cercanos disponibles
  //
  // Estrategia dual:
  //   • Redis activo  → GEOSEARCH (< 5 ms, geoespacial nativo)
  //                     + enriquecer con datos de Firestore por ID
  //   • Solo Firestore → query con índice compuesto + haversine en cliente
  //
  // El fallback garantiza que la app funcione aunque Redis no esté disponible.
  // ─────────────────────────────────────────────────────────────────────────
  Future<List<DriverModel>> getNearbyDrivers({
    required double lat,
    required double lng,
    String? vehicleType,
  }) async {
    // ── Intento Redis GEOSEARCH ──────────────────────────────────────────
    if (AppConstants.redisEnabled) {
      try {
        final radiusKm = AppConstants.maxDriverSearchRadius / 1000.0;
        final geoResults = await _telemetry.getDriversNearby(
          lat: lat,
          lng: lng,
          radiusKm: radiusKm,
          limit: AppConstants.maxNearbyDriverFetch,
        );

        if (geoResults.isNotEmpty) {
          // Cargar documentos de Firestore en paralelo por sus IDs
          final ids = geoResults.map((r) => r['driverId'] as String).toList();
          final docs = await Future.wait(
            ids.map((id) => _drivers.doc(id).get()),
          );

          final drivers = <DriverModel>[];
          for (int i = 0; i < docs.length; i++) {
            final doc = docs[i];
            if (!doc.exists) continue;
            final driver = DriverModel.fromFirestore(doc);

            // Filtrar por tipo de vehículo si se especificó
            if (vehicleType != null && driver.vehicleType != vehicleType) {
              continue;
            }
            // Confirmar que el conductor está activo y online
            if (!driver.isOnline ||
                driver.status != AppConstants.driverStatusActive) {
              continue;
            }

            // Sobrescribir coordenadas con la posición Redis (más fresca que Firestore)
            final geoEntry = geoResults[i];
            drivers.add(driver.copyWith(
              currentLat: geoEntry['lat'] as double,
              currentLng: geoEntry['lng'] as double,
            ));
          }
          return drivers;
        }
      } catch (_) {
        // Redis no disponible — continuar con Firestore como fallback
      }
    }

    // ── Fallback: Firestore con índice compuesto + haversine ─────────────
    // Índice: drivers → isOnline ASC, status ASC (ver firestore.indexes.json)
    // Límite de 50 candidatos: O(50 docs) vs O(todos los online).
    Query query = _drivers
        .where('isOnline', isEqualTo: true)
        .where('status', isEqualTo: AppConstants.driverStatusActive)
        .limit(AppConstants.maxNearbyDriverFetch);

    if (vehicleType != null) {
      query = query.where('vehicleType', isEqualTo: vehicleType);
    }

    final snapshot = await query.get();
    final drivers = snapshot.docs
        .map((doc) => DriverModel.fromFirestore(doc))
        .toList();

    // Filtro de distancia en cliente (haversine) — O(n) sobre ≤50 docs
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
  // Distancia Haversine (metros) usando dart:math nativo
  // Fórmula: a = sin²(Δlat/2) + cos(lat1)·cos(lat2)·sin²(Δlng/2)
  // dart:math compila a instrucciones FPU nativas: más preciso y más rápido
  // que las aproximaciones manuales por series de Taylor / Newton-Raphson.
  // ─────────────────────────────────────────────────────────────────────────
  double _calculateDistance(
      double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371000;
    final double dLat = _toRadians(lat2 - lat1);
    final double dLng = _toRadians(lng2 - lng1);
    final double sinDLat = math.sin(dLat / 2);
    final double sinDLng = math.sin(dLng / 2);
    final double a = sinDLat * sinDLat +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
            sinDLng * sinDLng;
    final double c = 2 * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;
}
