1. Vulnerabilidad Crítica de Privacidad: Lectura Masiva de Datos de Conductores (Fuga de Información)
Archivo: 
firestore.rules
 (Línea 132)
Criticidad: CRÍTICA (Seguridad / Privacidad de Datos)
Descripción: La regla de seguridad en la colección driver_identities permite a cualquier usuario autenticado realizar una descarga masiva de la colección:
javascript


allow list: if signedIn();
Impacto: Esta colección contiene información altamente sensible de todos los conductores (Cédula de ciudadanía, placa del vehículo, teléfono, correo electrónico e ID del conductor). Un usuario malintencionado con rol de pasajero podría ejecutar un script simple para listar y extraer la base de datos completa de todos los transportadores de la aplicación.
Recomendación: Cambiar la regla para que la lista masiva solo esté permitida a los administradores:
javascript


allow list: if isAdmin();
Las comprobaciones de duplicados durante el registro de un conductor (cédula, placa, celular) deben migrarse para ser validadas en el servidor (a través de una Cloud Function como createPSETransaction o un endpoint de registro) en lugar de que el cliente realice consultas directas sobre la colección completa en Firestore.
2. Error de Activación de Suscripciones: Mapeo Incorrecto de Nombre de Campo en Webhook
Archivo: 
functions/index.js
 (Línea 618)
Criticidad: CRÍTICA (Impacto Financiero / Funcional)
Descripción: En la función del Webhook de Wompi (wompiWebhook), cuando la pasarela de pagos aprueba una transacción, se actualiza el documento del conductor en Firestore con el campo subscriptionEnd:
javascript


batch.update(driverRef, {
  subscriptionStatus: "active",
  subscriptionPlan:   plan,
  subscriptionEnd:    endDate,
  updatedAt:          admin.firestore.Timestamp.now(),
});
Sin embargo, el cliente móvil en Flutter espera y mapea el campo subscriptionExpiry a través de 
DriverModel
.
Impacto: Al procesar un pago exitoso, el webhook actualizará subscriptionEnd, dejando subscriptionExpiry en null o vencido en la base de datos. Como consecuencia, el conductor nunca verá su suscripción activa en la aplicación móvil y no podrá ponerse en línea para trabajar a pesar de haber pagado.
Recomendación: Cambiar el nombre del campo en la actualización del lote en functions/index.js para que coincida con el modelo de datos esperado:
javascript


batch.update(driverRef, {
  subscriptionStatus: "active",
  subscriptionPlan:   plan,
  subscriptionExpiry:  endDate,
  updatedAt:          admin.firestore.Timestamp.now(),
});
3. Bloqueo del Proceso de Pago: Restricción Excesiva de Dominios en WebView
Archivo: 
driver_subscription_page.dart
 (Líneas 611 a 616)
Criticidad: CRÍTICA (Bloqueo Operativo)
Descripción: El widget _PSEWebView que renderiza la pasarela de Wompi define una lista restrictiva de dominios permitidos (wompi.co, pse.com.co, web.app, firebaseapp.com).
Impacto: Durante el flujo de pago PSE, Wompi redirige obligatoriamente al conductor hacia el portal de login seguro de su entidad financiera (ej. grupobancolombia.com, davivienda.com, nequi.com.co). Dado que estos hosts bancarios externos no coinciden con la lista permitida de _allowedDomainSuffixes, el delegado de navegación del WebView abortará el flujo inmediatamente (NavigationDecision.prevent), bloqueando al transportador para completar su pago.
Recomendación: Eliminar el filtrado de dominios bancarios en el WebView durante la pasarela o relajar la regla permitiendo cualquier navegación HTTPS que no sea catalogada como riesgosa. Solo se debería interceptar y detener la navegación cuando la URL coincida con la URL de redirección final configurada (AppConstants.wompiRedirectUrl) para cerrar el WebView y validar el pago.
4. Bypass de Bloqueo en Cloud Functions: Falta de Validación de Tokens Revocados
Archivo: 
functions/index.js
 (Línea 165)
Criticidad: ALTA (Vulnerabilidad de Seguridad)
Descripción: La función auxiliar verifyToken de las Cloud Functions valida la firma criptográfica del Firebase ID Token:
javascript


return await admin.auth().verifyIdToken(auth.split("Bearer ")[1]);
Sin embargo, no pasa el parámetro checkRevoked configurado en true.
Impacto: Cuando un administrador suspende o bloquea una cuenta (cambiando isActive a false), el backend revoca los refresh tokens de Auth de forma inmediata. Sin embargo, los ID tokens de Firebase ya emitidos son stateless JWTs válidos por hasta 1 hora. Dado que las Cloud Functions no comprueban si el token fue revocado o si el usuario fue inhabilitado en Firebase Auth, un usuario bloqueado puede seguir consumiendo endpoints HTTP (ej: actualizando su ubicación GPS en Redis o creando transacciones PSE) durante una hora después de su bloqueo.
Recomendación: Habilitar el chequeo de revocación al verificar el ID Token:
javascript


return await admin.auth().verifyIdToken(auth.split("Bearer ")[1], true);
(Nota: Se debe envolver adecuadamente en try-catch ya que este cambio hace que la función lance una excepción si el token ha sido revocado).
5. Inconsistencia de Datos: Asignación Manual No Atómica
Archivo: 
trip_service.dart
 (Líneas 185 a 208)
