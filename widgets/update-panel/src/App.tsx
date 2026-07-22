import { useEffect, useState, type ReactNode } from 'react';
import * as zebar from 'zebar';
import {
  RefreshCw, ChevronRight, ChevronDown, MousePointer2, RotateCcw,
  EyeOff, Loader2, Check, X, Search,
} from 'lucide-react';
import { useUpdatePanel, type RowState } from './useUpdatePanel';
import { CHANNELS, CHANNEL_LABEL, channelItems, driverItems, type ChannelKey, type UpdateItem } from './status';

// Popups require focused:true so tauri://blur fires; also close on Escape.
function useClose() {
  useEffect(() => {
    const w = zebar.currentWidget();
    w.tauriWindow.listen('tauri://blur', () => w.close());
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') w.close();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);
}

const badge = 'text-[10px] px-1.5 py-0.5 rounded-md border border-border/60 text-icon/80';

function RowStatusIcon({ st }: { st?: RowState }) {
  if (!st) return null;
  if (st.state === 'updating') return <Loader2 className="h-3.5 w-3.5 animate-spin text-icon" />;
  if (st.state === 'done') return <Check className="h-3.5 w-3.5 text-[#a3be8c]" />;
  return <X className="h-3.5 w-3.5 text-[#bf616a]" />;
}

function ItemRow({ it, st, onUpdate, onHide }: { it: UpdateItem; st?: RowState; onUpdate: () => void; onHide: () => void }) {
  return (
    <div className="flex items-center gap-2 px-2 py-1.5 rounded-lg hover:bg-white/5">
      <div className="flex-1 min-w-0">
        <div className="truncate text-text text-xs">{it.name}</div>
        <div className="truncate text-[10px] text-icon/60">{(it.current || '—') + ' → ' + (it.available || 'latest')}</div>
        <div className="flex flex-wrap gap-1 mt-0.5">
          {it.interactive === 'yes' && (
            <span className={badge}><MousePointer2 className="inline h-2.5 w-2.5" /> interactive</span>
          )}
          {it.driverClass === 'display' && <span className="text-[10px] px-1.5 py-0.5 rounded-md border border-[#d08770]/60 text-[#d08770]">may replace vendor driver</span>}
          {it.rebootHint && <span className={badge}><RotateCcw className="inline h-2.5 w-2.5" /> reboot</span>}
        </div>
      </div>
      <RowStatusIcon st={st} />
      <button onClick={onHide} title="Hide this update" className="p-1 text-icon/60 hover:text-text"><EyeOff className="h-3.5 w-3.5" /></button>
      <button onClick={onUpdate} className="text-[11px] px-2 py-1 rounded-md border border-border hover:border-button-border text-text">Update</button>
    </div>
  );
}

function Group({ title, count, onUpdateAll, defaultOpen, children }: { title: string; count: number; onUpdateAll?: () => void; defaultOpen?: boolean; children: ReactNode }) {
  const [open, setOpen] = useState(!!defaultOpen);
  if (!count) return null;
  return (
    <div className="rounded-xl border border-border/60 overflow-hidden">
      <div className="flex items-center gap-2 px-2 py-1.5 bg-white/5">
        <button onClick={() => setOpen(!open)} className="flex items-center gap-1 flex-1 text-left text-text text-xs">
          {open ? <ChevronDown className="h-3.5 w-3.5" /> : <ChevronRight className="h-3.5 w-3.5" />}
          {title} <span className="text-icon/60">({count})</span>
        </button>
        {onUpdateAll && (
          <button onClick={onUpdateAll} className="text-[11px] px-2 py-0.5 rounded-md border border-border hover:border-button-border text-text">Update all</button>
        )}
      </div>
      {open && <div className="p-1 space-y-0.5">{children}</div>}
    </div>
  );
}

export default function App() {
  useClose();
  const p = useUpdatePanel();
  const { status, ignore, rows } = p;

  const perChannel = CHANNELS.map((ch) => ({ ch, items: channelItems(status, ch) }));
  const drivers = driverItems(status);
  const total = perChannel.reduce((n, c) => n + c.items.length, 0) + drivers.length;
  const hidden = [
    ...(ignore?.skipVersion ?? []).map((e) => ({ channel: e.channel as ChannelKey, id: e.id, kind: 'version' })),
    ...(ignore?.ignorePackage ?? []).map((e) => ({ channel: e.channel as ChannelKey, id: e.id, kind: 'package' })),
  ];

  return (
    <div className="h-screen w-screen p-2 text-text antialiased font-mono select-none">
      <div className="h-full flex flex-col rounded-2xl border border-border bg-background-deeper/95 backdrop-blur-xl drop-shadow-lg overflow-hidden">
        <div className="flex items-center gap-2 px-3 py-2 border-b border-border/60">
          <RefreshCw className="h-4 w-4 text-icon" />
          <div className="flex-1 text-sm">{total + ' update' + (total === 1 ? '' : 's') + ' available'}</div>
          <button disabled={p.busy} onClick={() => p.checkNow()} title="Check now" className="p-1 text-icon/70 hover:text-text disabled:opacity-40"><Search className="h-3.5 w-3.5" /></button>
          <button disabled={p.busy || total === 0} onClick={() => p.updateAll(false)} className="text-[11px] px-2 py-1 rounded-md border border-border hover:border-button-border disabled:opacity-40 text-text">Update everything</button>
        </div>
        {p.notice && <div className="px-3 py-1 text-[11px] text-icon/70">{p.notice}</div>}

        <div className="flex-1 overflow-y-auto p-2 space-y-2">
          {total === 0 && <div className="text-center text-icon/60 text-xs py-10">Everything is up to date.</div>}
          {perChannel.map(({ ch, items }) => (
            <Group key={ch} title={CHANNEL_LABEL[ch]} count={items.length} onUpdateAll={() => p.updateChannel(ch)} defaultOpen>
              {items.map((it) => (
                <ItemRow key={it.id} it={it} st={rows[it.id]} onUpdate={() => p.updateItem(it)} onHide={() => p.hide(it)} />
              ))}
            </Group>
          ))}
          <Group title="Windows Update — drivers" count={drivers.length} onUpdateAll={() => p.updateDrivers()}>
            {drivers.map((it) => (
              <ItemRow key={it.id} it={it} st={rows[it.id]} onUpdate={() => p.updateItem(it)} onHide={() => p.hide(it)} />
            ))}
          </Group>
          {hidden.length > 0 && (
            <Group title="Hidden" count={hidden.length} defaultOpen={false}>
              {hidden.map((h, i) => (
                <div key={i} className="flex items-center gap-2 px-2 py-1.5 text-xs">
                  <div className="flex-1 truncate text-icon/70">{h.id} <span className="text-[10px] text-icon/50">({h.kind})</span></div>
                  <button onClick={() => p.unhide(h.channel, h.id)} className="text-[11px] px-2 py-0.5 rounded-md border border-border hover:border-button-border text-text">Un-hide</button>
                </div>
              ))}
            </Group>
          )}
        </div>
      </div>
    </div>
  );
}
