import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/driver_model.dart';
import '../../../../services/driver_service.dart';

class AdminDriversPage extends StatefulWidget {
  const AdminDriversPage({super.key});

  @override
  State<AdminDriversPage> createState() => _AdminDriversPageState();
}

class _AdminDriversPageState extends State<AdminDriversPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DriverService _driverService = DriverService();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transportadores'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Todos'),
            Tab(text: 'Activos'),
            Tab(text: 'Suspendidos'),
          ],
          labelStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
      body: Column(
        children: [
          // Búsqueda
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre o placa...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),

          // Lista de conductores
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _DriverList(
                  stream: _driverService.watchAllDrivers(),
                  searchQuery: _searchQuery,
                  onSuspend: _suspendDriver,
                  onReactivate: _reactivateDriver,
                ),
                _DriverList(
                  stream: _driverService
                      .watchAllDrivers()
                      .map((d) => d
                          .where((driver) =>
                              driver.subscriptionStatus == 'active')
                          .toList()),
                  searchQuery: _searchQuery,
                  onSuspend: _suspendDriver,
                  onReactivate: _reactivateDriver,
                ),
                _DriverList(
                  stream: _driverService
                      .watchAllDrivers()
                      .map((d) => d
                          .where((driver) =>
                              driver.status ==
                              AppConstants.driverStatusSuspended)
                          .toList()),
                  searchQuery: _searchQuery,
                  onSuspend: _suspendDriver,
                  onReactivate: _reactivateDriver,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _suspendDriver(DriverModel driver) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Suspender conductor'),
        content: Text(
            '¿Suspender a ${driver.name}? No podrá recibir viajes hasta renovar su suscripción.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _driverService.suspendDriver(
                  driver.id, 'Suspendido por administrador');
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorColor),
            child: const Text('Suspender'),
          ),
        ],
      ),
    );
  }

  void _reactivateDriver(DriverModel driver) async {
    await _driverService.reactivateDriver(driver.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${driver.name} fue reactivado')),
      );
    }
  }
}

class _DriverList extends StatelessWidget {
  final Stream<List<DriverModel>> stream;
  final String searchQuery;
  final void Function(DriverModel) onSuspend;
  final void Function(DriverModel) onReactivate;

  const _DriverList({
    required this.stream,
    required this.searchQuery,
    required this.onSuspend,
    required this.onReactivate,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DriverModel>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var drivers = snapshot.data!;
        if (searchQuery.isNotEmpty) {
          drivers = drivers
              .where((d) =>
                  d.name.toLowerCase().contains(searchQuery) ||
                  d.vehiclePlate.toLowerCase().contains(searchQuery))
              .toList();
        }

        if (drivers.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_off_outlined,
                    size: 60,
                    color: AppTheme.textSecondary.withValues(alpha: 0.3)),
                const SizedBox(height: 12),
                Text(
                  'No hay conductores',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: drivers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _DriverCard(
            driver: drivers[i],
            onSuspend: () => onSuspend(drivers[i]),
            onReactivate: () => onReactivate(drivers[i]),
          ),
        );
      },
    );
  }
}

class _DriverCard extends StatelessWidget {
  final DriverModel driver;
  final VoidCallback onSuspend;
  final VoidCallback onReactivate;

  const _DriverCard({
    required this.driver,
    required this.onSuspend,
    required this.onReactivate,
  });

  @override
  Widget build(BuildContext context) {
    final isSuspended = driver.status == AppConstants.driverStatusSuspended;
    final isOnline = driver.isOnline;
    final subscriptionDays = driver.daysUntilExpiry;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSuspended
              ? AppTheme.errorColor.withValues(alpha: 0.3)
              : AppTheme.dividerColor,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 24,
                backgroundColor: isSuspended
                    ? AppTheme.errorColor.withValues(alpha: 0.1)
                    : AppTheme.primaryColor.withValues(alpha: 0.1),
                child: Text(
                  driver.name.isNotEmpty ? driver.name[0].toUpperCase() : 'D',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: isSuspended
                        ? AppTheme.errorColor
                        : AppTheme.primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driver.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            driver.vehiclePlate,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          driver.vehicleType == 'moto'
                              ? Icons.two_wheeler
                              : Icons.directions_car,
                          size: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Estado online
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isOnline
                      ? AppTheme.successColor.withValues(alpha: 0.1)
                      : AppTheme.textSecondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isOnline ? 'En línea' : 'Offline',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isOnline
                        ? AppTheme.successColor
                        : AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Suscripción
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSuspended
                  ? AppTheme.errorColor.withValues(alpha: 0.05)
                  : driver.isSubscriptionActive
                      ? AppTheme.successColor.withValues(alpha: 0.05)
                      : AppTheme.warningColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  isSuspended
                      ? Icons.block
                      : driver.isSubscriptionActive
                          ? Icons.check_circle_outline
                          : Icons.warning_amber,
                  size: 16,
                  color: isSuspended
                      ? AppTheme.errorColor
                      : driver.isSubscriptionActive
                          ? AppTheme.successColor
                          : AppTheme.warningColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isSuspended
                        ? 'Suspendido'
                        : driver.isSubscriptionActive
                            ? 'Activo · ${driver.subscriptionPlan == 'weekly' ? 'Plan semanal' : 'Plan mensual'} · $subscriptionDays día(s)'
                            : 'Suscripción vencida',
                    style: TextStyle(
                      fontSize: 12,
                      color: isSuspended
                          ? AppTheme.errorColor
                          : driver.isSubscriptionActive
                              ? AppTheme.successColor
                              : AppTheme.warningColor,
                    ),
                  ),
                ),

                // Acciones
                if (isSuspended)
                  TextButton(
                    onPressed: onReactivate,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(70, 28),
                    ),
                    child: const Text('Reactivar',
                        style: TextStyle(fontSize: 12)),
                  )
                else
                  TextButton(
                    onPressed: onSuspend,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(70, 28),
                      foregroundColor: AppTheme.errorColor,
                    ),
                    child: const Text('Suspender',
                        style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
