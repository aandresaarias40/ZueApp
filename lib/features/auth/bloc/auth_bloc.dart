import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../models/user_model.dart';
import '../../../services/auth_service.dart';
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

class AuthErrorState extends AuthState {
  final String message;
  AuthErrorState({required this.message});
  @override
  List<Object?> get props => [message];
}

// BLoC
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepositoryImpl authRepository;

  AuthBloc({required this.authRepository}) : super(AuthInitialState()) {
    on<AuthCheckStatusEvent>(_onCheckStatus);
    on<AuthLoginEvent>(_onLogin);
    on<AuthRegisterPassengerEvent>(_onRegisterPassenger);
    on<AuthLogoutEvent>(_onLogout);
  }

  Future<void> _onCheckStatus(
      AuthCheckStatusEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoadingState());
    try {
      final user = await authRepository.getCurrentUser();
      if (user != null) {
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
      emit(AuthAuthenticatedState(user: user));
    } catch (e) {
      emit(AuthErrorState(message: e.toString()));
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
      emit(AuthAuthenticatedState(user: user));
    } catch (e) {
      emit(AuthErrorState(message: e.toString()));
      emit(AuthUnauthenticatedState());
    }
  }

  Future<void> _onLogout(
      AuthLogoutEvent event, Emitter<AuthState> emit) async {
    await authRepository.signOut();
    emit(AuthUnauthenticatedState());
  }
}
