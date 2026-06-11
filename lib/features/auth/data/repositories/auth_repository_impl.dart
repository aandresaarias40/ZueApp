import 'package:firebase_auth/firebase_auth.dart';
import '../../../../models/user_model.dart';
import '../../../../services/auth_service.dart';

class AuthRepositoryImpl {
  final AuthService _authService = AuthService();

  Future<UserModel?> getCurrentUser() async {
    final user = _authService.currentUser;
    if (user == null) return null;
    try {
      return await _authService.getUserById(user.uid);
    } catch (_) {
      return null;
    }
  }

  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    return await _authService.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<UserModel> registerPassenger({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    return await _authService.registerPassenger(
      name: name,
      email: email,
      phone: phone,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _authService.signOut();
  }

  Stream<User?> get authStateChanges => _authService.authStateChanges;

  /// Stream del documento del usuario (para detectar bloqueos en vivo).
  Stream<UserModel?> watchUser(String uid) => _authService.watchUser(uid);

  /// Mensaje estándar para cuentas bloqueadas.
  String blockedMessage(UserModel user) =>
      AuthService.blockedAccountMessage(user);
}
