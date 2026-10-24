<script setup>
// The frame shared by the signed-out pages (sign in, forgot password).
//
// Left: a compact, light-blue panel that holds the form (the slot).
// Right: a dark, textured brand panel with the logo and a live, animated watch.
// Small screens: a slim dark brand strip on top, the form below.

const CX = 200
const CY = 200

// Where a point sits on the dial: angle in degrees from 12 o'clock, clockwise.
function polar(angle, radius) {
  const rad = (angle * Math.PI) / 180
  return { x: CX + Math.sin(rad) * radius, y: CY - Math.cos(rad) * radius }
}

// ---------- The time the hands start from ----------
// The hands are animated with SVG's own <animateTransform>, so there is no timer
// running in JavaScript. Each hand starts at today's real time and then turns
// at the right speed (60 s, 1 h and 12 h for a full turn).
const now = new Date()
const seconds = now.getSeconds() + now.getMilliseconds() / 1000
const minutes = now.getMinutes() + seconds / 60
const hours = (now.getHours() % 12) + minutes / 60
const start = { second: seconds * 6, minute: minutes * 6, hour: hours * 30 }

// People who prefer reduced motion get the watch standing still at the current time.
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches

// 60 minute marks around the bezel, with a heavier, longer mark every fifth.
const bezelTicks = Array.from({ length: 60 }, (_, i) => {
  const major = i % 5 === 0
  const a = polar(i * 6, major ? 146 : 162)
  const b = polar(i * 6, 178)
  return { major, x1: a.x, y1: a.y, x2: b.x, y2: b.y }
})
</script>

<template>
  <div class="min-h-screen lg:grid lg:grid-cols-[minmax(26rem,32%)_1fr]">
    <!-- Brand strip: small screens only -->
    <header
      class="auth-texture relative flex justify-center border-b border-line px-5 py-6 lg:hidden"
    >
      <img src="/logo.png" alt="VirtuWatch" class="relative z-10 h-12 w-auto" />
    </header>

    <!-- Sign-in panel -->
    <main
      class="auth-light relative flex min-h-[calc(100vh-5.5rem)] items-center justify-center overflow-hidden px-6 py-10 sm:px-10 lg:min-h-screen"
    >
      <!-- Faint bezel arc in the corner, echoing the watch on the other side -->
      <svg
        class="pointer-events-none absolute -left-40 -top-40 hidden h-[420px] w-[420px] text-[#0e1a2b] theme-dark:text-cream lg:block"
        viewBox="0 0 200 200"
        fill="none"
        aria-hidden="true"
      >
        <circle cx="100" cy="100" r="98" stroke="currentColor" stroke-opacity="0.08" />
        <circle cx="100" cy="100" r="76" stroke="currentColor" stroke-opacity="0.06" />
      </svg>

      <div class="relative w-full max-w-sm">
        <slot />
      </div>
    </main>

    <!-- Brand panel: wide screens only -->
    <aside
      class="auth-texture relative hidden flex-col items-center justify-between overflow-hidden border-l border-line px-10 py-10 lg:flex"
      aria-hidden="false"
    >
      <!-- Concentric rings behind the watch -->
      <svg
        class="pointer-events-none absolute inset-0 h-full w-full text-cream"
        viewBox="0 0 1000 1000"
        preserveAspectRatio="xMidYMid slice"
        fill="none"
        aria-hidden="true"
      >
        <circle cx="500" cy="470" r="270" stroke="currentColor" stroke-opacity="0.05" />
        <circle
          cx="500"
          cy="470"
          r="330"
          stroke="currentColor"
          stroke-opacity="0.06"
          stroke-width="3"
          stroke-dasharray="1 11"
          stroke-linecap="round"
        />
        <circle cx="500" cy="470" r="400" stroke="currentColor" stroke-opacity="0.035" />
        <circle cx="500" cy="470" r="500" stroke="currentColor" stroke-opacity="0.03" />
        <circle cx="500" cy="470" r="620" stroke="currentColor" stroke-opacity="0.02" />
      </svg>

      <img src="/logo.png" alt="VirtuWatch" class="relative z-10 w-52" />

      <!-- The watch: bezel marks and three hands, nothing else -->
      <svg
        class="relative z-10 my-4 h-[clamp(260px,calc(100vh-430px),620px)] w-auto"
        viewBox="0 0 400 400"
        role="img"
        aria-label="An analog clock showing the current time"
      >
        <circle :cx="CX" :cy="CY" r="193" fill="none" stroke="#f5f1e8" stroke-opacity="0.2" />
        <circle :cx="CX" :cy="CY" r="132" fill="none" stroke="#f5f1e8" stroke-opacity="0.07" />

        <g stroke="#f5f1e8" stroke-linecap="round">
          <line
            v-for="(t, i) in bezelTicks"
            :key="i"
            :x1="t.x1"
            :y1="t.y1"
            :x2="t.x2"
            :y2="t.y2"
            :stroke-width="t.major ? 2.4 : 1.1"
            :stroke-opacity="t.major ? 0.5 : 0.2"
          />
        </g>

        <!-- Hour hand: one turn every 12 hours -->
        <g :transform="`rotate(${start.hour} ${CX} ${CY})`">
          <animateTransform
            v-if="!reduceMotion"
            attributeName="transform"
            type="rotate"
            :from="`${start.hour} ${CX} ${CY}`"
            :to="`${start.hour + 360} ${CX} ${CY}`"
            dur="43200s"
            repeatCount="indefinite"
          />
          <line :x1="CX" :y1="CY + 10" :x2="CX" :y2="CY - 84" stroke="#f5f1e8" stroke-opacity="0.55" stroke-width="4" stroke-linecap="round" />
        </g>

        <!-- Minute hand: one turn every hour -->
        <g :transform="`rotate(${start.minute} ${CX} ${CY})`">
          <animateTransform
            v-if="!reduceMotion"
            attributeName="transform"
            type="rotate"
            :from="`${start.minute} ${CX} ${CY}`"
            :to="`${start.minute + 360} ${CX} ${CY}`"
            dur="3600s"
            repeatCount="indefinite"
          />
          <line :x1="CX" :y1="CY + 12" :x2="CX" :y2="CY - 124" stroke="#f5f1e8" stroke-opacity="0.55" stroke-width="3" stroke-linecap="round" />
        </g>

        <!-- Second hand: a smooth sweep, one turn every minute -->
        <g :transform="`rotate(${start.second} ${CX} ${CY})`">
          <animateTransform
            v-if="!reduceMotion"
            attributeName="transform"
            type="rotate"
            :from="`${start.second} ${CX} ${CY}`"
            :to="`${start.second + 360} ${CX} ${CY}`"
            dur="60s"
            repeatCount="indefinite"
          />
          <line :x1="CX" :y1="CY + 28" :x2="CX" :y2="CY - 140" stroke="#e8bf6a" stroke-opacity="0.75" stroke-width="1.2" stroke-linecap="round" />
        </g>

        <circle :cx="CX" :cy="CY" r="5" fill="#f5f1e8" fill-opacity="0.7" />
        <circle :cx="CX" :cy="CY" r="2.6" fill="#0e1a2b" />
      </svg>

      <div class="relative z-10 max-w-md text-center">
        <p class="text-3xl font-semibold leading-tight text-cream xl:text-4xl">
          Manage the watches customers try on.
        </p>
        <p class="mt-3 text-sm leading-relaxed text-mist">
          List watches, keep their specs accurate, and see what customers save and view.
        </p>
      </div>
    </aside>
  </div>
