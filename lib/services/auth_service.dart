import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../models/driver_model.dart';
import '../core/constants/app_constants.dart';
import 'location_telemetry_service.dart';

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
      final user = await getUserById(uid);

      // Cuenta bloqueada por un administrador → rechazar el acceso.
      if (!user.isActive) {
        await _auth.signOut();
        throw Exception(blockedAccountMessage(user));
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapFirebaseAuthException(e));
    }
  }

  /// Mensaje mostrado a un usuario bloqueado (incluye categoría y motivo).
  static String blockedAccountMessage(UserModel user) {
    final buffer = StringBuffer('Tu cuenta ha sido bloqueada por el equipo de Zue.');
    buffer.write('\nCategoría: ${user.blockCategoryLabel}.');
    if (user.blockReason != null && user.blockReason!.trim().isNotEmpty) {
      buffer.write('\nMotivo: ${user.blockReason}.');
    }
    buffer.write('\nSi crees que es un error, contacta a soporte.');
    return buffer.toString();
  }

  /// Stream del documento del usuario autenticado.
  /// Usado por AuthBloc para expulsar en tiempo real a cuentas bloqueadas.
  Stream<UserModel?> watchUser(String uid) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? UserModel.fromFirestore(doc) : null);
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
      throw Exception(_mapFirebaseAuthException(e));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Registro de transportador con:
  //   • Validación anti-fraude (cédula, placa y celular únicos en Firestore)
  //   • Período de prueba gratuita de 3 días para conductores nuevos
  //
  // ORDEN DE OPERACIONES:
  //   1. Crear cuenta Firebase Auth → el usuario queda autenticado
  //   2. Verificar duplicados en driver_identities (ya con request.auth válido)
  //   3. Si hay duplicado → borrar la cuenta Auth recién creada y lanzar error
  //   4. Si pasa → batch write atómico de user + driver + identidad
  // ─────────────────────────────────────────────────────────────────────────
  Future<DriverModel> registerDriver({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String vehicleType,
    required String vehiclePlate,
    required String vehicleModel,
    required String vehicleColor,
    required String cedula,          // Cédula de ciudadanía (para PSE y antifraude)
    required String licenseNumber,   // Número de licencia de conducción
    required String subscriptionPlan,
  }) async {
    final normalizedCedula = cedula.trim();
    final normalizedPlate  = vehiclePlate.trim().toUpperCase();
    final normalizedPhone  = phone.trim();

    // ── 1. Crear cuenta en Firebase Auth ──────────────────────────────────
    //    Primero creamos la cuenta para que las reglas de Firestore reciban
    //    un request.auth válido en los pasos siguientes.
    late UserCredential credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapFirebaseAuthException(e));
    }

    final uid = credential.user!;

    // ── 2. Verificación anti-fraude (ya autenticado) ───────────────────────
    final identitiesRef =
        _firestore.collection(AppConstants.driverIdentitiesCollection);

    try {
      // Verificar cédula (ID del documento = cédula → O(1))
      final cedulaDoc = await identitiesRef.doc(normalizedCedula).get();
      if (cedulaDoc.exists) {
        throw Exception(
          'Ya existe un conductor registrado con esa cédula. '
          'Si olvidaste tu contraseña, usa la opción de recuperación.',
        );
      }

      // Verificar placa
      final plateQuery = await identitiesRef
          .where('plate', isEqualTo: normalizedPlate)
          .limit(1)
          .get();
      if (plateQuery.docs.isNotEmpty) {
        throw Exception(
          'Ya existe un conductor registrado con esa placa ($normalizedPlate). '
          'Verifica los datos e intenta de nuevo.',
        );
      }

      // Verificar celular
      final phoneQuery = await identitiesRef
          .where('phone', isEqualTo: normalizedPhone)
          .limit(1)
          .get();
      if (phoneQuery.docs.isNotEmpty) {
        throw Exception(
          'Ya existe un conductor registrado con ese número de celular. '
          'Si olvidaste tu contraseña, usa la opción de recuperación.',
        );
      }
    } catch (e) {
      // ── 3. Duplicado encontrado → limpiar la cuenta Auth y relanzar ───────
      await uid.delete();
      rethrow;
    }

    // ── 4. Todo OK → batch write atómico ─────────────────────────────────
    try {
      final now         = DateTime.now();
      final trialExpiry = now.add(
        const Duration(days: AppConstants.driverTrialDays),
      );

      final user = UserModel(
        id: uid.uid,
        name: name.trim(),
        email: email.trim(),
        phone: normalizedPhone,
        role: AppConstants.roleDriver,
        isActive: true,
        createdAt: now,
      );

      final driver = DriverModel(
        id: uid.uid,
        userId: uid.uid,
        name: name.trim(),
        email: email.trim(),
        phone: normalizedPhone,
        vehicleType: vehicleType,
        vehiclePlate: normalizedPlate,
        vehicleModel: vehicleModel,
        vehicleColor: vehicleColor,
        cedula: normalizedCedula,
        licenseNumber: licenseNumber.trim(),
        status: AppConstants.driverStatusInactive,
        subscriptionPlan: subscriptionPlan,
        subscriptionStatus: AppConstants.subscriptionStatusTrial,
        trialExpiresAt: trialExpiry,
        createdAt: now,
      );

      final batch = _firestore.batch();

      batch.set(
        _firestore.collection(AppConstants.usersCollection).doc(uid.uid),
        user.toFirestore(),
      );
      batch.set(
        _firestore.collection(AppConstants.driversCollection).doc(uid.uid),
        driver.toFirestore(),
      );
      batch.set(
        identitiesRef.doc(normalizedCedula),
        {
          'cedula'   : normalizedCedula,
          'plate'    : normalizedPlate,
          'phone'    : normalizedPhone,
          'email'    : email.trim(),
          'driverId' : uid.uid,
          'createdAt': Timestamp.fromDate(now),
        },
      );

      await batch.commit();
      await uid.updateDisplayName(name);

      return driver;
    } on FirebaseAuthException catch (e) {
      await uid.delete();
      throw Exception(_mapFirebaseAuthException(e));
    } catch (e) {
      await uid.delete();
      rethrow;
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
  // Marca al conductor como offline en Firestore antes de cerrar la sesión
  // para que no quede visible en el mapa de pasajeros.
  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        // Verificar si el usuario es conductor antes de tocar la colección drivers
        final userDoc = await _firestore
            .collection(AppConstants.usersCollection)
            .doc(uid)
            .get();
        final role = userDoc.exists
            ? (userDoc.data() as Map<String, dynamic>)['role'] as String?
            : null;

        if (role == AppConstants.roleDriver) {
          await _firestore
              .collection(AppConstants.driversCollection)
              .doc(uid)
              .update({
            'isOnline': false,
            'status': AppConstants.driverStatusInactive,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          // Limpiar también el índice Redis (vía Cloud Function) para que el
          // conductor desaparezca del mapa de inmediato y no tras el EXPIRE
          // de 120 s. Debe ejecutarse ANTES de _auth.signOut() porque la CF
          // requiere el ID Token del usuario aún autenticado.
          await LocationTelemetryService().setDriverOffline(uid);
        }
      } catch (_) {
        // No bloquear el logout si Firestore falla
      }
    }
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
