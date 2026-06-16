/**
 * ZueApp — Cloud Functions Backend (Gen 2)
 * ==========================================
 * Flutter → HTTPS → Cloud Function → TCP → Upstash Redis (ioredis)
 *
 * invoker: "public"  → Cloud Run permite llamadas sin token IAM
 * La autenticación real la hacemos nosotros con Firebase ID Token.
 * Token Upstash almacenado SOLO aquí — nunca en el APK de Flutter.
 */

const { onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin  = require("firebase-admin");
const Redis  = require("ioredis");
const crypto = require("crypto");

admin.initializeApp();

// ── Constantes Redis ───────────────────────────────────────────────────────────
const DRIVER_POS_PREFIX  = "driver:pos:";
const ONLINE_DRIVERS_KEY = "drivers:online";
const GEO_KEY            = "drivers:geo";
const EXPIRE_SECONDS     = 120;

// ── Llave privada Wompi (SOLO en servidor — NUNCA en el APK) ─────────────────
// Cómo configurarla:
//   firebase functions:config:set wompi.private_key="prv_test_TU_LLAVE_PRIVADA"
// O en Firebase Console → Functions → Variables de entorno.
// En desarrollo local: crea functions/.env con: WOMPI_EVENTS_SECRET=prv_test_...
//
// ⚠️  NUNCA pongas la llave privada en el APK ni en este archivo en git.
const WOMPI_EVENTS_SECRET = process.env.WOMPI_EVENTS_SECRET || "";
const WOMPI_USE_SANDBOX = process.env.WOMPI_USE_SANDBOX !== "false"; // default: sandbox

// ── Colecciones Firestore ──────────────────────────────────────────────────────
const COL_PAYMENTS      = "payments";
const COL_SUBSCRIPTIONS = "subscriptions";
const COL_DRIVERS       = "drivers";

// ── Credenciales Upstash (SOLO en servidor — nunca en el APK) ─────────────────
// Configurar en functions/.env (local) o Firebase Console → Functions → Variables de entorno.
// ⚠️  NUNCA pongas estos valores directamente en este archivo ni en git.
const UPSTASH_HOST     = process.env.UPSTASH_HOST     || "";
const UPSTASH_PORT     = parseInt(process.env.UPSTASH_PORT || "6379", 10);
const UPSTASH_PASSWORD = process.env.UPSTASH_PASSWORD || "";

// ── Tarifas Fusagasugá (COP) — deben coincidir con AppConstants en Flutter ───
const FARE = {
  minimumFareDistanceKm: 6.0,  // rutas < 6 km → tarifa fija
  // Carro
  minimumFare:  8000,          // tarifa fija mínima carro
  carBaseFare:  3000,          // base carro (>= 6 km)
  carPerKmRate: 1200,          // $/km adicional carro
  // Moto
  motoMinimumFare:  4500,      // tarifa fija mínima moto
  motoBaseFare:     1500,      // base moto (>= 6 km)
  motoPerKmRate:    600,       // $/km adicional moto
  // Recargo nocturno (carro y moto)
  nightSurcharge: 1000,        // $1.000 extra de 7pm a 5am
  nightStartHour: 19,          // 7:00 pm
  nightEndHour:   5,           // 5:00 am
};
const VEHICLE_MOTO = "moto";

// Hora (0-23) en zona horaria de Colombia para una fecha dada (hora de servidor).
function bogotaHour(date) {
  const h = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Bogota",
    hour: "numeric",
    hour12: false,
  }).format(date);
  return parseInt(h, 10) % 24;
}

// ¿Es horario nocturno en Colombia? (7:00 pm a 5:00 am)
function isNightTimeBogota(date) {
  const hour = bogotaHour(date);
  return hour >= FARE.nightStartHour || hour < FARE.nightEndHour;
}

// Tarifa oficial (COP) calculada en el servidor, con recargo nocturno si aplica.
// [now] es la hora de servidor; el recargo NO depende del reloj del teléfono.
function computeFare(distanceKm, vehicleType, now) {
  const surcharge = isNightTimeBogota(now) ? FARE.nightSurcharge : 0;
  const ceil100 = (v) => Math.ceil(v / 100) * 100;

  if (vehicleType === VEHICLE_MOTO) {
    if (distanceKm < FARE.minimumFareDistanceKm) {
      return FARE.motoMinimumFare + surcharge;
    }
    return ceil100(FARE.motoBaseFare + distanceKm * FARE.motoPerKmRate) + surcharge;
  }
  // Carro (default)
  if (distanceKm < FARE.minimumFareDistanceKm) {
    return FARE.minimumFare + surcharge;
  }
  return ceil100(FARE.carBaseFare + distanceKm * FARE.carPerKmRate) + surcharge;
}

