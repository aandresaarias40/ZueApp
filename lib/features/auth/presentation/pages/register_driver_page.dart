import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../services/auth_service.dart';
import '../widgets/auth_text_field.dart';

class RegisterDriverPage extends StatefulWidget {
  const RegisterDriverPage({super.key});

  @override
  State<RegisterDriverPage> createState() => _RegisterDriverPageState();
}

class _RegisterDriverPageState extends State<RegisterDriverPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _plateController = TextEditingController();
  final _vehicleModelController = TextEditingController();
  final _vehicleColorController = TextEditingController();
  final _cedulaController = TextEditingController();
  final _licenseController = TextEditingController();

  String _selectedVehicleType = AppConstants.vehicleCar;
  String _selectedPlan = AppConstants.planWeekly;
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _plateController.dispose();
    _vehicleModelController.dispose();
    _vehicleColorController.dispose();
    _cedulaController.dispose();
    _licenseController.dispose();
    super.dispose();
  }

  Future<void> _onRegister() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final authService = AuthService();
      await authService.registerDriver(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text,
        vehicleType: _selectedVehicleType,
        vehiclePlate: _plateController.text.trim().toUpperCase(),
        vehicleModel: _vehicleModelController.text.trim(),
        vehicleColor: _vehicleColorController.text.trim(),
        cedula: _cedulaController.text.trim(),
        licenseNumber: _licenseController.text.trim(),
        subscriptionPlan: _selectedPlan,
      );
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle,
                      color: AppTheme.successColor, size: 44),
                ),
                const SizedBox(height: 20),
                const Text(
                  '¡Registro exitoso!',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Tu cuenta fue creada correctamente. '
                  'Activa tu suscripción desde el panel del conductor para comenzar a recibir viajes.',
                  style: TextStyle(
                      fontSize: 14, color: AppTheme.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.go(AppRoutes.driverHome);
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(160, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Entrar al panel'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(
          context,
          e.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro Transportador'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.go(AppRoutes.login),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Sección 1: Datos personales ──────────────────────────
              _SectionHeader(
                icon: Icons.person_outline,
                title: 'Datos Personales',
              ),
              const SizedBox(height: 16),

              AuthTextField(
                controller: _nameController,
                label: 'Nombre completo',
                prefixIcon: Icons.person_outline,
                validator: (v) =>
                    v == null || v.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),

              AuthTextField(
                controller: _emailController,
                label: 'Correo electrónico',
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.email_outlined,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requerido';
                  if (!v.contains('@')) return 'Correo inválido';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              AuthTextField(
                controller: _phoneController,
                label: 'Celular',
                hint: '3001234567',
                keyboardType: TextInputType.phone,
                prefixIcon: Icons.phone_outlined,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requerido';
                  if (v.length != 10) return 'Debe tener 10 dígitos';
                  if (!v.startsWith('3')) return 'Debe comenzar con 3';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              AuthTextField(
                controller: _cedulaController,
                label: 'Número de cédula',
                hint: '1234567890',
                keyboardType: TextInputType.number,
                prefixIcon: Icons.badge_outlined,
                maxLength: 11,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requerido';
                  if (v.length < 6) return 'Mínimo 6 dígitos';
                  if (v.length > 11) return 'Máximo 11 dígitos';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              AuthTextField(
                controller: _passwordController,
                label: 'Contraseña',
                obscureText: _obscurePassword,
                prefixIcon: Icons.lock_outline,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AppTheme.textSecondary,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requerido';
                  if (v.length < 6) return 'Mínimo 6 caracteres';
                  return null;
                },
              ),

              const SizedBox(height: 28),

              // ── Sección 2: Vehículo ───────────────────────────────────
              _SectionHeader(
                icon: Icons.directions_car_outlined,
                title: 'Datos del Vehículo',
              ),
              const SizedBox(height: 16),

              // Tipo de vehículo
              const Text(
                'Tipo de vehículo',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _VehicleTypeCard(
                    icon: Icons.directions_car,
                    label: 'Carro',
                    isSelected:
                        _selectedVehicleType == AppConstants.vehicleCar,
                    onTap: () {
                      setState(() => _selectedVehicleType = AppConstants.vehicleCar);
                      // Limpiar placa para que el usuario la reescriba con el formato correcto
                      if (_plateController.text.isNotEmpty) {
                        _plateController.clear();
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  _VehicleTypeCard(
                    icon: Icons.two_wheeler,
                    label: 'Moto',
                    isSelected:
                        _selectedVehicleType == AppConstants.vehicleMoto,
                    onTap: () {
                      setState(() => _selectedVehicleType = AppConstants.vehicleMoto);
                      if (_plateController.text.isNotEmpty) {
                        _plateController.clear();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              AuthTextField(
                controller: _plateController,
                label: 'Placa del vehículo',
                hint: _selectedVehicleType == AppConstants.vehicleCar
                    ? 'ABC123'
                    : 'ABC12D',
                prefixIcon: Icons.confirmation_number_outlined,
                maxLength: 6,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                  LengthLimitingTextInputFormatter(6),
                ],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requerido';
                  final plate = v.trim().toUpperCase();
                  if (_selectedVehicleType == AppConstants.vehicleCar) {
                    // Formato carro: 3 letras + 3 números  (ej: ABC123)
                    if (!RegExp(r'^[A-Z]{3}[0-9]{3}$').hasMatch(plate)) {
                      return 'Carro: 3 letras y 3 números (ej: ABC123)';
                    }
                  } else {
                    // Formato moto: 3 letras + 2 números + 1 letra  (ej: ABC12D)
                    if (!RegExp(r'^[A-Z]{3}[0-9]{2}[A-Z]$').hasMatch(plate)) {
                      return 'Moto: 3 letras, 2 números y 1 letra (ej: ABC12D)';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              AuthTextField(
                controller: _vehicleModelController,
                label: 'Marca y modelo',
                hint: 'Chevrolet Spark 2020',
                prefixIcon: Icons.directions_car_outlined,
                validator: (v) =>
                    v == null || v.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),

              AuthTextField(
                controller: _vehicleColorController,
                label: 'Color del vehículo',
                hint: 'Blanco',
                prefixIcon: Icons.color_lens_outlined,
                validator: (v) =>
                    v == null || v.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),

              AuthTextField(
                controller: _licenseController,
                label: 'Número de licencia de conducción',
                hint: 'Ej: 80123456789',
                keyboardType: TextInputType.text,
                prefixIcon: Icons.drive_eta_outlined,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                  LengthLimitingTextInputFormatter(15),
                ],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requerido';
                  if (v.length < 5) return 'Número de licencia inválido';
                  return null;
                },
              ),

              const SizedBox(height: 28),

              // ── Sección 3: Plan de suscripción ───────────────────────
              _SectionHeader(
                icon: Icons.card_membership_outlined,
                title: 'Plan de Suscripción',
              ),
              const SizedBox(height: 8),
              Text(
                'Elige tu plan. Activarás el pago desde el panel del conductor.',
                style:
                    TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),

              _PlanCard(
                title: 'Plan Semanal',
                price:
                    '\$${AppConstants.weeklyPrice.toStringAsFixed(0)} COP',
                description: 'Pago cada 7 días.',
                isSelected: _selectedPlan == AppConstants.planWeekly,
                onTap: () =>
                    setState(() => _selectedPlan = AppConstants.planWeekly),
              ),
              const SizedBox(height: 12),
              _PlanCard(
                title: 'Plan Mensual',
                price:
                    '\$${AppConstants.monthlyPrice.toStringAsFixed(0)} COP',
                description: '¡Ahorra más! Pago cada 30 días.',
                isSelected: _selectedPlan == AppConstants.planMonthly,
                badge: '¡Mejor valor!',
                onTap: () =>
                    setState(() => _selectedPlan = AppConstants.planMonthly),
              ),

              const SizedBox(height: 32),

              // ── Botón registrar ───────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _onRegister,
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Crear cuenta'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Widgets auxiliares ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.primaryColor, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _VehicleTypeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _VehicleTypeCard({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryColor.withValues(alpha: 0.1)
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  isSelected ? AppTheme.primaryColor : AppTheme.dividerColor,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 30,
                  color: isSelected
                      ? AppTheme.primaryColor
                      : AppTheme.textSecondary),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? AppTheme.primaryColor
                      : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final String price;
  final String description;
  final bool isSelected;
  final String? badge;
  final VoidCallback onTap;

  const _PlanCard({
    required this.title,
    required this.price,
    required this.description,
    required this.isSelected,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.07)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : AppTheme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? AppTheme.primaryColor
                      : AppTheme.dividerColor,
                  width: 2,
                ),
                color:
                    isSelected ? AppTheme.primaryColor : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 13)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accentColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(badge!,
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87)),
                        ),
                      ],
                    ],
                  ),
                  Text(description,
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            Text(
              price,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isSelected
                    ? AppTheme.primaryColor
                    : AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
