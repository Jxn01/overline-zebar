import { useEffect, useState } from 'react';

// Sensors that Zebar cannot provide, read from LibreHardwareMonitor's JSON web
// server (http://localhost:8085/data.json).
//
// Why LHM: Windows exposes no usable CPU die temp on this board
// (MSAcpi_ThermalZoneTemperature returns "not supported"), and Zebar's
// CpuOutput has no temperature field at all. LHM reads it via a kernel driver
// and is autostarted elevated by a scheduled task.
//
// Why its web server rather than WMI: fetching one JSON beats spawning a
// PowerShell process every few seconds, and it yields the NVIDIA GPU figures
// in the same call.
//
// The values live in state and are refreshed by an interval, giving React a
// real reactive dependency. Reading them inline at render time would let the
// React Compiler memoise the component and freeze the readout (as happened
// with the clock).

export interface LhmSensors {
  cpuTemp: number | null;
  gpuLoad: number | null;
  gpuTemp: number | null;
  /** false once a fetch has failed, so the UI can show a dash instead of stale data */
  ok: boolean;
}

// Sensor ids from LHM. IMPORTANT: use the /gpu-nvidia/ ids, not /gpu-amd/ —
// this machine also reports the onboard Radeon, which is not what we want.
const ID_CPU_TEMP = '/amdcpu/0/temperature/2'; // Core (Tctl/Tdie)
const ID_GPU_LOAD = '/gpu-nvidia/0/load/0'; // GPU Core load
const ID_GPU_TEMP = '/gpu-nvidia/0/temperature/0'; // GPU Core temp

function parseNum(v: unknown): number | null {
  if (typeof v !== 'string') return null;
  const m = v.replace(',', '.').match(/-?\d+(\.\d+)?/);
  return m ? parseFloat(m[0]) : null;
}

interface LhmNode {
  SensorId?: string;
  Value?: string;
  Children?: LhmNode[];
}

const LHM_URL = 'http://localhost:8085/data.json';

// Zebar's service worker caches CROSS-ORIGIN GETs (see /__zebar/sw.js: it
// returns early for same-origin or non-GET, and calls respondWith otherwise).
// With the pack's 7-day default duration, our LHM reading froze at its first
// value. Neither workaround applies here: LHM 404s on a cache-busting query
// string, and POST returns a stub body. So evict the entry explicitly before
// each read. This touches only Cache Storage - NOT localStorage, where the
// user's theme lives.
async function evictCached(url: string) {
  try {
    if (typeof caches === 'undefined') return;
    const keys = await caches.keys();
    await Promise.all(
      keys.map(async (k) => {
        const c = await caches.open(k);
        await c.delete(url);
      })
    );
  } catch {
    /* best effort */
  }
}

export function useLhmSensors(intervalMs = 3000): LhmSensors {
  const [sensors, setSensors] = useState<LhmSensors>({
    cpuTemp: null,
    gpuLoad: null,
    gpuTemp: null,
    ok: false,
  });

  useEffect(() => {
    let cancelled = false;

    const read = async () => {
      try {
        await evictCached(LHM_URL);
        const res = await fetch(LHM_URL, { cache: 'no-store' });
        const json: LhmNode = await res.json();

        const byId: Record<string, string | undefined> = {};
        const walk = (n: LhmNode) => {
          if (n.SensorId) byId[n.SensorId] = n.Value;
          n.Children?.forEach(walk);
        };
        walk(json);

        if (cancelled) return;
        setSensors({
          cpuTemp: parseNum(byId[ID_CPU_TEMP]),
          gpuLoad: parseNum(byId[ID_GPU_LOAD]),
          gpuTemp: parseNum(byId[ID_GPU_TEMP]),
          ok: true,
        });
      } catch {
        // LHM not running / web server off: mark not-ok, keep last values.
        if (!cancelled) setSensors((s) => ({ ...s, ok: false }));
      }
    };

    read();
    const id = setInterval(read, intervalMs);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [intervalMs]);

  return sensors;
}
