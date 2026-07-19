import { useEffect, useState } from 'react';
import * as zebar from 'zebar';
import {
  Cloud,
  CloudDrizzle,
  CloudFog,
  CloudLightning,
  CloudRain,
  CloudSnow,
  Sun,
} from 'lucide-react';

// 7-day weather forecast, opened from the weather part of the centre island.
// Zebar's weather provider has no forecast data, so this fetches Open-Meteo
// (free, no key) for the machine's IP-geolocated location (falls back to
// Budapest). Read-only.
interface DayForecast {
  date: string;
  code: number;
  max: number;
  min: number;
}

const DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

function codeIcon(code: number, cls: string) {
  if (code === 0) return <Sun className={cls} />;
  if (code <= 3) return <Cloud className={cls} />;
  if (code === 45 || code === 48) return <CloudFog className={cls} />;
  if (code >= 51 && code <= 57) return <CloudDrizzle className={cls} />;
  if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82))
    return <CloudRain className={cls} />;
  if ((code >= 71 && code <= 77) || code === 85 || code === 86)
    return <CloudSnow className={cls} />;
  if (code >= 95) return <CloudLightning className={cls} />;
  return <Cloud className={cls} />;
}

function App() {
  const [days, setDays] = useState<DayForecast[] | null>(null);
  const [city, setCity] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    zebar.currentWidget().tauriWindow.listen('tauri://blur', () => {
      zebar.currentWidget().close();
    });
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') zebar.currentWidget().close();
    };
    window.addEventListener('keydown', onKey);

    (async () => {
      let lat = 47.4984;
      let lon = 19.0404;
      let name = 'Budapest';
      try {
        const g = await (await fetch('https://ipapi.co/json/')).json();
        if (g.latitude && g.longitude) {
          lat = g.latitude;
          lon = g.longitude;
          name = g.city || name;
        }
      } catch {
        /* fall back to Budapest */
      }
      setCity(name);
      try {
        const url =
          `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}` +
          `&daily=temperature_2m_max,temperature_2m_min,weather_code&timezone=auto&forecast_days=7`;
        const f = await (await fetch(url)).json();
        if (!f.daily) throw new Error('no data');
        setDays(
          f.daily.time.map((t: string, i: number) => ({
            date: t,
            code: f.daily.weather_code[i],
            max: f.daily.temperature_2m_max[i],
            min: f.daily.temperature_2m_min[i],
          }))
        );
      } catch {
        setError('Could not load forecast');
      }
    })();

    return () => window.removeEventListener('keydown', onKey);
  }, []);

  return (
    <div className="h-screen w-screen flex items-start justify-center p-1 font-mono antialiased select-none text-text">
      <div className="w-full rounded-2xl border border-border bg-background-deeper/95 backdrop-blur-xl drop-shadow-lg p-3 flex flex-col gap-1.5">
        <div className="flex items-center justify-between px-1 pb-1.5 border-b border-border">
          <span className="font-semibold">{city || 'Weather'}</span>
          <span className="text-xs text-text-muted">7-day forecast</span>
        </div>

        {error && (
          <div className="text-xs text-danger px-1 py-5 text-center">{error}</div>
        )}
        {!days && !error && (
          <div className="text-xs text-text-muted px-1 py-5 text-center">Loading…</div>
        )}

        {days &&
          days.map((d, i) => {
            const dt = new Date(d.date + 'T00:00');
            const label = i === 0 ? 'Today' : DAY_NAMES[dt.getDay()];
            return (
              <div
                key={d.date}
                className="flex items-center justify-between px-1 py-0.5"
              >
                <span className={'w-14 ' + (i === 0 ? 'font-semibold' : 'text-text-muted')}>
                  {label}
                </span>
                {codeIcon(d.code, 'h-5 w-5 text-icon shrink-0')}
                <span className="flex items-center justify-end gap-2 tabular-nums w-20">
                  <span className="font-semibold">{Math.round(d.max)}°</span>
                  <span className="text-text-muted">{Math.round(d.min)}°</span>
                </span>
              </div>
            );
          })}
      </div>
    </div>
  );
}

export default App;
