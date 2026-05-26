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

// ── Verificar token Firebase del cliente ──────────────────────────────────────
async function verifyToken(req) {
  const auth = (req.headers.authorization || "");
  if (!auth.startsWith("Bearer ")) return null;
  try {
    return await admin.auth().verifyIdToken(auth.split("Bearer ")[1]);
  } catch {
    return null;
  }
}

function setCors(res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
}

// =============================================================================
// updateDriverLocation — conductor actualiza GPS
// Body: { driverId, lat, lng, status? }
// =============================================================================
exports.updateDriverLocation = onRequest(OPTS, async (req, res) => {
  setCors(res);
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
  setCors(res);
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
  setCors(res);
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
  setCors(res);
  if (req.method === "OPTIONS") return res.status(204).send("");
  if (req.method !== "POST")    return res.status(405).json({ error: "Metodo no permitido" });

  // 1. Verificar firma de Wompi
  // Wompi envia en headers: x-wompi-timestamp y x-wompi-checksum
  // checksum = SHA256( transactionId + timestamp + privateKey )
  const timestamp = req.headers["x-wompi-timestamp"] || "";
  const checksum  = req.headers["x-wompi-checksum"]  || "";

  if (!checksum) {
    console.warn("wompiWebhook: falta x-wompi-checksum");
    return res.status(401).json({ error: "Firma requerida" });
  }

  if (!WOMPI_EVENTS_SECRET) {
    console.error("wompiWebhook: WOMPI_EVENTS_SECRET no configurada");
    return res.status(500).json({ error: "Configuracion incompleta del servidor" });
  }

  // 1b. Validar que el timestamp no sea mayor a 5 minutos (anti-replay por tiempo)
  const tsNum = parseInt(timestamp, 10);
  if (!tsNum || Math.abs(Date.now() / 1000 - tsNum) > 300) {
    console.warn("wompiWebhook: timestamp fuera de ventana", { timestamp });
    return res.status(401).json({ error: "Timestamp invalido o expirado" });
  }

  const event = req.body;
  const txId  = event && event.data && event.data.transaction
    ? event.data.transaction.id
    : "";

  const toSign   = `${txId}${timestamp}${WOMPI_EVENTS_SECRET}`;
  const expected = crypto.createHash("sha256").update(toSign).digest("hex");

  if (expected !== checksum) {
    console.warn("wompiWebhook: firma invalida", { expected, checksum });
    return res.status(401).json({ error: "Firma invalida" });
  }

  // 1c. Anti-replay: verificar que este checksum exacto no fue procesado antes.
  // Se guarda en Redis con TTL de 10 min (más que la ventana de 5 min).
  const replayKey = `wompi:seen:${checksum}`;
  let redis;
  try {
    redis = getRedis();
    const alreadySeen = await redis.set(replayKey, "1", "EX", 600, "NX");
    if (alreadySeen === null) {
      // NX falló → la clave ya existía → es un reenvío
      console.warn("wompiWebhook: replay detectado para checksum", checksum);
      return res.status(200).json({ ok: true, ignored: "replay detectado" });
    }
  } catch (redisErr) {
    // Si Redis falla, logueamos pero NO bloqueamos (fail-open para no perder pagos reales).
    console.error("wompiWebhook: error al verificar replay en Redis", redisErr.message);
  }

  // 2. Ignorar eventos que no sean transaction.updated
  const eventType = event && event.event;
  if (eventType !== "transaction.updated") {
    return res.status(200).json({ ok: true, ignored: true });
  }

  // 3. Extraer datos de la transaccion
  const tx        = event.data.transaction;
  const txStatus  = tx.status;    // APPROVED | DECLINED | PENDING | ERROR | VOIDED
  const reference = tx.reference; // "ZUE-XXXXXX-XXXXXXXX"

  if (!txId || !txStatus || !reference) {
    console.error("wompiWebhook: payload incompleto", { txId, txStatus, reference });
    return res.status(400).json({ error: "Payload incompleto" });
  }

  const db = admin.firestore();

  // 4. Buscar el pago por referencia
  const paymentsSnap = await db.collection(COL_PAYMENTS)
    .where("referenceId", "==", reference)
    .limit(1)
    .get();

  if (paymentsSnap.empty) {
    // No es un error nuestro — responder 200 para que Wompi no reintente
    console.warn("wompiWebhook: pago no encontrado para referencia", reference);
    return res.status(200).json({ ok: true, warning: "Pago no encontrado" });
  }

  const paymentRef  = paymentsSnap.docs[0].ref;
  const paymentData = paymentsSnap.docs[0].data();
  const paymentId   = paymentsSnap.docs[0].id;

  // Idempotencia: si ya fue procesado, ignorar
  if (paymentData.status === "approved" || paymentData.status === "declined") {
    return res.status(200).json({ ok: true, ignored: "ya procesado" });
  }

  const driverId = paymentData.driverId;
  const plan     = paymentData.plan;   // "weekly" | "monthly"
  const amount   = paymentData.amount;

  if (txStatus === "APPROVED") {
    const now     = admin.firestore.Timestamp.now();
    const endDate = plan === "weekly"
      ? admin.firestore.Timestamp.fromMillis(Date.now() + 7  * 24 * 60 * 60 * 1000)
      : admin.firestore.Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000);

    const subRef = db.collection(COL_SUBSCRIPTIONS).doc();
    const batch  = db.batch();

    // Crear suscripcion activa
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

    // Marcar pago como aprobado
    batch.update(paymentRef, {
      status:             "approved",
      subscriptionId:     subRef.id,
      approvedAt:         admin.firestore.Timestamp.now(),
      transactionId:      txId,
    });

    // Activar suscripcion en el documento del conductor
    const driverRef = db.collection(COL_DRIVERS).doc(driverId);
    batch.update(driverRef, {
      subscriptionStatus: "active",
      subscriptionPlan:   plan,
      subscriptionEnd:    endDate,
      updatedAt:          admin.firestore.Timestamp.now(),
    });

    await batch.commit();
    console.log("wompiWebhook: pago aprobado", { driverId, plan, txId });
    return res.status(200).json({ ok: true, status: "approved" });

  } else if (txStatus === "DECLINED" || txStatus === "VOIDED" || txStatus === "ERROR") {
    await paymentRef.update({
      status:    "declined",
      failedAt:  admin.firestore.Timestamp.now(),
      txStatus,
      transactionId: txId,
    });
    console.log("wompiWebhook: pago rechazado", { driverId, txStatus, txId });
    return res.status(200).json({ ok: true, status: "declined" });

  } else {
    // PENDING — Wompi reintentará cuando cambie el estado
    console.log("wompiWebhook: pago pendiente", { driverId, txStatus, txId });
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
  setCors(res);
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
    console.error("createPSETransaction: variables de entorno Wompi no configuradas");
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
    console.error("createPSETransaction: cédula/licenseNumber del conductor vacío", { driverId });
    return res.status(400).json({ error: "Perfil incompleto: se requiere cédula del conductor" });
  }
  if (!driver.email) {
    console.error("createPSETransaction: email del conductor vacío", { driverId });
    return res.status(400).json({ error: "Perfil incompleto: se requiere email del conductor" });
  }

  // Calcular firma de integridad (SOLO en servidor)
  // Wompi: SHA256(reference + amountInCents + currency + integritySecret)
  const amountInt    = parseInt(amountInCents, 10);
  const signatureStr = `${reference}${amountInt}COP${WOMPI_INTEGRITY_SECRET}`;
  const integrityHash = crypto.createHash("sha256").update(signatureStr).digest("hex");

  console.log("createPSETransaction: iniciando", {
    driverId, plan, reference, amountInt,
    signatureInput: `${reference}${amountInt}COP[secret]`,
    integrityHash,
  });

  try {
    // 1. Obtener acceptance_token Y personal_data_auth_token de Wompi
    // Wompi PSE requiere AMBOS tokens — sin personal_data_auth_token devuelve 422
    const merchantRes  = await fetch(`${WOMPI_BASE_URL}/merchants/${WOMPI_PUBLIC_KEY}`);
    const merchantData = await merchantRes.json();

    if (!merchantData.data) {
      console.error("createPSETransaction: respuesta merchants inesperada", JSON.stringify(merchantData));
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

    console.log("createPSETransaction: enviando a Wompi", JSON.stringify({
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
      console.error("Wompi PSE error:", JSON.stringify(txData));
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
        console.warn("createPSETransaction: sandbox PSE sin async_payment_url (normal en sandbox)", {
          transactionId, financialInstitutionCode,
        });
        return res.json({ transactionId, redirectUrl: null, sandboxMode: true });
      }
      // Producción: no debería ocurrir con un banco PSE válido
      console.error("createPSETransaction: sin async_payment_url en producción", {
        transactionId, financialInstitutionCode,
        paymentMethodExtra: txData.data.payment_method?.extra,
      });
      return res.status(500).json({
        error: "El banco seleccionado no generó URL de pago.",
        transactionId,
      });
    }

    console.log("createPSETransaction: transacción creada", { driverId, transactionId, plan });
    return res.json({ transactionId, redirectUrl });

  } catch (e) {
    console.error("createPSETransaction error:", e.message);
    return res.status(500).json({ error: "Error al crear transacción: " + e.message });
  }
});
