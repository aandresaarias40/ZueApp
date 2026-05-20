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

admin.initializeApp();

// ── Constantes Redis ───────────────────────────────────────────────────────────
const DRIVER_POS_PREFIX  = "driver:pos:";
const ONLINE_DRIVERS_KEY = "drivers:online";
const GEO_KEY            = "drivers:geo";
const EXPIRE_SECONDS     = 120;

// ── Credenciales Upstash (SOLO en servidor — nunca en el APK) ─────────────────
const UPSTASH_HOST     = "endless-grouper-132192.upstash.io";
const UPSTASH_PORT     = 6379;
const UPSTASH_PASSWORD = "gQAAAAAAAgRgAAIgcDJlNDA5ZDFkYjhkYzU0ODRlODcyMjk0ODZmNTU1YjAxNw";

// ── Singleton Redis por instancia de función ───────────────────────────────────
let _redis = null;
function getRedis() {
  if (!_redis) {
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

// ═══════════════════════════════════════════════════════════════════════════════
// updateDriverLocation — conductor actualiza GPS
// Body: { driverId, lat, lng, status? }
// ═══════════════════════════════════════════════════════════════════════════════
exports.updateDriverLocation = onRequest(OPTS, async (req, res) => {
  setCors(res);
  if (req.method === "OPTIONS") return res.status(204).send("");

  const user = await verifyToken(req);
  if (!user) return res.status(401).json({ error: "No autorizado" });

  const { driverId, lat, lng, status = "active" } = req.body;
  if (!driverId || lat == null || lng == null)
    return res.status(400).json({ error: "Faltan campos: driverId, lat, lng" });
  if (user.uid !== driverId)
    return res.status(403).json({ error: "No puedes actualizar posición de otro conductor" });

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

// ═══════════════════════════════════════════════════════════════════════════════
// getNearbyDrivers — pasajero busca conductores cercanos (GEOSEARCH TCP)
// Body: { lat, lng, radiusKm?, limit? }
// ═══════════════════════════════════════════════════════════════════════════════
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

// ═══════════════════════════════════════════════════════════════════════════════
// setDriverOffline — conductor se desconecta, limpia índices Redis
// Body: { driverId }
// ═══════════════════════════════════════════════════════════════════════════════
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
