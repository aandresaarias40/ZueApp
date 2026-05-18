import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/driver_model.dart';
import '../../../../models/user_model.dart';
import '../../../auth/bloc/auth_bloc.dart';
import '../../bloc/driver_bloc.dart';

class DriverProfilePage extends StatefulWidget {
  const DriverProfilePage({super.key});

  @override
  State<DriverProfilePage> createState() => _DriverProfilePageState();
}

class _DriverProfilePageState extends State<DriverProfilePage> {
  @override
  void initState() {
    super.initState();
    // Si el DriverBloc no tiene datos, recargar
    final driverState = context.read<DriverBloc>().state;
    if (driverState is DriverInitialState || driverState is DriverErrorState) {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticatedState) {
        context.read<DriverBloc>().add(
              LoadDriverEvent(driverId: authState.user.id),
            );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.go(AppRoutes.driverHome),
        ),
      ),
      body: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, authState) {
          // Datos básicos siempre disponibles desde AuthBloc
          final user = authState is AuthAuthenticatedState
              ? authState.user
              : null;

          return BlocBuilder<DriverBloc, DriverState>(
            builder: (context, driverState) {
              // ── Cargando ──────────────────────────────────────────────
              if (driverState is DriverLoadingState ||
                  driverState is DriverInitialState) {
                return _ProfileLoading(user: user);
              }

              // ── Error: mostrar perfil básico desde AuthBloc ────────────
              if (driverState is DriverErrorState) {
                return _BasicProfile(
                  user: user,
                  errorMessage: driverState.message,
                  onRetry: () {
                    if (user != null) {
                      context.read<DriverBloc>().add(
                            LoadDriverEvent(driverId: user.id),
                          );
                    }
                  },
                );
              }

              // ── Perfil completo ────────────────────────────────────────
              if (driverState is DriverLoadedState) {
                return _FullProfile(
                  driver: driverState.driver,
                  onLogout: () =>
                      context.read<AuthBloc>().add(AuthLogoutEvent()),
                );
              }

              return _ProfileLoading(user: user);
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget: Cargando (con datos básicos del usuario si están disponibles)
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileLoading extends StatelessWidget {
  final UserModel? user;
  const _ProfileLoading({this.user});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Avatar con inicial del nombre
          CircleAvatar(
            radius: 50,
            backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
            child: user != null && user!.name.isNotEmpty
                ? Text(
                    user!.name[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor,
                    ),
                  )
                : const Icon(Icons.person,
                    size: 40, color: AppTheme.primaryColor),
          ),
          const SizedBox(height: 16),
          if (user != null) ...[
            Text(
              user!.name,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              user!.email,
              style:
                  const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
          ],
          const SizedBox(height: 32),
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            'Cargando perfil...',
            style:
                TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget: Perfil básico cuando hay error cargando datos del conductor
// ─────────────────────────────────────────────────────────────────────────────
class _BasicProfile extends StatelessWidget {
  final UserModel? user;
  final String errorMessage;
  final VoidCallback onRetry;

  const _BasicProfile({
    this.user,
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Avatar
          CircleAvatar(
            radius: 50,
            backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
            child: user != null && user!.name.isNotEmpty
                ? Text(
                    user!.name[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor,
                    ),
                  )
                : const Icon(Icons.person,
                    size: 40, color: AppTheme.primaryColor),
          ),
          const SizedBox(height: 16),

          if (user != null) ...[
            Text(
              user!.name,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              user!.email,
              style: const TextStyle(
                  fontSize: 14, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            if (user!.phone.isNotEmpty)
              Text(
                user!.phone,
                style: const TextStyle(
                    fontSize: 14, color: AppTheme.textSecondary),
              ),
          ],

          const SizedBox(height: 24),

          // Info de suscripción pendiente
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.warningColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppTheme.warningColor.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                const Icon(Icons.credit_card_off_outlined,
                    color: AppTheme.warningColor, size: 32),
                const SizedBox(height: 8),
                const Text(
                  'Suscripción pendiente',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.warningColor,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Activa tu suscripción para comenzar a recibir viajes en Zue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        context.go(AppRoutes.driverSubscription),
                    icon: const Icon(Icons.account_balance, size: 18),
                    label: const Text('Activar con PSE'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Botón reintentar
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Recargar perfil'),
          ),

          const SizedBox(height: 20),

          // Cerrar sesión
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () =>
                  context.read<AuthBloc>().add(AuthLogoutEvent()),
              icon: const Icon(Icons.logout, color: AppTheme.errorColor),
              label: const Text(
                'Cerrar Sesión',
                style: TextStyle(color: AppTheme.errorColor),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.errorColor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget: Perfil completo cuando el DriverBloc cargó correctamente
// ─────────────────────────────────────────────────────────────────────────────
class _FullProfile extends StatelessWidget {
  final DriverModel driver;
  final VoidCallback onLogout;

  const _FullProfile({required this.driver, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Avatar
          CircleAvatar(
            radius: 50,
            backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
            child: Text(
              driver.name.isNotEmpty ? driver.name[0].toUpperCase() : 'D',
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            driver.name,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),

          // Estrellas de calificación (solo cuando hay ≥5 viajes)
          if (driver.hasRating)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ...List.generate(
                  5,
                  (i) => Icon(
                    i < driver.rating.round()
                        ? Icons.star
                        : Icons.star_border,
                    size: 18,
                    color: AppTheme.accentColor,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  driver.rating.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.textSecondary),
                ),
              ],
            )
          else
            Text(
              'Sin calificación aún',
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary),
            ),

          const SizedBox(height: 32),

          // ── Tarjeta de suscripción ──────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.verified, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Estado de Suscripción',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  driver.isSubscriptionActive ? 'ACTIVA ✓' : 'PENDIENTE',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (driver.isSubscriptionActive)
                  Text(
                    'Vence en ${driver.daysUntilExpiry} día(s) · '
                    'Plan ${driver.subscriptionPlan == 'weekly' ? 'Semanal' : 'Mensual'}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 13,
                    ),
                  )
                else
                  const Text(
                    'Activa tu suscripción para recibir viajes',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 13),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () =>
                        context.go(AppRoutes.driverSubscription),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.primaryColor,
                    ),
                    child: Text(driver.isSubscriptionActive
                        ? 'Renovar plan'
                        : 'Activar ahora'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Estadísticas ─────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  value: driver.totalTrips.toString(),
                  label: 'Viajes',
                  icon: Icons.directions_car,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  value: driver.ratingDisplay,
                  label: 'Calificación',
                  icon: Icons.star,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Vehículo ─────────────────────────────────────────────────
          if (driver.vehiclePlate.isNotEmpty)
            _InfoSection(
              title: 'Vehículo',
              items: [
                _InfoItem('Tipo',
                    driver.vehicleType == 'car' ? 'Carro' : 'Moto'),
                _InfoItem('Placa', driver.vehiclePlate),
                if (driver.vehicleModel.isNotEmpty)
                  _InfoItem('Modelo', driver.vehicleModel),
                if (driver.vehicleColor.isNotEmpty)
                  _InfoItem('Color', driver.vehicleColor),
              ],
            )
          else
            // Si no tiene vehículo registrado, mostrar botón para completar perfil
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AppTheme.primaryColor.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.directions_car_outlined,
                      color: AppTheme.primaryColor, size: 32),
                  const SizedBox(height: 8),
                  const Text(
                    'Completa tus datos de vehículo',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Agrega la información de tu vehículo para empezar',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // ── Datos personales ──────────────────────────────────────────
          _InfoSection(
            title: 'Datos Personales',
            items: [
              _InfoItem('Celular', driver.phone),
              _InfoItem('Email', driver.email),
              if (driver.licenseNumber.isNotEmpty)
                _InfoItem('Cédula/Licencia', driver.licenseNumber),
            ],
          ),

          const SizedBox(height: 24),

          // ── Cerrar sesión ────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout, color: AppTheme.errorColor),
              label: const Text(
                'Cerrar Sesión',
                style: TextStyle(color: AppTheme.errorColor),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.errorColor),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets menores
// ─────────────────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;

  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 28),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w700)),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final String title;
  final List<_InfoItem> items;

  const _InfoSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(item.label,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13)),
                  Flexible(
                    child: Text(
                      item.value.isEmpty ? '—' : item.value,
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 13),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoItem {
  final String label;
  final String value;
  const _InfoItem(this.label, this.value);
}
