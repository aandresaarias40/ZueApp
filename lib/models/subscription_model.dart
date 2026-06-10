import 'package:cloud_firestore/cloud_firestore.dart';

// Las suscripciones las crea y gestiona exclusivamente el webhook de
// Cloud Functions; el cliente no las lee ni escribe, por eso aquí solo
// vive el modelo de pagos.
class PaymentModel {
  final String id;
  final String driverId;
  final String driverName;
  final String subscriptionId;
  final String plan;           // PIEZA FALTANTE: weekly, monthly
  final double amount;
  final String currency;
  final String paymentMethod; // PSE
  final String status;        // pending, approved, declined, failed
  final String? wompiTransactionId;
  final String? referenceId;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? paidAt;

  const PaymentModel({
    required this.id,
    required this.driverId,
    required this.driverName,
    required this.subscriptionId,
    required this.plan,        // Agregado al constructor
    required this.amount,
    this.currency = 'COP',
    this.paymentMethod = 'PSE',
    required this.status,
    this.wompiTransactionId,
    this.referenceId,
    this.errorMessage,
    required this.createdAt,
    this.paidAt,
  });

  factory PaymentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PaymentModel(
      id: doc.id,
      driverId: data['driverId'] ?? '',
      driverName: data['driverName'] ?? '',
      subscriptionId: data['subscriptionId'] ?? '',
      plan: data['plan'] ?? 'weekly', // Mapeo desde Firestore
      amount: (data['amount'] ?? 0.0).toDouble(),
      currency: data['currency'] ?? 'COP',
      paymentMethod: data['paymentMethod'] ?? 'PSE',
      status: data['status'] ?? 'pending',
      wompiTransactionId: data['wompiTransactionId'],
      referenceId: data['referenceId'],
      errorMessage: data['errorMessage'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      paidAt: (data['paidAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'driverId': driverId,
      'driverName': driverName,
      'subscriptionId': subscriptionId,
      'plan': plan,           // Guardado en Firestore
      'amount': amount,
      'currency': currency,
      'paymentMethod': paymentMethod,
      'status': status,
      'wompiTransactionId': wompiTransactionId,
      'referenceId': referenceId,
      'errorMessage': errorMessage,
      'createdAt': Timestamp.fromDate(createdAt),
      'paidAt': paidAt != null ? Timestamp.fromDate(paidAt!) : null,
    };
  }
}