import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../models/driver_model.dart';
import '../core/constants/app_constants.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Stream del usuario actual
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  // Login con email y contraseña
  Future<UserModel> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = credential.user!.uid;
      return await getUserById(uid);
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthException(e);
    }
  }

  // Registro de pasajero
  Future<UserModel> registerPassenger({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = credential.user!.uid;

      final user = UserModel(
        id: uid,
        name: name.trim(),
        email: email.trim(),
        phone: phone.trim(),
        role: AppConstants.rolePassenger,
        isActive: true,
        createdAt: DateTime.now(),
      );

      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .set(user.toFirestore());

      // Actualizar displayName en Firebase Auth
      await credential.user!.updateDisplayName(name);

      return user;
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthException(e);
    }
  }

  // Registro de transportador
  Future<DriverModel> registerDriver({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String vehicleType,
    required String vehiclePlate,
    required String vehicleModel,
    required String vehicleColor,
    required String licenseNumber,
    required String subscriptionPlan,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = credential.user!.uid;

      // Crear usuario base
      final user = UserModel(
        id: uid,
        name: name.trim(),
        email: email.trim(),
        phone: phone.trim(),
        role: AppConstants.roleDriver,
        isActive: true,
        createdAt: DateTime.now(),
      );

      // Crear perfil de conductor
      final driver = DriverModel(
        id: uid,
        userId: uid,
        name: name.trim(),
        email: email.trim(),
        phone: phone.trim(),
        vehicleType: vehicleType,
        vehiclePlate: vehiclePlate.toUpperCase(),
        vehicleModel: vehicleModel,
        vehicleColor: vehicleColor,
        licenseNumber: licenseNumber,
        status: AppConstants.driverStatusInactive,
        subscriptionPlan: subscriptionPlan,
        subscriptionStatus: 'pending', // Requiere pago
        createdAt: DateTime.now(),
      );

      // Batch write para atomicidad
      final batch = _firestore.batch();
      batch.set(
        _firestore.collection(AppConstants.usersCollection).doc(uid),
        user.toFirestore(),
      );
      batch.set(
        _firestore.collection(AppConstants.driversCollection).doc(uid),
        driver.toFirestore(),
      );
      await batch.commit();

      await credential.user!.updateDisplayName(name);

      return driver;
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthException(e);
    }
  }

  // Obtener usuario por ID
  Future<UserModel> getUserById(String uid) async {
    final doc = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .get();
    if (!doc.exists) throw Exception('Usuario no encontrado');
    return UserModel.fromFirestore(doc);
  }

  // Cerrar sesión
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Recuperar contraseña
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  // Mapear errores de Firebase Auth a mensajes en español
  String _mapFirebaseAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No existe una cuenta con este correo electrónico.';
      case 'wrong-password':
        return 'Contraseña incorrecta. Intenta de nuevo.';
      case 'email-already-in-use':
        return 'Este correo ya está registrado. Intenta iniciar sesión.';
      case 'weak-password':
        return 'La contraseña debe tener al menos 6 caracteres.';
      case 'invalid-email':
        return 'El formato del correo electrónico no es válido.';
      case 'user-disabled':
        return 'Tu cuenta ha sido deshabilitada. Contacta soporte.';
      case 'too-many-requests':
        return 'Demasiados intentos fallidos. Espera un momento e intenta de nuevo.';
      case 'network-request-failed':
        return 'Sin conexión a internet. Verifica tu conexión.';
      default:
        return 'Error de autenticación: ${e.message}';
    }
  }
}