</template>

<style>
/* Dark, textured surface: a warm glow, a fine diamond lattice and a darkened edge. */
.auth-texture {
  /* This panel is dark in every look, so it carries its own dark colors. */
  color-scheme: dark;
  --color-ink: #0e1a2b;
  --color-case: #0a1422;
  --color-cream: #f5f1e8;
  --color-mist: #a9b4c4;
  --color-gold: #e8bf6a;
  --color-line: rgb(232 191 106 / 0.14);

  background-color: var(--color-case);
  background-image:
    radial-gradient(55% 45% at 50% 46%, rgb(245 241 232 / 0.05), transparent 70%),
    repeating-linear-gradient(45deg, rgb(245 241 232 / 0.02) 0 1px, transparent 1px 30px),
    repeating-linear-gradient(-45deg, rgb(245 241 232 / 0.02) 0 1px, transparent 1px 30px);
}

.auth-texture::after {
  content: '';
  position: absolute;
  inset: 0;
  pointer-events: none;
  background: radial-gradient(120% 90% at 50% 50%, transparent 55%, rgb(4 9 17 / 0.65) 100%);
}

/*
  The sign-in panel is light blue. The pages inside it are written with the app's
  dark-theme colors (text-cream, text-mist, .input ...), so those color names are
  re-pointed here to light-theme values. Nothing outside this panel is affected.
  In the Dark look the panel is not light blue: it just uses the dark colors.
*/
:root:not([data-theme='dark']) .auth-light {
  color-scheme: light;
  background: linear-gradient(160deg, #eef3fa 0%, #dce6f3 100%);

  --color-cream: #0e1a2b; /* main text */
  --color-mist: #4a5b74; /* secondary text */
  --color-gold: #8c6212; /* links and accents: a deeper gold, readable on light blue */
  --color-gold-light: #6a4a0d;
  --color-dial: #ffffff; /* input background */
  --color-line: rgb(14 26 43 / 0.16);
  --color-slate-700: #d3deec; /* secondary button hover */
}

:root:not([data-theme='dark']) .auth-light .input {
  box-shadow: 0 1px 2px rgb(14 26 43 / 0.06);
}

:root:not([data-theme='dark']) .auth-light .btn-primary {
  background: #0e1a2b;
  color: #f5f1e8;
  box-shadow: 0 10px 22px -10px rgb(14 26 43 / 0.7);
}

:root:not([data-theme='dark']) .auth-light .btn-primary:hover:not(:disabled) {
  background: #1b3050;
}

:root:not([data-theme='dark']) .auth-light .alert-error {
  color: #991b1b;
  background: rgb(220 38 38 / 0.08);
  border-color: rgb(220 38 38 / 0.3);
}

:root:not([data-theme='dark']) .auth-light .alert-success {
  color: #065f46;
  background: rgb(16 185 129 / 0.1);
  border-color: rgb(16 185 129 / 0.35);
}
</style>