import * as zebar from 'zebar';
import {
  ArrowDown,
  ArrowUp,
  Cpu,
  HardDrive,
  MemoryStick,
  Microchip,
} from 'lucide-react';
import { LhmSensors } from '../../hooks/useLhmSensors';

interface StatsProps {
  cpu: zebar.CpuOutput | null;
  memory: zebar.MemoryOutput | null;
  network: zebar.NetworkOutput | null;
  disk: zebar.DiskOutput | null;
  lhm: LhmSensors;
}

// The system drive: prefer C:, else the first fixed drive.
function systemDrive(disk: zebar.DiskOutput | null) {
  const drives = disk?.disks?.filter((d) => !d.isRemovable) ?? [];
  if (!drives.length) return null;
  return (
    drives.find((x) => (x.mountPoint ?? '').toUpperCase().startsWith('C')) ??
    drives[0]
  );
}

// Space used on the system drive, as a percentage.
// (Zebar's disk provider reports capacity only - it has no I/O throughput.)
export function diskUsedPct(disk: zebar.DiskOutput | null): number | null {
  const d = systemDrive(disk);
  const total = d?.totalSpace?.bytes ?? 0;
  const avail = d?.availableSpace?.bytes ?? 0;
  if (total <= 0) return null;
  return ((total - avail) / total) * 100;
}

const TIB = 1024 ** 4;

// "1.4/2.5 TB" - used/total. Uses binary terabytes (TiB) but labels them TB,
// matching what Windows Explorer and fastfetch show for this drive.
function diskUsedTb(disk: zebar.DiskOutput | null): string | null {
  const d = systemDrive(disk);
  const total = d?.totalSpace?.bytes ?? 0;
  const avail = d?.availableSpace?.bytes ?? 0;
  if (total <= 0) return null;
  const used = total - avail;
  return `${(used / TIB).toFixed(1)}/${(total / TIB).toFixed(1)} TB`;
}

// Compact rate formatter: DataSizeMeasure gives siValue/siUnit (e.g. 2.4 "MB").
function rate(m: zebar.DataSizeMeasure | undefined | null) {
  if (!m) return '--';
  const v = m.siValue;
  const unit = m.siUnit ?? '';
  return v >= 100 ? `${Math.round(v)} ${unit}` : `${v.toFixed(1)} ${unit}`;
}

function pct(v: number | null | undefined) {
  return v === null || v === undefined ? '--' : `${Math.round(v)}%`;
}

function temp(v: number | null | undefined) {
  return v === null || v === undefined ? '--' : `${Math.round(v)}°`;
}

// One always-present island:
//   CPU% temp · GPU% temp · RAM% · disk% + TB · net up · net down
// Icons instead of text labels. There is no GPU glyph in lucide, so the GPU
// uses Microchip alongside the CPU's Cpu glyph; tooltips disambiguate.
export default function Stats({
  cpu,
  memory,
  network,
  disk,
  lhm,
}: StatsProps) {
  const icon = 'h-3.5 w-3.5 text-icon shrink-0';
  const tempHint = lhm.ok
    ? ''
    : ' (unavailable - is LibreHardwareMonitor running?)';

  return (
    <div className="flex items-center gap-2.5 h-full tabular-nums text-sm">
      <span
        className="flex items-center gap-1.5"
        title={`CPU usage and temperature${tempHint}`}
      >
        <Cpu className={icon} />
        <span>{pct(cpu?.usage)}</span>
        <span>{temp(lhm.cpuTemp)}</span>
      </span>

      <span
        className="flex items-center gap-1.5"
        title={`NVIDIA GPU usage and temperature${tempHint}`}
      >
        <Microchip className={icon} />
        <span>{pct(lhm.gpuLoad)}</span>
        <span>{temp(lhm.gpuTemp)}</span>
      </span>

      <span className="flex items-center gap-1.5" title="RAM usage">
        <MemoryStick className={icon} />
        <span>{pct(memory?.usage)}</span>
      </span>

      <span
        className="flex items-center gap-1.5"
        title="Disk space used on the system drive"
      >
        <HardDrive className={icon} />
        <span>{pct(diskUsedPct(disk))}</span>
        <span className="text-text-muted">{diskUsedTb(disk) ?? ''}</span>
      </span>

      <span className="flex items-center gap-0.5" title="Network upload">
        <ArrowUp className="h-3 w-3 text-icon shrink-0" />
        <span>{rate(network?.traffic?.transmitted)}</span>
      </span>

      <span className="flex items-center gap-0.5" title="Network download">
        <ArrowDown className="h-3 w-3 text-icon shrink-0" />
        <span>{rate(network?.traffic?.received)}</span>
      </span>
    </div>
  );
}
