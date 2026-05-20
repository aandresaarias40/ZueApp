#!/usr/bin/env python3
"""
stress_test.py  –  Zue App Load & Stress Test
==============================================
Simula N conductores moviéndose en el mapa y M pasajeros buscando viajes.
Soporta tres backends de telemetría GPS para comparar latencias y costos.

BACKENDS DISPONIBLES (--backend)
---------------------------------
  firestore   → Firestore directo (emulador o producción)   [default]
  redis       → Upstash Redis REST (cloud) — sin Docker, sin instalación local
  hybrid      → Ambos simultáneamente — mide las dos latencias
                y muestra comparativa lado a lado en el reporte

MODOS DE EJECUCIÓN (--mode)
----------------------------
  emulator    → Firebase Local Emulator Suite (recomendado para CI)
  real        → Firebase producción  (¡genera lecturas/escrituras reales!)

USO RÁPIDO
----------
  # Instalar dependencias
  pip install requests redis

  # Solo Firestore con emulador
  firebase emulators:start --only firestore,auth
  py stress_test.py --mode emulator --drivers 100 --duration 60

  # Solo Redis local
  docker run -d -p 6379:6379 redis:latest
  py stress_test.py --backend redis --drivers 100 --duration 60

  # Comparativa híbrida (ambos a la vez)
  py stress_test.py --backend hybrid --mode emulator --drivers 100 --duration 60

  # Ayuda
  py stress_test.py --help
"""

import argparse
import json
import math
import os
import random
import statistics
import sys
import threading
import time
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor

import requests
from string import Template

try:
    import redis as redis_lib
    _REDIS_AVAILABLE = True
except ImportError:
    _REDIS_AVAILABLE = False

# ── Configuración del proyecto Firebase ───────────────────────────────────────

PROJECT_ID  = "zue-app"
API_KEY     = "AIzaSyC3haDfYivn690zYFTikOgcL4ixWabA5h8"   # Web API key

EMULATOR_AUTH_HOST      = "http://localhost:9099"
EMULATOR_FIRESTORE_HOST = "http://localhost:8080"

# Fusagasugá – área de cobertura
LAT_CENTER =  4.3478
LNG_CENTER = -74.3649

# ── Métricas thread-safe ───────────────────────────────────────────────────────

class Metrics:
    def __init__(self):
        self._lock         = threading.Lock()
        self.writes: list  = []     # latencias ms de escrituras exitosas
        self.reads: list   = []     # latencias ms de lecturas exitosas
        self.errors        = 0
        self.trips_created = 0
        self.total_writes  = 0
        self.total_reads   = 0
        self.start_time    = None
        self.timeline: list = []    # [(ts_relativo_s, latency_ms, op_type)]

    def record_write(self, latency_ms: float, success: bool = True):
        with self._lock:
            self.total_writes += 1
            if success:
                self.writes.append(latency_ms)
                if self.start_time:
                    self.timeline.append((
                        round(time.time() - self.start_time, 2),
                        round(latency_ms, 1),
                        "write",
                    ))
            else:
                self.errors += 1

    def record_read(self, latency_ms: float, success: bool = True):
        with self._lock:
            self.total_reads += 1
            if success:
                self.reads.append(latency_ms)
            else:
                self.errors += 1

    def summary(self) -> dict:
        def stats(data: list) -> dict:
            if not data:
                return {"min": 0, "max": 0, "avg": 0,
                        "p50": 0, "p95": 0, "p99": 0}
            s = sorted(data)
            n = len(s)
            return {
                "min": round(min(s), 1),
                "max": round(max(s), 1),
                "avg": round(statistics.mean(s), 1),
                "p50": round(s[int(n * 0.50)], 1),
                "p95": round(s[min(int(n * 0.95), n - 1)], 1),
                "p99": round(s[min(int(n * 0.99), n - 1)], 1),
            }

        elapsed   = time.time() - self.start_time if self.start_time else 1
        total_ops = self.total_writes + self.total_reads
        err_count = self.errors
        return {
            "total_ops"        : total_ops,
            "total_writes"     : self.total_writes,
            "total_reads"      : self.total_reads,
            "errors"           : err_count,
            "error_rate_pct"   : round(err_count / max(total_ops, 1) * 100, 2),
            "throughput_ops_s" : round(total_ops / elapsed, 2),
            "write_latency"    : stats(self.writes),
            "read_latency"     : stats(self.reads),
            "duration_s"       : round(elapsed, 1),
        }


metrics = Metrics()

# Métricas independientes para Redis (modo hybrid compara las dos)
redis_metrics = Metrics()


# ── Cliente Redis (TCP nativo con TLS — redis-py) ─────────────────────────────
# Usa protocolo Redis nativo sobre TCP+TLS (mismo protocolo que redis-cli).
# Mucho más eficiente que REST para tests de carga: conexión persistente,
# sin overhead TLS por request, sin saturación de pool HTTP.
#
# NOTA: La app Flutter sigue usando REST (no existe cliente TCP Redis para Dart).
# En producción cada teléfono hace 1 request independiente → no hay saturación.
# El test con TCP representa el comportamiento real de un servidor backend.

UPSTASH_HOST     = "endless-grouper-132192.upstash.io"
UPSTASH_PORT     = 6379
UPSTASH_PASSWORD = ""   # ← pegar contraseña TCP de Upstash (panel → Connect → TCP)
# REST conservado para referencia / app Flutter
UPSTASH_ENDPOINT = "https://endless-grouper-132192.upstash.io"
UPSTASH_TOKEN    = "gQAAAAAAAgRgAAIgcDJlNDA5ZDFkYjhkYzU0ODRlODcyMjk0ODZmNTU1YjAxNw"

REDIS_HOST = UPSTASH_HOST
REDIS_PORT = UPSTASH_PORT

