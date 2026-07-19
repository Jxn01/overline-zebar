import { useWidgetSetting } from '@overline-zebar/config';
import { DateOutput } from 'zebar';

interface TimeDisplayProps {
  dateOutput: DateOutput | null;
}

// Single-line clock: "HH:mm:ss  yyyy.mm.dd", for the centre island.
// Re-renders on each date-provider tick (dateOutput changes).
export function TimeDisplay({ dateOutput }: TimeDisplayProps) {
  const [timeLocale] = useWidgetSetting('main', 'timeLocale');
  const locale = timeLocale || 'en-GB';

  void dateOutput;
  const now = new Date();

  let time: string;
  try {
    time = new Intl.DateTimeFormat(locale, {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false,
    }).format(now);
  } catch {
    time = now.toLocaleTimeString();
  }

  const yyyy = now.getFullYear();
  const mm = String(now.getMonth() + 1).padStart(2, '0');
  const dd = String(now.getDate()).padStart(2, '0');
  const date = `${yyyy}.${mm}.${dd}`;

  return (
    <div className="h-full flex items-center justify-center gap-2 tabular-nums">
      <span className="font-semibold">{time}</span>
      <span className="text-text-muted">{date}</span>
    </div>
  );
}
