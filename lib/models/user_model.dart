import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String role; // passenger, driver, admin
  final String? photoUrl;
  final bool isActive;

  // ── Bloqueo administrativo (medida disciplinaria / incidente) ────────────
  final String? blockCategory; // incident, disciplinary, fraud, other
  final String? blockReason;   // Descripción escrita por el admin
  final DateTime? blockedAt;

  final DateTime createdAt;
  final DateTime? updatedAt;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.photoUrl,
    this.isActive = true,
    this.blockCategory,
    this.blockReason,
    this.blockedAt,
    required this.createdAt,
    this.updatedAt,
  });

  bool get isBlocked => !isActive;

  /// Etiqueta legible de la categoría del bloqueo.
  String get blockCategoryLabel {
    switch (blockCategory) {
      case 'incident':      return 'Incidente';
      case 'disciplinary':  return 'Medida disciplinaria';
      case 'fraud':         return 'Fraude';
      case 'other':         return 'Otro';
      default:              return 'Sin categoría';
    }
  }

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      id: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      role: data['role'] ?? 'passenger',
      photoUrl: data['photoUrl'],
      isActive: data['isActive'] ?? true,
      blockCategory: data['blockCategory'],
      blockReason: data['blockReason'],
      blockedAt: (data['blockedAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
      'photoUrl': photoUrl,
      'isActive': isActive,
      'blockCategory': blockCategory,
      'blockReason': blockReason,
      'blockedAt': blockedAt != null ? Timestamp.fromDate(blockedAt!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  UserModel copyWith({
    String? name,
    String? email,
    String? phone,
    String? role,
    String? photoUrl,
    bool? isActive,
    String? blockCategory,
    String? blockReason,
    DateTime? blockedAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      photoUrl: photoUrl ?? this.photoUrl,
      isActive: isActive ?? this.isActive,
      blockCategory: blockCategory ?? this.blockCategory,
      blockReason: blockReason ?? this.blockReason,
      blockedAt: blockedAt ?? this.blockedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
