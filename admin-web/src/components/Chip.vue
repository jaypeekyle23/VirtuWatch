<script setup>
import { computed } from 'vue'

// A small status pill. tone: success | neutral | warn | gold | danger
const props = defineProps({
  tone: { type: String, default: 'neutral' },
})

const TONES = {
  success: 'bg-emerald-400/15 text-emerald-300',
  neutral: 'bg-slate-700 text-mist',
  warn: 'bg-amber-400/15 text-amber-300',
  gold: 'bg-gold/15 text-gold',
  danger: 'bg-red-400/15 text-red-300',
}

const toneClass = computed(() => TONES[props.tone] ?? TONES.neutral)
</script>

<template>
  <span
    class="inline-flex items-center whitespace-nowrap rounded-full px-2.5 py-0.5 text-xs font-medium"
    :class="toneClass"
  >
    <slot />
  </span>
</template>