// ── Singleton Redis por instancia de función ───────────────────────────────────
let _redis = null;
function getRedis() {
  if (!_redis) {
    if (!UPSTASH_HOST || !UPSTASH_PASSWORD) {
      throw new Error("Faltan variables de entorno UPSTASH_HOST / UPSTASH_PASSWORD");
    }
    _redis = new Redis({
      host:                 UPSTASH_HOST,
      port:                 UPSTASH_PORT,
      password:             UPSTASH_PASSWORD,
      tls:                  {},
      maxRetriesPerRequest: 3,
    });
    _redis.on("error", (err) => console.error("Redis error:", err.message));
  }
  return _redis;
}

// ── Opciones comunes ───────────────────────────────────────────────────────────
const OPTS = {
  region:  "us-central1",
  invoker: "public",        // permite llamadas HTTP sin token IAM de Google
};

// ── Logging estructurado ───────────────────────────────────────────────────────
// En producción solo se emiten warn/error. En sandbox se incluye info/debug.
const log = {
  info:  (...a) => { if (WOMPI_USE_SANDBOX) console.info(...a);  },
  debug: (...a) => { if (WOMPI_USE_SANDBOX) console.debug(...a); },
  warn:  (...a) => console.warn(...a),
  error: (...a) => console.error(...a),
};

// ── Dominios permitidos en CORS ────────────────────────────────────────────────
const ALLOWED_ORIGINS = [
  "https://zue-app.web.app",
  "https://zue-app.firebaseapp.com",
];

// ── Rate limiting distribuido en Redis (por IP) ────────────────────────────────
// Usa INCR + EXPIRE para contar peticiones por IP en una ventana de 60 s.
// Al estar en Redis es efectivo incluso con múltiples instancias de Cloud Run.
const RATE_LIMIT_MAX    = 20;  // máx peticiones por ventana
const RATE_LIMIT_WINDOW = 60;  // ventana en segundos

async function isRateLimited(ip) {
  try {
    const redis = getRedis();
    const key   = `rate:webhook:${ip}`;
    const count = await redis.incr(key);
    if (count === 1) await redis.expire(key, RATE_LIMIT_WINDOW);
    return count > RATE_LIMIT_MAX;
  } catch {
    // Si Redis falla, no bloqueamos (fail-open)
    return false;
  }
}

// ── Verificar token Firebase del cliente ──────────────────────────────────────
async function verifyToken(req) {
  const auth = (req.headers.authorization || "");
  if (!auth.startsWith("Bearer ")) return null;
  try {
    // checkRevoked=true: rechaza tokens de cuentas bloqueadas/revocadas.
    return await admin.auth().verifyIdToken(auth.split("Bearer ")[1], true);
  } catch {
    return null;
  }
}

function setCors(req, res) {
  const origin = req.headers.origin || "";
  const allowed = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  res.set("Access-Control-Allow-Origin", allowed);
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.set("Vary", "Origin");
}

// =============================================================================
// updateDriverLocation — conductor actualiza GPS
// Body: { driverId, lat, lng, status? }
// =============================================================================
exports.updateDriverLocation = onRequest(OPTS, async (req, res) => {
  setCors(req, res);
  if (req.method === "OPTIONS") return res.status(204).send("");

  const user = await verifyToken(req);
  if (!user) return res.status(401).json({ error: "No autorizado" });

  const { driverId, lat, lng, status = "active" } = req.body;
  if (!driverId || lat == null || lng == null)
    return res.status(400).json({ error: "Faltan campos: driverId, lat, lng" });
  if (user.uid !== driverId)
    return res.status(403).json({ error: "No puedes actualizar posicion de otro conductor" });

  const redis = getRedis();
  const key   = `${DRIVER_POS_PREFIX}${driverId}`;
  const pipe  = redis.pipeline();
  pipe.hset(key, "lat", lat, "lng", lng, "ts", Date.now(), "status", status, "driverId", driverId);
  pipe.expire(key, EXPIRE_SECONDS);
  pipe.sadd(ONLINE_DRIVERS_KEY, driverId);
  pipe.geoadd(GEO_KEY, lng, lat, driverId);
  await pipe.exec();

  return res.json({ ok: true });
});

