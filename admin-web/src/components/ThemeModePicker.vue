<script setup>
import { THEME_MODES, themeMode, themeInfo, setThemeMode } from '../composables/useTheme'
</script>

<template>
  <div>
    <div class="flex flex-wrap gap-2" role="group" aria-label="Appearance">
      <button
        v-for="mode in THEME_MODES"
        :key="mode.value"
        type="button"
        class="rounded-full border px-4 py-2 text-[13px] transition-colors"
        :class="
          themeMode === mode.value
            ? 'border-cream bg-cream/10 text-cream'
            : 'border-cream/25 text-mist hover:text-cream'
        "
        :aria-pressed="themeMode === mode.value"
        @click="setThemeMode(mode.value)"
      >
        {{ mode.label }}
      </button>
    </div>
    <p class="mt-2.5 text-xs text-mist" aria-live="polite">{{ themeInfo.description }}</p>
  </div>
</template>