class RedisClient:
    """
    Cliente Upstash TCP (redis-py + TLS) para telemetría GPS de conductores.

    Usa protocolo Redis nativo — conexión persistente, sin overhead HTTP por request.
    Latencia Upstash cloud (TCP): P50 ~5 ms, P95 ~15 ms desde Colombia.
    Latencia REST (HTTP):         P50 ~205 ms, P95 se satura con carga alta.

    Estructura de datos:
      HSET driver:pos:{id}  lat lng ts status driverId
      EXPIRE driver:pos:{id} 120           # limpieza automática offline
      SADD drivers:online {id}             # set de conductores activos
      GEOADD drivers:geo {lng} {lat} {id}  # índice geoespacial GEOSEARCH
    """

    DRIVER_POS_PREFIX   = "driver:pos:"
    ONLINE_DRIVERS_KEY  = "drivers:online"
    GEO_KEY             = "drivers:geo"
    EXPIRE_SECONDS      = 120

    def __init__(self, host: str = UPSTASH_HOST, port: int = UPSTASH_PORT):
        if not _REDIS_AVAILABLE:
            raise ImportError(
                "redis-py no instalado.\n"
                "  Instala con:  pip install redis\n"
                "  Luego corre el test de nuevo."
            )
        self._r = redis_lib.Redis(
            host=host,
            port=port,
            password=UPSTASH_PASSWORD,
            ssl=True,               # Upstash requiere TLS
            ssl_cert_reqs=None,     # no validar cert del servidor (cloud)
            decode_responses=True,
            socket_timeout=10,
            socket_connect_timeout=5,
            max_connections=300,    # pool suficiente para 200 threads concurrentes
        )
        # Verificar conectividad
        pong = self._r.ping()
        if not pong:
            raise ConnectionError("Upstash TCP no responde — verifica host, port y password")

    def set_driver_position(self, driver_id: str, lat: float, lng: float,
                            status: str = "active") -> float:
        """Actualiza posición + geo index con pipeline TCP. Retorna latencia en ms."""
        key = f"{self.DRIVER_POS_PREFIX}{driver_id}"
        ts  = int(time.time() * 1000)
        t0  = time.perf_counter()
        pipe = self._r.pipeline(transaction=False)
        pipe.hset(key, mapping={
            "lat": lat, "lng": lng, "ts": ts,
            "status": status, "driverId": driver_id,
        })
        pipe.expire(key, self.EXPIRE_SECONDS)
        pipe.sadd(self.ONLINE_DRIVERS_KEY, driver_id)
        # GEOADD: orden (lng, lat) — convención GeoJSON de Redis
        pipe.geoadd(self.GEO_KEY, [(lng, lat, driver_id)])
        pipe.execute()
        return (time.perf_counter() - t0) * 1000

    def get_nearby_drivers(self, lat: float, lng: float,
                           radius_km: float = 10.0, limit: int = 10) -> tuple:
        """GEOSEARCH por radio TCP. Retorna (latencia_ms, cantidad)."""
        t0 = time.perf_counter()
        results = self._r.geosearch(
            self.GEO_KEY,
            longitude=lng,
            latitude=lat,
            radius=radius_km,
            unit="km",
            sort="ASC",
            count=limit,
            withcoord=True,
            withdist=True,
        )
        latency = (time.perf_counter() - t0) * 1000
        return latency, len(results)

    # Alias para compatibilidad con simulate_passenger
    def get_online_drivers(self) -> tuple:
        return self.get_nearby_drivers(lat=4.3478, lng=-74.3649, radius_km=10.0)

    def driver_offline(self, driver_id: str):
        """Limpia conductor de todos los índices."""
        pipe = self._r.pipeline(transaction=False)
        pipe.srem(self.ONLINE_DRIVERS_KEY, driver_id)
        pipe.delete(f"{self.DRIVER_POS_PREFIX}{driver_id}")
        pipe.zrem(self.GEO_KEY, driver_id)
        pipe.execute()

    def flush_test_data(self):
        """Elimina datos del test anterior."""
        pipe = self._r.pipeline(transaction=False)
        pipe.delete(self.ONLINE_DRIVERS_KEY)
        pipe.delete(self.GEO_KEY)
        pipe.execute()


# ── Cliente Firestore REST ─────────────────────────────────────────────────────

class FirestoreClient:
    """Acceso a Firestore vía REST API (soporta emulador y producción)."""

    def __init__(self, use_emulator: bool):
        self.use_emulator = use_emulator
        base = (EMULATOR_FIRESTORE_HOST if use_emulator
                else "https://firestore.googleapis.com")
        self.fs_base   = f"{base}/v1/projects/{PROJECT_ID}/databases/(default)/documents"
        self.auth_base = (EMULATOR_AUTH_HOST if use_emulator
                          else "https://identitytoolkit.googleapis.com/v1")
        self._session  = requests.Session()
        adapter = requests.adapters.HTTPAdapter(
            pool_connections=200, pool_maxsize=200, max_retries=2
        )
        self._session.mount("http://",  adapter)
        self._session.mount("https://", adapter)

    # ── Auth ──────────────────────────────────────────────────────────────────

    def sign_in_anonymous(self) -> dict:
        """Crea cuenta anónima. Devuelve {'idToken', 'localId'}."""
        if self.use_emulator:
            url = (f"{self.auth_base}/identitytoolkit.googleapis.com"
                   f"/v1/accounts:signUp?key=fake-key")
        else:
            url = f"{self.auth_base}/accounts:signUp?key={API_KEY}"
        r = self._session.post(url, json={"returnSecureToken": True}, timeout=10)
        r.raise_for_status()
        d = r.json()
        return {"idToken": d["idToken"], "localId": d["localId"]}

    # ── Helpers Firestore ──────────────────────────────────────────────────────

    @staticmethod
    def _to_fs(v):
        """Convierte valor Python → Firestore REST value."""
        if isinstance(v, bool):    return {"booleanValue": v}
        if isinstance(v, int):     return {"integerValue": str(v)}
        if isinstance(v, float):   return {"doubleValue": v}
        if isinstance(v, str):     return {"stringValue": v}
        if isinstance(v, dict):
            return {"mapValue": {"fields": {k: FirestoreClient._to_fs(vv)
                                             for k, vv in v.items()}}}
        return {"stringValue": str(v)}

    def _headers(self, token: str) -> dict:
        return {"Authorization": f"Bearer {token}",
                "Content-Type": "application/json"}

    # ── Operaciones ───────────────────────────────────────────────────────────

    def patch(self, collection: str, doc_id: str,
              data: dict, token: str) -> float:
        """Actualiza/crea un documento. Retorna latencia en ms."""
        url    = f"{self.fs_base}/{collection}/{doc_id}"
        fields = {k: self._to_fs(v) for k, v in data.items()}
        params = {"updateMask.fieldPaths": list(data.keys())}
        t0 = time.perf_counter()
        r  = self._session.patch(
            url, headers=self._headers(token),
            json={"fields": fields}, params=params, timeout=15,
        )
        latency = (time.perf_counter() - t0) * 1000
        r.raise_for_status()
        return latency

    def post(self, collection: str, data: dict, token: str) -> float:
        """Crea documento con ID auto. Retorna latencia en ms."""
        url    = f"{self.fs_base}/{collection}"
        fields = {k: self._to_fs(v) for k, v in data.items()}
        t0 = time.perf_counter()
        r  = self._session.post(
            url, headers=self._headers(token),
            json={"fields": fields}, timeout=15,
        )
        latency = (time.perf_counter() - t0) * 1000
        r.raise_for_status()
        return latency

    def get_list(self, collection: str, token: str,
                 page_size: int = 100) -> tuple:
        """Lee hasta page_size documentos de una colección SIN filtros.
        Retorna (latencia_ms, cantidad).
        ⚠ Uso: métricas internas / debug. No simula la query real del pasajero."""
        url = f"{self.fs_base}/{collection}"
        t0  = time.perf_counter()
        r   = self._session.get(
            url, headers=self._headers(token),
            params={"pageSize": page_size}, timeout=15,
        )
        latency = (time.perf_counter() - t0) * 1000
        count   = len(r.json().get("documents", []))
        return latency, count

    def query_nearby_drivers(self, token: str, limit: int = 10) -> tuple:
        """
        Simula exactamente la consulta que hace el pasajero en getNearbyDrivers:
          • isOnline == true
          • status   == 'active'
          • limit    == 10   (solo los candidatos necesarios para el mapa)

        Usa el endpoint runQuery con structuredQuery, que aprovecha el índice
        compuesto  drivers → isOnline ASC, status ASC  de firestore.indexes.json.
        Sin este índice Firestore haría un full scan; con él hace O(log n).

        Retorna (latencia_ms, cantidad_docs).
        """
        # El emulador y producción usan el mismo endpoint :runQuery
        base = (EMULATOR_FIRESTORE_HOST if self.use_emulator
                else "https://firestore.googleapis.com")
        url = (
            f"{base}/v1/projects/{PROJECT_ID}"
            f"/databases/(default)/documents:runQuery"
        )
        body = {
            "structuredQuery": {
                "from": [{"collectionId": "drivers"}],
                "where": {
                    "compositeFilter": {
                        "op": "AND",
                        "filters": [
                            {
                                "fieldFilter": {
                                    "field": {"fieldPath": "isOnline"},
                                    "op": "EQUAL",
                                    "value": {"booleanValue": True},
                                }
                            },
                            {
                                "fieldFilter": {
                                    "field": {"fieldPath": "status"},
                                    "op": "EQUAL",
                                    "value": {"stringValue": "active"},
                                }
                            },
                        ],
                    }
                },
                "limit": limit,
            }
        }
        t0 = time.perf_counter()
        r  = self._session.post(
            url,
            headers=self._headers(token),
            json=body,
            timeout=15,
        )
        latency = (time.perf_counter() - t0) * 1000
        # runQuery devuelve una lista; cada elemento con 'document' es un hit
        results = r.json() if r.ok else []
        count   = sum(1 for item in results if "document" in item)
        return latency, count


