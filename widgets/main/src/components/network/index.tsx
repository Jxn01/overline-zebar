import { NetworkOutput } from 'zebar';
import { Cable, Unplug, Wifi } from 'lucide-react';

interface NetworkProps {
  network: NetworkOutput | null;
  iconClassnames?: string;
}

// Network system indicator (GNOME-style). Windows renders network as a shell
// element that a tray-spy cannot capture, so we surface it from Zebar's own
// `network` provider instead. Ethernet -> cable, Wi-Fi -> wifi (+ SSID
// tooltip), nothing -> unplugged.
export default function Network({
  network,
  iconClassnames = 'h-3.5 w-3.5 text-icon',
}: NetworkProps) {
  if (!network) return null;

  const connected = !!network.defaultInterface;
  let Icon = Unplug;
  let label = 'Disconnected';

  if (connected) {
    if (network.type === 'wifi') {
      Icon = Wifi;
      label = network.ssid ? `Wi-Fi: ${network.ssid}` : 'Wi-Fi';
    } else if (network.type === 'ethernet') {
      Icon = Cable;
      label = 'Ethernet';
    } else {
      Icon = Cable;
      label = 'Connected';
    }
  }

  return (
    <div className="flex items-center h-full" title={label}>
      <Icon className={iconClassnames} />
    </div>
  );
}
