import { useCallback, useEffect, useState } from 'react';
import * as zebar from 'zebar';
import type { UpdateStatus } from './status';

const POLL_MS = 60_000;

// Reads the engine's status.json cheaply. `cmd /c type` avoids a ~0.5s pwsh cold-start
// on every poll (fable review #3); reading a local file via shellExec also sidesteps
// Zebar's 7-day service-worker cache (see zebar-overline-build memory).
export function useUpdateStatus() {
  const [status, setStatus] = useState<UpdateStatus | null>(null);

  const read = useCallback(async () => {
    try {
      const res = await zebar.shellExec('cmd', [
        '/c',
        'type',
        '%LOCALAPPDATA%\\overline-updates\\status.json',
      ]);
      const text = (res.stdout ?? '').trim();
      if (!text) {
        setStatus(null);
        return;
      }
      setStatus(JSON.parse(text) as UpdateStatus);
    } catch {
      // missing file / not-yet-run / parse error -> treat as no updates
      setStatus(null);
    }
  }, []);

  useEffect(() => {
    read();
    const id = setInterval(read, POLL_MS);
    const onFocus = () => read();
    window.addEventListener('focus', onFocus);
    return () => {
      clearInterval(id);
      window.removeEventListener('focus', onFocus);
    };
  }, [read]);

  return { status, refresh: read };
}