// =============================================================================
// getNearbyDrivers — pasajero busca conductores cercanos (GEOSEARCH TCP)
// Body: { lat, lng, radiusKm?, limit? }
// =============================================================================
exports.getNearbyDrivers = onRequest(OPTS, async (req, res) => {
  setCors(req, res);
  if (req.method === "OPTIONS") return res.status(204).send("");

  const user = await verifyToken(req);
  if (!user) return res.status(401).json({ error: "No autorizado" });

  const { lat, lng, radiusKm = 10, limit = 10 } = req.body;
  if (lat == null || lng == null)
    return res.status(400).json({ error: "Faltan campos: lat, lng" });

  const redis   = getRedis();
  const results = await redis.call(
    "GEOSEARCH", GEO_KEY,
    "FROMLONLAT", lng, lat,
    "BYRADIUS", radiusKm, "km",
    "ASC", "COUNT", limit,
    "WITHCOORD", "WITHDIST",
  );

  const drivers = (results || []).map((e) => ({
    driverId:   e[0],
    distanceKm: parseFloat(e[1]),
    lng:        parseFloat(e[2][0]),
    lat:        parseFloat(e[2][1]),
  }));

  return res.json({ drivers });
});

// =============================================================================
// setDriverOffline — conductor se desconecta, limpia indices Redis
// Body: { driverId }
// =============================================================================
exports.setDriverOffline = onRequest(OPTS, async (req, res) => {
  setCors(req, res);
  if (req.method === "OPTIONS") return res.status(204).send("");

  const user = await verifyToken(req);
  if (!user) return res.status(401).json({ error: "No autorizado" });

  const { driverId } = req.body;
  if (!driverId) return res.status(400).json({ error: "Falta driverId" });
  if (user.uid !== driverId)
    return res.status(403).json({ error: "No autorizado" });

  const redis = getRedis();
  const pipe  = redis.pipeline();
  pipe.srem(ONLINE_DRIVERS_KEY, driverId);
  pipe.del(`${DRIVER_POS_PREFIX}${driverId}`);
  pipe.zrem(GEO_KEY, driverId);
  await pipe.exec();

  return res.json({ ok: true });
});

// =============================================================================
// MODERACIÓN — bloqueo de usuarios/conductores y gestión de administradores
// =============================================================================
const COL_USERS      = "users";
const COL_ADMINS     = "admins";
const COL_MODERATION = "moderation_log";

const BLOCK_CATEGORIES = ["incident", "disciplinary", "fraud", "other"];

// Verifica el ID Token Y que el llamador sea administrador (doc en admins/).
async function verifyAdminCaller(req) {
  const user = await verifyToken(req);
  if (!user) return null;
  const adminDoc = await admin.firestore()
    .collection(COL_ADMINS).doc(user.uid).get();
  return adminDoc.exists ? user : null;
}

// Limpia los índices Redis de un conductor (mejor esfuerzo).
async function removeDriverFromRedis(driverId) {
  try {
    const redis = getRedis();
    const pipe  = redis.pipeline();
    pipe.srem(ONLINE_DRIVERS_KEY, driverId);
    pipe.del(`${DRIVER_POS_PREFIX}${driverId}`);
    pipe.zrem(GEO_KEY, driverId);
    await pipe.exec();
  } catch (e) {
    log.warn("removeDriverFromRedis falló:", e.message);
  }
}

