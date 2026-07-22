import { Chip } from '@overline-zebar/ui';
import { RefreshCw, Package, Box, MonitorDown } from 'lucide-react';
import { useUpdateStatus } from './useUpdateStatus';
import { actionableCount, CHANNELS, type ChannelKey } from './status';

const CHANNEL_ICON: Record<ChannelKey, typeof Package> = {
  scoop: Box,
  winget: Package,
  windowsUpdate: MonitorDown,
};

// Auto-hiding "N updates" island. Renders nothing when there is nothing actionable
// (the same null-return idiom the Media island uses to disappear when idle).
export default function UpdateIsland({ onOpen }: { onOpen: () => void }) {
  const { status } = useUpdateStatus();
  const { total, perChannel } = actionableCount(status);
  if (!total) return null;

  return (
    <Chip
      as="button"
      onClick={onOpen}
      title={`${total} update${total === 1 ? '' : 's'} available — click to manage`}
      className="cursor-pointer gap-2"
    >
      <RefreshCw className="h-3.5 w-3.5 text-icon" />
      <span className="text-text tabular-nums text-sm">{total}</span>
      <span className="flex items-center gap-1">
        {CHANNELS.filter((ch) => perChannel[ch] > 0).map((ch) => {
          const Icon = CHANNEL_ICON[ch];
          return <Icon key={ch} className="h-3 w-3 text-icon/80" />;
        })}
      </span>
    </Chip>
  );
}
