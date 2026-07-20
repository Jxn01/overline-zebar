import { useEffect, useState } from 'react';
import { useWidgetSetting } from '@overline-zebar/config';

// Single-line clock: "HH:mm:ss  yyyy.mm.dd", for the centre island.
//
// This drives its OWN tick with an interval rather than relying on the zebar
// `date` provider. Why: the rendered output is derived from `new Date()`, not
// from a prop, so the React Compiler saw no reactive dependency and memoised
// the component permanently — the clock froze at its first render. Holding the
// current time in state gives the compiler a real dependency (a new Date object
// each second is a new reference), so it re-renders reliably.
export function TimeDisplay() {
  const [timeLocale] = useWidgetSetting('main', 'timeLocale');
  const locale = timeLocale || 'en-GB';

  const [now, setNow] = useState(() => new Date());

  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(id);
  }, []);

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
