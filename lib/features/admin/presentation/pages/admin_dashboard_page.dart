import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/bloc/auth_bloc.dart';

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel Zue Admin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () =>
                context.read<AuthBloc>().add(AuthLogoutEvent()),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bienvenida
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
                  const Text(
                    'Panel de Control',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Gestiona tu plataforma Zue',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Métricas en tiempo real
            const Text(
              'Métricas en tiempo real',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.4,
              children: [
                _MetricCard(
                  title: 'Conductores activos',
                  stream: FirebaseFirestore.instance
                      .collection(AppConstants.driversCollection)
                      .where('isOnline', isEqualTo: true)
                      .snapshots()
                      .map((s) => s.size.toString()),
                  icon: Icons.directions_car,
                  color: AppTheme.successColor,
                ),
                _MetricCard(
                  title: 'Viajes en curso',
                  stream: FirebaseFirestore.instance
                      .collection(AppConstants.tripsCollection)
                      .where('status',
                          isEqualTo: AppConstants.tripStatusInProgress)
                      .snapshots()
                      .map((s) => s.size.toString()),
                  icon: Icons.navigation,
                  color: AppTheme.primaryColor,
                ),
                _MetricCard(
                  title: 'Suscripciones vencidas',
                  stream: FirebaseFirestore.instance
                      .collection(AppConstants.driversCollection)
                      .where('subscriptionStatus', isEqualTo: 'expired')
                      .snapshots()
                      .map((s) => s.size.toString()),
                  icon: Icons.warning_amber,
                  color: AppTheme.warningColor,
                ),
                _MetricCard(
                  title: 'Viajes pendientes',
                  stream: FirebaseFirestore.instance
                      .collection(AppConstants.tripsCollection)
                      .where('status',
                          isEqualTo: AppConstants.tripStatusRequested)
                      .snapshots()
                      .map((s) => s.size.toString()),
                  icon: Icons.hourglass_top,
                  color: AppTheme.accentColor,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Acciones rápidas
            const Text(
              'Gestión',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),

            _AdminMenuCard(
              icon: Icons.person_outline,
              title: 'Transportadores',
              subtitle: 'Ver, suspender y gestionar conductores',
              color: AppTheme.primaryColor,
              onTap: () => context.push(AppRoutes.adminDrivers),
            ),
            const SizedBox(height: 10),

            _AdminMenuCard(
              icon: Icons.manage_accounts_outlined,
              title: 'Usuarios',
              subtitle: 'Bloquear cuentas por incidentes o medidas disciplinarias',
              color: AppTheme.errorColor,
              onTap: () => context.push(AppRoutes.adminUsers),
            ),
            const SizedBox(height: 10),

            _AdminMenuCard(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Administradores',
              subtitle: 'Promover o revocar administradores de la plataforma',
              color: AppTheme.warningColor,
              onTap: () => context.push(AppRoutes.adminAdmins),
            ),
            const SizedBox(height: 10),

            _AdminMenuCard(
              icon: Icons.payments_outlined,
              title: 'Pagos & Suscripciones',
              subtitle: 'Control de pagos PSE y estados de suscripción',
              color: AppTheme.successColor,
              onTap: () => context.push(AppRoutes.adminPayments),
            ),
            const SizedBox(height: 10),

            _AdminMenuCard(
              icon: Icons.map_outlined,
              title: 'Viajes',
              subtitle: 'Monitoreo y despacho manual de viajes',
              color: AppTheme.accentColor,
              onTap: () => context.push(AppRoutes.adminTrips),
            ),
            const SizedBox(height: 24),

            // Ingresos del mes
            const Text(
              'Ingresos del mes',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection(AppConstants.paymentsCollection)
                  .where('status', isEqualTo: AppConstants.paymentStatusApproved)
                  .where(
                    'paidAt',
                    isGreaterThanOrEqualTo: Timestamp.fromDate(
                      DateTime(DateTime.now().year, DateTime.now().month, 1),
                    ),
                  )
                  .snapshots(),
              builder: (context, snapshot) {
                double totalRevenue = 0;
                int paymentsCount = 0;
                if (snapshot.hasData) {
                  paymentsCount = snapshot.data!.docs.length;
                  for (final doc in snapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    totalRevenue += (data['amount'] as num? ?? 0).toDouble();
                  }
                }
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.trending_up,
                          color: AppTheme.successColor, size: 40),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '\$${totalRevenue.toStringAsFixed(0)} COP',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.successColor,
                              ),
                            ),
                            Text(
                              '$paymentsCount pagos este mes',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final Stream<String> stream;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.stream,
    required this.icon,
    required this.color,
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
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 28),
          StreamBuilder<String>(
            stream: stream,
            builder: (_, snapshot) => Text(
              snapshot.data ?? '-',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminMenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _AdminMenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.dividerColor),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}
