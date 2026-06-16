# 🚗 ZUE — Guía de Configuración y Arquitectura

Aplicación de transporte de pasajeros para Colombia. Flutter + Firebase + PSE (Wompi).

---

## 📐 Arquitectura del Proyecto

```
lib/
├── main.dart                        # Punto de entrada
├── firebase_options.dart            # Generado por FlutterFire CLI
│
├── core/
│   ├── constants/app_constants.dart # Constantes globales
│   ├── theme/app_theme.dart         # Tema visual de la app
│   └── router/app_router.dart       # Navegación con GoRouter
│
├── models/
│   ├── user_model.dart              # Modelo de usuario (pasajero/admin)
│   ├── driver_model.dart            # Modelo de conductor
│   ├── trip_model.dart              # Modelo de viaje
│   └── subscription_model.dart     # Modelos de suscripción y pago
│
├── services/
│   ├── auth_service.dart            # Firebase Auth
│   ├── driver_service.dart          # CRUD conductores + Firestore
│   ├── trip_service.dart            # CRUD viajes + Firestore
│   └── payment_service.dart         # Integración Wompi/PSE
│
└── features/
    ├── auth/                        # Login, Registro pasajero/conductor
    ├── passenger/                   # Home mapa, solicitar viaje, tracking, historial
    ├── driver/                      # Home conductor, suscripción, perfil
    ├── trips/                       # BLoC de viajes
    └── admin/                       # Dashboard, conductores, pagos, viajes
```

---

## 🚀 Pasos para Configurar

### 1. Prerrequisitos
- Flutter 3.x instalado
- Android Studio / VS Code
- Cuenta de Firebase
- Cuenta de Google Cloud (para Maps)
- Cuenta de Wompi Colombia (para pagos PSE)

### 2. Clonar e instalar dependencias

```bash
cd ZueApp
flutter pub get
```

### 3. Crear proyecto Firebase

