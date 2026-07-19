import { useEffect, useState } from 'react';
import * as zebar from 'zebar';
import {
  ChevronLeft,
  ChevronRight,
  Cloud,
  CloudLightning,
  CloudRain,
  CloudSnow,
  Moon,
  Sun,
  Wind,
} from 'lucide-react';
import type { WeatherOutput, WeatherStatus } from 'zebar';

// Calendar panel opened from the centre island of the main bar. Read-only —
// a month view + a weather summary (Zebar's weather data is limited to temp /
// wind / condition / day-night, so this surfaces all of it). No events.
const providers = zebar.createProviderGroup({
  date: { type: 'date', formatting: 'yyyy', locale: 'en-GB' },
  weather: { type: 'weather' },
});

const WEEKDAYS = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
const MONTHS = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

function weatherIcon(status: WeatherStatus | undefined, cls: string) {
  switch (status) {
    case 'clear_day': return <Sun className={cls} />;
    case 'clear_night': return <Moon className={cls} />;
    case 'light_rain_day':
    case 'light_rain_night':
    case 'heavy_rain_day':
    case 'heavy_rain_night': return <CloudRain className={cls} />;
    case 'snow_day':
    case 'snow_night': return <CloudSnow className={cls} />;
    case 'thunder_day':
    case 'thunder_night': return <CloudLightning className={cls} />;
    default: return <Cloud className={cls} />;
  }
}

function statusLabel(status: WeatherStatus | undefined) {
  if (!status) return '';
  return status
    .replace(/_(day|night)$/, '')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

function App() {
  const [output, setOutput] = useState(providers.outputMap);
  const [view, setView] = useState(() => {
    const d = new Date();
    return { year: d.getFullYear(), month: d.getMonth() };
  });

  useEffect(() => {
    providers.onOutput(() => setOutput(providers.outputMap));
    // Dismiss when the panel loses focus (click elsewhere) or on Escape.
    zebar.currentWidget().tauriWindow.listen('tauri://blur', () => {
      zebar.currentWidget().close();
    });
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') zebar.currentWidget().close();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const weather = output.weather as WeatherOutput | null;
  const today = new Date();
  const { year, month } = view;

  const firstWeekday = (new Date(year, month, 1).getDay() + 6) % 7; // Monday-first
  const daysInMonth = new Date(year, month + 1, 0).getDate();

  const cells: (number | null)[] = [];
  for (let i = 0; i < firstWeekday; i++) cells.push(null);
  for (let d = 1; d <= daysInMonth; d++) cells.push(d);
  // Always pad to 6 rows (42 cells) so every month is the same height and the
  // window never clips the last row (e.g. a month that starts on Sat/Sun).
  while (cells.length < 42) cells.push(null);

  const isToday = (d: number) =>
    d === today.getDate() &&
    month === today.getMonth() &&
    year === today.getFullYear();

  const prevMonth = () =>
    setView((v) =>
      v.month === 0 ? { year: v.year - 1, month: 11 } : { year: v.year, month: v.month - 1 }
    );
  const nextMonth = () =>
    setView((v) =>
      v.month === 11 ? { year: v.year + 1, month: 0 } : { year: v.year, month: v.month + 1 }
    );

  return (
    <div className="h-screen w-screen flex items-start justify-center p-1 font-mono antialiased select-none text-text">
      <div className="w-full rounded-2xl border border-border bg-background-deeper/95 backdrop-blur-xl drop-shadow-lg p-3 flex flex-col gap-3">
        {/* Weather summary */}
        {weather && (
          <div className="flex items-center justify-between px-1 pb-1 border-b border-border">
            <div className="flex items-center gap-2">
              {weatherIcon(weather.status, 'h-6 w-6 text-icon')}
              <div className="flex flex-col leading-none">
                <span className="text-lg font-semibold">
                  {Math.round(weather.celsiusTemp)}°C
                </span>
                <span className="text-xs text-text-muted">
                  {Math.round(weather.fahrenheitTemp)}°F
                </span>
              </div>
            </div>
            <div className="flex flex-col items-end leading-tight gap-1">
              <span className="text-xs text-text-muted">
                {statusLabel(weather.status)}
              </span>
              <span className="text-xs text-text-muted flex items-center gap-1">
                <Wind className="h-3 w-3" />
                {Math.round(weather.windSpeed)} km/h
              </span>
            </div>
          </div>
        )}

        {/* Month navigation */}
        <div className="flex items-center justify-between">
          <button onClick={prevMonth} className="p-1 rounded-lg hover:bg-button outline-none">
            <ChevronLeft className="h-4 w-4" />
          </button>
          <span className="font-semibold">
            {MONTHS[month]} {year}
          </span>
          <button onClick={nextMonth} className="p-1 rounded-lg hover:bg-button outline-none">
            <ChevronRight className="h-4 w-4" />
          </button>
        </div>

        {/* Weekday header */}
        <div className="grid grid-cols-7 gap-1 text-center text-xs text-text-muted">
          {WEEKDAYS.map((w) => (
            <div key={w}>{w}</div>
          ))}
        </div>

        {/* Day cells */}
        <div className="grid grid-cols-7 gap-1 text-center text-sm">
          {cells.map((d, i) => (
            <div key={i} className="aspect-square flex items-center justify-center">
              {d && (
                <span
                  className="flex items-center justify-center h-7 w-7 rounded-full font-bold"
                  style={
                    isToday(d)
                      ? { backgroundColor: 'var(--text)', color: 'var(--background)' }
                      : undefined
                  }
                >
                  {d}
                </span>
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

export default App;
