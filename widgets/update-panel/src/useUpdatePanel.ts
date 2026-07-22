import { useCallback, useEffect, useState } from 'react';
import * as zebar from 'zebar';
import type { UpdateStatus, IgnoreStore, ChannelKey, UpdateItem } from './status';

// SECURITY: package ids/versions come from winget/scoop/WU output and must never be spliced
// into a shell string. We resolve %LOCALAPPDATA% once via cmd (pwsh does not expand %VAR%),
// then invoke everything as shellExec/shellSpawn(program, [args...]) — args passed as a real
// argv array, not a shell string — so those values cannot inject commands.
let rootAbs: string | null = null;
async function root(): Promise<string> {
  if (rootAbs) return rootAbs;
  const res = await zebar.shellExec('cmd', ['/c', 'echo %LOCALAPPDATA%']);
  rootAbs = `${(res.stdout ?? '').trim()}\\overline-updates`;
  return rootAbs;
}
const PWSH = ['-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File'];

async function readJson<T>(file: string): Promise<T | null> {
  try {
    const res = await zebar.shellExec('cmd', ['/c', 'type', `${await root()}\\${file}`]);
    const t = (res.stdout ?? '').trim();
    return t ? (JSON.parse(t) as T) : null;
  } catch {
    return null;
  }
}
async function readText(abs: string): Promise<string> {
  try {
    return (await zebar.shellExec('cmd', ['/c', 'type', abs])).stdout ?? '';
  } catch {
    return '';
  }
}
async function runScript(file: string, args: string[]): Promise<void> {
  await zebar.shellExec('pwsh', [...PWSH, `${await root()}\\engine\\${file}`, ...args]);
}
async function spawnScript(file: string, args: string[]): Promise<void> {
  await zebar.shellSpawn('pwsh', [...PWSH, `${await root()}\\engine\\${file}`, ...args]);
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
    async (args: string[]) => {
      if (busy) return;
      setBusy(true);
      setNotice('');
      setRows({});
      const runId = Math.random().toString(36).slice(2, 10);
      const runLog = `${await root()}\\run-${runId}.log`;
      try {
        await spawnScript('apply.ps1', [...args, '-RunId', runId]);
      } catch {
        /* spawn failure surfaces as an empty log below */
      }
      const start = Date.now();
      for (;;) {
        await new Promise((res) => setTimeout(res, 800));
        const lines = (await readText(runLog)).split(/\r?\n/);
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

  const updateAll = useCallback((drivers = false) => runApply(drivers ? ['-All', '-IncludeDrivers'] : ['-All']), [runApply]);
  const updateChannel = useCallback((ch: ChannelKey) => runApply(['-Channel', ch]), [runApply]);
  const updateDrivers = useCallback(() => runApply(['-Channel', 'windowsUpdate', '-IncludeDrivers']), [runApply]);
  const updateItem = useCallback((it: UpdateItem) => runApply(['-Ids', it.id]), [runApply]);

  const checkNow = useCallback(async () => {
    if (busy) return;
    setBusy(true);
    setNotice('checking…');
    await runScript('check.ps1', []);
    await reload();
    setNotice('');
    setBusy(false);
  }, [busy, reload]);

  const hide = useCallback(
    async (it: UpdateItem, pkg = false) => {
      const args = pkg
        ? ['-Action', 'ignorePkg', '-Channel', it.channel, '-Id', it.id]
        : ['-Action', 'skip', '-Channel', it.channel, '-Id', it.id, '-Version', it.available || '0'];
      await runScript('ignore.ps1', args);
      await runScript('check.ps1', []);
      await reload();
    },
    [reload]
  );

  const unhide = useCallback(
    async (channel: ChannelKey, id: string) => {
      await runScript('ignore.ps1', ['-Action', 'unhide', '-Channel', channel, '-Id', id]);
      await runScript('check.ps1', []);
      await reload();
    },
    [reload]
  );

  return { status, ignore, rows, busy, notice, reload, updateAll, updateChannel, updateDrivers, updateItem, checkNow, hide, unhide };
}
