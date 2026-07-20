import { SVGProps } from 'react';

// The official lucide "gpu" glyph - a graphics card with two fans.
//
// Inlined rather than imported: this repo pins lucide-react 0.460, which
// predates the icon (it landed in a later 1.x release), and bumping the whole
// monorepo across a major version for one glyph risks breaking every other
// icon. The path data is copied verbatim from lucide-static's icon-nodes, and
// the svg attributes match lucide's own component output so it renders
// identically to its siblings (Cpu, MemoryStick, HardDrive).
export function GpuIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width={24}
      height={24}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      {...props}
    >
      <path d="M2 17h18a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2H2" />
      <path d="M2 21V3" />
      <path d="M7 17v3a1 1 0 0 0 1 1h5a1 1 0 0 0 1-1v-3" />
      <circle cx="16" cy="11" r="2" />
      <circle cx="8" cy="11" r="2" />
    </svg>
  );
}
