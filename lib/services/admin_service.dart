import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../core/constants/app_constants.dart';
import '../models/user_model.dart';

/// Operaciones exclusivas del panel de administración.
///
/// Las acciones sensibles (bloquear cuentas, promover/revocar admins) se
/// ejecutan vía Cloud Functions con Admin SDK: deshabilitan la cuenta en
/// Firebase Auth, revocan tokens y dejan registro en moderation_log.
/// Las lecturas usan Firestore directamente (las reglas permiten list a
/// los admins).
class AdminService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final http.Client _http = http.Client();

  // ── Lecturas ──────────────────────────────────────────────────────────────

  /// Usuarios por rol ('passenger', 'driver', 'admin'), ordenados por nombre.
  Stream<List<UserModel>> watchUsersByRole(String role) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .where('role', isEqualTo: role)
        .snapshots()
        .map((snap) {
      final users = snap.docs.map(UserModel.fromFirestore).toList();
      users.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return users;
    });
  }

  /// Cuentas bloqueadas (cualquier rol).
  Stream<List<UserModel>> watchBlockedUsers() {
    return _firestore
        .collection(AppConstants.usersCollection)
        .where('isActive', isEqualTo: false)
        .snapshots()
        .map((snap) {
      final users = snap.docs.map(UserModel.fromFirestore).toList();
      users.sort((a, b) {
        final da = a.blockedAt ?? DateTime(2000);
        final db = b.blockedAt ?? DateTime(2000);
        return db.compareTo(da); // más recientes primero
      });
      return users;
    });
  }

  /// Busca un usuario por correo exacto. Devuelve null si no existe.
  Future<UserModel?> findUserByEmail(String email) async {
    final snap = await _firestore
        .collection(AppConstants.usersCollection)
        .where('email', isEqualTo: email.trim())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return UserModel.fromFirestore(snap.docs.first);
  }

  // ── Acciones (Cloud Functions, solo admins) ───────────────────────────────

  /// Bloquea o desbloquea una cuenta (usuario o conductor).
  ///
  /// [category]: incident | disciplinary | fraud | other.
  /// Al bloquear: deshabilita el login, suspende al conductor, lo saca del
  /// mapa y expulsa la sesión activa en tiempo real.
  Future<void> setUserBlocked({
    required String userId,
    required bool blocked,
    String category = AppConstants.blockCategoryOther,
    String reason = '',
  }) {
    return _callFunction(AppConstants.cfSetUserBlocked, {
      'userId': userId,
      'blocked': blocked,
      'category': category,
      'reason': reason.trim(),
    });
  }

  /// Promueve un usuario a administrador o le revoca el rol.
  Future<void> setAdminRole({
    required String userId,
    required bool makeAdmin,
  }) {
    return _callFunction(AppConstants.cfSetAdminRole, {
      'userId': userId,
      'makeAdmin': makeAdmin,
    });
  }

  Future<void> _callFunction(String url, Map<String, dynamic> body) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Sesión expirada. Inicia sesión de nuevo.');

    final token = await user.getIdToken();
    final response = await _http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      String message = 'Error del servidor (${response.statusCode})';
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['error'] != null) message = data['error'].toString();
      } catch (_) {}
      throw Exception(message);
    }
  }
}