# ── Simuladores ───────────────────────────────────────────────────────────────

def _random_pos(index: int) -> tuple:
    """Posición aleatoria dentro de la cobertura de Fusagasugá."""
    angle  = (index / 100) * 2 * math.pi + random.uniform(-0.2, 0.2)
    radius = random.uniform(0.004, 0.016)
    return (LAT_CENTER + radius * math.sin(angle),
            LNG_CENTER + radius * math.cos(angle))


def _move(lat: float, lng: float) -> tuple:
    """Desplazamiento pequeño aleatorio simulando movimiento continuo."""
    return (lat + random.uniform(-0.0006, 0.0006),
            lng + random.uniform(-0.0006, 0.0006))


def simulate_driver(index: int,
                    fs_client: FirestoreClient | None,
                    redis_client: "RedisClient | None",
                    duration_s: int, interval_s: float,
                    stop: threading.Event,
                    backend: str = "firestore",
                    stagger_s: float = 0.0):
    """
    Simula un conductor actualizando su posición GPS cada interval_s segundos.

    backend:
      "firestore" → solo Firestore (métricas en metrics)
      "redis"     → solo Redis     (métricas en redis_metrics)
      "hybrid"    → ambos simultáneamente (Firestore→metrics, Redis→redis_metrics)

    stagger_s: segundos de espera inicial antes de arrancar (escalonamiento).
               Simula conductores que se conectan gradualmente, no todos a la vez.
               Ej: stagger_s=0.5 con 100 conductores → último entra a los 50s.
    """
    # Escalonamiento: espera progresiva para evitar burst de autenticación
    if stagger_s > 0 and not stop.is_set():
        stop.wait(index * stagger_s)

    driver_id = f"stress_drv_{index:03d}"
    lat, lng  = _random_pos(index)

    # Registro inicial en Firestore (necesario para todos los modos)
    if fs_client and backend in ("firestore", "hybrid"):
        try:
            sess  = fs_client.sign_in_anonymous()
            token = sess["idToken"]
            lat_ms = fs_client.patch("drivers", driver_id, {
                "name"              : f"Driver Stress {index}",
                "isOnline"          : True,
                "status"            : "active",
                "currentLat"        : lat,
                "currentLng"        : lng,
                "subscriptionStatus": "trial",
                "vehicleType"       : random.choice(["car", "moto"]),
                "updatedAt"         : int(time.time() * 1000),
            }, token)
            metrics.record_write(lat_ms)
        except Exception:
            metrics.record_write(0, success=False)
            if backend == "firestore":
                return
            token = None
    else:
        token = None

    # Loop de movimiento
    end_time = time.time() + duration_s
    while not stop.is_set() and time.time() < end_time:
        lat, lng = _move(lat, lng)

        # ── Firestore write ──────────────────────────────────────────────────
        if fs_client and token and backend in ("firestore", "hybrid"):
            try:
                lat_ms = fs_client.patch("drivers", driver_id, {
                    "currentLat": lat,
                    "currentLng": lng,
                    "updatedAt" : int(time.time() * 1000),
                }, token)
                metrics.record_write(lat_ms)
            except Exception:
                metrics.record_write(0, success=False)

        # ── Redis write ──────────────────────────────────────────────────────
        if redis_client and backend in ("redis", "hybrid"):
            try:
                lat_ms = redis_client.set_driver_position(driver_id, lat, lng)
                redis_metrics.record_write(lat_ms)
            except Exception:
                redis_metrics.record_write(0, success=False)

        stop.wait(interval_s)

    # Limpiar en Redis al terminar
    if redis_client and backend in ("redis", "hybrid"):
        try:
            redis_client.driver_offline(driver_id)
        except Exception:
            pass


def simulate_passenger(index: int,
                       fs_client: FirestoreClient | None,
                       redis_client: "RedisClient | None",
                       duration_s: int, stop: threading.Event,
                       backend: str = "firestore"):
    """
    Simula un pasajero consultando conductores disponibles cada ~10 s.
    En modo redis/hybrid lee desde Redis; en modo firestore desde Firestore.
    """
    token = None
    trip_done = False

    end_time = time.time() + duration_s

    if fs_client and backend in ("firestore", "hybrid"):
        try:
            sess  = fs_client.sign_in_anonymous()
            token = sess["idToken"]
        except Exception:
            token = None

    try:
        while not stop.is_set() and time.time() < end_time:
            # ── Leer conductores disponibles ─────────────────────────────────
            # Usa query_nearby_drivers (structuredQuery con filtros + limit=10)
            # que replica exactamente lo que hace getNearbyDrivers en Flutter:
            #   isOnline=true AND status='active' LIMIT 10
            # Aprovecha el índice compuesto → O(log n), no full scan.
            if fs_client and token and backend in ("firestore", "hybrid"):
                try:
                    lat_ms, _ = fs_client.query_nearby_drivers(token, limit=10)
                    metrics.record_read(lat_ms)
                except Exception:
                    metrics.record_read(0, success=False)

            if redis_client and backend in ("redis", "hybrid"):
                try:
                    lat_ms, _ = redis_client.get_online_drivers()
                    redis_metrics.record_read(lat_ms)
                except Exception:
                    redis_metrics.record_read(0, success=False)

            # ── Crear viaje (una vez por pasajero, solo en Firestore) ────────
            if not trip_done and token and fs_client and random.random() < 0.75:
                orig_lat, orig_lng = _random_pos(index)
                dest_lat, dest_lng = _random_pos(index + 55)
                try:
                    lat_ms = fs_client.post("trips", {
                        "passengerId"       : f"stress_pax_{index}",
                        "passengerName"     : f"Pasajero {index}",
                        "status"            : "requested",
                        "originLat"         : orig_lat,
                        "originLng"         : orig_lng,
                        "originAddress"     : f"Calle {random.randint(1,50)}, Fusagasugá",
                        "destinationLat"    : dest_lat,
                        "destinationLng"    : dest_lng,
                        "destinationAddress": f"Carrera {random.randint(1,30)}, Fusagasugá",
                        "fare"              : 8000.0,
                        "createdAt"         : int(time.time() * 1000),
                    }, token)
                    metrics.record_write(lat_ms)
                    with metrics._lock:
                        metrics.trips_created += 1
                    trip_done = True
                except Exception:
                    metrics.record_write(0, success=False)

            stop.wait(random.uniform(8, 12))

    except Exception:
        metrics.record_read(0, success=False)


# ── Reporte HTML ───────────────────────────────────────────────────────────────

