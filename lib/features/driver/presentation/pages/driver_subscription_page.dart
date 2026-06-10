import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
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
  String? _transactionId;
  // true cuando la CF devuelve sandboxMode:true (sin redirectUrl)
  bool _sandboxWaiting = false;

  final PaymentService _paymentService = PaymentService();

  /// Paso 1: mostrar selector de banco y, al confirmar, crear la transacción PSE.
  Future<void> _initiatePayment() async {
    if (!mounted) return;
    final driverState = context.read<DriverBloc>().state;
    if (driverState is! DriverLoadedState) return;

    setState(() => _isLoading = true);

    // Cargar bancos PSE
    List<PseBankModel> banks;
    try {
      banks = await _paymentService.getPseBanks();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cargar la lista de bancos: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    // Mostrar bottom sheet de selección de banco
    final selectedBank = await showModalBottomSheet<PseBankModel>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _BankSelectionSheet(banks: banks),
    );

    if (selectedBank == null || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final result = await _paymentService.initiatePSEPayment(
        driver: driverState.driver,
        plan: _selectedPlan,
        financialInstitutionCode: selectedBank.financialInstitutionCode,
      );

      if (!mounted) return;

      final redirectUrl   = result['redirectUrl'] as String?;
      final paymentId     = result['paymentId']   as String;
      final transactionId = result['transactionId'] as String;

      setState(() {
        _paymentUrl      = redirectUrl;
        _paymentId       = paymentId;
        _transactionId   = transactionId;
        _sandboxWaiting  = redirectUrl == null;
        _isLoading       = false;
      });

      // Sandbox: sin redirect al banco → escuchar Firestore directamente.
      // El webhook dispara al aprobar la tx desde comercios.wompi.co.
      if (redirectUrl == null) {
        _verifyAndConfirmPayment(transactionId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al iniciar pago: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  /// Después de que el WebView captura el redirect de Wompi, esperamos que el
  /// webhook de Cloud Functions actualice el estado del pago en Firestore.
  /// El cliente NO escribe nada — solo escucha. El Admin SDK del webhook
  /// tiene permisos completos y es la fuente de verdad.
  Future<void> _verifyAndConfirmPayment(String transactionId) async {
    if (_paymentId == null) return;
    setState(() => _isLoading = true);

    final completer = Completer<String>();

    // Timeout de 60 s — PSE puede tardar en responder
    final timer = Timer(const Duration(seconds: 60), () {
      if (!completer.isCompleted) completer.complete('pending_timeout');
    });

    // Escuchar el documento de pago en Firestore hasta que el webhook lo actualice
    final sub = _paymentService.streamPayment(_paymentId!).listen((data) {
      if (completer.isCompleted || data == null) return;
      final status = (data['status'] as String? ?? '').toLowerCase();
      if (status == 'approved' || status == 'declined' || status == 'failed') {
        completer.complete(status);
      }
    });

    final finalStatus = await completer.future;
    await sub.cancel();
    timer.cancel();

    if (!mounted) return;
    setState(() {
      _isLoading      = false;
      _sandboxWaiting = false;
    });

    switch (finalStatus) {
      case 'approved':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Pago aprobado! Tu suscripción está activa.'),
            backgroundColor: AppTheme.successColor,
          ),
        );
        context.go(AppRoutes.driverHome);
      case 'pending_timeout':
        // El banco PSE puede confirmar horas después — el webhook lo resolverá
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pago en proceso. Tu banco confirmará en breve.',
            ),
          ),
        );
        context.go(AppRoutes.driverHome);
      default:
        setState(() => _paymentUrl = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('El pago fue rechazado. Intenta de nuevo.'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sandbox: transacción creada pero sin redirect al banco
    if (_sandboxWaiting && _transactionId != null) {
      return _SandboxPendingView(
        transactionId: _transactionId!,
        isLoading: _isLoading,
        onCancel: () => setState(() {
          _sandboxWaiting = false;
          _paymentId      = null;
          _transactionId  = null;
        }),
      );
    }

    // Si hay URL de pago, mostrar WebView del banco PSE
    if (_paymentUrl != null) {
      return _PSEWebView(
        url: _paymentUrl!,
        redirectUrlPattern: AppConstants.wompiRedirectUrl,
        onRedirectCapture: (uri) {
          // Wompi redirige con ?id=...&status=...&reference=...
          final txId = uri.queryParameters['id'] ??
              uri.queryParameters['transaction_id'] ??
              _transactionId ??
              '';
          _verifyAndConfirmPayment(txId);
        },
        onBack: () => setState(() {
          _paymentUrl = null;
          _paymentId = null;
          _transactionId = null;
        }),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suscripción Zue'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.go(AppRoutes.driverHome),
          tooltip: 'Volver',
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
                if (driver != null && driver.isOnTrial)
                  _StatusCard(
                    color: AppTheme.primaryColor,
                    icon: Icons.redeem_outlined,
                    title: '¡Período de prueba gratuita!',
                    subtitle: 'Tienes ${driver.trialDaysRemaining} día(s) '
                        'gratis para explorar Zue sin costo.',
                  )
                else if (driver != null && driver.isSubscriptionActive)
                  _StatusCard(
                    color: AppTheme.successColor,
                    icon: Icons.check_circle,
                    title: 'Suscripción activa',
                    subtitle: driver.subscriptionExpiry != null
                        ? 'Vence en ${driver.daysUntilExpiry} día(s)'
                        : 'Plan activo',
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
              ? AppTheme.primaryColor.withValues(alpha: 0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : AppTheme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
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

// ── Widget de estado de suscripción/trial ─────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;

  const _StatusCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 13, color: color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── WebView PSE ───────────────────────────────────────────────────────────────
// Carga la URL del banco y captura el redirect de Wompi cuando termina el pago.

class _PSEWebView extends StatefulWidget {
  final String url;
  final String redirectUrlPattern; // dominio a interceptar (e.g. zueapp.com/payment/callback)
  final void Function(Uri redirectUri) onRedirectCapture;
  final VoidCallback onBack;

  const _PSEWebView({
    required this.url,
    required this.redirectUrlPattern,
    required this.onRedirectCapture,
    required this.onBack,
  });

  @override
  State<_PSEWebView> createState() => _PSEWebViewState();
}

class _PSEWebViewState extends State<_PSEWebView> {
  WebViewController? _controller;
  bool _isLoading = true;
  bool _captured = false; // evita disparar onRedirectCapture más de una vez
  bool _blockedUrl = false; // URL inicial fuera de la lista permitida

  /// Dominios permitidos dentro del WebView de pago PSE.
  /// Solo se navegará a URLs cuyo host termine en uno de estos sufijos.
  /// Los bancos PSE colombianos y Wompi usan subdominios de estos dominios.
  static const _allowedDomainSuffixes = [
    'wompi.co',       // checkout.wompi.co, sandbox.wompi.co, production.wompi.co
    'pse.com.co',     // portal PSE de ACH Colombia
    'web.app',        // zue-app.web.app (redirect de regreso a la app)
    'firebaseapp.com',// alternativa Firebase Hosting
  ];

  /// Devuelve true si la URL pertenece a un dominio permitido o
  /// si no tiene host (esquemas como about:blank usados internamente).
  bool _isAllowedUrl(String url) {
    // Bloquear esquemas peligrosos siempre, independientemente del dominio
    final lower = url.toLowerCase();
    if (lower.startsWith('javascript:') ||
        lower.startsWith('data:') ||
        lower.startsWith('file:') ||
        lower.startsWith('content:')) {
      return false;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    // Permitir about:blank y URLs sin host (navegación interna del banco)
    if (uri.host.isEmpty) return true;
    return _allowedDomainSuffixes.any((suffix) =>
        uri.host == suffix || uri.host.endsWith('.$suffix'));
  }

  @override
  void initState() {
    super.initState();

    // Validar la URL inicial antes de cargarla — también en release.
    // Si no pertenece a los dominios permitidos, no se carga nada.
    if (!_isAllowedUrl(widget.url)) {
      _blockedUrl = true;
      return;
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _isLoading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _isLoading = false);
        },
        onNavigationRequest: (request) {
          // 1. Interceptar la URL de redirect de Wompi (fin del flujo de pago)
          if (!_captured && request.url.contains(widget.redirectUrlPattern)) {
            _captured = true;
            final uri = Uri.parse(request.url);
            widget.onRedirectCapture(uri);
            return NavigationDecision.prevent;
          }
          // 2. Bloquear navegación a dominios fuera de la lista permitida
          if (!_isAllowedUrl(request.url)) {
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    if (_blockedUrl) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Pago PSE'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: widget.onBack,
          ),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'La URL de pago no es válida. Por seguridad, el pago fue cancelado. Intenta de nuevo.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pago PSE'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancelar pago',
          onPressed: widget.onBack,
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller!),
          if (_isLoading)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Conectando con tu banco...'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Pantalla de espera sandbox ────────────────────────────────────────────────
// Wompi PSE sandbox no genera async_payment_url (limitación ACH Colombia).
// El conductor aprueba manualmente desde comercios.wompi.co y el webhook activa
// la suscripción en Firestore.

class _SandboxPendingView extends StatelessWidget {
  final String transactionId;
  final bool isLoading;
  final VoidCallback onCancel;

  const _SandboxPendingView({
    required this.transactionId,
    required this.isLoading,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transacción creada'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: onCancel,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.account_balance, size: 72, color: AppTheme.primaryColor),
            const SizedBox(height: 24),
            const Text(
              'Transacción PSE creada',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'ID: $transactionId',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Modo Sandbox',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.amber.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'En sandbox, Wompi no redirige al banco. Para aprobar este pago:\n\n'
                    '1. Ve a comercios.wompi.co\n'
                    '2. Sección Transacciones\n'
                    '3. Encuentra la transacción con el ID de arriba\n'
                    '4. Apruébala manualmente\n\n'
                    'Esta app detectará la aprobación automáticamente.',
                    style: TextStyle(fontSize: 13, color: Colors.amber.shade900),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            if (isLoading) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                'Esperando confirmación del pago...',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Selector de banco PSE ──────────────────────────────────────────────────────

class _BankSelectionSheet extends StatefulWidget {
  final List<PseBankModel> banks;
  const _BankSelectionSheet({required this.banks});

  @override
  State<_BankSelectionSheet> createState() => _BankSelectionSheetState();
}

class _BankSelectionSheetState extends State<_BankSelectionSheet> {
  final _searchController = TextEditingController();
  List<PseBankModel> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.banks;
    _searchController.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filtered = widget.banks
          .where((b) =>
              b.financialInstitutionName.toLowerCase().contains(q))
          .toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (_, scrollController) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.dividerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Selecciona tu banco',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Elige el banco desde donde harás el débito PSE',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            // Buscador
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar banco...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.dividerColor),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('No se encontró el banco'))
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final bank = _filtered[i];
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 4),
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.account_balance,
                                color: AppTheme.primaryColor, size: 22),
                          ),
                          title: Text(
                            bank.financialInstitutionName,
                            style: const TextStyle(fontSize: 14),
                          ),
                          trailing: const Icon(Icons.chevron_right,
                              color: AppTheme.textSecondary),
                          onTap: () => Navigator.pop(context, bank),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
