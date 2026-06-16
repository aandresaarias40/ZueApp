# ZueApp

Aplicación de transporte de pasajeros para **Fusagasugá / Colombia**. Conecta
pasajeros con conductores (carro y moto), con tarificación oficial calculada en
el servidor, suscripciones para conductores vía PSE (Wompi) y un panel de
administración con moderación.

## Stack

- **App:** Flutter (Dart), arquitectura por features, gestión de estado con `bloc`/`flutter_bloc`, navegación con `go_router`.
- **Backend:** Firebase — Firestore (datos + reglas de seguridad endurecidas), Firebase Auth, Cloud Functions (Gen 2, Node 22).
- **Tiempo real / geo:** Upstash Redis (GEOSEARCH para conductores cercanos) vía Cloud Functions.
- **Pagos:** Wompi (PSE) — la firma de integridad y la confirmación se hacen solo en el servidor.
- **Mapas:** Google Maps Flutter + Geolocator.

## Estructura

```
lib/
  core/        # constantes, router, tema, widgets comunes
  features/    # auth, passenger, driver, trips, admin (presentación + bloc)
  models/      # user, driver, trip, subscription
  services/    # auth, trip, driver, payment, admin, telemetría GPS
functions/     # Cloud Functions (tarifas, geo, webhook Wompi, moderación)
firestore.rules         # reglas de seguridad (fuente de verdad)
firestore.indexes.json  # índices compuestos
```

## Puesta en marcha

Requisitos: Flutter SDK (>=3.1.0), Node 22, Firebase CLI y un proyecto Firebase.

```bash
flutter pub get
# Reglas e índices
firebase deploy --only firestore:rules,firestore:indexes
# Cloud Functions (configura antes functions/.env — ver ZUE_SETUP_GUIDE.md)
firebase deploy --only functions
# Ejecutar la app
flutter run
```

La guía completa de configuración (variables de entorno, Wompi, primer
administrador, etc.) está en [`ZUE_SETUP_GUIDE.md`](./ZUE_SETUP_GUIDE.md).

## Seguridad

- Secretos (Wompi, Upstash) solo en `functions/.env` — nunca en el APK ni en git.
- Tarifas y montos de pago se validan/recalculan en el servidor; no se confía en el cliente.
- Reglas de Firestore restrictivas: `subscriptions`/`admins` solo escribibles por Cloud Functions.

> Proyecto privado — `publish_to: 'none'`.
