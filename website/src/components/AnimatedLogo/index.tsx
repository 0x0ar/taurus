import React, {useRef, useEffect} from 'react';
import useBaseUrl from '@docusaurus/useBaseUrl';
import styles from './styles.module.css';

// The Taurus logo, painted in layers exactly like the desktop shell does
// (src/quickshell/reusables/display/TaurusLogo.qml): a bull line over a patch of
// cross-hatching that breaks up into fragments. The hatch strokes are real
// polygons, so here they drift and shimmer like water.
const VW = 300;
const VH = 190;
const FADE_MS = 1100;

type Rgb = [number, number, number];
type Particle = {
  pts: number[]; // x0,y0,x1,y1,...
  cx: number;
  cy: number;
  dx: number; // unit vector along the stroke
  dy: number;
  phase: number;
  speed: number;
  amp: number;
  sway: number;
  twinkle: number;
};
type Group = {name: 'base' | 'light' | 'dark'; particles: Particle[]};

function parseCssColor(value: string, fallback: Rgb): Rgb {
  const t = value.trim();
  if (t.startsWith('#')) {
    let hex = t.slice(1);
    if (hex.length === 3) hex = hex.split('').map((c) => c + c).join('');
    if (hex.length >= 6) {
      const n = [0, 2, 4].map((i) => parseInt(hex.slice(i, i + 2), 16));
      if (n.every((v) => !Number.isNaN(v))) return n as Rgb;
    }
  }
  const m = t.match(/rgba?\((\d+)[,\s]+(\d+)[,\s]+(\d+)/);
  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : fallback;
}

// Same as Qt.darker(): divide the HSV value by `factor`.
const darker = (c: Rgb, f: number): Rgb => c.map((v) => Math.round(v / f)) as Rgb;
const css = (c: Rgb, a = 1) => `rgba(${c[0]}, ${c[1]}, ${c[2]}, ${a})`;

// Small deterministic generator so the motion is the same on every load.
function rng(seed: number) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function parseParticles(svg: string, name: Group['name'], seed: number): Particle[] {
  const rand = rng(seed);
  const out: Particle[] = [];
  for (const m of svg.matchAll(/points="([^"]+)"/g)) {
    const pts = m[1].trim().split(/[\s,]+/).map(Number);
    if (pts.length < 6 || pts.some((v) => Number.isNaN(v))) continue;
    let sx = 0;
    let sy = 0;
    const n = pts.length / 2;
    for (let i = 0; i < pts.length; i += 2) {
      sx += pts[i];
      sy += pts[i + 1];
    }
    const cx = sx / n;
    const cy = sy / n;
    // The first edge of every stroke runs along it.
    let dx = pts[2] - pts[0];
    let dy = pts[3] - pts[1];
    const len = Math.hypot(dx, dy) || 1;
    dx /= len;
    dy /= len;
    const loose = name === 'base';
    out.push({
      pts,
      cx,
      cy,
      dx,
      dy,
      // a slow wave travelling across the whole patch, plus a little disorder
      phase: cx * 0.045 + cy * 0.03 + rand() * (loose ? 6.28 : 0.9),
      speed: loose ? 0.7 + rand() * 1.0 : 0.5 + rand() * 0.35,
      amp: loose ? 4 + rand() * 7 : 2.4 + rand() * 3.8,
      sway: loose ? 1.2 + rand() * 2.0 : 0.5 + rand() * 0.8,
      twinkle: rand() * 6.28,
    });
  }
  return out;
}