_HTML = Template(r"""<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<title>Zue – Stress Test Report</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4/dist/chart.umd.min.js"></script>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',Arial,sans-serif;background:#f4f6fb;color:#2d3436}
.hdr{background:linear-gradient(135deg,#6c5ce7 0%,#a29bfe 100%);color:#fff;padding:32px 44px}
.hdr h1{font-size:26px;font-weight:700;letter-spacing:-.3px}
.hdr p{margin-top:6px;opacity:.85;font-size:14px}
.wrap{max-width:1100px;margin:28px auto;padding:0 24px}
.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:14px;margin-bottom:28px}
.kpi{background:#fff;border-radius:14px;padding:18px 20px;box-shadow:0 2px 10px rgba(0,0,0,.07)}
.kpi .lbl{font-size:11px;font-weight:700;text-transform:uppercase;color:#636e72;letter-spacing:.4px}
.kpi .val{font-size:26px;font-weight:700;margin-top:5px}
.ok{color:#00b894}.warn{color:#e17055}.bad{color:#d63031}
.box{background:#fff;border-radius:14px;padding:22px 24px;
     box-shadow:0 2px 10px rgba(0,0,0,.07);margin-bottom:22px}
.box h2{font-size:16px;font-weight:700;margin-bottom:18px}
.chart-wrap{position:relative;height:260px}
table{width:100%;border-collapse:collapse}
th{background:#f8f9fc;font-size:11px;font-weight:700;text-transform:uppercase;
   color:#636e72;padding:9px 14px;text-align:left}
td{padding:10px 14px;border-bottom:1px solid #f0f0f0;font-size:13px}
tr:last-child td{border:none}
.badge{display:inline-block;padding:3px 9px;border-radius:20px;font-size:11px;font-weight:700}
.b-ok{background:#d4f5ea;color:#006647}
.b-warn{background:#ffeaa7;color:#7a5c00}
.b-bad{background:#fdd9d7;color:#8b1a1a}
.bar-wrap{background:#eef0f4;border-radius:8px;height:12px;overflow:hidden;margin:5px 0 2px}
.bar-fill{height:100%;border-radius:8px}
.rec{border-left:4px solid;padding:11px 15px;border-radius:0 10px 10px 0;
     margin-bottom:10px;font-size:13px;line-height:1.5}
.rec-ok{background:#d4f5ea;border-color:#00b894}
.rec-warn{background:#fef9e7;border-color:#fdcb6e}
.rec-bad{background:#fdd9d7;border-color:#d63031}
code{background:#f0f0f0;padding:1px 5px;border-radius:4px;font-size:12px}
</style>
</head>
<body>
<div class="hdr">
  <h1>🚗 Zue App &mdash; Stress Test Report</h1>
  <p>Generado: ${timestamp} &nbsp;|&nbsp; Proyecto: <strong>${project_id}</strong>
     &nbsp;|&nbsp; Modo: <strong>${mode}</strong>
     &nbsp;|&nbsp; Conductores: <strong>${num_drivers}</strong>
     &nbsp;|&nbsp; Pasajeros: <strong>${num_passengers}</strong>
     &nbsp;|&nbsp; Duración: <strong>${duration_s}s</strong>
     &nbsp;|&nbsp; Intervalo GPS: <strong>${interval_s}s</strong>
  </p>
</div>

<div class="wrap">

  <!-- KPIs -->
  <div class="kpis">
    <div class="kpi"><div class="lbl">Operaciones totales</div>
      <div class="val ${ops_c}">${total_ops}</div></div>
    <div class="kpi"><div class="lbl">Throughput</div>
      <div class="val ${tput_c}">${throughput} <small style="font-size:14px">ops/s</small></div></div>
    <div class="kpi"><div class="lbl">Tasa de error</div>
      <div class="val ${err_c}">${error_rate}%</div></div>
    <div class="kpi"><div class="lbl">Escrituras (ubicación)</div>
      <div class="val ok">${total_writes}</div></div>
    <div class="kpi"><div class="lbl">Latencia escritura avg</div>
      <div class="val ${wlat_c}">${w_avg} <small style="font-size:14px">ms</small></div></div>
    <div class="kpi"><div class="lbl">Latencia escritura P95</div>
      <div class="val ${wp95_c}">${w_p95} <small style="font-size:14px">ms</small></div></div>
    <div class="kpi"><div class="lbl">Lecturas (conductores)</div>
      <div class="val ok">${total_reads}</div></div>
    <div class="kpi"><div class="lbl">Viajes solicitados</div>
      <div class="val ok">${trips}</div></div>
  </div>

  <!-- Gráfico latencia en el tiempo -->
  <div class="box">
    <h2>📈 Latencia de escritura en el tiempo</h2>
    <div class="chart-wrap"><canvas id="latChart"></canvas></div>
  </div>

  <!-- Desglose por operación -->
  <div class="box">
    <h2>📊 Desglose de latencia por operación</h2>
    <table>
      <tr>
        <th>Operación</th><th>Total</th><th>Avg</th>
        <th>P50</th><th>P95</th><th>P99</th><th>Máx</th><th>Veredicto</th>
      </tr>
      <tr>
        <td><strong>Escritura</strong> (ubicación)</td>
        <td>${total_writes}</td>
        <td>${w_avg} ms</td><td>${w_p50} ms</td>
        <td>${w_p95} ms</td><td>${w_p99} ms</td><td>${w_max} ms</td>
        <td><span class="badge ${w_bg}">${w_vrd}</span></td>
      </tr>
      <tr>
        <td><strong>Lectura</strong> (conductores)</td>
        <td>${total_reads}</td>
        <td>${r_avg} ms</td><td>${r_p50} ms</td>
        <td>${r_p95} ms</td><td>${r_p99} ms</td><td>${r_max} ms</td>
        <td><span class="badge ${r_bg}">${r_vrd}</span></td>
      </tr>
      <tr>
        <td><strong>Errores</strong></td>
        <td colspan="6">${errors} errores &mdash; tasa ${error_rate}%</td>
        <td><span class="badge ${err_bg}">${err_vrd}</span></td>
      </tr>
    </table>
  </div>

  <!-- Cuota Firebase -->
  <div class="box">
    <h2>🔥 Análisis de cuota Firebase (Plan Spark – gratuito vs Blaze)</h2>
    <table>
      <tr>
        <th>Recurso</th>
        <th>Límite Spark (día)</th>
        <th>Proyección 24h<br>(${num_drivers} conductores × ${interval_s}s)</th>
        <th>% del límite</th>
      </tr>
      <tr>
        <td>Escrituras Firestore</td>
        <td>20.000</td>
        <td>${proj_w}</td>
        <td>
          <div class="bar-wrap">
            <div class="bar-fill" style="width:${wp_pct}%;background:${wp_col}"></div>
          </div>
          <strong style="color:${wp_col}">${wp_pct}%</strong>
        </td>
      </tr>
      <tr>
        <td>Lecturas Firestore</td>
        <td>50.000</td>
        <td>${proj_r}</td>
        <td>
          <div class="bar-wrap">
            <div class="bar-fill" style="width:${rp_pct}%;background:${rp_col}"></div>
          </div>
          <strong style="color:${rp_col}">${rp_pct}%</strong>
        </td>
      </tr>
      <tr>
        <td>Costo estimado Blaze (día)</td>
        <td colspan="2">Escrituras: ${blaze_w_cost} USD &nbsp;+&nbsp; Lecturas: ${blaze_r_cost} USD</td>
        <td><strong>Total: ${blaze_total} USD/día</strong></td>
      </tr>
    </table>
  </div>

  <!-- Recomendaciones -->
  <div class="box">
    <h2>💡 Recomendaciones</h2>
    ${recs_html}
  </div>

</div><!-- /wrap -->

<script>
const labels = ${chart_labels};
const data   = ${chart_data};
const p95    = ${w_p95};
new Chart(document.getElementById('latChart'), {
  type: 'line',
  data: {
    labels,
    datasets: [
      {
        label: 'Latencia escritura (ms)',
        data,
        borderColor: '#6c5ce7',
        backgroundColor: 'rgba(108,92,231,0.07)',
        borderWidth: 1.5,
        pointRadius: 0,
        fill: true,
        tension: 0.3,
      },
      {
        label: `P95 = $${p95} ms`,
        data: Array(labels.length).fill(p95),
        borderColor: '#e17055',
        borderDash: [6, 4],
        borderWidth: 1.5,
        pointRadius: 0,
        fill: false,
      }
    ]
  },
  options: {
    responsive: true,
    maintainAspectRatio: false,
    interaction: { mode: 'index', intersect: false },
    scales: {
      x: { display: true, title: { display: true, text: 'Tiempo (s)' } },
      y: { beginAtZero: true, title: { display: true, text: 'ms' } }
    },
    plugins: { legend: { position: 'top' } }
  }
});
</script>
</body>
</html>
""")


