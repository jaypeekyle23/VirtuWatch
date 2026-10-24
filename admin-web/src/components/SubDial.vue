<script setup>
import { computed } from 'vue'

// A watch-bezel gauge: 60 minute marks that light up gold from 12 o'clock,
// clockwise, in proportion to "value" (0 to 1).
const props = defineProps({
  value: { type: Number, default: 0 },
  primary: { type: String, default: '' },
  secondary: { type: String, default: '' },
  // Read aloud by screen readers, since the dial itself is decorative.
  label: { type: String, default: '' },
  loading: { type: Boolean, default: false },
})

const TICKS = 60

const ticks = Array.from({ length: TICKS }, (_, i) => {
  const angle = (i / TICKS) * Math.PI * 2
  const major = i % 5 === 0
  const outer = 96
  const inner = major ? 83 : 89
  return {
    i,
    major,
    x1: 100 + Math.sin(angle) * inner,
    y1: 100 - Math.cos(angle) * inner,
    x2: 100 + Math.sin(angle) * outer,
    y2: 100 - Math.cos(angle) * outer,
  }
})

const litCount = computed(() => {
  if (props.loading) return 0
  const v = Math.min(Math.max(props.value, 0), 1)
  const count = Math.round(v * TICKS)
  // A non-zero value should always show at least one lit mark.
  return v > 0 ? Math.max(count, 1) : 0
})
</script>

<template>
  <div class="relative aspect-square w-full max-w-[220px]" role="img" :aria-label="label">
    <svg viewBox="0 0 200 200" class="h-full w-full" aria-hidden="true">
      <circle
        cx="100"
        cy="100"
        r="99"
        fill="none"
        stroke="currentColor"
        stroke-opacity="0.15"
        stroke-width="0.6"
        class="text-gold"
      />
      <line
        v-for="t in ticks"
        :key="t.i"
        :x1="t.x1"
        :y1="t.y1"
        :x2="t.x2"
        :y2="t.y2"
        stroke="currentColor"
        :stroke-width="t.major ? 2.4 : 1.3"
        stroke-linecap="round"
        :class="t.i < litCount ? 'dial-tick-on text-gold' : 'text-slate-600'"
        :style="t.i < litCount ? { animationDelay: `${t.i * 10}ms` } : undefined"
      />
    </svg>

    <div class="absolute inset-0 flex flex-col items-center justify-center text-center">
      <span class="text-3xl font-semibold tabular-nums text-cream">
        {{ loading ? '–' : primary }}
      </span>
      <span class="mt-0.5 max-w-[110px] text-xs leading-snug text-mist">{{ secondary }}</span>
    </div>
  </div>
</template>

<style scoped>
/* The one animated moment in the app: the marks light up in sequence. */
@keyframes dial-tick-on {
  from {
    opacity: 0.15;
  }
  to {
    opacity: 1;
  }
}

.dial-tick-on {
  animation: dial-tick-on 0.25s ease-out both;
}
</style>