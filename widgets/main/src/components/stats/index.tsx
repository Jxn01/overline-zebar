import * as zebar from 'zebar';
import { ArrowDown, ArrowUp } from 'lucide-react';
import { LhmSensors } from '../../hooks/useLhmSensors';

interface StatsProps {
  cpu: zebar.CpuOutput | null;
  memory: zebar.MemoryOutput | null;
  network: zebar.NetworkOutput | null;
  disk: zebar.DiskOutput | null;
  lhm: LhmSensors;
}

// Space used on the system drive. Prefer C:, else the first fixed drive.
// (Zebar's disk provider reports capacity only - it has no I/O throughput.)
export function diskUsedPct(disk: zebar.DiskOutput | null): number | null {
  const drives = disk?.disks?.filter((d) => !d.isRemovable) ?? [];
  if (!drives.length) return null;
  const d =
    drives.find((x) => (x.mountPoint ?? '').toUpperCase().startsWith('C')) ??
    drives[0];
  const total = d.totalSpace?.bytes ?? 0;
  const avail = d.availableSpace?.bytes ?? 0;
  if (total <= 0) return null;
  return ((total - avail) / total) * 100;
}

// Compact rate formatter: DataSizeMeasure gives siValue/siUnit (e.g. 2.4 "MB").
function rate(m: zebar.DataSizeMeasure | undefined | null) {
  if (!m) return '--';
  const v = m.siValue;
  const unit = (m.siUnit ?? '').replace('B', 'B');
  if (v >= 100) return `${Math.round(v)} ${unit}`;
  if (v >= 10) return `${v.toFixed(1)} ${unit}`;
  return `${v.toFixed(1)} ${unit}`;
}

function pct(v: number | null | undefined) {
  return v === null || v === undefined ? '--' : `${Math.round(v)}%`;
}

function temp(v: number | null | undefined) {
  return v === null || v === undefined ? '--' : `${Math.round(v)}°`;
}

// One always-present island:
//   CPU% · CPU temp · GPU% · GPU temp · RAM% · net up · net down
// CPU/RAM/network come from Zebar providers (reactive props); the temps and
// NVIDIA GPU load come from LibreHardwareMonitor via useLhmSensors.
export default function Stats({ cpu, memory, network, disk, lhm }: StatsProps) {
  const label = 'text-text-muted';

  return (
    <div className="flex items-center gap-2.5 h-full tabular-nums text-sm">
      <span className="flex items-center gap-1" title="CPU usage">
        <span className={label}>CPU</span>
        <span>{pct(cpu?.usage)}</span>
      </span>

      <span
        className="flex items-center gap-1"
        title={lhm.ok ? 'CPU temperature (Tctl/Tdie)' : 'CPU temp unavailable - is LibreHardwareMonitor running?'}
      >
        <span>{temp(lhm.cpuTemp)}</span>
      </span>

      <span className="flex items-center gap-1" title="NVIDIA GPU usage">
        <span className={label}>GPU</span>
        <span>{pct(lhm.gpuLoad)}</span>
      </span>

      <span className="flex items-center gap-1" title="NVIDIA GPU temperature">
        <span>{temp(lhm.gpuTemp)}</span>
      </span>

      <span className="flex items-center gap-1" title="RAM usage">
        <span className={label}>RAM</span>
        <span>{pct(memory?.usage)}</span>
      </span>

      <span className="flex items-center gap-1" title="Disk space used (C:)">
        <span className={label}>DISK</span>
        <span>{pct(diskUsedPct(disk))}</span>
      </span>

      <span className="flex items-center gap-0.5" title="Network upload">
        <ArrowUp className="h-3 w-3 text-icon" />
        <span>{rate(network?.traffic?.transmitted)}</span>
      </span>

      <span className="flex items-center gap-0.5" title="Network download">
        <ArrowDown className="h-3 w-3 text-icon" />
        <span>{rate(network?.traffic?.received)}</span>
      </span>
    </div>
  );
}
