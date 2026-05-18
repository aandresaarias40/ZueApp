import 'package:cloud_firestore/cloud_firestore.dart';

class SubscriptionModel {
  final String id;
  final String driverId;
  final String driverName;
  final String plan;           // weekly, monthly
  final String status;         // active, expired, pending, cancelled
  final double amount;         // Monto en COP
  final DateTime startDate;
  final DateTime endDate;
  final String? paymentId;     // ID del pago en Wompi
  final String? transactionId;
  final DateTime createdAt;

  const SubscriptionModel({
    required this.id,
    required this.driverId,
    required this.driverName,
    required this.plan,
    required this.status,
    required this.amount,
    required this.startDate,
    required this.endDate,
    this.paymentId,
    this.transactionId,
    required this.createdAt,
  });

  bool get isActive =>
      status == 'active' && endDate.isAfter(DateTime.now());

  int get daysRemaining =>
      isActive ? endDate.difference(DateTime.now()).inDays : 0;

  factory SubscriptionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SubscriptionModel(
      id: doc.id,
      driverId: data['driverId'] ?? '',
      driverName: data['driverName'] ?? '',
      plan: data['plan'] ?? 'weekly',
      status: data['status'] ?? 'pending',
      amount: (data['amount'] ?? 0.0).toDouble(),
      startDate: (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (data['endDate'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(days: 7)),
      paymentId: data['paymentId'],
      transactionId: data['transactionId'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'driverId': driverId,
      'driverName': driverName,
      'plan': plan,
      'status': status,
      'amount': amount,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'paymentId': paymentId,
      'transactionId': transactionId,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

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