import 'dart:io' show HttpDate;

import 'package:http/http.dart' as http;

/// Provee la hora REAL (de servidor), independiente del reloj del teléfono.
///
/// Estrategia: al sincronizar, se consulta la cabecera `Date` de una respuesta
/// HTTPS (hora UTC del servidor) y se calcula el desfase respecto al reloj del
/// dispositivo. Luego `nowUtc()` devuelve siempre la hora de servidor estimada
/// (reloj del dispositivo + desfase), por lo que aunque el usuario cambie la
/// fecha/hora o la zona horaria del teléfono, la hora resultante sigue siendo
/// correcta. `nowColombia()` aplica el desfase fijo de Colombia (UTC-5, sin
/// horario de verano).
class ServerTimeService {
  ServerTimeService._();
  static final ServerTimeService instance = ServerTimeService._();

  /// Colombia no usa horario de verano: siempre UTC-5.
  static const Duration colombiaOffset = Duration(hours: -5);

  /// Fuente de hora confiable (cualquier respuesta HTTPS trae cabecera `Date`).
  static const String _timeSourceUrl = 'https://www.google.com';

  /// Desfase = horaServidorUtc - horaDispositivoUtc (al momento de sincronizar).
  Duration _offset = Duration.zero;
  bool _synced = false;

  /// `true` si se obtuvo la hora real de la red al menos una vez.
  bool get isSynced => _synced;

  /// Sincroniza el desfase con la hora real del servidor.
  /// Si falla (sin conexión), conserva el último desfase conocido.
  Future<void> sync() async {
    try {
      final response = await http
          .head(Uri.parse(_timeSourceUrl))
          .timeout(const Duration(seconds: 5));
      final dateHeader = response.headers['date'];
      if (dateHeader != null && dateHeader.isNotEmpty) {
        final serverUtc = HttpDate.parse(dateHeader).toUtc();
        _offset = serverUtc.difference(DateTime.now().toUtc());
        _synced = true;
      }
    } catch (_) {
      // Sin red: se mantiene el último desfase conocido (o cero la 1ra vez).
    }
  }

  /// Hora real en UTC (reloj del dispositivo corregido con el desfase).
  DateTime nowUtc() => DateTime.now().toUtc().add(_offset);

  /// Hora real en Colombia (UTC-5).
  DateTime nowColombia() => nowUtc().add(colombiaOffset);
}
