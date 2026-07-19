import { useEffect, useState } from 'react';
import * as zebar from 'zebar';
import { Chip } from '@overline-zebar/ui';
import Media from './components/media';
import Network from './components/network';
import Systray from './components/systray';
import { TimeDisplay } from './components/TimeDisplay';
import VolumeControl from './components/volume';
import Weather from './components/weather';

// Redesigned per user request into a transparent bar with three rounded
// "islands" (Chip). Removed: the whole-bar background/blur, CPU & RAM stats,
// the power button, and the GlazeWM-dependent left buttons / workspace /
// window-title widgets (GlazeWM isn't installed). Layout:
//   left   = media
//   centre = time · date · weather (one line -> thin bar)
//   right  = network · volume · systray
const providers = zebar.createProviderGroup({
  media: { type: 'media' },
  network: { type: 'network' },
  date: { type: 'date', formatting: 'EEE d MMM t', locale: 'en-GB' },
  weather: { type: 'weather' },
  audio: { type: 'audio' },
  systray: { type: 'systray' },
});

function App() {
  const [output, setOutput] = useState(providers.outputMap);

  useEffect(() => {
    providers.onOutput(() => setOutput(providers.outputMap));
  }, []);

  const iconClassnames = 'h-3.5 w-3.5 text-icon';

  return (
    <div className="relative flex justify-between items-center h-screen px-2 py-1 text-text antialiased select-none font-mono">
      {/* Left island: media */}
      <div className="flex items-center h-full z-10">
        <Media media={output.media} />
      </div>

      {/* Centre island: time · date · weather */}
      <div className="absolute left-1/2 -translate-x-1/2 h-full flex items-center">
        <Chip className="gap-3">
          <TimeDisplay dateOutput={output.date} />
          <Weather weather={output.weather} />
        </Chip>
      </div>

      {/* Right island: network · volume · systray */}
      <div className="flex items-center h-full z-10">
        <Chip className="gap-2.5">
          <Network network={output.network} iconClassnames={iconClassnames} />
          <VolumeControl audio={output.audio} iconClassnames={iconClassnames} />
          <Systray systray={output.systray} />
        </Chip>
      </div>
    </div>
  );
}

export default App;