1. Ve a [Firebase Console](https://console.firebase.google.com)
2. Crea un nuevo proyecto llamado **"zue-app"**
3. Agrega una app flutter con package name: `com.zue.app`
4. Descarga `google-services.json` y colócalo en `android/app/`

### 4. Configurar Firebase con FlutterFire CLI

```bash
# Instalar FlutterFire CLI
dart pub global activate flutterfire_cli

# Configurar (genera firebase_options.dart automáticamente)
flutterfire configure --project=zue-app
```

### 5. Habilitar servicios Firebase

En Firebase Console, habilita:
- **Authentication** → Email/Password
- **Firestore Database** → Crear base de datos (modo producción)
- **Cloud Messaging** → Para notificaciones push
- **Storage** → Para fotos de perfil

### 6. Reglas de Firestore

> ⚠️ **NO copies reglas a mano en la consola.** La fuente de verdad de las
> reglas de seguridad es el archivo [`firestore.rules`](./firestore.rules) del
> repositorio. Despliégalo siempre con el CLI:
>
> ```bash
> firebase deploy --only firestore:rules
> ```
>
> **Por qué se eliminó el DDL de ejemplo que estaba aquí:** era vulnerable y
> permitía escalada de privilegios. En concreto:
>
> - `match /users/{userId}` con `allow write: if request.auth.uid == userId`
>   dejaba que **cualquier usuario escribiera su propio campo `role`** y se
>   pusiera `role: "admin"`. Como el resto de reglas concedían permisos de admin
>   con `get(.../users/$(uid)).data.role == 'admin'`, cualquiera podía
>   **auto-coronarse administrador**.
> - `payments` y `subscriptions` con `allow write: if request.auth != null`
>   permitían a cualquier autenticado **crear/editar pagos y activarse una
>   suscripción sin pagar**.
>
> Las reglas reales en `firestore.rules` ya corrigen esto: `subscriptions` y
> `admins` son `write: if false` (solo las Cloud Functions, vía Admin SDK,
> pueden escribirlas), `payments` solo lo crea el conductor con restricciones y
> el update/delete es exclusivo de admin, y la elevación de rol pasa por
> `isAdmin()`. No reintroduzcas reglas inline en esta guía.

### 7. Índices Firestore

Crea estos índices en Firebase Console → Firestore → Índices:

| Colección | Campos | Tipo |
|-----------|--------|------|
| `trips` | `passengerId ASC`, `status ASC`, `createdAt DESC` | Compuesto |
| `trips` | `driverId ASC`, `status ASC` | Compuesto |
| `drivers` | `isOnline ASC`, `status ASC`, `subscriptionStatus ASC` | Compuesto |
| `payments` | `driverId ASC`, `createdAt DESC` | Compuesto |
| `payments` | `status ASC`, `createdAt DESC` | Compuesto |
| `payments` | `status ASC`, `paidAt ASC` | Compuesto |

### 8. Google Maps API Key

1. Ve a [Google Cloud Console](https://console.cloud.google.com)
2. Crea/selecciona tu proyecto
3. Habilita:
   - **Maps SDK for Android**
   - **Geocoding API**
   - **Directions API**
   - **Places API**
4. Crea una API Key y restrígela a tu app Android
5. Reemplaza `TU_GOOGLE_MAPS_API_KEY_AQUI` en `android/app/src/main/AndroidManifest.xml`

### 9. Configurar Wompi (Pagos PSE)

1. Crea una cuenta en [Wompi Colombia](https://comercios.wompi.co)
2. Obtén tus llaves en el Dashboard de Wompi:
   - **Llave pública** (`pub_test_...` para sandbox)
   - **Llave privada** (para Cloud Functions)
3. En `lib/core/constants/app_constants.dart`:
   ```dart
   static const String wompiPublicKey = 'pub_test_TU_LLAVE_PUBLICA';
   ```

> ⚠️ Para producción usar `pub_prod_...` y la URL `wompiProdUrl`

### 10. Configurar Precios

En `lib/core/constants/app_constants.dart` ajusta los precios según tu modelo de negocio:

```dart
static const double weeklyPrice = 40000;   // $40.000 COP / semana
static const double monthlyPrice = 140000;  // $140.000 COP / mes
```

### 11. Crear primer Administrador

El **primer** administrador se crea manualmente (bootstrap). Esto es necesario
porque las reglas de Firestore impiden que un usuario se asigne `role` a sí mismo,
y la Cloud Function `setAdminRole` exige que quien la invoca **ya sea admin**.

1. Registra un usuario normal en la app.
2. En **Firebase Console → Firestore** (como Owner del proyecto, lo que omite las
   reglas de seguridad) edita su documento:

```
users/{userId}
  role: "admin"
```

> A partir de aquí **NO vuelvas a editar roles a mano.** Los siguientes
> administradores se asignan con la Cloud Function `setAdminRole`, que valida que
> el solicitante sea admin y deja registro de auditoría:
>
> ```
> POST /setAdminRole   (Authorization: Bearer <ID token de un admin>)
> body: { "userId": "<uid destino>", "makeAdmin": true }
> ```

### 12. Ejecutar la app

```bash
flutter run
```

---

## 🔒 Lógica de Suspensión Automática

El sistema verifica automáticamente si la suscripción de un conductor está activa:

1. `DriverModel.isSubscriptionActive` compara `subscriptionExpiry` con `DateTime.now()`
2. Si la suscripción vence, `canWork` retorna `false`
3. El conductor ve un **banner de advertencia** 3 días antes de vencer
4. Al intentar conectarse sin suscripción activa, se le bloquea y se le redirige a pagar
5. El administrador puede suspender manualmente cualquier conductor

**Para suspensión automática** (recomendado en producción), crea una Firebase Cloud Function:

```javascript
// functions/index.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

// Ejecutar cada día a medianoche Colombia (UTC-5)
exports.checkExpiredSubscriptions = functions.pubsub
  .schedule('0 5 * * *')
  .onRun(async (context) => {
    const now = admin.firestore.Timestamp.now();
    const db = admin.firestore();

    const expiredDrivers = await db.collection('drivers')
      .where('subscriptionStatus', '==', 'active')
      .where('subscriptionExpiry', '<', now)
      .get();

    const batch = db.batch();
    expiredDrivers.docs.forEach(doc => {
      batch.update(doc.ref, {
        subscriptionStatus: 'expired',
        status: 'suspended',
        isOnline: false,
        updatedAt: now,
      });
    });

    await batch.commit();
    console.log(`${expiredDrivers.size} conductores suspendidos por suscripción vencida`);
  });
```

---

## 📦 Estructura de Colecciones Firestore

### `users`
```json
{
  "id": "uid",
  "name": "Juan Pérez",
  "email": "juan@email.com",
  "phone": "3001234567",
  "role": "passenger | driver | admin",
  "isActive": true,
  "createdAt": "Timestamp"
}
```

### `drivers`
```json
{
  "id": "uid",
  "name": "Carlos López",
  "vehicleType": "car | moto",
  "vehiclePlate": "ABC123",
  "vehicleModel": "Chevrolet Spark 2020",
  "vehicleColor": "Blanco",
  "status": "active | inactive | busy | suspended",
  "isOnline": false,
  "currentLat": 4.7110,
  "currentLng": -74.0721,
  "rating": 4.8,
  "totalTrips": 150,
  "subscriptionPlan": "weekly | monthly",
  "subscriptionStatus": "active | expired | pending",
  "subscriptionExpiry": "Timestamp"
}
```

### `trips`
```json
{
  "passengerId": "uid",
  "passengerName": "María García",
  "driverId": "uid | null",
  "status": "requested | accepted | in_progress | completed | cancelled",
  "originLat": 4.7110,
  "originLng": -74.0721,
  "originAddress": "Calle 100 #15-50, Bogotá",
  "destinationLat": 4.6500,
  "destinationLng": -74.1000,
  "destinationAddress": "Calle 72 #10-20, Bogotá",
  "fare": 15000,
  "distance": 8.5,
  "assignmentType": "auto | manual",
  "createdAt": "Timestamp"
}
```

---

## 📱 Usuarios y Roles

| Rol | Acceso |
|-----|--------|
| `passenger` | Solicitar viajes, ver tracking, historial |
| `driver` | Recibir viajes, gestionar suscripción, perfil |
| `admin` | Dashboard, gestionar conductores, pagos, despacho manual |

---

## 🛠️ Stack Tecnológico

| Componente | Tecnología |
|-----------|-----------|
| Framework | Flutter 3.x |
| Estado | BLoC (flutter_bloc) |
| Base de datos | Firebase Firestore |
| Autenticación | Firebase Auth |
| Notificaciones | Firebase Cloud Messaging |
| Mapas | Google Maps Flutter |
| Ubicación | Geolocator + Geocoding |
| Pagos | Wompi Colombia (PSE) |
| Navegación | GoRouter |

---

## 📞 Soporte

Para dudas sobre la configuración, revisar:
- [Firebase Docs](https://firebase.google.com/docs)
- [Flutter Docs](https://flutter.dev/docs)
- [Wompi Docs](https://docs.wompi.co)
- [Google Maps Flutter](https://pub.dev/packages/google_maps_flutter)
