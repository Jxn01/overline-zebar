import { useCallback, useEffect, useState } from 'react';
import * as zebar from 'zebar';
import type { UpdateStatus, IgnoreStore, ChannelKey, UpdateItem } from './status';

// Everything is launched through `cmd /c` so %LOCALAPPDATA% expands (pwsh does not expand
// %VAR%). apply.ps1 writes STATUS lines + a DONE sentinel to run-<id>.log, which we tail.
// No double-quotes in these command strings: cmd /c mangles embedded quotes, and the engine
// paths under %LOCALAPPDATA%\overline-updates contain no spaces, so quoting is unnecessary.
const ROOT = '%LOCALAPPDATA%\\overline-updates';
const ENG = `${ROOT}\\engine`;
const PWSH = (file: string, args: string) =>
  `pwsh -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ${ENG}\\${file} ${args}`;

async function cmd(command: string): Promise<string> {
  const res = await zebar.shellExec('cmd', ['/c', command]);
  return res.stdout ?? '';
}
async function readJson<T>(file: string): Promise<T | null> {
  try {
    const t = (await cmd(`type ${ROOT}\\${file}`)).trim();
    return t ? (JSON.parse(t) as T) : null;
  } catch {
    return null;
  }
}

export type RowState = { state: 'updating' | 'done' | 'failed'; detail?: string };

export function useUpdatePanel() {
  const [status, setStatus] = useState<UpdateStatus | null>(null);
  const [ignore, setIgnore] = useState<IgnoreStore | null>(null);
  const [rows, setRows] = useState<Record<string, RowState>>({});
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState('');

  const reload = useCallback(async () => {
    setStatus(await readJson<UpdateStatus>('status.json'));
    setIgnore(await readJson<IgnoreStore>('ignore.json'));
  }, []);
  useEffect(() => {
    reload();
  }, [reload]);

  const runApply = useCallback(
    async (args: string) => {
      if (busy) return;
      setBusy(true);
      setNotice('');
      setRows({});
      const runId = Math.random().toString(36).slice(2, 10);
      const runLog = `${ROOT}\\run-${runId}.log`;
      try {
        await zebar.shellSpawn('cmd', ['/c', PWSH('apply.ps1', `${args} -RunId ${runId}`)]);
      } catch {
        /* spawn failure shows as an empty log below */
      }
      const start = Date.now();
      for (;;) {
        await new Promise((r) => setTimeout(r, 800));
        let text = '';
        try {
          text = await cmd(`type ${runLog}`);
        } catch {
          text = '';
        }
        const lines = text.split(/\r?\n/);
        const next: Record<string, RowState> = {};
        for (const ln of lines) {
          let m = ln.match(/^STATUS (\S+) updating/);
          if (m) next[m[1]] = { state: 'updating' };
          m = ln.match(/^STATUS (\S+) done/);
          if (m) next[m[1]] = { state: 'done' };
          m = ln.match(/^STATUS (\S+) failed (.*)/);
          if (m) next[m[1]] = { state: 'failed', detail: m[2] };
        }
        setRows(next);
        if (lines.some((l) => /^DONE /.test(l))) break;
        if (Date.now() - start > 20 * 60 * 1000) {
          setNotice('timed out');
          break;
        }
      }
      await reload();
      setBusy(false);
    },
    [busy, reload]
  );

  const script = useCallback(async (file: string, args: string) => {
    try {
      await cmd(PWSH(file, args));
    } catch {
      /* best-effort */
    }
  }, []);

  const updateAll = useCallback((drivers = false) => runApply(drivers ? '-All -IncludeDrivers' : '-All'), [runApply]);
  const updateChannel = useCallback((ch: ChannelKey) => runApply(`-Channel ${ch}`), [runApply]);
  const updateDrivers = useCallback(() => runApply('-Channel windowsUpdate -IncludeDrivers'), [runApply]);
  const updateItem = useCallback((it: UpdateItem) => runApply(`-Ids ${it.id}`), [runApply]);

  const checkNow = useCallback(async () => {
    if (busy) return;
    setBusy(true);
    setNotice('checking…');
    await script('check.ps1', '');
    await reload();
    setNotice('');
    setBusy(false);
  }, [busy, reload, script]);

  const hide = useCallback(
    async (it: UpdateItem, pkg = false) => {
      const a = pkg
        ? `-Action ignorePkg -Channel ${it.channel} -Id ${it.id}`
        : `-Action skip -Channel ${it.channel} -Id ${it.id} -Version ${it.available || '0'}`;
      await script('ignore.ps1', a);
      await script('check.ps1', '');
      await reload();
    },
    [script, reload]
  );

  const unhide = useCallback(
    async (channel: ChannelKey, id: string) => {
      await script('ignore.ps1', `-Action unhide -Channel ${channel} -Id ${id}`);
      await script('check.ps1', '');
      await reload();
    },
    [script, reload]
  );

  return { status, ignore, rows, busy, notice, reload, updateAll, updateChannel, updateDrivers, updateItem, checkNow, hide, unhide };
}