// =============================================================================
// setUserBlocked — bloquear/desbloquear usuario o conductor (SOLO admins)
// Body: { userId, blocked: bool, category?, reason? }
//
// Efectos al bloquear:
//   • users/{id}:   isActive=false + categoría/motivo/fecha/admin
//   • drivers/{id}: status='suspended', isOnline=false (si es conductor)
//   • Firebase Auth: cuenta deshabilitada + refresh tokens revocados
//   • Redis: conductor removido de los índices de mapa
//   • moderation_log: registro de auditoría
// El cliente además escucha users/{id} y cierra la sesión en tiempo real.
// =============================================================================
exports.setUserBlocked = onRequest(OPTS, async (req, res) => {
  setCors(req, res);
  if (req.method === "OPTIONS") return res.status(204).send("");
  if (req.method !== "POST")    return res.status(405).json({ error: "Metodo no permitido" });

  const caller = await verifyAdminCaller(req);
  if (!caller) return res.status(403).json({ error: "Solo administradores" });

  const { userId, blocked, category = "other", reason = "" } = req.body || {};
  if (!userId || typeof blocked !== "boolean")
    return res.status(400).json({ error: "Faltan campos: userId, blocked" });
  if (userId === caller.uid)
    return res.status(400).json({ error: "No puedes bloquear tu propia cuenta" });
  if (blocked && !BLOCK_CATEGORIES.includes(category))
    return res.status(400).json({ error: "Categoria invalida" });

  const db      = admin.firestore();
  const userRef = db.collection(COL_USERS).doc(userId);
  const snap    = await userRef.get();
  if (!snap.exists) return res.status(404).json({ error: "Usuario no encontrado" });

  const target = snap.data();
  if (target.role === "admin")
    return res.status(403).json({ error: "No se puede bloquear a un administrador. Revoca su rol primero." });

  const now   = admin.firestore.FieldValue.serverTimestamp();
  const batch = db.batch();

  batch.update(userRef, {
    isActive:      !blocked,
    blockCategory: blocked ? category : null,
    blockReason:   blocked ? String(reason).slice(0, 500) : null,
    blockedAt:     blocked ? now : null,
    blockedBy:     blocked ? caller.uid : null,
    updatedAt:     now,
  });

  // Si es conductor: suspender operación y sacarlo del mapa.
  if (target.role === "driver") {
    const driverRef = db.collection(COL_DRIVERS).doc(userId);
    const driverSnap = await driverRef.get();
    if (driverSnap.exists) {
      batch.update(driverRef, blocked
        ? {
            status: "suspended",
            isOnline: false,
            suspensionReason: `[${category}] ${reason}`.slice(0, 500),
            updatedAt: now,
          }
        : {
            status: "inactive",
            suspensionReason: null,
            updatedAt: now,
          });
    }
  }

  // Auditoría.
  batch.set(db.collection(COL_MODERATION).doc(), {
    action:     blocked ? "block" : "unblock",
    targetId:   userId,
    targetRole: target.role,
    targetName: target.name || "",
    category:   blocked ? category : null,
    reason:     blocked ? String(reason).slice(0, 500) : null,
    adminId:    caller.uid,
    createdAt:  now,
  });

  await batch.commit();

  // Deshabilitar la cuenta en Firebase Auth: impide iniciar sesión.
  // Revocar refresh tokens: la sesión activa muere al expirar el ID token
  // (≤1 h); la expulsión inmediata la hace el listener del cliente.
  try {
    await admin.auth().updateUser(userId, { disabled: blocked });
    if (blocked) await admin.auth().revokeRefreshTokens(userId);
  } catch (e) {
    log.warn("setUserBlocked: no se pudo actualizar Auth:", e.message);
  }

  if (blocked && target.role === "driver") await removeDriverFromRedis(userId);

  return res.json({ ok: true, blocked });
});

// =============================================================================
// setAdminRole — promover/revocar administradores (SOLO admins)
// Body: { userId, makeAdmin: bool }
//
// Al promover: crea admins/{userId} y cambia users.role → 'admin'
//              (guarda previousRole para poder revertir).
// Al revocar:  borra admins/{userId} y restaura el rol anterior.
// =============================================================================
exports.setAdminRole = onRequest(OPTS, async (req, res) => {
  setCors(req, res);
  if (req.method === "OPTIONS") return res.status(204).send("");
  if (req.method !== "POST")    return res.status(405).json({ error: "Metodo no permitido" });

  const caller = await verifyAdminCaller(req);
  if (!caller) return res.status(403).json({ error: "Solo administradores" });

  const { userId, makeAdmin } = req.body || {};
  if (!userId || typeof makeAdmin !== "boolean")
    return res.status(400).json({ error: "Faltan campos: userId, makeAdmin" });
  if (userId === caller.uid && !makeAdmin)
    return res.status(400).json({ error: "No puedes revocar tu propio rol de administrador" });

  const db      = admin.firestore();
  const userRef = db.collection(COL_USERS).doc(userId);
  const snap    = await userRef.get();
  if (!snap.exists) return res.status(404).json({ error: "Usuario no encontrado" });

  const target = snap.data();
  const now    = admin.firestore.FieldValue.serverTimestamp();
  const batch  = db.batch();
  const adminRef = db.collection(COL_ADMINS).doc(userId);

  if (makeAdmin) {
    if (target.isActive === false)
      return res.status(400).json({ error: "No se puede promover a un usuario bloqueado" });
    if (target.role === "admin")
      return res.status(400).json({ error: "El usuario ya es administrador" });

    batch.set(adminRef, {
      email:      target.email || "",
      name:       target.name || "",
      promotedBy: caller.uid,
      createdAt:  now,
    });
    batch.update(userRef, {
      previousRole: target.role,
      role:         "admin",
      updatedAt:    now,
    });
  } else {
    if (target.role !== "admin")
      return res.status(400).json({ error: "El usuario no es administrador" });

    batch.delete(adminRef);
    batch.update(userRef, {
      role:         target.previousRole || "passenger",
      previousRole: admin.firestore.FieldValue.delete(),
      updatedAt:    now,
    });
  }

  batch.set(db.collection(COL_MODERATION).doc(), {
    action:     makeAdmin ? "promote_admin" : "demote_admin",
    targetId:   userId,
    targetRole: target.role,
    targetName: target.name || "",
    adminId:    caller.uid,
    createdAt:  now,
  });

  await batch.commit();
  return res.json({ ok: true, role: makeAdmin ? "admin" : (target.previousRole || "passenger") });
});

