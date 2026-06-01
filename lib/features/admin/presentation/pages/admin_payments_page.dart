import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/subscription_model.dart';
import '../../../../services/payment_service.dart';

class AdminPaymentsPage extends StatefulWidget {
  const AdminPaymentsPage({super.key});

  @override
  State<AdminPaymentsPage> createState() => _AdminPaymentsPageState();
}

class _AdminPaymentsPageState extends State<AdminPaymentsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final PaymentService _paymentService = PaymentService();

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
        title: const Text('Pagos & Suscripciones'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Todos'),
            Tab(text: 'Aprobados'),
            Tab(text: 'Pendientes'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _PaymentList(
            stream: _paymentService.watchAllPayments(),
          ),
          _PaymentList(
            stream: _paymentService.watchAllPayments(
                status: AppConstants.paymentStatusApproved),
          ),
          _PaymentList(
            stream: _paymentService.watchAllPayments(
                status: AppConstants.paymentStatusPending),
          ),
        ],
      ),
    );
  }
}

class _PaymentList extends StatelessWidget {
  final Stream<List<PaymentModel>> stream;

  const _PaymentList({required this.stream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PaymentModel>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final payments = snapshot.data!;
        if (payments.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 60,
                    color: AppTheme.textSecondary.withValues(alpha: 0.3)),
                const SizedBox(height: 12),
                Text(
                  'No hay pagos',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          );
        }

        // Calcular total
        final total = payments
            .where((p) => p.status == AppConstants.paymentStatusApproved)
            .fold(0.0, (sum, p) => sum + p.amount);

        return Column(
          children: [
            // Resumen
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet,
                      color: AppTheme.successColor),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total recaudado',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.successColor,
                        ),
                      ),
                      Text(
                        '\$${total.toStringAsFixed(0)} COP',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.successColor,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    '${payments.length} pagos',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView.separated(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                itemCount: payments.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _PaymentCard(payment: payments[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final PaymentModel payment;

  const _PaymentCard({required this.payment});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy, h:mm a', 'es_CO');
    final statusConfig = _getStatusConfig(payment.status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: statusConfig['color'].withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(statusConfig['icon'],
                color: statusConfig['color'], size: 22),
          ),
          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.driverName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  payment.plan == AppConstants.planWeekly
                      ? 'Plan Semanal'
                      : 'Plan Mensual',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                Text(
                  dateFormat.format(payment.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${payment.amount.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryColor,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusConfig['color'].withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusConfig['label'],
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: statusConfig['color'],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getStatusConfig(String status) {
    switch (status) {
      case AppConstants.paymentStatusApproved:
        return {
          'label': 'Aprobado',
          'color': AppTheme.successColor,
          'icon': Icons.check_circle_outline,
        };
      case AppConstants.paymentStatusPending:
        return {
          'label': 'Pendiente',
          'color': AppTheme.warningColor,
          'icon': Icons.hourglass_top,
        };
      case AppConstants.paymentStatusDeclined:
        return {
          'label': 'Rechazado',
          'color': AppTheme.errorColor,
          'icon': Icons.cancel_outlined,
        };
      default:
        return {
          'label': 'Fallido',
          'color': AppTheme.errorColor,
          'icon': Icons.error_outline,
        };
    }
  }
}
