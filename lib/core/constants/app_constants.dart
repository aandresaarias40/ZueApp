class AppConstants {
  // Firestore Collections
  static const String usersCollection = 'users';
  static const String driversCollection = 'drivers';
  static const String tripsCollection = 'trips';
  static const String paymentsCollection = 'payments';

  // User Roles
  static const String rolePassenger = 'passenger';
  static const String roleDriver = 'driver';
  static const String roleAdmin = 'admin';

  // Trip Status
  static const String tripStatusRequested = 'requested';
  static const String tripStatusAccepted = 'accepted';
  static const String tripStatusOnRoute = 'on_route';
  static const String tripStatusInProgress = 'in_progress';
  static const String tripStatusCompleted = 'completed';
  static const String tripStatusCancelled = 'cancelled';

  // Driver Status
  static const String driverStatusActive = 'active';
  static const String driverStatusInactive = 'inactive';
  static const String driverStatusBusy = 'busy';
  static const String driverStatusSuspended = 'suspended'; // Sin pago

  // Subscription Plans
  static const String planWeekly = 'weekly';
  static const String planMonthly = 'monthly';

  // Subscription Prices (COP)
  static const double weeklyPrice = 40000;  // $40.000 COP / semana
  static const double monthlyPrice = 140000; // $140.000 COP / mes

  // Payment
  static const String paymentStatusPending = 'pending';
  static const String paymentStatusApproved = 'approved';
  static const String paymentStatusDeclined = 'declined';

  // Vehicle Types
  static const String vehicleCar = 'car';
  static const String vehicleMoto = 'moto';

  // Tarifas Carro – Fusagasugá (COP)
  static const double minimumFareDistanceKm = 6.0;  // Rutas < 6 km → tarifa fija
  static const double minimumFare = 8000;            // $8.000 COP tarifa fija mínima (carro)
  static const double carBaseFare = 3000;            // Tarifa base carro (rutas >= 6 km)
  static const double carPerKmRate = 1200;           // $1.200 por km adicional (carro)

  // Tarifas Moto – Fusagasugá (COP)
  static const double motoMinimumFare = 4500;        // $4.500 COP tarifa fija mínima (moto)
  static const double motoBaseFare = 1500;           // Tarifa base moto (rutas >= 6 km)
  static const double motoPerKmRate = 600;           // $600 por km adicional (moto)

  // Recargo nocturno (aplica a carro y moto)
  static const double nightSurcharge = 1000;          // $1.000 COP extra en horario nocturno
  static const int nightStartHour = 19;               // 7:00 pm
  static const int nightEndHour = 5;                  // 5:00 am

  // Período de prueba para conductores nuevos
  static const int driverTrialDays = 3;
  static const String subscriptionStatusTrial = 'trial';

  // Anti-fraude: colección de identidades de conductores
  static const String driverIdentitiesCollection = 'driver_identities';

  // ── Moderación / bloqueos administrativos ────────────────────────────────
  static const String adminsCollection = 'admins';
  static const String moderationLogCollection = 'moderation_log';

  // Categorías de bloqueo (medida disciplinaria / incidente)
  static const String blockCategoryIncident = 'incident';
  static const String blockCategoryDisciplinary = 'disciplinary';
  static const String blockCategoryFraud = 'fraud';
  static const String blockCategoryOther = 'other';

  static const Map<String, String> blockCategoryLabels = {
    blockCategoryIncident: 'Incidente',
    blockCategoryDisciplinary: 'Medida disciplinaria',
    blockCategoryFraud: 'Fraude',
    blockCategoryOther: 'Otro',
  };

  // Google Maps
  static const double defaultLat = 4.3478;  // Fusagasugá, Cundinamarca
  static const double defaultLng = -74.3649;
  static const double defaultZoom = 14.0;

  // ── Redis / Upstash (telemetría GPS hot-path) ─────────────────────────────
  // Las credenciales Upstash viven SOLO en Cloud Functions (functions/index.js).
  // redisEnabled = false → usar solo Firestore (comportamiento original).
  static const bool redisEnabled = true;
  static const int  firestoreSyncIntervalSec = 30; // sync Redis→Firestore cada 30 s

  // GPS / Location tracking (conductores en línea)
  // Resultado stress test: P50 = 15ms (excelente), P95 = 2079ms (burst inicial).
  // Aumentar filtros reduce 1.7M escrituras/día → ~345K (salvo movimiento constante).
  static const int gpsDistanceFilter = 50;        // metros mínimos de movimiento
  static const int gpsMinIntervalSeconds = 10;    // throttle: mínimo 10s entre writes

  // Timeouts & Limits
  static const int maxDriverSearchRadius = 10000; // 10 km
  // Máx candidatos que Firestore devuelve antes del filtro haversine en cliente.
  // Limita el payload: O(50 docs) vs O(todos los online). El índice compuesto
  // isOnline+status resuelve el LIMIT en servidor sin table scan.
  static const int maxNearbyDriverFetch = 50;

  // Pagination
  static const int pageSize = 20;

  // ── Payment Gateway (Wompi Colombia) ─────────────────────────────────────
  // SETUP:
  //   1. Entra a https://dashboard.wompi.co → Desarrolladores → Llaves de API
  //   2. Copia la llave pública de SANDBOX (empieza con pub_test_) y reemplaza
  //      wompiSandboxPublicKey abajo.
  //   3. La llave PRIVADA (prv_test_...) va SOLO en functions/index.js
  //      como constante WOMPI_PRIVATE_KEY — NUNCA en este archivo.
  //   4. Para producción: compila con --dart-define=WOMPI_SANDBOX=false
  //      (la llave de producción ya está en wompiProdPublicKey).
  //
  // ⚠️  NUNCA pongas la llave privada aquí — el APK puede ser decompilado.

  // Configurable por entorno SIN tocar código:
  //   flutter build apk --dart-define=WOMPI_SANDBOX=false  → producción
  //   (por defecto true = sandbox, seguro para desarrollo)
  static const bool wompiUseSandbox =
      bool.fromEnvironment('WOMPI_SANDBOX', defaultValue: true);

  // Llaves públicas (seguro incluirlas en el APK — solo inician transacciones)
  static const String wompiSandboxPublicKey =
      'pub_test_x34zykJEK8CFRGMid8X3iffgPGu961L6';
  static const String wompiProdPublicKey =
      'pub_prod_nIeXMtOGEWbZK35uXhF8BJw47yszYMZ5';

  // Selector automático según entorno
  static String get wompiPublicKey =>
      wompiUseSandbox ? wompiSandboxPublicKey : wompiProdPublicKey;

  // ⚠️  Las llaves de integridad NO van en el APK.
  // La firma SHA-256 la calcula la Cloud Function createPSETransaction
  // usando WOMPI_INTEGRITY_SECRET del entorno del servidor (functions/.env).

  // URLs base de la API
  static const String wompiSandboxUrl    = 'https://sandbox.wompi.co/v1';
  static const String wompiProductionUrl = 'https://production.wompi.co/v1';
  static String get wompiBaseUrl =>
      wompiUseSandbox ? wompiSandboxUrl : wompiProductionUrl;

  // URL de redirect tras el pago PSE.
  // El WebView intercepta cualquier navegación hacia este dominio para
  // capturar los parámetros id, status, reference, etc.
  // Wompi NO acepta custom schemes (zue://); debe ser HTTPS.
  // URL de redirect de Wompi. El WebView la intercepta en la app — no necesita
  // cargar nada real. Usa Firebase Hosting del proyecto zue-app.
  static const String wompiRedirectUrl =
      'https://zue-app.web.app/payment/callback';

  // ── Cloud Functions URLs (Cloud Run Gen 2) ───────────────────────────────
  // Sufijo -avqcfqbgeq es único del proyecto zue-app (ver firebase deploy output).
  // Formato: https://{functionname}-avqcfqbgeq-uc.a.run.app
  static const String cfCreatePSETransaction =
      'https://createpsetransaction-avqcfqbgeq-uc.a.run.app';

  // Moderación (solo admins; la CF verifica el token y la colección admins)
  static const String cfSetUserBlocked =
      'https://setuserblocked-avqcfqbgeq-uc.a.run.app';
  static const String cfSetAdminRole =
      'https://setadminrole-avqcfqbgeq-uc.a.run.app';
}
