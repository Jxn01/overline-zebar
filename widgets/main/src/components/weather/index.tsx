import * as zebar from 'zebar';
import { useWidgetSetting } from '@overline-zebar/config';
import Stat from '../stat/Stat';
import { getWeatherIcon } from '../../utils/weatherIcons';

interface WeatherProps {
  weather: zebar.WeatherOutput | null;
}

// Standalone weather indicator (icon + temperature), extracted from the old
// StatProviders bundle so it can live in the centre island next to the clock.
// CPU/RAM were removed per user request; weather is the only stat kept.
export default function Weather({ weather }: WeatherProps) {
  const [weatherThresholds] = useWidgetSetting('main', 'weatherThresholds');
  const [weatherUnit] = useWidgetSetting('main', 'weatherUnit');

  if (!weather) return null;

  const statIconClassnames = 'size-3.5 text-icon';

  return (
    <Stat
      Icon={getWeatherIcon(weather, statIconClassnames)}
      stat={
        weatherUnit === 'celsius'
          ? `${Math.round(weather.celsiusTemp)}°C`
          : `${Math.round(weather.fahrenheitTemp)}°F`
      }
      threshold={weatherThresholds}
      type="inline"
    />
  );
}