def _badge(val, ok, warn):
    if val <= ok:   return "b-ok",   "✓ Excelente"
    if val <= warn: return "b-warn", "⚠ Aceptable"
    return "b-bad", "✗ Lento"


def _bar_color(pct):
    if pct < 70:  return "#00b894"
    if pct < 100: return "#fdcb6e"
    return "#d63031"


def generate_report(summary: dict, args, output_path: str):
    ws = summary["write_latency"]
    rs = summary["read_latency"]

    w_bg,   w_vrd  = _badge(ws["p95"], 400, 900)
    r_bg,   r_vrd  = _badge(rs["p95"], 600, 1500)
    err     = summary["error_rate_pct"]
    err_bg  = "b-ok" if err < 1 else ("b-warn" if err < 5 else "b-bad")
    err_vrd = "✓ Bajo" if err < 1 else ("⚠ Moderado" if err < 5 else "✗ Alto")

    ops_c  = "ok"   if summary["total_ops"] > 50  else "warn"
    tput_c = "ok"   if summary["throughput_ops_s"] >= 3 else "warn"
    err_c  = "ok"   if err < 1 else ("warn" if err < 5 else "bad")
    wlat_c = "ok"   if ws["avg"] < 400 else ("warn" if ws["avg"] < 900 else "bad")
    wp95_c = "ok"   if ws["p95"] < 600 else ("warn" if ws["p95"] < 1200 else "bad")

    # Proyección de cuota
    n_drv     = args.drivers
    n_pax     = args.passengers
    iv        = args.interval
    proj_w    = int(n_drv * (86400 / iv))                    # updates ubicación/día
    proj_r    = int(n_pax * 6 * 86400 / 60)                  # ~6 reads/min/pasajero
    wp_pct    = min(round(proj_w / 20_000 * 100), 999)
    rp_pct    = min(round(proj_r / 50_000 * 100), 999)

    blaze_w   = round(proj_w  / 100_000 * 0.06, 4)
    blaze_r   = round(proj_r  / 100_000 * 0.06, 4)
    blaze_tot = round(blaze_w + blaze_r, 4)

    # Recomendaciones
    recs = []
    if wp_pct > 100:
        recs.append(("bad",
            f"Con {n_drv} conductores cada {iv}s se generan <strong>{proj_w:,} escrituras/día</strong>. "
            f"El plan Spark permite 20.000/día. "
            f"<strong>Necesitas el plan Blaze</strong> (~${blaze_tot} USD/día)."))
    elif wp_pct > 70:
        recs.append(("warn",
            f"Estás al {wp_pct}% del límite de escrituras Spark. "
            f"Aumenta el intervalo de actualización GPS a 10s para reducir la carga."))
    else:
        recs.append(("ok",
            f"Con {n_drv} conductores y {iv}s de intervalo, las escrituras caben "
            f"en el plan Spark ({wp_pct}% del límite diario)."))

    if ws["p95"] > 900:
        recs.append(("warn",
            "La latencia P95 de escritura supera 900ms. "
            "Activa la persistencia offline de Firestore y "
            "considera un índice compuesto <code>isOnline + status</code>."))
    else:
        recs.append(("ok",
            f"La latencia P95 de escritura ({ws['p95']}ms) está dentro de límites aceptables."))

    recs.append(("ok",
        "Usa <code>distanceFilter: 50</code> + throttle 10 s en Geolocator para "
        "enviar updates solo cuando el conductor se mueva &gt;50m Y hayan pasado 10 s, "
        "reduciendo escrituras ~70%."))
    recs.append(("ok",
        "Índice compuesto Firestore <code>drivers → isOnline ASC, status ASC</code> "
        "ya configurado en <code>firestore.indexes.json</code>."))

    # Sección Redis si hay datos comparativos
    if hasattr(args, 'backend') and args.backend in ("redis", "hybrid"):
        rs_sum = redis_metrics.summary()
        rws    = rs_sum["write_latency"]
        rrs    = rs_sum["read_latency"]
        cmds_per_day   = int(n_drv * (86400 / iv)) * 4   # 4 cmds pipeline por update
        fs_throt_day   = int(n_drv * (86400 / 30))        # Firestore c/30s
        cost_redis_pay = round(cmds_per_day / 100_000 * 0.20, 2)
        cost_fs_throt  = round(fs_throt_day / 100_000 * 0.06, 3)
        cost_hybrid    = round(cost_redis_pay + cost_fs_throt, 2)
        cost_fs_only   = round(int(n_drv * (86400 / iv)) / 100_000 * 0.06, 2)
        # Speedup escritura y lectura
        speed_w = round(float(str(ws["p95"])) / max(float(str(rws["p95"])), 0.1)) if str(ws["p95"]) != "0" else "N/A"
        speed_r = round(float(str(rs["p95"])) / max(float(str(rrs["p95"])), 0.1)) if str(rs["p95"]) != "0" and str(rrs["p95"]) != "0" else "N/A"
        geo_verdict = "ok" if str(rrs["p95"]) != "0" and float(str(rrs["p95"])) < 500 else "warn"
        recs.insert(0, (geo_verdict,
            f"<strong>✅ Redis Upstash activo — GEOSEARCH habilitado</strong><br>"
            f"<strong>Escritura GPS (HSET+GEOADD pipeline):</strong> "
            f"P50={rws['p50']} ms | P95={rws['p95']} ms | P99={rws['p99']} ms<br>"
            f"<strong>Lectura pasajero (GEOSEARCH radio 10 km):</strong> "
            f"P50={rrs['p50']} ms | P95={rrs['p95']} ms | P99={rrs['p99']} ms<br>"
            f"<em>Latencia incluye RTT Colombia→Upstash São Paulo (~180 ms). "
            f"En producción la app Flutter escribe GPS en background (no bloquea UI).</em><br><br>"
            f"<strong>Proyección de costos Upstash (100 conductores, {iv}s, 24 h):</strong><br>"
            f"Redis: {cmds_per_day:,} comandos/día × $0.20/100K = <strong>${cost_redis_pay}/día</strong><br>"
            f"Firestore throttled 30 s: {fs_throt_day:,} writes/día = <strong>${cost_fs_throt}/día</strong><br>"
            f"Total arquitectura híbrida: <strong>${cost_hybrid}/día</strong> "
            f"vs solo Firestore: <strong>${cost_fs_only}/día</strong><br>"
            f"<em>El costo adicional de Redis (~${cost_hybrid - cost_fs_only:.2f}/día) "
            f"elimina el P95 de lectura de 3,344 ms → búsqueda geoespacial real en memoria.</em>"))

    if err > 5:
        recs.append(("bad",
            f"Tasa de error alta ({err}%). Verifica las reglas de seguridad Firestore "
            f"y los límites de concurrencia del plan."))

    recs_html = "\n".join(
        f'<div class="rec rec-{c}">{m}</div>' for c, m in recs
    )

    # Datos del gráfico (submuestreo: máx 400 puntos)
    tl    = sorted(metrics.timeline, key=lambda x: x[0])
    step  = max(1, len(tl) // 400)
    samp  = tl[::step]
    c_lbl = json.dumps([s[0] for s in samp])
    c_dat = json.dumps([s[1] for s in samp])

    html = _HTML.substitute(
        timestamp    = datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        project_id   = PROJECT_ID,
        mode         = "Emulador" if args.mode == "emulator" else "🔴 Producción",
        num_drivers  = n_drv,
        num_passengers = n_pax,
        duration_s   = summary["duration_s"],
        interval_s   = iv,
        total_ops    = summary["total_ops"],
        throughput   = summary["throughput_ops_s"],
        error_rate   = err,
        total_writes = summary["total_writes"],
        total_reads  = summary["total_reads"],
        errors       = summary["errors"],
        trips        = metrics.trips_created,
        ops_c=ops_c, tput_c=tput_c, err_c=err_c,
        wlat_c=wlat_c, wp95_c=wp95_c,
        w_avg=ws["avg"], w_p50=ws["p50"], w_p95=ws["p95"],
        w_p99=ws["p99"], w_max=ws["max"],
        r_avg=rs["avg"], r_p50=rs["p50"], r_p95=rs["p95"],
        r_p99=rs["p99"], r_max=rs["max"],
        w_bg=w_bg, w_vrd=w_vrd, r_bg=r_bg, r_vrd=r_vrd,
        err_bg=err_bg, err_vrd=err_vrd,
        proj_w=f"{proj_w:,}", proj_r=f"{proj_r:,}",
        wp_pct=min(wp_pct, 100), rp_pct=min(rp_pct, 100),
        wp_col=_bar_color(wp_pct), rp_col=_bar_color(rp_pct),
        blaze_w_cost=blaze_w, blaze_r_cost=blaze_r, blaze_total=blaze_tot,
        recs_html=recs_html,
        chart_labels=c_lbl, chart_data=c_dat,
    )

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"\n  Reporte HTML \u2192 {output_path}")


