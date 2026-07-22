// Types mirror the engine's status.json (see engine/UpdateEngine.psm1 New-UpdateItem
// and docs/superpowers/specs/2026-07-22-update-island-design.md §5). Kept in sync by hand.

export type Scope = 'user' | 'machine';
export type Interactive = 'yes' | 'no' | 'unknown';
export type DriverClass = 'display' | 'input' | 'audio' | 'other' | null;
export type ChannelKey = 'scoop' | 'winget' | 'windowsUpdate';

export const CHANNELS: ChannelKey[] = ['scoop', 'winget', 'windowsUpdate'];

export interface UpdateItem {
  channel: ChannelKey;
  id: string;
  name: string;
  current: string;
  available: string;
  scope: Scope;
  interactive: Interactive;
  driver: boolean;
  driverClass: DriverClass;
  rebootHint: boolean;
  suspectStale: boolean;
}

export interface ChannelResult {
  checkedAt: string;
  stale: boolean;
  error: string | null;
  items: UpdateItem[];
}

export interface UpdateStatus {
  generatedAt: string;
  wingetLocked: boolean;
  channels: Record<ChannelKey, ChannelResult>;
}

// Actionable = not a suspected false-positive. Drivers ARE counted (decision 2026-07-22);
// pinned/ignored items never reach status.json (the engine drops them at check time).
export function isActionable(it: UpdateItem): boolean {
  return !it.suspectStale;
}

export function actionableCount(status: UpdateStatus | null): {
  total: number;
  perChannel: Record<ChannelKey, number>;
} {
  const perChannel: Record<ChannelKey, number> = { scoop: 0, winget: 0, windowsUpdate: 0 };
  if (!status) return { total: 0, perChannel };
  let total = 0;
  for (const ch of CHANNELS) {
    const n = (status.channels?.[ch]?.items ?? []).filter(isActionable).length;
    perChannel[ch] = n;
    total += n;
  }
  return { total, perChannel };
}
