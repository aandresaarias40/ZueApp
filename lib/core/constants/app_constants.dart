class AppConstants {
  // App Info
  static const String appName = 'Zue';
  static const String appVersion = '1.0.0';
  static const String appCountry = 'CO'; // Colombia
  static const String appCurrency = 'COP';
  static const String appCurrencySymbol = '\$';

  // Firestore Collections
  static const String usersCollection = 'users';
  static const String driversCollection = 'drivers';
  static const String tripsCollection = 'trips';
  static const String paymentsCollection = 'payments';
  static const String subscriptionsCollection = 'subscriptions';
  static const String notificationsCollection = 'notifications';
  static const String adminCollection = 'admins';
  static const String settingsCollection = 'settings';

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
  static const double weeklyPrice = 35000;  // $35.000 COP / semana
  static const double monthlyPrice = 120000; // $120.000 COP / mes

  // Payment
  static const String paymentStatusPending = 'pending';
  static const String paymentStatusApproved = 'approved';
  static const String paymentStatusDeclined = 'declined';
  static const String paymentStatusFailed = 'failed';

  // Vehicle Types
  static const String vehicleCar = 'car';
  static const String vehicleMoto = 'moto';

  // Tarifas Fusagasugá (COP)
  static const double minimumFareDistanceKm = 6.0;  // Rutas < 6 km → tarifa fija
  static const double minimumFare = 8000;            // $8.000 COP tarifa fija mínima

  // Período de prueba para conductores nuevos
  static const int driverTrialDays = 3;
  static const String subscriptionStatusTrial = 'trial';

  // Anti-fraude: colección de identidades de conductores
  static const String driverIdentitiesCollection = 'driver_identities';

  // Google Maps
  static const double defaultLat = 4.3478;  // Fusagasugá, Cundinamarca
  static const double defaultLng = -74.3649;
  static const double defaultZoom = 14.0;
  static const double nearbyDriverRadius = 5000; // 5 km en metros

  // Timeouts & Limits
  static const int tripRequestTimeout = 60; // segundos para que un conductor acepte
  static const int maxDriverSearchRadius = 10000; // 10 km
  static const int maxActiveTripsPerDriver = 1;

  // Shared Preferences Keys
  static const String prefUserToken = 'user_token';
  static const String prefUserId = 'user_id';
  static const String prefUserRole = 'user_role';
  static const String prefOnboardingDone = 'onboarding_done';
  static const String prefThemeMode = 'theme_mode';
  static const String prefNotifications = 'notifications_enabled';

  // Pagination
  static const int pageSize = 20;

  // Payment Gateway (Wompi Colombia)
  static const String wompiPublicKey = 'pub_test_YOUR_WOMPI_KEY'; // Cambiar en producción
  static const String wompiBaseUrl = 'https://sandbox.wompi.co/v1'; // Sandbox
  static const String wompiProdUrl = 'https://production.wompi.co/v1';

  // Assets Paths
  static const String logoPath = 'assets/images/logo.png';
  static const String logoWhitePath = 'assets/images/logo_white.png';
  static const String splashAnimation = 'assets/animations/splash.json';
  static const String emptyAnimation = 'assets/animations/empty.json';
  static const String loadingAnimation = 'assets/animations/loading.json';
  static const String successAnimation = 'assets/animations/success.json';
  static const String carIcon = 'assets/icons/car_marker.png';
  static const String motoIcon = 'assets/icons/moto_marker.png';
}
