import { HostOutput } from 'zebar';
import { Timer } from 'lucide-react';

interface UptimeProps {
  host: HostOutput | null;
}

function formatUptime(seconds: number) {
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

// Uptime readout for its own island. Derived from the host provider's
// `uptime` prop (a real reactive dependency), so it re-renders on each
// provider tick — unlike a value read from an impure source, which the
// React Compiler would memoise and freeze.
export default function Uptime({ host }: UptimeProps) {
  if (!host) return null;

  // HostOutput.uptime is in MILLISECONDS (verified against a known system
  // uptime: raw ~104,860,800 vs 104,662 real seconds -> factor of 1000).
  const secs = Math.floor(host.uptime / 1000);

  return (
    <div
      className="flex items-center gap-1.5 h-full"
      title={`Up ${formatUptime(secs)}`}
    >
      <Timer className="h-3.5 w-3.5 text-icon" />
      <span className="tabular-nums">{formatUptime(secs)}</span>
    </div>
  );
}
