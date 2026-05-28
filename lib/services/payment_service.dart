import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../models/subscription_model.dart';
import '../models/driver_model.dart';
import '../core/constants/app_constants.dart';


/// Modelo de banco PSE
class PseBankModel {
  final String financialInstitutionCode;
  final String financialInstitutionName;

  const PseBankModel({
    required this.financialInstitutionCode,
    required this.financialInstitutionName,
  });

  factory PseBankModel.fromJson(Map<String, dynamic> json) => PseBankModel(
        financialInstitutionCode: json['financial_institution_code'] ?? '',
        financialInstitutionName: json['financial_institution_name'] ?? '',
      );
}

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

  // ── Cache de bancos PSE (evita llamadas repetidas) ─────────────────────────
  List<PseBankModel>? _pseBanksCache;

  /// Obtener lista de bancos disponibles para PSE
  /// Wompi requiere que el usuario seleccione su banco antes de crear la transacción.
  Future<List<PseBankModel>> getPseBanks() async {
    if (_pseBanksCache != null) return _pseBanksCache!;
    final response = await _dio.get(
      '${AppConstants.wompiBaseUrl}/pse/financial_institutions',
      options: Options(
        headers: {'Authorization': 'Bearer ${AppConstants.wompiPublicKey}'},
      ),
    );
    final list = (response.data['data'] as List)
        .map((e) => PseBankModel.fromJson(e as Map<String, dynamic>))
        .toList();
    _pseBanksCache = list;
    return list;
  }

  /// Iniciar pago PSE para suscripción del transportador.
  ///
  /// Delega a la Cloud Function [createPSETransaction] para que la firma de
  /// integridad se calcule en el servidor y la llave secreta nunca viaje en el APK.
  /// Retorna la URL de redirección al banco (null en sandbox — limitación de ACH).
  Future<Map<String, dynamic>> initiatePSEPayment({
    required DriverModel driver,
    required String plan, // weekly, monthly
    required String financialInstitutionCode,
  }) async {
    final double amount = plan == AppConstants.planWeekly
        ? AppConstants.weeklyPrice
        : AppConstants.monthlyPrice;

    // Referencia única para esta transacción
    final reference =
        'ZUE-${driver.id.substring(0, 6).toUpperCase()}-${_uuid.v4().substring(0, 8).toUpperCase()}';

    final int amountInCents = (amount * 100).toInt();

    // Token de identidad Firebase — la CF lo verifica para autenticar al conductor
    final idToken =
        await FirebaseAuth.instance.currentUser?.getIdToken() ?? '';

    try {
      // 1. Llamar a la Cloud Function (firma de integridad se calcula allá)
      final response = await _dio.post(
        AppConstants.cfCreatePSETransaction,
        options: Options(
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
        ),
        data: jsonEncode({
          'driverId': driver.id,
          'plan': plan,
          'financialInstitutionCode': financialInstitutionCode,
          'reference': reference,
          'amountInCents': amountInCents,
        }),
      );

      final data = response.data as Map<String, dynamic>;
      final transactionId = data['transactionId'] as String;
      final String? redirectUrl = data['redirectUrl'] as String?;

      // 2. Guardar pago en Firestore
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
        'wompiTransactionId': transactionId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return {
        'paymentId': paymentDoc.id,
        'transactionId': transactionId,
        'redirectUrl': redirectUrl, // null en sandbox (limitación ACH Colombia)
        'reference': reference,
        'amount': amount,
      };
    } catch (e) {
      if (e is DioException) {
        print('====== ERROR CLOUD FUNCTION / WOMPI ======');
        print('Status: ${e.response?.statusCode}');
        print('Error Data: ${e.response?.data}');
        print('==========================================');
      }
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

    // Idempotencia: si ya fue procesado, no crear duplicados
    final currentStatus = data['status'] as String?;
    if (currentStatus == AppConstants.paymentStatusApproved ||
        currentStatus == AppConstants.paymentStatusDeclined) {
      return;
    }

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
      // ✅ También actualiza subscriptionPlan para reflejar el plan pagado
      batch.update(
        _firestore.collection(AppConstants.driversCollection).doc(driverId),
        {
          'subscriptionStatus': 'active',
          'subscriptionPlan': plan,          // ← fix: actualizar el plan
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

  /// Escuchar cambios en tiempo real de un pago específico.
  /// Úsalo para saber cuando el webhook actualiza el estado (approved/declined).
  Stream<Map<String, dynamic>?> streamPayment(String paymentId) {
    return _payments.doc(paymentId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return doc.data() as Map<String, dynamic>;
    });
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
