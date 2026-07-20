import { useEffect, useState } from 'react';
import * as zebar from 'zebar';

// 5-minute graphs, opened from the stats island.
//
// The bar widget samples into localStorage (same-origin across widgets, which
// the theme config already relies on); this panel only reads. It re-reads on
// an interval so it stays live while open — the values are held in state, not
// read inline at render, so the React Compiler can't memoise them away.
const HISTORY_KEY = 'overline-stats-history';
const WINDOW_MS = 5 * 60 * 1000;

interface Sample {
  t: number;
  cpu: number;
  ram: number;
  gpu: number;
  cpuTemp: number;
  gpuTemp: number;
  up: number;
  down: number;
}

type SeriesKey = keyof Omit<Sample, 't'>;

const SERIES: { key: SeriesKey; label: string; unit: string; max?: number }[] = [
  { key: 'cpu', label: 'CPU', unit: '%', max: 100 },
  { key: 'cpuTemp', label: 'CPU temp', unit: '°C' },
  { key: 'gpu', label: 'GPU', unit: '%', max: 100 },
  { key: 'gpuTemp', label: 'GPU temp', unit: '°C' },
  { key: 'ram', label: 'RAM', unit: '%', max: 100 },
  { key: 'down', label: 'Net down', unit: '' },
  { key: 'up', label: 'Net up', unit: '' },
];

function humanBytes(v: number) {
  if (v >= 1e9) return `${(v / 1e9).toFixed(1)} GB`;
  if (v >= 1e6) return `${(v / 1e6).toFixed(1)} MB`;
  if (v >= 1e3) return `${(v / 1e3).toFixed(0)} kB`;
  return `${Math.round(v)} B`;
}

function Sparkline({
  samples,
  seriesKey,
  max,
}: {
  samples: Sample[];
  seriesKey: SeriesKey;
  max?: number;
}) {
  const w = 150;
  const h = 26;
  if (samples.length < 2) {
    return <svg width={w} height={h} />;
  }

  const vals = samples.map((s) => s[seriesKey] ?? 0);
  const hi = max ?? Math.max(...vals, 1);
  const t0 = samples[0].t;
  const span = Math.max(samples[samples.length - 1].t - t0, 1);

  const pts = samples
    .map((s) => {
      const x = ((s.t - t0) / span) * w;
      const y = h - ((s[seriesKey] ?? 0) / hi) * (h - 2) - 1;
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(' ');

  return (
    <svg width={w} height={h} className="overflow-visible">
      <polyline
        points={pts}
        fill="none"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinejoin="round"
        strokeLinecap="round"
      />
    </svg>
  );
}

function App() {
  const [samples, setSamples] = useState<Sample[]>([]);

  useEffect(() => {
    zebar.currentWidget().tauriWindow.listen('tauri://blur', () => {
      zebar.currentWidget().close();
    });
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') zebar.currentWidget().close();
    };
    window.addEventListener('keydown', onKey);

    const read = () => {
      try {
        const raw = localStorage.getItem(HISTORY_KEY);
        const hist: Sample[] = raw ? JSON.parse(raw) : [];
        const cutoff = Date.now() - WINDOW_MS;
        setSamples(hist.filter((s) => s.t >= cutoff));
      } catch {
        setSamples([]);
      }
    };
    read();
    const id = setInterval(read, 3000);

    return () => {
      window.removeEventListener('keydown', onKey);
      clearInterval(id);
    };
  }, []);

  const newest = samples.length ? samples[samples.length - 1] : null;
  const minutes = samples.length
    ? Math.round((samples[samples.length - 1].t - samples[0].t) / 60000)
    : 0;

  return (
    <div className="h-screen w-screen flex items-start justify-center p-1 font-mono antialiased select-none text-text">
      <div className="w-full rounded-2xl border border-border bg-background-deeper/95 backdrop-blur-xl drop-shadow-lg p-3 flex flex-col gap-1">
        <div className="flex items-center justify-between px-1 pb-1.5 border-b border-border">
          <span className="font-semibold">System</span>
          <span className="text-xs text-text-muted">
            {samples.length < 2
              ? 'collecting…'
              : `last ${minutes || '<1'} min · ${samples.length} samples`}
          </span>
        </div>

        {SERIES.map((s) => {
          const v = newest ? newest[s.key] ?? 0 : 0;
          const isBytes = s.key === 'up' || s.key === 'down';
          return (
            <div key={s.key} className="flex items-center gap-2 px-1 py-0.5">
              <span className="w-16 text-xs text-text-muted shrink-0">{s.label}</span>
              <span className="flex-1 text-icon">
                <Sparkline samples={samples} seriesKey={s.key} max={s.max} />
              </span>
              <span className="w-16 text-right text-xs tabular-nums shrink-0">
                {isBytes ? humanBytes(v) : `${Math.round(v)}${s.unit}`}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

export default App;
