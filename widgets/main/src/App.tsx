import { useEffect, useRef, useState } from 'react';
import * as zebar from 'zebar';
import { Chip } from '@overline-zebar/ui';
import { Power } from 'lucide-react';
import { useLhmSensors } from './hooks/useLhmSensors';
import Stats, { diskUsedPct } from './components/stats';
import Media from './components/media';
import UpdateIsland from './components/updates/UpdateIsland';
import Network from './components/network';
import Systray from './components/systray';
import { TimeDisplay } from './components/TimeDisplay';
import Uptime from './components/uptime';
import VolumeControl from './components/volume';
import Weather from './components/weather';

// Redesigned per user request into a transparent bar with three rounded
// "islands" (Chip). Removed: the whole-bar background/blur, CPU & RAM stats,
// the power button, and the GlazeWM-dependent left buttons / workspace /
// window-title widgets (GlazeWM isn't installed). Layout:
//   left   = media
//   centre = time · date · weather (one line -> thin bar)
//   right  = network · volume · systray
// No `date` provider: TimeDisplay drives its own 1s tick, so a date provider
// here would only re-render the whole bar every second for nothing.
const providers = zebar.createProviderGroup({
  media: { type: 'media' },
  network: { type: 'network' },
  weather: { type: 'weather' },
  audio: { type: 'audio' },
  systray: { type: 'systray' },
  host: { type: 'host' },
  cpu: { type: 'cpu' },
  memory: { type: 'memory' },
  disk: { type: 'disk' },
});

// Rolling 5-minute history for the stats graph panel. The bar is the only
// always-running widget, so it does the sampling; the panel just reads this.
// Shared via localStorage, which is same-origin across widgets (the theme
// config already relies on that).
const HISTORY_KEY = 'overline-stats-history';
const HISTORY_WINDOW_MS = 5 * 60 * 1000;
const SAMPLE_MS = 3000;

function App() {
  const [output, setOutput] = useState(providers.outputMap);
  const lhm = useLhmSensors(SAMPLE_MS);

  useEffect(() => {
    providers.onOutput(() => setOutput(providers.outputMap));
  }, []);

  // Keep the newest readings in a ref so the sampler interval below never
  // closes over stale values.
  const latest = useRef({ cpu: 0, ram: 0, gpu: 0, cpuTemp: 0, gpuTemp: 0, disk: 0, up: 0, down: 0 });
  latest.current = {
    cpu: output.cpu?.usage ?? 0,
    ram: output.memory?.usage ?? 0,
    gpu: lhm.gpuLoad ?? 0,
    cpuTemp: lhm.cpuTemp ?? 0,
    gpuTemp: lhm.gpuTemp ?? 0,
    disk: diskUsedPct(output.disk) ?? 0,
    up: output.network?.traffic?.transmitted?.bytes ?? 0,
    down: output.network?.traffic?.received?.bytes ?? 0,
  };

  useEffect(() => {
    const id = setInterval(() => {
      try {
        const raw = localStorage.getItem(HISTORY_KEY);
        const hist: Array<Record<string, number>> = raw ? JSON.parse(raw) : [];
        hist.push({ t: Date.now(), ...latest.current });
        const cutoff = Date.now() - HISTORY_WINDOW_MS;
        localStorage.setItem(
          HISTORY_KEY,
          JSON.stringify(hist.filter((h) => h.t >= cutoff))
        );
      } catch {
        /* history is best-effort */
      }
    }, SAMPLE_MS);
    return () => clearInterval(id);
  }, []);

  const iconClassnames = 'h-3.5 w-3.5 text-icon';

  // Panels open just below the bar, horizontally centred. Clicking the
  // time/date opens the calendar; clicking the weather opens the 7-day forecast.
  const openPanel = async (
    widget: string,
    width: string,
    height: string,
    anchor: 'top_center' | 'top_right' | 'top_left' = 'top_center',
    offsetX = '0px'
  ) => {
    const windowSize = await zebar.currentWidget().tauriWindow.outerSize();
    await zebar.startWidget(
      widget,
      {
        anchor,
        offsetX,
        offsetY: `${windowSize.height + 6}px`,
        width,
        height,
        monitorSelection: { type: 'primary' },
        dockToEdge: { enabled: false, edge: 'top', windowMargin: `${windowSize.height}px` },
      },
      {}
    );
  };
  const openCalendar = () => openPanel('calendar', '300px', '420px');
  const openForecast = () => openPanel('forecast', '260px', '290px');
  // Power menu is anchored right, under the power island.
  const openPower = () => openPanel('power', '220px', '250px', 'top_right', '-8px');
  // Stats graphs are anchored left, under the stats island.
  const openStatsGraph = () =>
    openPanel('stats-graph', '420px', '360px', 'top_left', '8px');
  // Update manager panel, anchored left under the stats/update islands.
  const openUpdatePanel = () =>
    openPanel('update-panel', '360px', '520px', 'top_left', '8px');

  return (
    <div className="relative flex justify-between items-center h-screen px-2 py-1 text-text antialiased select-none font-mono">
      {/* Left: stats island (always present) then media when something plays */}
      <div className="flex items-center h-full z-10 gap-2">
        <Chip
          as="button"
          onClick={openStatsGraph}
          title="System stats - click for 5 minute graphs"
          className="cursor-pointer"
        >
          <Stats
            cpu={output.cpu}
            memory={output.memory}
            network={output.network}
            disk={output.disk}
            lhm={lhm}
          />
        </Chip>
        <UpdateIsland onOpen={openUpdatePanel} />
        <Media media={output.media} />
      </div>

      {/* Centre island: time · date · weather. Click -> calendar.
          inset-y-0 + py-1 matches the bar's own py-1 so this absolutely-
          positioned island is the SAME height as the in-flow side islands. */}
      <div className="absolute inset-y-0 left-1/2 -translate-x-1/2 py-1 flex items-center">
        <Chip className="gap-3 text-base">
          <button
            onClick={openCalendar}
            title="Open calendar"
            className="h-full flex items-center outline-none cursor-pointer"
          >
            <TimeDisplay />
          </button>
          <button
            onClick={openForecast}
            title="7-day forecast"
            className="h-full flex items-center outline-none cursor-pointer"
          >
            <Weather weather={output.weather} />
          </button>
        </Chip>
      </div>

      {/* Right: four separate islands — uptime | volume | network+systray | power */}
      <div className="flex items-center h-full z-10 gap-2">
        <Chip>
          <Uptime host={output.host} />
        </Chip>

        <Chip>
          <VolumeControl audio={output.audio} iconClassnames={iconClassnames} />
        </Chip>

        <Chip className="gap-2.5">
          <Network network={output.network} iconClassnames={iconClassnames} />
          <Systray systray={output.systray} />
        </Chip>

        <Chip
          as="button"
          onClick={openPower}
          title="Power"
          className="cursor-pointer"
        >
          <Power className="h-3.5 w-3.5 text-icon" />
        </Chip>
      </div>
    </div>
  );
}

export default App;
