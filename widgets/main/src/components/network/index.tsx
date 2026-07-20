import * as zebar from 'zebar';
import { NetworkOutput } from 'zebar';
import { Cable, Unplug, Wifi } from 'lucide-react';

interface NetworkProps {
  network: NetworkOutput | null;
  iconClassnames?: string;
}

// Network system indicator (GNOME-style). Windows renders network as a shell
// element that a tray-spy cannot capture, so we surface it from Zebar's own
// `network` provider instead. Ethernet -> cable, Wi-Fi -> wifi (+ SSID
// tooltip), nothing -> unplugged. Click opens Windows network settings
// (needs `explorer` in the widget's zpack shellCommands privileges).
export default function Network({
  network,
  iconClassnames = 'h-3.5 w-3.5 text-icon',
}: NetworkProps) {
  if (!network) return null;

  // NOTE: type lives on defaultInterface, NOT on NetworkOutput itself.
  // Reading network.type gave undefined and always fell through to "Connected".
  const iface = network.defaultInterface;
  const connected = !!iface;
  let Icon = Unplug;
  let label = 'Disconnected';

  if (iface) {
    if (iface.type === 'wifi') {
      Icon = Wifi;
      label = iface.friendlyName ? `Wi-Fi: ${iface.friendlyName}` : 'Wi-Fi';
    } else if (iface.type === 'ethernet') {
      Icon = Cable;
      label = iface.friendlyName ?? 'Ethernet';
    } else {
      Icon = Cable;
      label = iface.friendlyName ?? 'Connected';
    }
  }
  void connected;

  const openNetworkSettings = () => {
    zebar.shellSpawn('explorer', ['ms-settings:network-status']).catch(() => {});
  };

  return (
    <button
      className="flex items-center h-full outline-none"
      title={`${label} — click for network settings`}
      onClick={openNetworkSettings}
    >
      <Icon className={iconClassnames} />
    </button>
  );
}
