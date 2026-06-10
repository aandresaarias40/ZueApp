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
        assert(() {
          // ignore: avoid_print
          print('====== ERROR CLOUD FUNCTION / WOMPI ======\n'
              'Status: ${e.response?.statusCode}\n'
              'Error Data: ${e.response?.data}\n'
              '==========================================');
          return true;
        }());
      }
      rethrow;
    }
  }
  // NOTA DE SEGURIDAD: la confirmación de pagos y la activación de
  // suscripciones la realiza EXCLUSIVAMENTE el webhook de Cloud Functions
  // (Admin SDK). El cliente nunca debe escribir en payments/subscriptions
  // más allá de crear el documento de pago en estado 'pending'.

  /// Escuchar cambios en tiempo real de un pago específico.
  /// Úsalo para saber cuando el webhook actualiza el estado (approved/declined).
  Stream<Map<String, dynamic>?> streamPayment(String paymentId) {
    return _payments.doc(paymentId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return doc.data() as Map<String, dynamic>;
    });
  }

  /// Obtener todos los pagos (para admin)
  Stream<List<PaymentModel>> watchAllPayments({String? status}) {
    Query query = _payments.orderBy('createdAt', descending: true);
    if (status != null) query = query.where('status', isEqualTo: status);
    return query.snapshots().map(
          (s) => s.docs.map((doc) => PaymentModel.fromFirestore(doc)).toList(),
        );
  }
}
