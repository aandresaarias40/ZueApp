import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_passenger_page.dart';
import '../../features/auth/presentation/pages/register_driver_page.dart';
import '../../features/auth/presentation/pages/splash_page.dart';
import '../../features/passenger/presentation/pages/passenger_home_page.dart';
import '../../features/passenger/presentation/pages/request_trip_page.dart';
import '../../features/passenger/presentation/pages/trip_tracking_page.dart';
import '../../features/passenger/presentation/pages/trip_history_page.dart';
import '../../features/driver/presentation/pages/driver_home_page.dart';
import '../../features/driver/presentation/pages/driver_subscription_page.dart';
import '../../features/driver/presentation/pages/driver_profile_page.dart';
import '../../features/admin/presentation/pages/admin_dashboard_page.dart';
import '../../features/admin/presentation/pages/admin_drivers_page.dart';
import '../../features/admin/presentation/pages/admin_payments_page.dart';
import '../../features/admin/presentation/pages/admin_trips_page.dart';
import '../../features/auth/bloc/auth_bloc.dart';

class AppRoutes {
  // Auth
  static const String splash = '/';
  static const String login = '/login';
  static const String registerPassenger = '/register/passenger';
  static const String registerDriver = '/register/driver';

  // Passenger
  static const String passengerHome = '/passenger/home';
  static const String requestTrip = '/passenger/request';
  static const String tripTracking = '/passenger/tracking/:tripId';
  static const String tripHistory = '/passenger/history';

  // Driver
  static const String driverHome = '/driver/home';
  static const String driverSubscription = '/driver/subscription';
  static const String driverProfile = '/driver/profile';

  // Admin
  static const String adminDashboard = '/admin/dashboard';
  static const String adminDrivers = '/admin/drivers';
  static const String adminPayments = '/admin/payments';
  static const String adminTrips = '/admin/trips';
}

class AppRouter {
  static GoRouter router(AuthState authState) {
    return GoRouter(
      initialLocation: AppRoutes.splash,
      redirect: (context, state) {
        final isLoggedIn = authState is AuthAuthenticatedState;
        final isLoading = authState is AuthLoadingState || authState is AuthInitialState;
        final isSplash = state.matchedLocation == AppRoutes.splash;
        final isAuthRoute = state.matchedLocation == AppRoutes.login ||
            state.matchedLocation == AppRoutes.registerPassenger ||
            state.matchedLocation == AppRoutes.registerDriver;

        if (isLoading) return isSplash ? null : AppRoutes.splash;
        if (!isLoggedIn && !isAuthRoute) return AppRoutes.login;

        if (isLoggedIn) {
          final user = (authState as AuthAuthenticatedState).user;
          if (isAuthRoute || isSplash) {
            switch (user.role) {
              case 'passenger': return AppRoutes.passengerHome;
              case 'driver': return AppRoutes.driverHome;
              case 'admin': return AppRoutes.adminDashboard;
              default: return AppRoutes.login;
            }
          }
        }
        return null;
      },
      routes: [
        // Splash
        GoRoute(
          path: AppRoutes.splash,
          builder: (_, __) => const SplashPage(),
        ),

        // Auth
        GoRoute(
          path: AppRoutes.login,
          builder: (_, __) => const LoginPage(),
        ),
        GoRoute(
          path: AppRoutes.registerPassenger,
          builder: (_, __) => const RegisterPassengerPage(),
        ),
        GoRoute(
          path: AppRoutes.registerDriver,
          builder: (_, __) => const RegisterDriverPage(),
        ),

        // Passenger Routes
        GoRoute(
          path: AppRoutes.passengerHome,
          builder: (_, __) => const PassengerHomePage(),
        ),
        GoRoute(
          path: AppRoutes.requestTrip,
          builder: (_, __) => const RequestTripPage(),
        ),
        GoRoute(
          path: AppRoutes.tripTracking,
          builder: (context, state) => TripTrackingPage(
            tripId: state.pathParameters['tripId']!,
          ),
        ),
        GoRoute(
          path: AppRoutes.tripHistory,
          builder: (_, __) => const TripHistoryPage(),
        ),

        // Driver Routes
        GoRoute(
          path: AppRoutes.driverHome,
          builder: (_, __) => const DriverHomePage(),
        ),
        GoRoute(
          path: AppRoutes.driverSubscription,
          builder: (_, __) => const DriverSubscriptionPage(),
        ),
        GoRoute(
          path: AppRoutes.driverProfile,
          builder: (_, __) => const DriverProfilePage(),
        ),

        // Admin Routes
        GoRoute(
          path: AppRoutes.adminDashboard,
          builder: (_, __) => const AdminDashboardPage(),
        ),
        GoRoute(
          path: AppRoutes.adminDrivers,
          builder: (_, __) => const AdminDriversPage(),
        ),
        GoRoute(
          path: AppRoutes.adminPayments,
          builder: (_, __) => const AdminPaymentsPage(),
        ),
        GoRoute(
          path: AppRoutes.adminTrips,
          builder: (_, __) => const AdminTripsPage(),
        ),
      ],
      errorBuilder: (context, state) => Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('Página no encontrada: ${state.error}'),
              TextButton(
                onPressed: () => context.go(AppRoutes.splash),
                child: const Text('Ir al inicio'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