// =============================================================================
// wompiWebhook — recibe eventos de Wompi y confirma pagos de forma segura.
//
// SETUP en el dashboard de Wompi:
//   Desarrolladores -> Webhooks -> Agregar endpoint:
//   URL: https://us-central1-TU_PROYECTO_ID.cloudfunctions.net/wompiWebhook
//   Eventos: transaction.updated
//
// La firma se verifica con WOMPI_EVENTS_SECRET para evitar eventos fraudulentos.
// Docs de firma: https://docs.wompi.co/docs/colombia/wompi-webhooks/
// =============================================================================
exports.wompiWebhook = onRequest({ ...OPTS, invoker: "public" }, async (req, res) => {
  setCors(req, res);
  if (req.method === "OPTIONS") return res.status(204).send("");
  if (req.method !== "POST")    return res.status(405).json({ error: "Metodo no permitido" });

  // 0. Rate limiting por IP (distribuido en Redis)
  const clientIp = req.headers["x-forwarded-for"]?.split(",")[0].trim() || req.ip || "unknown";
  if (await isRateLimited(clientIp)) {
    log.warn("wompiWebhook: rate limit excedido", { ip: clientIp });
    return res.status(429).json({ error: "Demasiadas peticiones" });
  }

  // 1. Verificar firma de Wompi
  const timestamp = req.headers["x-wompi-timestamp"] || "";
  const checksum  = req.headers["x-wompi-checksum"]  || "";

  if (!checksum) {
    log.warn("wompiWebhook: falta x-wompi-checksum");
    return res.status(401).json({ error: "Firma requerida" });
  }

  if (!WOMPI_EVENTS_SECRET) {
    log.error("wompiWebhook: WOMPI_EVENTS_SECRET no configurada");
    return res.status(500).json({ error: "Configuracion incompleta del servidor" });
  }

  // 1b. Validar que el timestamp no sea mayor a 24 horas (anti-replay por tiempo).
  const tsNum = parseInt(timestamp, 10);
  if (!tsNum || Math.abs(Date.now() / 1000 - tsNum) > 86400) {
    log.warn("wompiWebhook: timestamp fuera de ventana", { timestamp });
    return res.status(401).json({ error: "Timestamp invalido o expirado" });
  }

  const event = req.body;
  const txId  = event && event.data && event.data.transaction
    ? event.data.transaction.id
    : "";

  const toSign   = `${txId}${timestamp}${WOMPI_EVENTS_SECRET}`;
  const expected = crypto.createHash("sha256").update(toSign).digest("hex");

  if (expected !== checksum) {
    log.warn("wompiWebhook: firma invalida");
    return res.status(401).json({ error: "Firma invalida" });
  }

  // 1c. Anti-replay: verificar que este checksum exacto no fue procesado antes.
  const replayKey = `wompi:seen:${checksum}`;
  let redis;
  try {
    redis = getRedis();
    const alreadySeen = await redis.set(replayKey, "1", "EX", 600, "NX");
    if (alreadySeen === null) {
      log.warn("wompiWebhook: replay detectado");
      return res.status(200).json({ ok: true, ignored: "replay detectado" });
    }
  } catch (redisErr) {
    log.error("wompiWebhook: error al verificar replay en Redis", redisErr.message);
  }

  // 2. Ignorar eventos que no sean transaction.updated
  const eventType = event && event.event;
  if (eventType !== "transaction.updated") {
    return res.status(200).json({ ok: true, ignored: true });
  }

  // 3. Extraer datos de la transaccion
  const tx        = event.data.transaction;
  const txStatus  = tx.status;
  const reference = tx.reference;

  if (!txId || !txStatus || !reference) {
    log.error("wompiWebhook: payload incompleto", { txId, txStatus, reference });
    return res.status(400).json({ error: "Payload incompleto" });
  }

  const db = admin.firestore();

  // 4. Buscar el pago por referencia
  const paymentsSnap = await db.collection(COL_PAYMENTS)
    .where("referenceId", "==", reference)
    .limit(1)
    .get();

  if (paymentsSnap.empty) {
    log.warn("wompiWebhook: pago no encontrado para referencia", reference);
    return res.status(200).json({ ok: true, warning: "Pago no encontrado" });
  }

  const paymentRef  = paymentsSnap.docs[0].ref;
  const paymentData = paymentsSnap.docs[0].data();
  const paymentId   = paymentsSnap.docs[0].id;

  if (paymentData.status === "approved" || paymentData.status === "declined") {
    return res.status(200).json({ ok: true, ignored: "ya procesado" });
  }

  const driverId = paymentData.driverId;
  const plan     = paymentData.plan;
  const amount   = paymentData.amount;

  if (txStatus === "APPROVED") {
    const now     = admin.firestore.Timestamp.now();
    const endDate = plan === "weekly"
      ? admin.firestore.Timestamp.fromMillis(Date.now() + 7  * 24 * 60 * 60 * 1000)
      : admin.firestore.Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000);

    const subRef = db.collection(COL_SUBSCRIPTIONS).doc();
    const batch  = db.batch();

    batch.set(subRef, {
      driverId,
      driverName:    paymentData.driverName,
      plan,
      status:        "active",
      amount,
      startDate:     now,
      endDate,
      paymentId,
      transactionId: txId,
      createdAt:     now,
    });

    batch.update(paymentRef, {
      status:         "approved",
      subscriptionId: subRef.id,
      approvedAt:     admin.firestore.Timestamp.now(),
      transactionId:  txId,
    });

    const driverRef = db.collection(COL_DRIVERS).doc(driverId);
    batch.update(driverRef, {
      subscriptionStatus: "active",
      subscriptionPlan:   plan,
      subscriptionExpiry: endDate,
      updatedAt:          admin.firestore.Timestamp.now(),
    });

    await batch.commit();
    log.info("wompiWebhook: pago aprobado", { txId });
    return res.status(200).json({ ok: true, status: "approved" });

  } else if (txStatus === "DECLINED" || txStatus === "VOIDED" || txStatus === "ERROR") {
    await paymentRef.update({
      status:        "declined",
      failedAt:      admin.firestore.Timestamp.now(),
      txStatus,
      transactionId: txId,
    });
    log.info("wompiWebhook: pago rechazado", { txStatus, txId });
    return res.status(200).json({ ok: true, status: "declined" });

  } else {
    log.info("wompiWebhook: pago pendiente", { txStatus, txId });
    return res.status(200).json({ ok: true, status: "pending" });
  }
});

