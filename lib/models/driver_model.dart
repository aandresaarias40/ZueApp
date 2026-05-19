import 'package:cloud_firestore/cloud_firestore.dart';

class DriverModel {
  final String id;             // Mismo ID que UserModel
  final String userId;
  final String name;
  final String email;
  final String phone;
  final String? photoUrl;
  final String vehicleType;    // car, moto
  final String vehiclePlate;
  final String vehicleModel;
  final String vehicleColor;
  final String licenseNumber;
  final String status;         // active, inactive, busy, suspended
  final bool isOnline;
  final double? currentLat;
  final double? currentLng;
  final double rating;
  final int totalTrips;
  final int ratedTrips; // viajes con calificación acumulada
  final String subscriptionPlan; // weekly, monthly
  final String subscriptionStatus; // active, expired, pending, trial
  final DateTime? subscriptionExpiry;
  final DateTime? trialExpiresAt;  // Fecha de vencimiento del período de prueba
  final DateTime createdAt;
  final DateTime? updatedAt;

  const DriverModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.email,
    required this.phone,
    this.photoUrl,
    required this.vehicleType,
    required this.vehiclePlate,
    required this.vehicleModel,
    required this.vehicleColor,
    required this.licenseNumber,
    this.status = 'inactive',
    this.isOnline = false,
    this.currentLat,
    this.currentLng,
    this.rating = 0.0,
    this.totalTrips = 0,
    this.ratedTrips = 0,
    required this.subscriptionPlan,
    this.subscriptionStatus = 'pending',
    this.subscriptionExpiry,
    this.trialExpiresAt,
    required this.createdAt,
    this.updatedAt,
  });

  /// Verdadero si el conductor está dentro de su período de prueba gratuita.
  bool get isOnTrial {
    if (subscriptionStatus != 'trial') return false;
    if (trialExpiresAt == null) return false;
    return trialExpiresAt!.isAfter(DateTime.now());
  }

  /// Días restantes del período de prueba (0 si ya venció o no aplica).
  int get trialDaysRemaining {
    if (!isOnTrial) return 0;
    return trialExpiresAt!.difference(DateTime.now()).inDays + 1;
  }

  bool get isSubscriptionActive {
    // El período de prueba también habilita al conductor
    if (isOnTrial) return true;
    if (subscriptionStatus != 'active') return false;
    if (subscriptionExpiry == null) return false;
    return subscriptionExpiry!.isAfter(DateTime.now());
  }

  bool get canWork => isSubscriptionActive && status != 'suspended';

  /// La calificación solo se muestra cuando hay al menos 5 viajes completados.
  bool get hasRating => totalTrips >= 5;

  /// Texto de calificación para mostrar en UI.
  String get ratingDisplay =>
      hasRating ? rating.toStringAsFixed(1) : 'Sin calif.';

  int get daysUntilExpiry {
    if (isOnTrial) return trialDaysRemaining;          // Trial → días restantes del trial
    if (subscriptionExpiry == null) return 0;
    return subscriptionExpiry!.difference(DateTime.now()).inDays;
  }

  factory DriverModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DriverModel(
      id: doc.id,
      userId: data['userId'] ?? doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      photoUrl: data['photoUrl'],
      vehicleType: data['vehicleType'] ?? 'car',
      vehiclePlate: data['vehiclePlate'] ?? '',
      vehicleModel: data['vehicleModel'] ?? '',
      vehicleColor: data['vehicleColor'] ?? '',
      licenseNumber: data['licenseNumber'] ?? '',
      status: data['status'] ?? 'inactive',
      isOnline: data['isOnline'] ?? false,
      currentLat: data['currentLat']?.toDouble(),
      currentLng: data['currentLng']?.toDouble(),
      rating: (data['rating'] ?? 0.0).toDouble(),
      totalTrips: data['totalTrips'] ?? 0,
      ratedTrips: data['ratedTrips'] ?? 0,
      subscriptionPlan: data['subscriptionPlan'] ?? 'weekly',
      subscriptionStatus: data['subscriptionStatus'] ?? 'pending',
      subscriptionExpiry: (data['subscriptionExpiry'] as Timestamp?)?.toDate(),
      trialExpiresAt: (data['trialExpiresAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'name': name,
      'email': email,
      'phone': phone,
      'photoUrl': photoUrl,
      'vehicleType': vehicleType,
      'vehiclePlate': vehiclePlate,
      'vehicleModel': vehicleModel,
      'vehicleColor': vehicleColor,
      'licenseNumber': licenseNumber,
      'status': status,
      'isOnline': isOnline,
      'currentLat': currentLat,
      'currentLng': currentLng,
      'rating': rating,
      'totalTrips': totalTrips,
      'ratedTrips': ratedTrips,
      'subscriptionPlan': subscriptionPlan,
      'subscriptionStatus': subscriptionStatus,
      'subscriptionExpiry': subscriptionExpiry != null
          ? Timestamp.fromDate(subscriptionExpiry!)
          : null,
      'trialExpiresAt': trialExpiresAt != null
          ? Timestamp.fromDate(trialExpiresAt!)
          : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  DriverModel copyWith({
    String? name,
    String? status,
    bool? isOnline,
    double? currentLat,
    double? currentLng,
    double? rating,
    int? totalTrips,
    int? ratedTrips,
    String? subscriptionStatus,
    DateTime? subscriptionExpiry,
    DateTime? trialExpiresAt,
    DateTime? updatedAt,
  }) {
    return DriverModel(
      id: id,
      userId: userId,
      name: name ?? this.name,
      email: email,
      phone: phone,
      photoUrl: photoUrl,
      vehicleType: vehicleType,
      vehiclePlate: vehiclePlate,
      vehicleModel: vehicleModel,
      vehicleColor: vehicleColor,
      licenseNumber: licenseNumber,
      status: status ?? this.status,
      isOnline: isOnline ?? this.isOnline,
      currentLat: currentLat ?? this.currentLat,
      currentLng: currentLng ?? this.currentLng,
      rating: rating ?? this.rating,
      totalTrips: totalTrips ?? this.totalTrips,
      ratedTrips: ratedTrips ?? this.ratedTrips,
      subscriptionPlan: subscriptionPlan,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      subscriptionExpiry: subscriptionExpiry ?? this.subscriptionExpiry,
      trialExpiresAt: trialExpiresAt ?? this.trialExpiresAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
