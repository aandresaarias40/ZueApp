import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/driver/bloc/driver_bloc.dart';
import 'features/driver/data/repositories/driver_repository_impl.dart';
import 'features/trips/bloc/trip_bloc.dart';
import 'features/trips/data/repositories/trip_repository_impl.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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

class ZueApp extends StatelessWidget {
  const ZueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => AuthRepositoryImpl()),
        RepositoryProvider(create: (_) => DriverRepositoryImpl()),
        RepositoryProvider(create: (_) => TripRepositoryImpl()),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) => AuthBloc(
              authRepository: context.read<AuthRepositoryImpl>(),
            )..add(AuthCheckStatusEvent()),
          ),
          BlocProvider(
            create: (context) => DriverBloc(
              driverRepository: context.read<DriverRepositoryImpl>(),
            ),
          ),
          BlocProvider(
            create: (context) => TripBloc(
              tripRepository: context.read<TripRepositoryImpl>(),
            ),
          ),
        ],
        child: BlocBuilder<AuthBloc, AuthState>(
          builder: (context, state) {
            return MaterialApp.router(
              title: 'Zue',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: ThemeMode.light,
              routerConfig: AppRouter.router(state),
            );
          },
        ),
      ),
    );
  }
}