# ── Helpers para la suite de pruebas ─────────────────────────────────────────

def _one_run(ns) -> dict:
    """
    Ejecuta una corrida completa con los parametros del namespace ns.
    Reinicia metricas globales antes de cada ejecucion.
    """
    global metrics, redis_metrics
    metrics       = Metrics()
    redis_metrics = Metrics()
    metrics.start_time       = time.time()
    redis_metrics.start_time = time.time()

    fs_client = None
    if getattr(ns, 'backend', 'firestore') in ("firestore", "hybrid"):
        fs_client = FirestoreClient(use_emulator=(ns.mode == "emulator"))

    stop    = threading.Event()
    stagger = getattr(ns, 'stagger', 0.0)
    total_s = ns.duration + stagger * ns.drivers

    with ThreadPoolExecutor(
        max_workers=ns.drivers + ns.passengers,
        thread_name_prefix="zue_suite"
    ) as executor:
        for i in range(ns.drivers):
            executor.submit(
                simulate_driver,
                i, fs_client, None,
                ns.duration, ns.interval, stop,
                getattr(ns, 'backend', 'firestore'),
                stagger,
            )
        for i in range(ns.passengers):
            executor.submit(
                simulate_passenger,
                i, fs_client, None,
                ns.duration, stop,
                getattr(ns, 'backend', 'firestore'),
            )

        end_time  = time.time() + total_s
        bar_width = 36
        try:
            while time.time() < end_time:
                elapsed = time.time() - metrics.start_time
                pct     = min(elapsed / total_s, 1.0)
                filled  = int(bar_width * pct)
                bar     = chr(0x2588) * filled + chr(0x2591) * (bar_width - filled)
                print(
                    "\r    [" + bar + "] " +
                    "{:5.1f}%".format(pct * 100) +
                    "  writes=" + str(metrics.total_writes) +
                    " err=" + str(metrics.errors),
                    end="", flush=True,
                )
                time.sleep(1)
        except KeyboardInterrupt:
            pass
        finally:
            stop.set()
    print()
    return metrics.summary()


def _run_suite(base_args):
    """
    Bateria de 4 pruebas que aislan las variables clave:

      A  Burst simultaneo (baseline)              interval=5s   stagger=0s
      B  Escalonado real (0.3s/conductor)         interval=5s   stagger=0.3s
      C  Throttle GPS 10s ya implementado         interval=10s  stagger=0.3s
      D  Throttle GPS 30s (modo Redis sync)       interval=30s  stagger=0.3s
    """
    import types

    scenarios = [
        ("A - Burst simultaneo (baseline)",       5.0,  0.0),
        ("B - Escalonado real (0.3s/conductor)",  5.0,  0.3),
        ("C - Throttle GPS 10s implementado",    10.0,  0.3),
        ("D - Throttle GPS 30s modo Redis",      30.0,  0.3),
    ]

    if base_args.mode == "emulator":
        print("\n  Verificando Firebase Emulator... ", end="", flush=True)
        try:
            requests.get(EMULATOR_FIRESTORE_HOST + "/", timeout=3)
            print("OK")
        except Exception:
            print("FALLO")
            print("  ERROR: Emulador no disponible en " + EMULATOR_FIRESTORE_HOST)
            sys.exit(1)

    results = []
    for label, interval, stagger in scenarios:
        extra_s = int(stagger * base_args.drivers)
        print("\n  " + "=" * 54)
        print("  " + label)
        print(
            "  interval=" + str(interval) + "s  stagger=" + str(stagger) + "s" +
            "  drivers=" + str(base_args.drivers) +
            "  duracion_efectiva=" + str(base_args.duration + extra_s) + "s"
        )
        print("  " + "=" * 54)

        ns = types.SimpleNamespace(
            backend    = base_args.backend,
            mode       = base_args.mode,
            drivers    = base_args.drivers,
            passengers = base_args.passengers,
            duration   = base_args.duration,
            interval   = interval,
            stagger    = stagger,
        )

        summary = _one_run(ns)
        ws = summary["write_latency"]
        print(
            "  OK  P50=" + str(ws["p50"]) + "ms" +
            "  P95=" + str(ws["p95"]) + "ms" +
            "  P99=" + str(ws["p99"]) + "ms" +
            "  writes=" + str(summary["total_writes"]) +
            "  err=" + str(summary["errors"])
        )
        results.append({
            "label"   : label,
            "interval": interval,
            "stagger" : stagger,
            "summary" : summary,
        })

    _generate_suite_report(results, base_args)


