import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../core/constants/app_constants.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// LocationTelemetryService
/// ─────────────────────────────────────────────────────────────────────────────
/// Gestiona la telemetría GPS de conductores con una arquitectura de dos capas:
///
///  1. CAPA CALIENTE → Cloud Functions → Redis TCP (Upstash)   latencia ~50-80 ms
///     • Flutter llama HTTPS a Cloud Function (token Firebase en header)
///     • Cloud Function conecta a Upstash vía TCP nativo (ioredis)
///     • Redis responde en 2-5 ms — token Upstash NUNCA sale del servidor
///     • HSET driver:pos:{id}  lat lng ts status
///     • GEOADD drivers:geo    (índice geoespacial para GEOSEARCH)
///     • EXPIRE 120 s          (limpieza automática offline)
///
///  2. CAPA PERSISTENTE → Firestore                            latencia ~15-200 ms
///     • Escritura throttled cada [_firestoreSyncIntervalSec] segundos
///     • Historial, auditoría, reglas de seguridad, datos del conductor
///
/// SEGURIDAD:
///   El token Upstash está almacenado SOLO en el servidor (Cloud Functions).
///   Flutter solo usa su propio Firebase ID Token para autenticarse.
///
/// COSTO comparado (100 conductores, actualización cada 10 s, 24 h):
/// ┌──────────────────────────────────────────────┬──────────────┐
/// │ Arquitectura                                 │ Costo/día    │
/// ├──────────────────────────────────────────────┼──────────────┤
/// │ Solo Firestore (5 s)           1.73 M writes │ ~$1.04 USD   │
/// │ Cloud Fn + Redis + Firestore/30s             │ ~$0.20 USD   │
/// │   Cloud Functions: ~864K invocaciones/mes    │   gratis*    │
/// │   Redis (Upstash free tier)                  │   gratis*    │
/// │   Firestore throttled 30 s: 288K writes/día  │   $0.17 USD  │
/// │ * dentro del tier gratuito de Blaze          │              │
/// ├──────────────────────────────────────────────┼──────────────┤
/// │ Latencia escritura GPS    P95 < 100 ms       │ ✓ aceptable  │
/// │ Latencia lectura GEOSEARCH P95 < 100 ms      │ ✓ < 3 s ant. │
/// └──────────────────────────────────────────────┴──────────────┘
///
class LocationTelemetryService {
  // ── URLs de Cloud Functions ────────────────────────────────────────────────
  // Se actualizan automáticamente tras `firebase deploy --only functions`
  // URLs reales generadas por Firebase deploy (Cloud Run Gen 2)
  static const String _updateLocationUrl  = 'https://updatedriverlocation-avqcfqbgeq-uc.a.run.app';
  static const String _getNearbyUrl       = 'https://getnearbydrivers-avqcfqbgeq-uc.a.run.app';
  static const String _setOfflineUrl      = 'https://setdriveroffline-avqcfqbgeq-uc.a.run.app';

  /// Activa/desactiva la capa Redis vía Cloud Functions.
  /// false = solo Firestore (comportamiento original, sin backend).
  static const bool redisEnabled = AppConstants.redisEnabled;

  /// Segundos mínimos entre writes a Firestore cuando Redis está activo.
  static const int _firestoreSyncIntervalSec = AppConstants.firestoreSyncIntervalSec;

  // ── Estado interno ─────────────────────────────────────────────────────────
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth      _auth      = FirebaseAuth.instance;
  final http.Client       _http      = http.Client();

  /// Timestamp del último write a Firestore por conductor.
  final Map<String, DateTime> _lastFirestoreWrite = {};

  // ── API pública ────────────────────────────────────────────────────────────

  /// Actualiza la posición GPS de un conductor.
  ///
  /// Si Redis está activo:
  ///   • Llama Cloud Function (→ Redis TCP HSET + GEOADD, ~50-80 ms).
  ///   • Escribe a Firestore solo si han pasado [_firestoreSyncIntervalSec].
  ///
  /// Si Redis está desactivado:
  ///   • Escribe directamente a Firestore (comportamiento original).
  Future<void> updateDriverPosition({
    required String driverId,
    required double lat,
    required double lng,
    String status = 'active',
  }) async {
    if (redisEnabled) {
      // Hot path: Cloud Function → Redis TCP
      unawaited(_callFunction(_updateLocationUrl, {
        'driverId': driverId,
        'lat': lat,
        'lng': lng,
        'status': status,
      }));

      // Slow path: Firestore throttled
      final now      = DateTime.now();
      final lastWrite = _lastFirestoreWrite[driverId];
      final elapsed  = lastWrite == null
          ? const Duration(days: 1)
          : now.difference(lastWrite);
      if (elapsed.inSeconds >= _firestoreSyncIntervalSec) {
        _lastFirestoreWrite[driverId] = now;
        unawaited(_writeToFirestore(driverId: driverId, lat: lat, lng: lng));
      }
    } else {
      // Solo Firestore (modo legacy / sin backend desplegado)
      await _writeToFirestore(driverId: driverId, lat: lat, lng: lng);
    }
  }

  /// Marca al conductor como offline — limpia todos los índices Redis.
  Future<void> setDriverOffline(String driverId) async {
    if (!redisEnabled) return;
    try {
      await _callFunction(_setOfflineUrl, {'driverId': driverId});
    } catch (_) {
      // No crítico: Redis tiene EXPIRE automático de 120 s
    }
  }

  /// Busca conductores cercanos usando Redis GEOSEARCH vía Cloud Function.
  ///
  /// Retorna lista de {driverId, lat, lng, distanceKm}.
  /// Latencia esperada: 50-100 ms (red + 2-5 ms Redis).
  /// Si falla, retorna [] para que DriverService haga fallback a Firestore.
  Future<List<Map<String, dynamic>>> getDriversNearby({
    required double lat,
    required double lng,
    double radiusKm = 10.0,
    int limit = 10,
  }) async {
    if (!redisEnabled) return [];
    try {
      final body = await _callFunction(_getNearbyUrl, {
        'lat': lat,
        'lng': lng,
        'radiusKm': radiusKm,
        'limit': limit,
      });
      final drivers = body['drivers'] as List? ?? [];
      return drivers.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Lee posiciones desde Redis (alias para compatibilidad).
  Future<List<Map<String, dynamic>>> getOnlineDriverPositions() async {
    return getDriversNearby(lat: 4.3478, lng: -74.3649, radiusKm: 10.0);
  }

  void dispose() {
    _http.close();
  }

  // ── Implementación interna ─────────────────────────────────────────────────

  /// Llama a una Cloud Function autenticada con el Firebase ID Token del usuario.
  Future<Map<String, dynamic>> _callFunction(
    String url,
    Map<String, dynamic> body,
  ) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');

    final token = await user.getIdToken();
    final resp  = await _http
        .post(
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type':  'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 8));

    if (resp.statusCode != 200) {
      throw Exception('Cloud Function error ${resp.statusCode}: ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> _writeToFirestore({
    required String driverId,
    required double lat,
    required double lng,
  }) async {
    await _firestore
        .collection(AppConstants.driversCollection)
        .doc(driverId)
        .set(
      {
        'currentLat': lat,
        'currentLng': lng,
        'updatedAt':  FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
