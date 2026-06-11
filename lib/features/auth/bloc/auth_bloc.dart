import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../models/user_model.dart';
import '../data/repositories/auth_repository_impl.dart';

// Events
abstract class AuthEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthCheckStatusEvent extends AuthEvent {}

class AuthLoginEvent extends AuthEvent {
  final String email;
  final String password;
  AuthLoginEvent({required this.email, required this.password});
  @override
  List<Object?> get props => [email, password];
}

class AuthRegisterPassengerEvent extends AuthEvent {
  final String name;
  final String email;
  final String phone;
  final String password;
  AuthRegisterPassengerEvent({
    required this.name,
    required this.email,
    required this.phone,
    required this.password,
  });
}

class AuthLogoutEvent extends AuthEvent {}

/// Disparado internamente cuando el documento del usuario cambia en
/// Firestore (p. ej. un admin lo bloquea mientras tiene sesión abierta).
class AuthUserDocChangedEvent extends AuthEvent {
  final UserModel? user;
  AuthUserDocChangedEvent(this.user);
  @override
  List<Object?> get props => [user];
}

// States
abstract class AuthState extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthInitialState extends AuthState {}

class AuthLoadingState extends AuthState {}

class AuthAuthenticatedState extends AuthState {
  final UserModel user;
  AuthAuthenticatedState({required this.user});
  @override
  List<Object?> get props => [user];
}

class AuthUnauthenticatedState extends AuthState {}

/// La cuenta fue bloqueada por un administrador. Se cierra la sesión y
/// el login muestra el motivo. El router lo trata como "no autenticado".
class AuthBlockedState extends AuthState {
  final String message;
  AuthBlockedState({required this.message});
  @override
  List<Object?> get props => [message];
}

class AuthErrorState extends AuthState {
  final String message;
  AuthErrorState({required this.message});
  @override
  List<Object?> get props => [message];
}

// BLoC
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepositoryImpl authRepository;

  /// Suscripción en vivo al documento users/{uid} del usuario autenticado.
  /// Permite expulsar de inmediato a una cuenta bloqueada por un admin.
  StreamSubscription<UserModel?>? _userDocSub;

  AuthBloc({required this.authRepository}) : super(AuthInitialState()) {
    on<AuthCheckStatusEvent>(_onCheckStatus);
    on<AuthLoginEvent>(_onLogin);
    on<AuthRegisterPassengerEvent>(_onRegisterPassenger);
    on<AuthLogoutEvent>(_onLogout);
    on<AuthUserDocChangedEvent>(_onUserDocChanged);
  }

  void _watchUserDoc(String uid) {
    _userDocSub?.cancel();
    _userDocSub = authRepository
        .watchUser(uid)
        .listen((user) => add(AuthUserDocChangedEvent(user)));
  }

  Future<void> _stopWatchingUserDoc() async {
    await _userDocSub?.cancel();
    _userDocSub = null;
  }

  Future<void> _onCheckStatus(
      AuthCheckStatusEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoadingState());
    try {
      final user = await authRepository.getCurrentUser();
      if (user != null) {
        // Cuenta bloqueada → cerrar sesión y mostrar el motivo.
        if (!user.isActive) {
          await authRepository.signOut();
          emit(AuthBlockedState(message: authRepository.blockedMessage(user)));
          return;
        }
        _watchUserDoc(user.id);
        emit(AuthAuthenticatedState(user: user));
      } else {
        emit(AuthUnauthenticatedState());
      }
    } catch (_) {
      emit(AuthUnauthenticatedState());
    }
  }

  Future<void> _onLogin(
      AuthLoginEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoadingState());
    try {
      final user = await authRepository.signIn(
        email: event.email,
        password: event.password,
      );
      _watchUserDoc(user.id);
      emit(AuthAuthenticatedState(user: user));
    } catch (e) {
      emit(AuthErrorState(message: _authErrorMessage(e)));
      emit(AuthUnauthenticatedState());
    }
  }

  Future<void> _onRegisterPassenger(
      AuthRegisterPassengerEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoadingState());
    try {
      final user = await authRepository.registerPassenger(
        name: event.name,
        email: event.email,
        phone: event.phone,
        password: event.password,
      );
      _watchUserDoc(user.id);
      emit(AuthAuthenticatedState(user: user));
    } catch (e) {
      emit(AuthErrorState(message: _authErrorMessage(e)));
      emit(AuthUnauthenticatedState());
    }
  }

  /// El documento del usuario cambió en Firestore.
  /// Si fue bloqueado (isActive=false) → cerrar sesión inmediatamente.
  Future<void> _onUserDocChanged(
      AuthUserDocChangedEvent event, Emitter<AuthState> emit) async {
    if (state is! AuthAuthenticatedState) return;

    final user = event.user;
    if (user == null) {
      // El documento fue eliminado por un admin → sesión inválida.
      await _stopWatchingUserDoc();
      await authRepository.signOut();
      emit(AuthUnauthenticatedState());
      return;
    }

    if (!user.isActive) {
      await _stopWatchingUserDoc();
      await authRepository.signOut();
      emit(AuthBlockedState(message: authRepository.blockedMessage(user)));
      return;
    }

    // Mantener el estado sincronizado (cambios de nombre, rol, etc.).
    emit(AuthAuthenticatedState(user: user));
  }

  /// Traduce errores de FirebaseAuth a mensajes legibles en español.
  String _authErrorMessage(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          return 'Correo o contraseña incorrectos.';
        case 'user-not-found':
          return 'No existe una cuenta con este correo.';
        case 'invalid-email':
          return 'El correo electrónico no es válido.';
        case 'user-disabled':
          return 'Tu cuenta ha sido bloqueada. Contacta a soporte de Zue.';
        case 'too-many-requests':
          return 'Demasiados intentos fallidos. Intenta más tarde.';
        case 'network-request-failed':
          return 'Sin conexión. Verifica tu internet.';
        case 'email-already-in-use':
          return 'Ya existe una cuenta con este correo.';
        case 'weak-password':
          return 'La contraseña es muy débil. Usa al menos 6 caracteres.';
        case 'operation-not-allowed':
          return 'Método de inicio de sesión no habilitado.';
        default:
          return 'Error de autenticación (${e.code}).';
      }
    }
    // AuthService lanza Exception con mensajes ya traducidos al español
    final msg = e.toString().replaceFirst('Exception: ', '');
    return msg.isNotEmpty ? msg : 'Ocurrió un error. Intenta de nuevo.';
  }

  Future<void> _onLogout(
      AuthLogoutEvent event, Emitter<AuthState> emit) async {
    await _stopWatchingUserDoc();
    await authRepository.signOut();
    emit(AuthUnauthenticatedState());
  }

  @override
  Future<void> close() async {
    await _stopWatchingUserDoc();
    return super.close();
  }
}
