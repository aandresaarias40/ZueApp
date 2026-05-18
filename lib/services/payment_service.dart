import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../models/subscription_model.dart';
import '../models/driver_model.dart';
import '../core/constants/app_constants.dart';

/// Servicio de pagos con Wompi (Colombia)
/// Documentación: https://docs.wompi.co
class PaymentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Dio _dio = Dio();
  final Uuid _uuid = const Uuid();

  CollectionReference get _payments =>
      _firestore.collection(AppConstants.paymentsCollection);
  CollectionReference get _subscriptions =>
      _firestore.collection(AppConstants.subscriptionsCollection);

  /// Iniciar pago PSE para suscripción del transportador
  /// Retorna la URL de redirección a Wompi/PSE
  Future<Map<String, dynamic>> initiatePSEPayment({
    required DriverModel driver,
    required String plan, // weekly, monthly
  }) async {
    final double amount = plan == AppConstants.planWeekly
        ? AppConstants.weeklyPrice
        : AppConstants.monthlyPrice;

    // Generar referencia única
    final reference = 'ZUE-${driver.id.substring(0, 6).toUpperCase()}-${_uuid.v4().substring(0, 8).toUpperCase()}';

    // Crear registro de pago pendiente en Firestore
    final paymentDoc = await _payments.add({
      'driverId': driver.id,
      'driverName': driver.name,
      'subscriptionId': '',
      'amount': amount,
      'currency': 'COP',
      'paymentMethod': 'PSE',
      'status': AppConstants.paymentStatusPending,
      'referenceId': reference,
      'plan': plan,
      'createdAt': FieldValue.serverTimestamp(),
    });

    try {
      // Crear transacción en Wompi
      final response = await _dio.post(
        '${AppConstants.wompiBaseUrl}/transactions',
        options: Options(
          headers: {
            'Authorization': 'Bearer ${AppConstants.wompiPublicKey}',
            'Content-Type': 'application/json',
          },
        ),
        data: jsonEncode({
          'acceptance_token': await _getAcceptanceToken(),
          'amount_in_cents': (amount * 100).toInt(), // Wompi usa centavos
          'currency': 'COP',
          'customer_email': driver.email,
          'payment_method': {
            'type': 'PSE',
            'user_type': 0,         // 0=Persona natural, 1=Jurídica
            'user_legal_id_type': 'CC',
            'user_legal_id': driver.licenseNumber,
            'financial_institution_code': '', // El usuario selecciona en el checkout
            'payment_description': 'Suscripción Zue - ${plan == AppConstants.planWeekly ? "Semanal" : "Mensual"}',
          },
          'reference': reference,
          'redirect_url': 'zue://payment/callback',
          'customer_data': {
            'phone_number': driver.phone,
            'full_name': driver.name,
          },
        }),
      );

      final transactionId = response.data['data']['id'];
      final redirectUrl = response.data['data']['payment_method_info']['async_payment_url'];

      // Actualizar pago con ID de transacción
      await paymentDoc.update({
        'wompiTransactionId': transactionId,
      });

      return {
        'paymentId': paymentDoc.id,
        'transactionId': transactionId,
        'redirectUrl': redirectUrl,
        'reference': reference,
        'amount': amount,
      };
    } catch (e) {
      // Marcar pago como fallido
      await paymentDoc.update({'status': AppConstants.paymentStatusFailed});
      rethrow;
    }
  }

  /// Verificar estado del pago en Wompi
  Future<String> checkPaymentStatus(String transactionId) async {
    final response = await _dio.get(
      '${AppConstants.wompiBaseUrl}/transactions/$transactionId',
      options: Options(
        headers: {
          'Authorization': 'Bearer ${AppConstants.wompiPublicKey}',
        },
      ),
    );
    return response.data['data']['status']; // APPROVED, DECLINED, PENDING, ERROR
  }

  /// Procesar confirmación de pago exitoso
  /// (llamado desde webhook de Wompi o desde la app tras redirección)
  Future<void> confirmPayment({
    required String paymentId,
    required String transactionId,
    required String status,
  }) async {
    final paymentDoc = await _payments.doc(paymentId).get();
    if (!paymentDoc.exists) throw Exception('Pago no encontrado');

    final data = paymentDoc.data() as Map<String, dynamic>;
    final driverId = data['driverId'] as String;
    final plan = data['plan'] as String;
    final amount = (data['amount'] as num).toDouble();

    if (status == 'APPROVED') {
      // Calcular fechas de suscripción
      final now = DateTime.now();
      final endDate = plan == AppConstants.planWeekly
          ? now.add(const Duration(days: 7))
          : now.add(const Duration(days: 30));

      // Crear suscripción activa
      final subscriptionDoc = await _subscriptions.add({
        'driverId': driverId,
        'driverName': data['driverName'],
        'plan': plan,
        'status': 'active',
        'amount': amount,
        'startDate': Timestamp.fromDate(now),
        'endDate': Timestamp.fromDate(endDate),
        'paymentId': paymentId,
        'transactionId': transactionId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Batch: actualizar pago + conductor
      final batch = _firestore.batch();

      // Actualizar pago
      batch.update(_payments.doc(paymentId), {
        'status': AppConstants.paymentStatusApproved,
        'subscriptionId': subscriptionDoc.id,
        'wompiTransactionId': transactionId,
        'paidAt': FieldValue.serverTimestamp(),
      });

      // Activar suscripción del conductor
      batch.update(
        _firestore.collection(AppConstants.driversCollection).doc(driverId),
        {
          'subscriptionStatus': 'active',
          'subscriptionExpiry': Timestamp.fromDate(endDate),
          'status': AppConstants.driverStatusInactive,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );

      await batch.commit();
    } else {
      // Pago rechazado o fallido
      await _payments.doc(paymentId).update({
        'status': status == 'DECLINED'
            ? AppConstants.paymentStatusDeclined
            : AppConstants.paymentStatusFailed,
        'wompiTransactionId': transactionId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Obtener historial de pagos del conductor
  Stream<List<PaymentModel>> watchDriverPayments(String driverId) {
    return _payments
        .where('driverId', isEqualTo: driverId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) =>
            s.docs.map((doc) => PaymentModel.fromFirestore(doc)).toList());
  }

  /// Obtener todos los pagos (para admin)
  Stream<List<PaymentModel>> watchAllPayments({String? status}) {
    Query query = _payments.orderBy('createdAt', descending: true);
    if (status != null) query = query.where('status', isEqualTo: status);
    return query.snapshots().map(
          (s) => s.docs.map((doc) => PaymentModel.fromFirestore(doc)).toList(),
        );
  }

  /// Obtener token de aceptación de Wompi (requerido para crear transacciones)
  Future<String> _getAcceptanceToken() async {
    final response = await _dio.get(
      '${AppConstants.wompiBaseUrl}/merchants/${AppConstants.wompiPublicKey}',
    );
    return response.data['data']['presigned_acceptance']['acceptance_token'];
  }

  /// Obtener resumen de ingresos para el admin
  Future<Map<String, dynamic>> getRevenueSummary() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);

    final monthlyPayments = await _payments
        .where('status', isEqualTo: AppConstants.paymentStatusApproved)
        .where('paidAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .get();

    double totalRevenue = 0;
    for (final doc in monthlyPayments.docs) {
      final data = doc.data() as Map<String, dynamic>;
      totalRevenue += (data['amount'] as num).toDouble();
    }

    return {
      'monthlyRevenue': totalRevenue,
      'monthlyPaymentsCount': monthlyPayments.docs.length,
    };
  }
}