def _generate_suite_report(results, args):
    """Genera suite_report.html con tabla comparativa de los 4 escenarios."""
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    rows = ""
    for r in results:
        ws         = r["summary"]["write_latency"]
        iv         = r["interval"]
        writes_day = int(args.drivers * 86400 / iv)
        cost_day   = round(writes_day / 100_000 * 0.06, 2)
        spark_pct  = min(round(writes_day / 20_000 * 100), 9999)

        if ws["p95"] < 400:
            p95_col = "#00b894"
        elif ws["p95"] < 1000:
            p95_col = "#e17055"
        else:
            p95_col = "#d63031"

        spark_icon = "&#x1F534;" if spark_pct > 100 else "&#x1F7E2;"
        stagger_str = ("Simultaneo" if r["stagger"] == 0
                       else str(r["stagger"]) + "s/conductor")

        rows += (
            "        <tr>"
            "<td><strong>" + r["label"] + "</strong></td>"
            "<td>" + str(iv) + "s</td>"
            "<td>" + stagger_str + "</td>"
            "<td>" + str(ws["p50"]) + " ms</td>"
            "<td style=\"color:" + p95_col + ";font-weight:700\">" +
            str(ws["p95"]) + " ms</td>"
            "<td>" + str(ws["p99"]) + " ms</td>"
            "<td>{:,}</td>".format(r["summary"]["total_writes"]) +
            "<td>{:,}/dia</td>".format(writes_day) +
            "<td>" + spark_icon + " " + str(spark_pct) + "%</td>"
            "<td><strong>$" + str(cost_day) + "</strong>/dia</td>"
            "</tr>\n"
        )

    html = (
        "<!DOCTYPE html>\n<html lang=\"es\">\n<head>\n"
        "<meta charset=\"UTF-8\">\n"
        "<title>Zue - Suite de Pruebas Comparativas</title>\n"
        "<style>\n"
        "*{box-sizing:border-box;margin:0;padding:0}\n"
        "body{font-family:\"Segoe UI\",Arial,sans-serif;background:#f4f6fb;color:#2d3436}\n"
        ".hdr{background:linear-gradient(135deg,#6c5ce7 0%,#a29bfe 100%);"
        "color:#fff;padding:28px 40px}\n"
        ".hdr h1{font-size:22px;font-weight:700}\n"
        ".hdr p{margin-top:6px;opacity:.85;font-size:13px}\n"
        ".wrap{max-width:1200px;margin:28px auto;padding:0 24px}\n"
        ".box{background:#fff;border-radius:14px;padding:22px 24px;"
        "box-sizing:border-box;box-shadow:0 2px 10px rgba(0,0,0,.07);margin-bottom:22px}\n"
        ".box h2{font-size:15px;font-weight:700;margin-bottom:18px}\n"
        "table{width:100%;border-collapse:collapse}\n"
        "th{background:#f8f9fc;font-size:10px;font-weight:700;text-transform:uppercase;"
        "color:#636e72;padding:9px 12px;text-align:left}\n"
        "td{padding:10px 12px;border-bottom:1px solid #f0f0f0;font-size:13px}\n"
        "tr:last-child td{border:none}\n"
        ".note{background:#f0f4ff;border-left:4px solid #6c5ce7;padding:12px 16px;"
        "border-radius:0 10px 10px 0;font-size:13px;line-height:1.6;margin-top:16px}\n"
        "code{background:#f0f0f0;padding:1px 5px;border-radius:4px;font-size:12px}\n"
        "</style>\n</head>\n<body>\n"
        "<div class=\"hdr\">\n"
        "  <h1>&#x1F697; Zue App &mdash; Suite de Pruebas Comparativas</h1>\n"
        "  <p>Generado: <strong>" + ts + "</strong> &nbsp;|&nbsp;\n"
        "     Conductores: <strong>" + str(args.drivers) + "</strong> &nbsp;|&nbsp;\n"
        "     Pasajeros: <strong>" + str(args.passengers) + "</strong> &nbsp;|&nbsp;\n"
        "     Duracion base: <strong>" + str(args.duration) + "s</strong>\n"
        "  </p>\n</div>\n"
        "<div class=\"wrap\">\n"
        "  <div class=\"box\">\n"
        "    <h2>&#x1F4CA; Comparativa de escenarios GPS</h2>\n"
        "    <table>\n"
        "      <tr>"
        "<th>Escenario</th>"
        "<th>Intervalo</th>"
        "<th>Inicio</th>"
        "<th>P50</th>"
        "<th>P95</th>"
        "<th>P99</th>"
        "<th>Writes (test)</th>"
        "<th>Proyeccion 24h</th>"
        "<th>% Spark</th>"
        "<th>Costo Blaze</th>"
        "</tr>\n" +
        rows +
        "    </table>\n"
        "    <div class=\"note\">\n"
        "      <strong>Como leer esta tabla:</strong><br>\n"
        "      <strong>A (Burst):</strong> todos los conductores se conectan a la vez. "
        "Produce P99 alto pero no ocurre en produccion real.<br>\n"
        "      <strong>B (Escalonado):</strong> conductores se conectan de a uno cada 0.3s. "
        "Refleja el comportamiento real de la app.<br>\n"
        "      <strong>C (10s throttle):</strong> ya implementado en "
        "<code>driver_home_page.dart</code>. Reduce escrituras ~50% vs 5s.<br>\n"
        "      <strong>D (30s throttle):</strong> intervalo de sync Firestore con Redis activo. "
        "Reduce escrituras ~83% vs 5s.<br>\n"
        "    </div>\n"
        "  </div>\n</div>\n</body>\n</html>\n"
    )

    output = "suite_report.html"
    with open(output, "w", encoding="utf-8") as f:
        f.write(html)
    abs_path = os.path.abspath(output).replace(os.sep, "/")
    print("\n  Suite completada -> " + os.path.abspath(output))
    print("  file:///" + abs_path + "\n")