// ── Variables adicionales para crear transacciones Wompi ─────────────────────
const WOMPI_PUBLIC_KEY       = process.env.WOMPI_PUBLIC_KEY       || "";
const WOMPI_INTEGRITY_SECRET = process.env.WOMPI_INTEGRITY_SECRET || "";
const WOMPI_BASE_URL = WOMPI_USE_SANDBOX
  ? "https://sandbox.wompi.co/v1"
  : "https://production.wompi.co/v1";
const WOMPI_REDIRECT_URL = "https://zue-app.web.app/payment/callback";

// =============================================================================
// createPSETransaction — crea transacción PSE en Wompi de forma segura.
//
// El secreto de integridad NUNCA sale del servidor.
// Firma: SHA256(reference + amountInCents + "COP" + integritySecret)
//
// Body: { driverId, plan, financialInstitutionCode, reference, amountInCents }
// =============================================================================
exports.createPSETransaction = onRequest(OPTS, async (req, res) => {
  setCors(req, res);
  if (req.method === "OPTIONS") return res.status(204).send("");
  if (req.method !== "POST")    return res.status(405).json({ error: "Método no permitido" });

  const user = await verifyToken(req);
  if (!user) return res.status(401).json({ error: "No autorizado" });

  const { driverId, plan, financialInstitutionCode, reference, amountInCents } = req.body;

  if (!driverId || !plan || !financialInstitutionCode || !reference || !amountInCents) {
    return res.status(400).json({ error: "Faltan campos: driverId, plan, financialInstitutionCode, reference, amountInCents" });
  }
  if (user.uid !== driverId) {
    return res.status(403).json({ error: "No puedes crear transacciones para otro conductor" });
  }
  if (!WOMPI_INTEGRITY_SECRET || !WOMPI_PUBLIC_KEY) {
    log.error("createPSETransaction: variables de entorno Wompi no configuradas");
    return res.status(500).json({ error: "Configuración incompleta del servidor" });
  }

  // Leer datos del conductor en Firestore
  const db = admin.firestore();
  const driverDoc = await db.collection(COL_DRIVERS).doc(driverId).get();
  if (!driverDoc.exists) {
    return res.status(404).json({ error: "Conductor no encontrado" });
  }
  const driver = driverDoc.data();

  // El campo de identificación está guardado como licenseNumber en Firestore
  const legalId = driver.cedula || driver.licenseNumber || "";

  // Validar campos obligatorios del conductor antes de llamar a Wompi
  if (!legalId) {
    log.error("createPSETransaction: cédula/licenseNumber del conductor vacío");
    return res.status(400).json({ error: "Perfil incompleto: se requiere cédula del conductor" });
  }
  if (!driver.email) {
    log.error("createPSETransaction: email del conductor vacío");
    return res.status(400).json({ error: "Perfil incompleto: se requiere email del conductor" });
  }

  // Calcular firma de integridad (SOLO en servidor)
  // Wompi: SHA256(reference + amountInCents + currency + integritySecret)
  const amountInt    = parseInt(amountInCents, 10);
  const signatureStr = `${reference}${amountInt}COP${WOMPI_INTEGRITY_SECRET}`;
  const integrityHash = crypto.createHash("sha256").update(signatureStr).digest("hex");

  // Log de inicio solo en sandbox para no exponer datos internos en producción
  log.debug("createPSETransaction: iniciando", { driverId, plan, reference, amountInt });

  try {
    // 1. Obtener acceptance_token Y personal_data_auth_token de Wompi
    // Wompi PSE requiere AMBOS tokens — sin personal_data_auth_token devuelve 422
    const merchantRes  = await fetch(`${WOMPI_BASE_URL}/merchants/${WOMPI_PUBLIC_KEY}`);
    const merchantData = await merchantRes.json();

    if (!merchantData.data) {
      log.error("createPSETransaction: respuesta merchants inesperada");
      return res.status(500).json({ error: "Error al obtener tokens de Wompi" });
    }

    const acceptanceToken     = merchantData.data.presigned_acceptance.acceptance_token;
    const personalDataAuthToken = merchantData.data.presigned_personal_data_auth.acceptance_token;

    // 2. Crear transacción PSE en Wompi
    const txBody = {
      acceptance_token:         acceptanceToken,
      personal_data_auth_token: personalDataAuthToken,
      amount_in_cents:          amountInt,
      currency:                 "COP",
      customer_email:           driver.email,
      payment_method: {
        type:                       "PSE",
        user_type:                  0,          // 0 = persona natural
        user_legal_id_type:         "CC",
        user_legal_id:              legalId,
        financial_institution_code: financialInstitutionCode,
        payment_description:        `Suscripción Zue - ${plan === "weekly" ? "Semanal" : "Mensual"}`,
      },
      reference,
      redirect_url: WOMPI_REDIRECT_URL,
      customer_data: {
        phone_number: driver.phone   || "",
        full_name:    driver.name    || driver.email,
      },
      signature: integrityHash,
    };

  log.debug("createPSETransaction: enviando a Wompi", JSON.stringify({
    ...txBody,
    acceptance_token:         "[redacted]",
    personal_data_auth_token: "[redacted]",
  }));

    const txRes = await fetch(`${WOMPI_BASE_URL}/transactions`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${WOMPI_PUBLIC_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(txBody),
    });

    const txData = await txRes.json();

    if (!txRes.ok) {
      log.error("createPSETransaction: error Wompi PSE", txRes.status);
      return res.status(txRes.status).json({ error: txData });
    }

    const transactionId = txData.data.id;
    // Wompi PSE devuelve la URL en payment_method.extra.async_payment_url
    // (payment_method_info solo aplica a tarjetas)
    const redirectUrl =
      txData.data.payment_method?.extra?.async_payment_url ||
      txData.data.payment_method_info?.async_payment_url   ||
      null;

    if (!redirectUrl) {
      if (WOMPI_USE_SANDBOX) {
        // LIMITACIÓN CONOCIDA: el sandbox de Wompi NO genera async_payment_url.
        // ACH Colombia (operador de PSE) no tiene ambiente sandbox público.
        // Flujo sandbox: la transacción queda PENDING → ir a comercios.wompi.co
        // y aprobarla manualmente → webhook dispara → Firestore se actualiza.
        log.warn("createPSETransaction: sandbox PSE sin async_payment_url (normal en sandbox)");
        return res.json({ transactionId, redirectUrl: null, sandboxMode: true });
      }
      // Producción: no debería ocurrir con un banco PSE válido
      log.error("createPSETransaction: sin async_payment_url en producción", { transactionId });
      return res.status(500).json({
        error: "El banco seleccionado no generó URL de pago.",
        transactionId,
      });
    }

    log.info("createPSETransaction: transacción creada", { transactionId, plan });
    return res.json({ transactionId, redirectUrl });

  } catch (e) {
    log.error("createPSETransaction error:", e.message);
    return res.status(500).json({ error: "Error al crear transacción: " + e.message });
  }
});

