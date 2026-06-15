import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:go_router/go_router.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/driver/bloc/driver_bloc.dart';
import 'features/trips/bloc/trip_bloc.dart';
import 'firebase_options.dart';
import 'services/server_time_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar datos de locale para intl (DateFormat con 'es_CO')
  await initializeDateFormatting('es_CO', null);
  await initializeDateFormatting('es', null);

  // Inicializar Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Persistencia offline de Firestore.
  // Beneficio clave del stress test: el P95 de 2 s ocurre cuando varios
  // conductores intentan escribir simultáneamente y no hay conexión local.
  // Con persistencia offline, los writes se guardan en disco y se sincronizan
  // cuando hay red, sin bloquear la UI ni generar errores.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Sincronizar la hora REAL de servidor (para el recargo nocturno 7pm–5am).
  // No bloquea el arranque: si falla, se reintenta en segundo plano.
  unawaited(ServerTimeService.instance.sync());

  // Orientación fija vertical
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Barra de estado transparente
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const ZueApp());
}

class ZueApp extends StatefulWidget {
  const ZueApp({super.key});

  @override
  State<ZueApp> createState() => _ZueAppState();
}

class _ZueAppState extends State<ZueApp> {
  // Router y notificador creados UNA sola vez — no se destruyen en cada cambio
  // de estado de auth. Esto preserva el ScaffoldMessenger y sus snackbars.
  final _authNotifier = AuthRouterNotifier();
  late final GoRouter _router = AppRouter.createRouter(_authNotifier);

  @override
  void dispose() {
    _authNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider(
      create: (_) => AuthRepositoryImpl(),
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) => AuthBloc(
              authRepository: context.read<AuthRepositoryImpl>(),
            )..add(AuthCheckStatusEvent()),
          ),
          BlocProvider(create: (_) => DriverBloc()),
          BlocProvider(create: (_) => TripBloc()),
        ],
        // BlocListener (no BlocBuilder) para que MaterialApp.router no se
        // recree en cada estado de auth y el ScaffoldMessenger sobreviva.
        child: BlocListener<AuthBloc, AuthState>(
          listener: (context, state) => _authNotifier.update(state),
          child: MaterialApp.router(
            title: 'Zue',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.light,
            routerConfig: _router,
          ),
        ),
      ),
    );
  }
}