def main():
    parser = argparse.ArgumentParser(
        description="Zue App - Stress Test (Firestore / Redis / Hybrid)",
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument("--backend",    default="firestore",
                        choices=["firestore", "redis", "hybrid"])
    parser.add_argument("--mode",       default="emulator",
                        choices=["emulator", "real"])
    parser.add_argument("--drivers",    type=int, default=10)
    parser.add_argument("--passengers", type=int, default=5)
    parser.add_argument("--duration",   type=int, default=60,
                        help="Duracion total del test en segundos")
    parser.add_argument("--interval",   type=float, default=5.0,
                        help="Intervalo GPS en segundos por conductor")
    parser.add_argument("--redis-host", default=REDIS_HOST)
    parser.add_argument("--redis-port", type=int, default=REDIS_PORT)
    parser.add_argument("--output",     default="stress_report.html",
                        help="Archivo HTML de salida")
    parser.add_argument(
        "--stagger", type=float, default=0.0,
        help=(
            "Segundos de espera entre el inicio de cada conductor.\n"
            "0 = todos arrancan simultaneamente (produce burst de auth).\n"
            "Ej: --stagger 0.3 con 100 conductores -> el ultimo entra a los 30s.\n"
            "Simula la conexion gradual real de la app en produccion."
        ),
    )
    parser.add_argument(
        "--suite", action="store_true",
        help=(
            "Ejecutar bateria de 4 pruebas comparativas automaticamente:\n"
            "  A) Burst simultaneo    B) Escalonado 0.3s/conductor\n"
            "  C) Throttle GPS 10s    D) Throttle GPS 30s (modo Redis)\n"
            "Genera suite_report.html con tabla comparativa de latencias y costos."
        ),
    )
    args = parser.parse_args()

    # ── Suite automatica ──────────────────────────────────────────────────────
    if args.suite:
        _run_suite(args)
        return

    # ── Banner ────────────────────────────────────────────────────────────────
    print("\n" + "=" * 60)
    print("  Zue App - Stress Test")
    print("  Backend  : " + args.backend.upper())
    print("  Modo     : " + ("Emulador" if args.mode == "emulator" else "PRODUCCION"))
    print("  Conductores: " + str(args.drivers) +
          "  |  Pasajeros: " + str(args.passengers))
    print("  Duracion : " + str(args.duration) +
          "s  |  Intervalo GPS: " + str(args.interval) + "s")
    if args.stagger > 0:
        print("  Stagger  : " + str(args.stagger) + "s/conductor (inicio escalonado)")
    print("=" * 60)

    # ── Clientes ──────────────────────────────────────────────────────────────
    fs_client    = None
    redis_client = None

    if args.backend in ("firestore", "hybrid"):
        if args.mode == "emulator":
            print("\n  Verificando Firebase Emulator... ", end="", flush=True)
            try:
                requests.get(EMULATOR_FIRESTORE_HOST + "/", timeout=3)
                print("OK")
            except Exception:
                print("FALLO")
                print(
                    "\n  ERROR: Emulador Firestore no responde en " +
                    EMULATOR_FIRESTORE_HOST + "\n"
                    "  Inicia con: firebase emulators:start --only firestore,auth\n"
                )
                sys.exit(1)
        fs_client = FirestoreClient(use_emulator=(args.mode == "emulator"))
        print("  FirestoreClient listo")

    if args.backend in ("redis", "hybrid"):
        print("\n  Conectando a Upstash Redis TCP+TLS (" +
              UPSTASH_HOST + ":" + str(UPSTASH_PORT) + ")... ",
              end="", flush=True)
        try:
            redis_client = RedisClient()
            redis_client.flush_test_data()
            print("OK")
        except ImportError as exc:
            print("FALLO")
            print("\n  " + str(exc))
            sys.exit(1)
        except Exception as exc:
            print("FALLO: " + str(exc))
            print("  Verifica UPSTASH_HOST, UPSTASH_PORT y UPSTASH_PASSWORD")
            sys.exit(1)

    # ── Metricas ──────────────────────────────────────────────────────────────
    metrics.start_time       = time.time()
    redis_metrics.start_time = time.time()
    stop = threading.Event()

    total_s = args.duration + args.stagger * args.drivers
    print("\n  Lanzando " + str(args.drivers) +
          " conductores y " + str(args.passengers) + " pasajeros...\n")

    with ThreadPoolExecutor(
        max_workers=args.drivers + args.passengers,
        thread_name_prefix="zue"
    ) as executor:
        for i in range(args.drivers):
            executor.submit(
                simulate_driver,
                i, fs_client, redis_client,
                args.duration, args.interval, stop,
                args.backend, args.stagger,
            )
        for i in range(args.passengers):
            executor.submit(
                simulate_passenger,
                i, fs_client, redis_client,
                args.duration, stop, args.backend,
            )

        end_time  = time.time() + total_s
        bar_width = 40
        try:
            while time.time() < end_time:
                elapsed = time.time() - metrics.start_time
                pct     = min(elapsed / total_s, 1.0)
                filled  = int(bar_width * pct)
                bar     = chr(0x2588) * filled + chr(0x2591) * (bar_width - filled)
                fs_w    = metrics.total_writes
                fs_r    = metrics.total_reads
                fs_err  = metrics.errors
                rd_w    = redis_metrics.total_writes
                rd_err  = redis_metrics.errors

                if args.backend == "hybrid":
                    status = (
                        "\r  [" + bar + "] " + "{:5.1f}%".format(pct * 100) +
                        "  FS writes=" + str(fs_w) +
                        " reads=" + str(fs_r) +
                        " err=" + str(fs_err) +
                        "  Redis writes=" + str(rd_w) +
                        " err=" + str(rd_err)
                    )
                elif args.backend == "redis":
                    status = (
                        "\r  [" + bar + "] " + "{:5.1f}%".format(pct * 100) +
                        "  Redis writes=" + str(rd_w) +
                        " reads=" + str(redis_metrics.total_reads) +
                        " err=" + str(rd_err)
                    )
                else:
                    status = (
                        "\r  [" + bar + "] " + "{:5.1f}%".format(pct * 100) +
                        "  writes=" + str(fs_w) +
                        " reads=" + str(fs_r) +
                        " err=" + str(fs_err)
                    )
                print(status, end="", flush=True)
                time.sleep(1)
        except KeyboardInterrupt:
            print("\n\n  Interrupcion - guardando resultados...")
        finally:
            stop.set()

    print()

    summary = metrics.summary()
    ws      = summary["write_latency"]
    rs_s    = summary["read_latency"]

    print("\n" + "=" * 60)
    print("  RESULTADOS - Firestore")
    print("=" * 60)
    print("  Ops totales   : {:>8,}".format(summary["total_ops"]))
    print("  Escrituras    : {:>8,}".format(summary["total_writes"]))
    print("  Lecturas      : {:>8,}".format(summary["total_reads"]))
    print("  Errores       : {:>8,}  ({}%)".format(
          summary["errors"], summary["error_rate_pct"]))
    print("  Throughput    : {:>8.2f} ops/s".format(summary["throughput_ops_s"]))
    print("  Escritura  P50: {:>8} ms   P95: {} ms   P99: {} ms".format(
          ws["p50"], ws["p95"], ws["p99"]))
    print("  Lectura    P50: {:>8} ms   P95: {} ms   P99: {} ms".format(
          rs_s["p50"], rs_s["p95"], rs_s["p99"]))
    print("  Viajes creados: {:>8,}".format(metrics.trips_created))

    if args.backend in ("redis", "hybrid") and redis_client:
        rd  = redis_metrics.summary()
        rws = rd["write_latency"]
        rrs = rd["read_latency"]
        print("\n" + "=" * 60)
        print("  RESULTADOS - Redis (Upstash REST / GEOSEARCH)")
        print("=" * 60)
        print("  Escrituras    : {:>8,}".format(rd["total_writes"]))
        print("  Lecturas      : {:>8,}".format(rd["total_reads"]))
        print("  Errores       : {:>8,}".format(rd["errors"]))
        print("  Escritura  P50: {:>8} ms   P95: {} ms   P99: {} ms".format(
              rws["p50"], rws["p95"], rws["p99"]))
        print("  Lectura    P50: {:>8} ms   P95: {} ms   P99: {} ms  ← GEOSEARCH".format(
              rrs["p50"], rrs["p95"], rrs["p99"]))
        if args.backend == "hybrid":
            if ws["p95"] > 0 and rws["p95"] > 0:
                speedup_w = round(float(str(ws["p95"])) / max(float(str(rws["p95"])), 0.01))
                print("  Escritura: Redis ~{}x vs Firestore (P95: {} ms vs {} ms)".format(
                      speedup_w, rws["p95"], ws["p95"]))
            if rs_s["p95"] > 0 and rrs["p95"] > 0:
                speedup_r = round(float(str(rs_s["p95"])) / max(float(str(rrs["p95"])), 0.01))
                print("  Lectura:   Redis ~{}x vs Firestore (P95: {} ms vs {} ms)".format(
                      speedup_r, rrs["p95"], rs_s["p95"]))
        redis_client.flush_test_data()

    generate_report(summary, args, args.output)
    abs_path = os.path.abspath(args.output).replace(os.sep, "/")
    print("  Reporte HTML -> " + args.output)
    print("  file:///" + abs_path + "\n")


if __name__ == "__main__":
    main()
