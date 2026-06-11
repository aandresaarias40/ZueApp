import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/user_model.dart';
import '../../../../services/admin_service.dart';
import '../../../auth/bloc/auth_bloc.dart';

/// Gestión de administradores: promover usuarios existentes a admin y
/// revocar el rol. Todo pasa por la Cloud Function setAdminRole, que valida
/// que quien llama sea administrador.
class AdminAdminsPage extends StatefulWidget {
  const AdminAdminsPage({super.key});

  @override
  State<AdminAdminsPage> createState() => _AdminAdminsPageState();
}

class _AdminAdminsPageState extends State<AdminAdminsPage> {
  final AdminService _adminService = AdminService();
  final _emailController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String? get _currentAdminId {
    final state = context.read<AuthBloc>().state;
    return state is AuthAuthenticatedState ? state.user.id : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Administradores')),
      body: Column(
        children: [
          // Promover nuevo admin
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Promover a administrador',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'El usuario debe tener una cuenta registrada en Zue. '
                    'Obtendrá acceso total al panel: podrá bloquear cuentas, '
                    'gestionar pagos y nombrar otros administradores.',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            hintText: 'correo@ejemplo.com',
                            prefixIcon: Icon(Icons.email_outlined),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _busy ? null : _promoteByEmail,
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Promover'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Lista de admins actuales
          Expanded(
            child: StreamBuilder<List<UserModel>>(
              stream: _adminService.watchUsersByRole(AppConstants.roleAdmin),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Error al cargar administradores:\n${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.errorColor),
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final admins = snapshot.data!;
                if (admins.isEmpty) {
                  return Center(
                    child: Text(
                      'No hay administradores registrados',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: admins.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final adminUser = admins[i];
                    final isSelf = adminUser.id == _currentAdminId;
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.dividerColor),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor:
                                AppTheme.warningColor.withValues(alpha: 0.1),
                            child: const Icon(Icons.admin_panel_settings,
                                color: AppTheme.warningColor),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isSelf
                                      ? '${adminUser.name} (tú)'
                                      : adminUser.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  adminUser.email,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!isSelf)
                            TextButton(
                              onPressed:
                                  _busy ? null : () => _revoke(adminUser),
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.errorColor,
                              ),
                              child: const Text('Revocar',
                                  style: TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _promoteByEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showError('Ingresa un correo válido');
      return;
    }

    setState(() => _busy = true);
    try {
      final user = await _adminService.findUserByEmail(email);
      if (user == null) {
        _showError('No existe un usuario registrado con ese correo');
        return;
      }
      if (user.role == AppConstants.roleAdmin) {
        _showError('${user.name} ya es administrador');
        return;
      }
      if (user.isBlocked) {
        _showError('No se puede promover a un usuario bloqueado');
        return;
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Confirmar promoción'),
          content: Text(
              '¿Convertir a ${user.name} (${user.email}) en administrador? '
              'Tendrá control total de la plataforma.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Promover'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      await _adminService.setAdminRole(userId: user.id, makeAdmin: true);
      _emailController.clear();
      _showSuccess('${user.name} ahora es administrador');
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(UserModel adminUser) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Revocar administrador'),
        content: Text(
            '¿Quitar el rol de administrador a ${adminUser.name}? Volverá a '
            'su rol anterior y perderá acceso al panel.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: const Text('Revocar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await _adminService.setAdminRole(userId: adminUser.id, makeAdmin: false);
      _showSuccess('Rol de administrador revocado a ${adminUser.name}');
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.errorColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}
