import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
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
  final _licenseController = TextEditingController();

  String _selectedVehicleType = AppConstants.vehicleCar;
  String _selectedPlan = AppConstants.planWeekly;
  bool _obscurePassword = true;
  bool _isLoading = false;
  int _currentStep = 0;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _plateController.dispose();
    _vehicleModelController.dispose();
    _vehicleColorController.dispose();
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
        vehiclePlate: _plateController.text.trim(),
        vehicleModel: _vehicleModelController.text.trim(),
        vehicleColor: _vehicleColorController.text.trim(),
        licenseNumber: _licenseController.text.trim(),
        subscriptionPlan: _selectedPlan,
      );
      if (mounted) {
        // Redirigir a pago de suscripción
        context.go('/driver/subscription');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppTheme.errorColor,
          ),
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
        title: const Text('Registrarse como Transportador'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.pop(),
        ),
      ),
      body: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context)
              .colorScheme
              .copyWith(primary: AppTheme.primaryColor),
        ),
        child: Stepper(
          currentStep: _currentStep,
          onStepContinue: () {
            if (_currentStep < 2) {
              setState(() => _currentStep++);
            } else {
              _onRegister();
            }
          },
          onStepCancel: () {
            if (_currentStep > 0) {
              setState(() => _currentStep--);
            } else {
              context.pop();
            }
          },
          controlsBuilder: (context, details) {
            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  ElevatedButton(
                    onPressed: _isLoading ? null : details.onStepContinue,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            _currentStep == 2 ? 'Registrarse' : 'Continuar'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: details.onStepCancel,
                    child: const Text('Atrás'),
                  ),
                ],
              ),
            );
          },
          steps: [
            // Paso 1: Datos personales
            Step(
              title: const Text('Datos Personales'),
              isActive: _currentStep >= 0,
              state: _currentStep > 0 ? StepState.complete : StepState.indexed,
              content: Form(
                key: _currentStep == 0 ? _formKey : null,
                child: Column(
                  children: [
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
                      keyboardType: TextInputType.phone,
                      prefixIcon: Icons.phone_outlined,
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 12),
                    AuthTextField(
                      controller: _passwordController,
                      label: 'Contraseña',
                      obscureText: _obscurePassword,
                      prefixIcon: Icons.lock_outline,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Requerido';
                        if (v.length < 6) return 'Mínimo 6 caracteres';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    AuthTextField(
                      controller: _licenseController,
                      label: 'Número de cédula/licencia',
                      keyboardType: TextInputType.number,
                      prefixIcon: Icons.badge_outlined,
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Requerido' : null,
                    ),
                  ],
                ),
              ),
            ),

            // Paso 2: Datos del vehículo
            Step(
              title: const Text('Vehículo'),
              isActive: _currentStep >= 1,
              state: _currentStep > 1 ? StepState.complete : StepState.indexed,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tipo de vehículo',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _VehicleTypeCard(
                        type: AppConstants.vehicleCar,
                        icon: Icons.directions_car,
                        label: 'Carro',
                        isSelected: _selectedVehicleType == AppConstants.vehicleCar,
                        onTap: () => setState(
                            () => _selectedVehicleType = AppConstants.vehicleCar),
                      ),
                      const SizedBox(width: 12),
                      _VehicleTypeCard(
                        type: AppConstants.vehicleMoto,
                        icon: Icons.two_wheeler,
                        label: 'Moto',
                        isSelected: _selectedVehicleType == AppConstants.vehicleMoto,
                        onTap: () => setState(
                            () => _selectedVehicleType = AppConstants.vehicleMoto),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AuthTextField(
                    controller: _plateController,
                    label: 'Placa del vehículo',
                    hint: 'ABC 123',
                    prefixIcon: Icons.confirmation_number_outlined,
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  AuthTextField(
                    controller: _vehicleModelController,
                    label: 'Marca y modelo',
                    hint: 'Ej: Chevrolet Spark 2020',
                    prefixIcon: Icons.directions_car_outlined,
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  AuthTextField(
                    controller: _vehicleColorController,
                    label: 'Color del vehículo',
                    hint: 'Ej: Blanco',
                    prefixIcon: Icons.color_lens_outlined,
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Requerido' : null,
                  ),
                ],
              ),
            ),

            // Paso 3: Plan de suscripción
            Step(
              title: const Text('Plan de Suscripción'),
              isActive: _currentStep >= 2,
              state: StepState.indexed,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Elige tu plan de pago',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _PlanCard(
                    plan: AppConstants.planWeekly,
                    title: 'Plan Semanal',
                    price: '\$${AppConstants.weeklyPrice.toStringAsFixed(0)} COP',
                    description: 'Pago cada 7 días. Ideal para probar el servicio.',
                    isSelected: _selectedPlan == AppConstants.planWeekly,
                    onTap: () =>
                        setState(() => _selectedPlan = AppConstants.planWeekly),
                  ),
                  const SizedBox(height: 12),
                  _PlanCard(
                    plan: AppConstants.planMonthly,
                    title: 'Plan Mensual',
                    price: '\$${AppConstants.monthlyPrice.toStringAsFixed(0)} COP',
                    description: 'Pago cada 30 días. ¡Ahorra más con este plan!',
                    isSelected: _selectedPlan == AppConstants.planMonthly,
                    badge: '¡Mejor valor!',
                    onTap: () =>
                        setState(() => _selectedPlan = AppConstants.planMonthly),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: AppTheme.primaryColor, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Deberás completar el pago vía PSE para activar tu cuenta y comenzar a recibir viajes.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleTypeCard extends StatelessWidget {
  final String type;
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _VehicleTypeCard({
    required this.type,
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
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryColor.withOpacity(0.1)
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppTheme.primaryColor : AppTheme.dividerColor,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 32,
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
  final String plan;
  final String title;
  final String price;
  final String description;
  final bool isSelected;
  final String? badge;
  final VoidCallback onTap;

  const _PlanCard({
    required this.plan,
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
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withOpacity(0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : AppTheme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? AppTheme.primaryColor
                      : AppTheme.dividerColor,
                  width: 2,
                ),
                color: isSelected ? AppTheme.primaryColor : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accentColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              price,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
