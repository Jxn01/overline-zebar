import { useEffect, useState } from 'react';
import * as zebar from 'zebar';
import { Lock, LogOut, Moon, Power, RotateCcw } from 'lucide-react';

// Power menu opened from the power island. Four actions, each a single shell
// command. Destructive actions (shutdown/restart) ask for confirmation first,
// so a stray click can't end the session.
//
// NOTE on Sleep: `rundll32 powrprof.dll,SetSuspendState 0,1,0` is NOT sleep —
// rundll32 passes the arguments wrongly, and Windows HIBERNATES whenever
// hibernation is enabled (it is on this machine). A hibernated Windows leaves
// its NTFS volumes, the shared drive included, unsafe for the Linux dual-boot.
// So Sleep calls the real API through pwsh:
// Application.SetSuspendState(Suspend, force=false, disableWakeEvent=false).
type Action = {
  id: string;
  label: string;
  Icon: typeof Power;
  program: string;
  args: string[];
  confirm: boolean;
  danger?: boolean;
};

const ACTIONS: Action[] = [
  {
    id: 'lock',
    label: 'Lock',
    Icon: Lock,
    program: 'rundll32',
    args: ['user32.dll,LockWorkStation'],
    confirm: false,
  },
  {
    // True S3 sleep, never hibernate — see the note at the top.
    id: 'sleep',
    label: 'Sleep',
    Icon: Moon,
    program: 'pwsh',
    args: [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.Application]::SetSuspendState('Suspend', $false, $false)",
    ],
    confirm: false,
  },
  {
    id: 'restart',
    label: 'Restart',
    Icon: RotateCcw,
    program: 'shutdown',
    args: ['/r', '/t', '0'],
    confirm: true,
    danger: true,
  },
  {
    id: 'shutdown',
    label: 'Shut down',
    Icon: Power,
    program: 'shutdown',
    args: ['/s', '/t', '0'],
    confirm: true,
    danger: true,
  },
];

function App() {
  const [pending, setPending] = useState<string | null>(null);

  useEffect(() => {
    zebar.currentWidget().tauriWindow.listen('tauri://blur', () => {
      zebar.currentWidget().close();
    });
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') zebar.currentWidget().close();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const run = (a: Action) => {
    if (a.confirm && pending !== a.id) {
      setPending(a.id);
      return;
    }
    zebar.shellSpawn(a.program, a.args).catch(() => {});
    zebar.currentWidget().close();
  };

  return (
    <div className="h-screen w-screen flex items-start justify-center p-1 font-mono antialiased select-none text-text">
      <div className="w-full rounded-2xl border border-border bg-background-deeper/95 backdrop-blur-xl drop-shadow-lg p-2 flex flex-col gap-1">
        {ACTIONS.map((a) => {
          const armed = pending === a.id;
          return (
            <button
              key={a.id}
              onClick={() => run(a)}
              className={
                'flex items-center gap-3 px-3 py-2 rounded-xl outline-none text-left transition-colors ' +
                (armed ? 'bg-danger/20' : 'hover:bg-button')
              }
            >
              <a.Icon
                className={'h-4 w-4 ' + (a.danger ? 'text-danger' : 'text-icon')}
              />
              <span className={armed ? 'text-danger font-semibold' : ''}>
                {armed ? `Click again to ${a.label.toLowerCase()}` : a.label}
              </span>
            </button>
          );
        })}
        <button
          onClick={() => zebar.currentWidget().close()}
          className="flex items-center gap-3 px-3 py-2 rounded-xl outline-none text-left hover:bg-button text-text-muted"
        >
          <LogOut className="h-4 w-4 text-icon" />
          <span>Cancel</span>
        </button>
      </div>
    </div>
  );
}

export default App;
