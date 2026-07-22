// Mirrors the engine's status.json + ignore.json (see engine/UpdateEngine.psm1).

export type Scope = 'user' | 'machine';
export type Interactive = 'yes' | 'no' | 'unknown';
export type DriverClass = 'display' | 'input' | 'audio' | 'other' | null;
export type ChannelKey = 'scoop' | 'winget' | 'windowsUpdate';

export const CHANNELS: ChannelKey[] = ['scoop', 'winget', 'windowsUpdate'];
export const CHANNEL_LABEL: Record<ChannelKey, string> = {
  scoop: 'Scoop',
  winget: 'winget',
  windowsUpdate: 'Windows Update',
};

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

export interface IgnoreStore {
  skipVersion: { channel: ChannelKey; id: string; version: string }[];
  ignorePackage: { channel: ChannelKey; id: string }[];
}

export function isActionable(it: UpdateItem): boolean {
  return !it.suspectStale;
}

// Items shown in a channel group: actionable, non-driver. Drivers get their own sub-group.
export function channelItems(status: UpdateStatus | null, ch: ChannelKey): UpdateItem[] {
  return (status?.channels?.[ch]?.items ?? []).filter((it) => isActionable(it) && !it.driver);
}

export function suspectItems(status: UpdateStatus | null, ch: ChannelKey): UpdateItem[] {
  return (status?.channels?.[ch]?.items ?? []).filter((it) => it.suspectStale);
}

export function driverItems(status: UpdateStatus | null): UpdateItem[] {
  return (status?.channels?.windowsUpdate?.items ?? []).filter((it) => isActionable(it) && it.driver);
}