Criticidad: MEDIA (Integridad de Datos)
Descripción: En la función manuallyAssignTrip, la actualización del estado del viaje y el cambio de estado del conductor a busy se realizan mediante llamadas separadas no transaccionales:
dart


await _trips.doc(tripId).update({...});
await _firestore.collection(...).doc(driverId).update({'status': AppConstants.driverStatusBusy});
Impacto: Si la aplicación o el servidor pierden conexión o se interrumpen entre los dos comandos, el viaje quedará asignado y aceptado pero el conductor seguirá apareciendo como libre (active) en lugar de ocupado (busy). Esto permite que el conductor reciba o acepte otros viajes simultáneamente.
Recomendación: Agrupar ambas actualizaciones en un lote de escritura atómica (WriteBatch) o una transacción, asegurando que ambas operaciones se apliquen juntas o falle todo el bloque:
dart


final batch = _firestore.batch();
batch.update(_trips.doc(tripId), {...});
batch.update(_firestore.collection(AppConstants.driversCollection).doc(driverId), {'status': AppConstants.driverStatusBusy});
await batch.commit();
6. Caída del Fallback en Firestore: Falta de Índice Compuesto
Archivo: 
firestore.indexes.json
 y 
driver_service.dart
Criticidad: MEDIA (Robustez / Fallback)
Descripción: Cuando Redis está inactivo, getNearbyDrivers realiza una consulta de respaldo en Firestore filtrando opcionalmente por tipo de vehículo:
dart


Query query = _drivers
    .where('isOnline', isEqualTo: true)
    .where('status', isEqualTo: AppConstants.driverStatusActive)
    .limit(AppConstants.maxNearbyDriverFetch);
if (vehicleType != null) {
  query = query.where('vehicleType', isEqualTo: vehicleType);
}
Impacto: Si la consulta se realiza especificando un vehicleType (por ejemplo, para buscar solo motos), Firestore arrojará un error de ejecución debido a la falta de un índice compuesto específico para isOnline, status y vehicleType. Esto inhabilitará por completo la búsqueda de conductores cercanos en modo de contingencia (Firestore local).
Recomendación: Agregar un índice compuesto en 
firestore.indexes.json
 para soportar el caso de fallback filtrado:
json


{
  "collectionGroup": "drivers",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "isOnline", "order": "ASCENDING" },
    { "fieldPath": "status", "order": "ASCENDING" },
    { "fieldPath": "vehicleType", "order": "ASCENDING" }
  ]
}
7. Inconsistencia en Registro de Pasajeros
Archivo: 
auth_service.dart
 (Líneas 63 a 98)
Criticidad: MEDIA (Inconsistencia de Cuentas)
Descripción: A diferencia del registro de conductores, en la función registerPassenger, si ocurre un fallo de red o permisos al guardar el perfil en Firestore luego de haber creado el usuario en Firebase Auth, la excepción se propaga sin limpiar la cuenta de autenticación.
Impacto: La cuenta de Firebase Auth queda creada de forma huérfana (sin documento de usuario en la base de datos). Si el usuario intenta registrarse nuevamente, recibirá un error genérico indicando que el correo electrónico ya está en uso, impidiendo completar el proceso.
Recomendación: Implementar un bloque try-catch general en registerPassenger que elimine la cuenta creada en Firebase Auth en caso de que la escritura del perfil en Firestore falle:
dart


} catch (e) {
  if (credential.user != null) {
    await credential.user!.delete();
  }
  rethrow;
}
8. Errores Asíncronos No Controlados en Telemetría
Archivo: 
location_telemetry_service.dart
 (Líneas 85 a 100)
Criticidad: BAJA (Calidad de Código / Logs de Error)
Descripción: Se ejecutan llamadas asíncronas no esperadas (unawaited) a Cloud Functions y Firestore en segundo plano sin manejar posibles excepciones:
dart


unawaited(_callFunction(_updateLocationUrl, {...}));
Impacto: Si el conductor pierde temporalmente la conexión a Internet o se le deniega el permiso (por estar bloqueado), estas llamadas fallarán y lanzarán excepciones no controladas en el hilo asíncrono, lo que puede causar spam en herramientas de analítica y reporte de caídas como Firebase Crashlytics.
Recomendación: Agregar un manejador .catchError o envolver internamente los métodos asíncronos en bloques try-catch seguros:
dart


unawaited(_callFunction(_updateLocationUrl, {...}).catchError((e) {
  // Manejo de error o log silencioso
}));
9. Riesgo de Escalabilidad en Cancelación de Viajes Expirados
Archivo: 
functions/index.js
 (Línea 823)
Criticidad: BAJA (Escalabilidad)
Descripción: La función programada cancelStaleTrips recupera todos los viajes sin conductor creados hace más de 5 minutos y los cancela utilizando un único lote de escritura de Firestore (WriteBatch).
Impacto: Firestore limita la cantidad de escrituras en un solo batch a un máximo de 500 operaciones. Si en algún momento de alta demanda (o tras una caída temporal del sistema) hay más de 500 viajes pendientes por expirar, el lote fallará por completo al ejecutarse batch.commit(), impidiendo que los viajes se limpien.
Recomendación: Limitar la consulta inicial a un máximo de 500 documentos para garantizar que nunca se exceda el límite del lote:
javascript


const stale = await db.collection("trips")
  .where("status", "==", "requested")
  .where("createdAt", "<", cutoff)
  .limit(500)
  .get();
