import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../models/user_model.dart';
import '../../../../services/admin_service.dart';
import '../widgets/block_reason_dialog.dart';

/// Gestión de usuarios: bloquear/desbloquear pasajeros y conductores
/// como medida disciplinaria o por incidentes.
class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AdminService _adminService = AdminService();
  String _searchQuery = '';
  bool _busy = false;

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
        title: const Text('Usuarios'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Pasajeros'),
            Tab(text: 'Conductores'),
            Tab(text: 'Bloqueados'),
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre, correo o teléfono...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _UserList(
                  stream: _adminService
                      .watchUsersByRole(AppConstants.rolePassenger),
                  searchQuery: _searchQuery,
                  onBlock: _blockUser,
                  onUnblock: _unblockUser,
                ),
                _UserList(
                  stream:
                      _adminService.watchUsersByRole(AppConstants.roleDriver),
                  searchQuery: _searchQuery,
                  onBlock: _blockUser,
                  onUnblock: _unblockUser,
                ),
                _UserList(
                  stream: _adminService.watchBlockedUsers(),
                  searchQuery: _searchQuery,
                  onBlock: _blockUser,
                  onUnblock: _unblockUser,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _blockUser(UserModel user) async {
    final result = await showBlockReasonDialog(
      context,
      title: 'Bloquear cuenta',
      subtitle:
          '${user.name} (${user.role == 'driver' ? 'conductor' : 'pasajero'}) '
          'no podrá iniciar sesión y su sesión activa se cerrará de inmediato. '
          'El motivo quedará en el historial de moderación.',
      confirmLabel: 'Bloquear',
    );
    if (result == null) return;

    await _runAction(
      () => _adminService.setUserBlocked(
        userId: user.id,
        blocked: true,
        category: result.category,
        reason: result.reason,
      ),
      successMessage: '${user.name} fue bloqueado',
    );
  }

  Future<void> _unblockUser(UserModel user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Desbloquear cuenta'),
        content: Text(
            '¿Restaurar el acceso de ${user.name}? Podrá iniciar sesión y '
            'usar la app de nuevo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desbloquear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _runAction(
      () => _adminService.setUserBlocked(userId: user.id, blocked: false),
      successMessage: '${user.name} fue desbloqueado',
    );
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        AppSnackBar.success(context, successMessage);
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(
          context,
          e.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _UserList extends StatelessWidget {
  final Stream<List<UserModel>> stream;
  final String searchQuery;
  final void Function(UserModel) onBlock;
  final void Function(UserModel) onUnblock;

  const _UserList({
    required this.stream,
    required this.searchQuery,
    required this.onBlock,
    required this.onUnblock,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UserModel>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error al cargar usuarios:\n${snapshot.error}',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 13, color: AppTheme.errorColor),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var users = snapshot.data!;
        if (searchQuery.isNotEmpty) {
          users = users
              .where((u) =>
                  u.name.toLowerCase().contains(searchQuery) ||
                  u.email.toLowerCase().contains(searchQuery) ||
                  u.phone.toLowerCase().contains(searchQuery))
              .toList();
        }

        if (users.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline,
                    size: 60,
                    color: AppTheme.textSecondary.withValues(alpha: 0.3)),
                const SizedBox(height: 12),
                Text(
                  'No hay usuarios',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: users.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _UserCard(
            user: users[i],
            onBlock: () => onBlock(users[i]),
            onUnblock: () => onUnblock(users[i]),
          ),
        );
      },
    );
  }
}

class _UserCard extends StatelessWidget {
  final UserModel user;
  final VoidCallback onBlock;
  final VoidCallback onUnblock;

  const _UserCard({
    required this.user,
    required this.onBlock,
    required this.onUnblock,
  });

  @override
  Widget build(BuildContext context) {
    final isBlocked = user.isBlocked;
    final isDriver = user.role == AppConstants.roleDriver;
    final isAdmin = user.role == AppConstants.roleAdmin;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isBlocked
              ? AppTheme.errorColor.withValues(alpha: 0.3)
              : AppTheme.dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: isBlocked
                    ? AppTheme.errorColor.withValues(alpha: 0.1)
                    : AppTheme.primaryColor.withValues(alpha: 0.1),
                child: Text(
                  user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isBlocked
                        ? AppTheme.errorColor
                        : AppTheme.primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${user.email} · ${user.phone}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (isDriver
                          ? AppTheme.accentColor
                          : isAdmin
                              ? AppTheme.warningColor
                              : AppTheme.primaryColor)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isDriver
                      ? 'Conductor'
                      : isAdmin
                          ? 'Admin'
                          : 'Pasajero',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDriver
                        ? AppTheme.accentColor
                        : isAdmin
                            ? AppTheme.warningColor
                            : AppTheme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Estado + acción
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isBlocked
                  ? AppTheme.errorColor.withValues(alpha: 0.05)
                  : AppTheme.successColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  isBlocked ? Icons.block : Icons.check_circle_outline,
                  size: 16,
                  color:
                      isBlocked ? AppTheme.errorColor : AppTheme.successColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isBlocked
                        ? 'Bloqueado · ${user.blockCategoryLabel}'
                            '${user.blockedAt != null ? ' · ${DateFormat('dd/MM/yyyy').format(user.blockedAt!)}' : ''}'
                        : 'Cuenta activa',
                    style: TextStyle(
                      fontSize: 12,
                      color: isBlocked
                          ? AppTheme.errorColor
                          : AppTheme.successColor,
                    ),
                  ),
                ),
                if (isBlocked)
                  TextButton(
                    onPressed: onUnblock,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(90, 28),
                    ),
                    child: const Text('Desbloquear',
                        style: TextStyle(fontSize: 12)),
                  )
                else if (!isAdmin)
                  TextButton(
                    onPressed: onBlock,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(70, 28),
                      foregroundColor: AppTheme.errorColor,
                    ),
                    child:
                        const Text('Bloquear', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),

          // Motivo del bloqueo
          if (isBlocked &&
              user.blockReason != null &&
              user.blockReason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Motivo: ${user.blockReason}',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