export default function AnimatedLogo(): React.JSX.Element {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const urls = {
    base: useBaseUrl('/img/logo-layers/base.svg'),
    light: useBaseUrl('/img/logo-layers/light.svg'),
    dark: useBaseUrl('/img/logo-layers/dark.svg'),
    bull: useBaseUrl('/img/logo-layers/bull.svg'),
  };
  const anim = useRef({restart: () => {}});

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    let destroyed = false;
    let frame = 0;
    let start = performance.now();
    let isVisible = true;
    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    let groups: Group[] = [];
    let bullImg: HTMLImageElement | null = null;
    let bullTinted: HTMLCanvasElement | null = null;
    let bullTintKey = '';

    const colors = () => {
      const style = getComputedStyle(document.documentElement);
      const accent = parseCssColor(style.getPropertyValue('--ifm-color-primary'), [0, 230, 118]);
      const text = parseCssColor(style.getPropertyValue('--ifm-font-color-base'), [227, 245, 234]);
      return {
        base: darker(accent, 2.6),
        light: darker(accent, 1.2),
        dark: darker(accent, 1.9),
        bull: text,
      };
    };

    const tintedBull = (w: number, h: number, c: Rgb) => {
      const key = `${w}x${h}:${c.join(',')}`;
      if (bullTinted && key === bullTintKey) return bullTinted;
      if (!bullImg) return null;
      const off = document.createElement('canvas');
      off.width = w;
      off.height = h;
      const octx = off.getContext('2d');
      if (!octx) return null;
      octx.drawImage(bullImg, 0, 0, w, h);
      octx.globalCompositeOperation = 'source-in';
      octx.fillStyle = css(c);
      octx.fillRect(0, 0, w, h);
      bullTinted = off;
      bullTintKey = key;
      return off;
    };

    const draw = (now: number, fade: number, motion: boolean) => {
      const rect = canvas.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      const w = Math.round((rect.width || 520) * dpr);
      const h = Math.round(w * (VH / VW));
      if (canvas.width !== w || canvas.height !== h) {
        canvas.width = w;
        canvas.height = h;
      }
      const ctx = canvas.getContext('2d');
      if (!ctx) return;
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.clearRect(0, 0, w, h);
      const tint = colors();
      const k = w / VW;
      const t = motion ? (now - start) / 1000 : 0;

      ctx.setTransform(k, 0, 0, k, 0, 0);
      for (const g of groups) {
        const col = tint[g.name];
        for (const p of g.particles) {
          const along = Math.sin(t * p.speed + p.phase) * p.amp;
          const across = Math.cos(t * p.speed * 0.7 + p.phase) * p.sway;
          const ox = p.dx * along - p.dy * across;
          const oy = p.dy * along + p.dx * across;
          let a = 1;
          if (g.name === 'base') a = 0.35 + 0.65 * (0.5 + 0.5 * Math.sin(t * 0.9 + p.twinkle));
          else a = 0.8 + 0.2 * Math.sin(t * p.speed * 1.3 + p.twinkle);
          ctx.globalAlpha = a * fade;
          ctx.fillStyle = css(col);
          ctx.beginPath();
          const pts = p.pts;
          ctx.moveTo(pts[0] + ox, pts[1] + oy);
          for (let i = 2; i < pts.length; i += 2) ctx.lineTo(pts[i] + ox, pts[i + 1] + oy);
          ctx.closePath();
          ctx.fill();
        }
      }

      ctx.setTransform(1, 0, 0, 1, 0, 0);
      const bull = tintedBull(w, h, tint.bull);
      if (bull) {
        ctx.globalAlpha = fade;
        ctx.drawImage(bull, 0, 0);
      }
      ctx.globalAlpha = 1;
    };

    const tick = (now: number) => {
      frame = 0;
      if (destroyed) return;
      const fadeT = reducedMotion ? 1 : Math.min(1, (now - start) / FADE_MS);
      draw(now, 1 - Math.pow(1 - fadeT, 3), !reducedMotion);
      if (!reducedMotion && isVisible && !document.hidden) frame = requestAnimationFrame(tick);
    };
    const schedule = () => {
      if (!frame && !destroyed && groups.length && bullImg) frame = requestAnimationFrame(tick);
    };
    anim.current.restart = () => {
      start = performance.now();
      schedule();
    };

    // Load the layers.
    const names: Group['name'][] = ['base', 'light', 'dark'];
    Promise.all(names.map((n) => fetch(urls[n]).then((r) => r.text())))
      .then((texts) => {
        if (destroyed) return;
        groups = names.map((n, i) => ({name: n, particles: parseParticles(texts[i], n, 101 + i * 37)}));
        schedule();
      })
      .catch(() => {});
    const img = new Image();
    img.onload = () => {
      bullImg = img;
      schedule();
    };
    img.src = urls.bull;

    // Re-tint when the theme changes.
    const observer = new MutationObserver(() => {
      bullTinted = null;
      if (reducedMotion && groups.length && bullImg) draw(performance.now(), 1, false);
    });
    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['data-theme', 'data-preview-theme'],
    });

    // Stop animating when the logo is off screen or the tab is hidden.
    const io =
      typeof IntersectionObserver !== 'undefined'
        ? new IntersectionObserver(([entry]) => {
            isVisible = entry.isIntersecting;
            if (isVisible) schedule();
          })
        : null;
    io?.observe(canvas);
    const onVisibility = () => {
      if (!document.hidden) schedule();
    };
    document.addEventListener('visibilitychange', onVisibility);

    return () => {
      destroyed = true;
      if (frame) cancelAnimationFrame(frame);
      observer.disconnect();
      io?.disconnect();
      document.removeEventListener('visibilitychange', onVisibility);
    };
  }, [urls.base, urls.light, urls.dark, urls.bull]);

  return (
    <div className={styles.logoContainer} onClick={() => anim.current.restart()} title="Taurus">
      <canvas ref={canvasRef} className={styles.canvas} width={520} height={329} />
    </div>
  );
}
