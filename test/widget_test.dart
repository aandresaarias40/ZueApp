// Tests unitarios de lógica pura (sin Firebase).
//
// El smoke test anterior (pumpWidget(ZueApp())) fallaba siempre porque
// ZueApp requiere Firebase.initializeApp(), no disponible en tests de widget.

import 'package:flutter_test/flutter_test.dart';

import 'package:zue/core/router/app_router.dart';
import 'package:zue/features/auth/bloc/auth_bloc.dart';
import 'package:zue/models/user_model.dart';

void main() {
  group('AuthRouterNotifier', () {
    test('notifica en estados que requieren redirección', () {
      final notifier = AuthRouterNotifier();
      var notified = 0;
      notifier.addListener(() => notified++);

      notifier.update(AuthUnauthenticatedState());
      expect(notified, 1);
      expect(notifier.state, isA<AuthUnauthenticatedState>());

      notifier.update(AuthAuthenticatedState(
        user: UserModel(
          id: 'u1',
          name: 'Test',
          email: 'test@test.com',
          phone: '3000000000',
          role: 'passenger',
          isActive: true,
          createdAt: DateTime(2026, 1, 1),
        ),
      ));
      expect(notified, 2);
      expect(notifier.state, isA<AuthAuthenticatedState>());

      notifier.dispose();
    });

    test('ignora Loading y Error para no destruir el ScaffoldMessenger', () {
      final notifier = AuthRouterNotifier();
      var notified = 0;
      notifier.addListener(() => notified++);

      notifier.update(AuthLoadingState());
      notifier.update(AuthErrorState(message: 'error'));

      expect(notified, 0);
      expect(notifier.state, isA<AuthInitialState>());

      notifier.dispose();
    });
  });
}
