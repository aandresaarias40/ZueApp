#!/usr/bin/env python3
"""
stress_test.py  –  Zue App Load & Stress Test
==============================================
Simula N conductores moviéndose en el mapa y M pasajeros buscando viajes
para medir la capacidad de Firestore bajo carga real.

MODOS DE EJECUCIÓN
------------------
  --mode emulator   → Firebase Local Emulator Suite (sin costo, recomendado)
  --mode real       → Firebase producción  (¡genera lecturas/escrituras reales!)

USO RÁPIDO
----------
  # 1. Instalar dependencia
  pip install requests

  # 2a. Con emulador (recomendado)
  firebase emulators:start --only firestore,auth
  python stress_test.py --mode emulator --drivers 100 --passengers 20 --duration 60

  # 2b. Contra Firebase real
  python stress_test.py --mode real --drivers 50 --duration 30

  # Ver todas las opciones
  python stress_test.py --help
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
        """Lee hasta page_size documentos de una colección.
        Retorna (latencia_ms, cantidad)."""
        url = f"{self.fs_base}/{collection}"
        t0  = time.perf_counter()
        r   = self._session.get(
            url, headers=self._headers(token),
            params={"pageSize": page_size}, timeout=15,
        )
        latency = (time.perf_counter() - t0) * 1000
        count   = len(r.json().get("documents", []))
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


def simulate_driver(index: int, client: FirestoreClient,
                    duration_s: int, interval_s: float,
                    stop: threading.Event):
    """
    Simula un conductor:
      1. Autenticación anónima
      2. Creación del documento en /drivers
      3. Actualizaciones de ubicación cada `interval_s` segundos
    """
    try:
        sess      = client.sign_in_anonymous()
        token     = sess["idToken"]
        driver_id = f"stress_drv_{index:03d}_{sess['localId'][:6]}"
        lat, lng  = _random_pos(index)

        # Registro inicial
        try:
            lat_ms = client.patch("drivers", driver_id, {
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
            return

        # Loop de movimiento
        end_time = time.time() + duration_s
        while not stop.is_set() and time.time() < end_time:
            lat, lng = _move(lat, lng)
            try:
                lat_ms = client.patch("drivers", driver_id, {
                    "currentLat": lat,
                    "currentLng": lng,
                    "updatedAt" : int(time.time() * 1000),
                }, token)
                metrics.record_write(lat_ms)
            except Exception:
                metrics.record_write(0, success=False)
            stop.wait(interval_s)

    except Exception:
        metrics.record_write(0, success=False)


def simulate_passenger(index: int, client: FirestoreClient,
                       duration_s: int, stop: threading.Event):
    """
    Simula un pasajero:
      1. Autenticación anónima
      2. Consulta conductores disponibles cada ~10 s
      3. Crea una solicitud de viaje durante la sesión
    """
    try:
        sess  = client.sign_in_anonymous()
        token = sess["idToken"]
        trip_done = False

        end_time = time.time() + duration_s
        while not stop.is_set() and time.time() < end_time:
            # Leer conductores disponibles
            try:
                lat_ms, _ = client.get_list("drivers", token, page_size=50)
                metrics.record_read(lat_ms)
            except Exception:
                metrics.record_read(0, success=False)

            # Crear solicitud de viaje (una vez por pasajero)
            if not trip_done and random.random() < 0.75:
                orig_lat, orig_lng = _random_pos(index)
                dest_lat, dest_lng = _random_pos(index + 55)
                try:
                    lat_ms = client.post("trips", {
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
  <p>Generado: {timestamp} &nbsp;|&nbsp; Proyecto: <strong>{project_id}</strong>
     &nbsp;|&nbsp; Modo: <strong>{mode}</strong>
     &nbsp;|&nbsp; Conductores: <strong>{num_drivers}</strong>
     &nbsp;|&nbsp; Pasajeros: <strong>{num_passengers}</strong>
     &nbsp;|&nbsp; Duración: <strong>{duration_s}s</strong>
     &nbsp;|&nbsp; Intervalo GPS: <strong>{interval_s}s</strong>
  </p>
</div>

<div class="wrap">

  <!-- KPIs -->
  <div class="kpis">
    <div class="kpi"><div class="lbl">Operaciones totales</div>
      <div class="val {ops_c}">{total_ops}</div></div>
    <div class="kpi"><div class="lbl">Throughput</div>
      <div class="val {tput_c}">{throughput} <small style="font-size:14px">ops/s</small></div></div>
    <div class="kpi"><div class="lbl">Tasa de error</div>
      <div class="val {err_c}">{error_rate}%</div></div>
    <div class="kpi"><div class="lbl">Escrituras (ubicación)</div>
      <div class="val ok">{total_writes}</div></div>
    <div class="kpi"><div class="lbl">Latencia escritura avg</div>
      <div class="val {wlat_c}">{w_avg} <small style="font-size:14px">ms</small></div></div>
    <div class="kpi"><div class="lbl">Latencia escritura P95</div>
      <div class="val {wp95_c}">{w_p95} <small style="font-size:14px">ms</small></div></div>
    <div class="kpi"><div class="lbl">Lecturas (conductores)</div>
      <div class="val ok">{total_reads}</div></div>
    <div class="kpi"><div class="lbl">Viajes solicitados</div>
      <div class="val ok">{trips}</div></div>
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
        <td>{total_writes}</td>
        <td>{w_avg} ms</td><td>{w_p50} ms</td>
        <td>{w_p95} ms</td><td>{w_p99} ms</td><td>{w_max} ms</td>
        <td><span class="badge {w_bg}">{w_vrd}</span></td>
      </tr>
      <tr>
        <td><strong>Lectura</strong> (conductores)</td>
        <td>{total_reads}</td>
        <td>{r_avg} ms</td><td>{r_p50} ms</td>
        <td>{r_p95} ms</td><td>{r_p99} ms</td><td>{r_max} ms</td>
        <td><span class="badge {r_bg}">{r_vrd}</span></td>
      </tr>
      <tr>
        <td><strong>Errores</strong></td>
        <td colspan="6">{errors} errores &mdash; tasa {error_rate}%</td>
        <td><span class="badge {err_bg}">{err_vrd}</span></td>
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
        <th>Proyección 24h<br>({num_drivers} conductores × {interval_s}s)</th>
        <th>% del límite</th>
      </tr>
      <tr>
        <td>Escrituras Firestore</td>
        <td>20.000</td>
        <td>{proj_w:,}</td>
        <td>
          <div class="bar-wrap">
            <div class="bar-fill" style="width:{wp_pct}%;background:{wp_col}"></div>
          </div>
          <strong style="color:{wp_col}">{wp_pct}%</strong>
        </td>
      </tr>
      <tr>
        <td>Lecturas Firestore</td>
        <td>50.000</td>
        <td>{proj_r:,}</td>
        <td>
          <div class="bar-wrap">
            <div class="bar-fill" style="width:{rp_pct}%;background:{rp_col}"></div>
          </div>
          <strong style="color:{rp_col}">{rp_pct}%</strong>
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
    {recs_html}
  </div>

</div><!-- /wrap -->

<script>
const labels = {chart_labels};
const data   = {chart_data};
const p95    = {w_p95};
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
        label: `P95 = ${p95} ms`,
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
"""


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
        "Usa <code>distanceFilter: 20</code> en Geolocator (ya configurado) para "
        "enviar updates solo cuando el conductor se mueva &gt;20m, reduciendo escrituras ~60%."))
    recs.append(("ok",
        "Crea un índice compuesto en Firestore: "
        "<code>drivers → isOnline ASC, status ASC</code> "
        "para que la consulta de conductores disponibles sea O(log n) en lugar de full scan."))

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

    html = _HTML.format(
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
        proj_w=proj_w, proj_r=proj_r,
        wp_pct=min(wp_pct, 100), rp_pct=min(rp_pct, 100),
        wp_col=_bar_color(wp_pct), rp_col=_bar_color(rp_pct),
        blaze_w_cost=blaze_w, blaze_r_cost=blaze_r, blaze_total=blaze_tot,
        recs_html=recs_html,
        chart_labels=c_lbl, chart_data=c_dat,
    )

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"\n  Reporte HTML → {output_path}")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    p = argparse.ArgumentParser(
        description="Zue App Stress Test – simula conductores y pasajeros en Firestore"
    )
    p.add_argument("--mode",       choices=["emulator", "real"], default="emulator",
                   help="emulator = Firebase Local Emulator (default) | real = producción")
    p.add_argument("--drivers",    type=int,   default=100,
                   help="Número de conductores simulados (default: 100)")
    p.add_argument("--passengers", type=int,   default=20,
                   help="Número de pasajeros simulados (default: 20)")
    p.add_argument("--duration",   type=int,   default=60,
                   help="Duración total de la prueba en segundos (default: 60)")
    p.add_argument("--interval",   type=float, default=5.0,
                   help="Segundos entre actualizaciones de ubicación (default: 5)")
    p.add_argument("--output",     default="stress_report.html",
                   help="Nombre del reporte HTML (default: stress_report.html)")
    args = p.parse_args()

    print(f"""
╔══════════════════════════════════════════════════════════╗
║            ZUE APP  –  STRESS TEST                       ║
╠══════════════════════════════════════════════════════════╣
║  Modo              : {args.mode:<36}║
║  Conductores       : {args.drivers:<36}║
║  Pasajeros         : {args.passengers:<36}║
║  Duración          : {args.duration}s{' '*34}║
║  Intervalo GPS     : {args.interval}s (update de ubicación){' '*14}║
║  Reporte de salida : {args.output:<36}║
╚══════════════════════════════════════════════════════════╝
""")

    # Verificar emulador
    if args.mode == "emulator":
        print("  Verificando Firebase Emulator en localhost:8080 ...", end=" ")
        try:
            requests.get("http://localhost:8080", timeout=3)
            print("✓\n")
        except Exception:
            print("✗")
            print("""
  No se pudo conectar al emulador. Inícialo con:

    firebase emulators:start --only firestore,auth

  Si no tienes Firebase CLI:
    npm install -g firebase-tools
    firebase login
    firebase init emulators
""")
            sys.exit(1)
    else:
        print("  ADVERTENCIA: ejecutando contra Firebase PRODUCCIÓN.")
        print("  Esto generará lecturas/escrituras reales en tu proyecto.\n")
        resp = input("  ¿Continuar? (s/N): ").strip().lower()
        if resp != "s":
            print("  Cancelado.")
            sys.exit(0)

    client = FirestoreClient(use_emulator=(args.mode == "emulator"))
    stop   = threading.Event()

    metrics.start_time = time.time()
    total_threads      = args.drivers + args.passengers

    print(f"  Lanzando {args.drivers} conductores + {args.passengers} pasajeros "
          f"({total_threads} hilos)...")
    print("  Presiona Ctrl+C para detener antes de tiempo.\n")

    with ThreadPoolExecutor(max_workers=total_threads + 4) as pool:
        futures = []

        for i in range(args.drivers):
            futures.append(pool.submit(
                simulate_driver, i, client,
                args.duration, args.interval, stop,
            ))

        for i in range(args.passengers):
            futures.append(pool.submit(
                simulate_passenger, i, client,
                args.duration, stop,
            ))

        # Barra de progreso en consola
        try:
            t_start = time.time()
            while time.time() - t_start < args.duration + 10:
                elapsed = time.time() - t_start
                pct     = min(int(elapsed / args.duration * 100), 100)
                bar     = "█" * (pct // 4) + "░" * (25 - pct // 4)
                s       = metrics.summary()
                print(
                    f"\r  [{bar}] {pct:3d}%  "
                    f"ops={s['total_ops']:5d}  "
                    f"tput={s['throughput_ops_s']:5.1f}/s  "
                    f"err={s['error_rate_pct']:.1f}%  "
                    f"w_avg={s['write_latency']['avg']:5.0f}ms",
                    end="", flush=True,
                )
                if all(f.done() for f in futures):
                    break
                time.sleep(1)
        except KeyboardInterrupt:
            print("\n\n  Interrumpido. Deteniendo hilos...")
            stop.set()

    stop.set()
    print("\n\n  ✓ Test finalizado. Calculando resultados...\n")

    summary = metrics.summary()
    ws = summary["write_latency"]
    rs = summary["read_latency"]

    print("┌──────────────────────────────────────────────────────┐")
    print("│                    RESUMEN FINAL                     │")
    print("├──────────────────────────────────────────────────────┤")
    print(f"│  Duración total      : {summary['duration_s']}s")
    print(f"│  Operaciones totales : {summary['total_ops']}")
    print(f"│  Throughput          : {summary['throughput_ops_s']} ops/s")
    print(f"│  Tasa de error       : {summary['error_rate_pct']}%")
    print(f"│  Viajes creados      : {metrics.trips_created}")
    print(f"│  ─── Escrituras ({summary['total_writes']}) ───────────────────────── │")
    print(f"│  avg={ws['avg']}ms  p50={ws['p50']}ms  p95={ws['p95']}ms  p99={ws['p99']}ms  max={ws['max']}ms")
    print(f"│  ─── Lecturas   ({summary['total_reads']}) ───────────────────────── │")
    print(f"│  avg={rs['avg']}ms  p50={rs['p50']}ms  p95={rs['p95']}ms  p99={rs['p99']}ms  max={rs['max']}ms")
    print("└──────────────────────────────────────────────────────┘")

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), args.output)
    generate_report(summary, args, out)
    print(f"\n  Abre el reporte en tu navegador:\n  {out}\n")


if __name__ == "__main__":
    main()