// =============================================================================
// cancelStaleTrips — Cancela viajes en estado "requested" sin conductor
// tras 5 minutos. Corre cada minuto como scheduled function.
// Cubre el caso donde el pasajero cierra la app antes del timeout del cliente.
// =============================================================================
exports.cancelStaleTrips = onSchedule({
  schedule: "every 1 minutes",
  timeZone: "America/Bogota",
  ...OPTS,
}, async () => {
  const db = admin.firestore();
  const cutoff = admin.firestore.Timestamp.fromMillis(Date.now() - 5 * 60 * 1000);

  const stale = await db.collection("trips")
    .where("status", "==", "requested")
    .where("createdAt", "<", cutoff)
    .limit(500) // máx. de operaciones por WriteBatch en Firestore
    .get();

  if (stale.empty) return;

  const batch = db.batch();
  stale.docs.forEach((doc) => {
    batch.update(doc.ref, {
      status: "cancelled",
      cancelReason: "Timeout: sin conductor en 5 minutos",
      cancelledAt: admin.firestore.Timestamp.now(),
    });
  });

  await batch.commit();
  log.info(`cancelStaleTrips: ${stale.size} viaje(s) cancelados por timeout`);
});

// =============================================================================
// onTripCreated — recalcula la tarifa OFICIAL en el servidor.
//
// El estimado que envía el cliente (Flutter) es solo referencial. Aquí, al
// crearse el viaje, se recalcula la tarifa con la HORA DE SERVIDOR (zona
// America/Bogota), por lo que el recargo nocturno (7pm–5am, $1.000) no puede
// manipularse cambiando el reloj del teléfono. Se sobrescribe `fare` con el
// valor autoritativo y se guardan metadatos para auditoría.
// =============================================================================
exports.onTripCreated = onDocumentCreated({
  document: "trips/{tripId}",
  ...OPTS,
}, async (event) => {
  const snap = event.data;
  if (!snap) return;
  const trip = snap.data() || {};

  const distanceKm  = typeof trip.distance === "number" ? trip.distance : null;
  const vehicleType = trip.requestedVehicleType || "car";

  // Sin distancia no se puede calcular la tarifa oficial: se deja el estimado.
  if (distanceKm == null) {
    log.warn("onTripCreated: viaje sin distancia, no se recalcula tarifa", {
      tripId: event.params.tripId,
    });
    return;
  }

  const now          = new Date();                 // hora de servidor
  const night        = isNightTimeBogota(now);
  const officialFare = computeFare(distanceKm, vehicleType, now);

  // Evita reescrituras innecesarias (y bucles) si ya coincide.
  if (trip.fare === officialFare && trip.nightFareApplied === night) return;

  await snap.ref.update({
    fare:             officialFare,
    estimatedFare:    trip.fare ?? null,           // conserva el estimado del cliente
    nightFareApplied: night,
    nightSurcharge:   night ? FARE.nightSurcharge : 0,
    fareCalculatedAt: admin.firestore.Timestamp.fromDate(now),
  });

  log.info("onTripCreated: tarifa recalculada", {
    tripId: event.params.tripId,
    officialFare,
    night,
  });
});
