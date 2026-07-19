import { useState } from 'react';
import { SystrayIcon, SystrayOutput } from 'zebar';
import { ExpandingCarousel } from './components/ExpandingCarousel';
import { SystrayItem } from './components/SystrayItem';
import { useWidgetSetting } from '@overline-zebar/config';

type SystrayProps = {
  systray: SystrayOutput | null;
};

function arrangeIconsWithPinnedCenter(
  pinnedIcons: string[],
  icons: SystrayIcon[]
) {
  const pinnedHashes = pinnedIcons;

  const pinned = icons
    .filter((icon) => pinnedHashes.includes(icon.iconHash))
    .sort(
      (a, b) =>
        pinnedHashes.indexOf(a.iconHash) - pinnedHashes.indexOf(b.iconHash)
    );

  const others = icons
    .filter((icon) => !pinnedHashes.includes(icon.iconHash))
    .sort((a, b) => a.tooltip.localeCompare(b.tooltip));

  const half = Math.ceil(others.length / 2);
  return [...others.slice(0, half), ...pinned, ...others.slice(half)];
}

export default function Systray({ systray }: SystrayProps) {
  if (!systray) return;
  const icons = systray.icons;

  const [expanded, setExpanded] = useState(false);

  // Toggle icon expansion on Shift+Click
  const handleClick = (e: React.MouseEvent) => {
    if (e.shiftKey) {
      e.preventDefault();
      setExpanded(!expanded);
    }
  };

  const [pinnedSystrayIcons] = useWidgetSetting('main', 'pinnedSystrayIcons');

  // Show ALL captured tray icons (no carousel clipping), per user request —
  // a complete, GNOME-style tray. Zebar captures every icon (incl. Windows
  // overflow); overline previously capped the visible count at 4.
  const arrangedIcons = arrangeIconsWithPinnedCenter(pinnedSystrayIcons, icons);
  const visibleCount = Math.max(4, icons.length);
  const startIndex = 0;

  const systrayIcons = arrangedIcons.map((item) => (
    <SystrayItem key={item.id} systray={systray} icon={item} />
  ));

  return (
    <div className="flex items-center gap-1.5" onClick={handleClick}>
      <ExpandingCarousel
        items={systrayIcons}
        expanded={expanded}
        gap={4}
        itemWidth={16}
        visibleCount={visibleCount}
        startIndex={startIndex}
      />
    </div>
  );
}
