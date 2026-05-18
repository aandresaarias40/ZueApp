import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/bloc/auth_bloc.dart';
import '../../bloc/driver_bloc.dart';
import '../../../../services/payment_service.dart';

class DriverSubscriptionPage extends StatefulWidget {
  const DriverSubscriptionPage({super.key});

  @override
  State<DriverSubscriptionPage> createState() => _DriverSubscriptionPageState();
}

class _DriverSubscriptionPageState extends State<DriverSubscriptionPage> {
  String _selectedPlan = AppConstants.planWeekly;
  bool _isLoading = false;
  String? _paymentUrl;
  String? _paymentId;

  final PaymentService _paymentService = PaymentService();

  Future<void> _initiatePayment() async {
    final driverState = context.read<DriverBloc>().state;
    if (driverState is! DriverLoadedState) return;

    setState(() => _isLoading = true);

    try {
      final result = await _paymentService.initiatePSEPayment(
        driver: driverState.driver,
        plan: _selectedPlan,
      );

      setState(() {
        _paymentUrl = result['redirectUrl'];
        _paymentId = result['paymentId'];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al iniciar pago: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Si hay URL de pago, mostrar WebView
    if (_paymentUrl != null) {
      return _PSEWebView(
        url: _paymentUrl!,
        paymentId: _paymentId!,
        onSuccess: (transactionId) async {
          await _paymentService.confirmPayment(
            paymentId: _paymentId!,
            transactionId: transactionId,
            status: 'APPROVED',
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('¡Pago exitoso! Tu cuenta está activa.'),
                backgroundColor: AppTheme.successColor,
              ),
            );
            context.go(AppRoutes.driverHome);
          }
        },
        onFailed: () {
          setState(() => _paymentUrl = null);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('El pago no fue procesado. Intenta de nuevo.'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        },
        onBack: () => setState(() => _paymentUrl = null),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suscripción Zue'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.go(AppRoutes.driverHome),
        ),
      ),
      body: BlocBuilder<DriverBloc, DriverState>(
        builder: (context, state) {
          final driver =
              state is DriverLoadedState ? state.driver : null;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Estado de suscripción actual
                if (driver != null && driver.isSubscriptionActive)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppTheme.successColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: AppTheme.successColor),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Suscripción activa',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.successColor,
                              ),
                            ),
                            Text(
                              'Vence en ${driver.daysUntilExpiry} día(s)',
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.successColor),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                const Text(
                  'Elige tu plan',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Renueva o activa tu suscripción para recibir viajes en Zue',
                  style:
                      TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 32),

                // Plan semanal
                _PlanOption(
                  title: 'Plan Semanal',
                  price: '\$${AppConstants.weeklyPrice.toStringAsFixed(0)}',
                  period: 'por semana',
                  description:
                      'Perfecto para empezar. Renueva cada 7 días.',
                  features: const [
                    'Acceso completo por 7 días',
                    'Viajes ilimitados',
                    'Soporte 24/7',
                  ],
                  isSelected: _selectedPlan == AppConstants.planWeekly,
                  onTap: () => setState(
                      () => _selectedPlan = AppConstants.planWeekly),
                ),
                const SizedBox(height: 16),

                // Plan mensual
                _PlanOption(
                  title: 'Plan Mensual',
                  price: '\$${AppConstants.monthlyPrice.toStringAsFixed(0)}',
                  period: 'por mes',
                  description: 'El más popular. ¡Ahorra \$20.000 al mes!',
                  features: const [
                    'Acceso completo por 30 días',
                    'Viajes ilimitados',
                    'Soporte 24/7',
                    'Prioridad en asignación',
                  ],
                  isSelected: _selectedPlan == AppConstants.planMonthly,
                  isBestValue: true,
                  onTap: () => setState(
                      () => _selectedPlan = AppConstants.planMonthly),
                ),

                const SizedBox(height: 32),

                // Resumen del pago
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _SummaryRow(
                          label: 'Plan seleccionado',
                          value: _selectedPlan == AppConstants.planWeekly
                              ? 'Semanal'
                              : 'Mensual'),
                      const Divider(height: 16),
                      _SummaryRow(
                        label: 'Total a pagar',
                        value: _selectedPlan == AppConstants.planWeekly
                            ? '\$${AppConstants.weeklyPrice.toStringAsFixed(0)} COP'
                            : '\$${AppConstants.monthlyPrice.toStringAsFixed(0)} COP',
                        isTotal: true,
                      ),
                      const Divider(height: 16),
                      Row(
                        children: [
                          Image.network(
                            'https://upload.wikimedia.org/wikipedia/commons/thumb/7/7b/PSE_logo.svg/200px-PSE_logo.svg.png',
                            height: 24,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.account_balance,
                                color: AppTheme.primaryColor),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Pago seguro vía PSE',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _initiatePayment,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.account_balance),
                    label: Text(_isLoading ? 'Procesando...' : 'Pagar con PSE'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PlanOption extends StatelessWidget {
  final String title;
  final String price;
  final String period;
  final String description;
  final List<String> features;
  final bool isSelected;
  final bool isBestValue;
  final VoidCallback onTap;

  const _PlanOption({
    required this.title,
    required this.price,
    required this.period,
    required this.description,
    required this.features,
    required this.isSelected,
    this.isBestValue = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withOpacity(0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : AppTheme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    blurRadius: 12,
                  )
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (isBestValue) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '¡Mejor valor!',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      price,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? AppTheme.primaryColor
                            : AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      ' COP',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            ...features.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 16,
                      color: isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      f,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: isTotal ? AppTheme.textPrimary : AppTheme.textSecondary,
            fontWeight: isTotal ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 16 : 14,
            fontWeight: FontWeight.w700,
            color: isTotal ? AppTheme.primaryColor : AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _PSEWebView extends StatefulWidget {
  final String url;
  final String paymentId;
  final void Function(String transactionId) onSuccess;
  final VoidCallback onFailed;
  final VoidCallback onBack;

  const _PSEWebView({
    required this.url,
    required this.paymentId,
    required this.onSuccess,
    required this.onFailed,
    required this.onBack,
  });

  @override
  State<_PSEWebView> createState() => _PSEWebViewState();
}

class _PSEWebViewState extends State<_PSEWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) => setState(() => _isLoading = false),
        onNavigationRequest: (request) {
          // Manejar callback de pago
          if (request.url.contains('zue://payment/callback')) {
            final uri = Uri.parse(request.url);
            final status = uri.queryParameters['status'];
            final transactionId = uri.queryParameters['id'] ?? '';

            if (status == 'APPROVED') {
              widget.onSuccess(transactionId);
            } else {
              widget.onFailed();
            }
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pago PSE'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: widget.onBack,
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Cargando pasarela de pago...'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
