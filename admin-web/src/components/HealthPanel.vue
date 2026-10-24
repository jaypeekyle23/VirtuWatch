<script setup>
import SubDial from './SubDial.vue'

// A titled panel with a sub-dial and a short list of things that need attention.
// items: [{ count, label, hint, to }]. Only pass items with a count above zero.
defineProps({
  title: { type: String, required: true },
  subtitle: { type: String, default: '' },
  value: { type: Number, default: 0 },
  primary: { type: String, default: '' },
  secondary: { type: String, default: '' },
  dialLabel: { type: String, default: '' },
  loading: { type: Boolean, default: false },
  items: { type: Array, default: () => [] },
  allGoodText: { type: String, default: 'Nothing needs attention.' },
})
</script>

<template>
  <section class="rounded-xl border border-line bg-dial p-6">
    <h2 class="text-lg font-semibold text-cream">{{ title }}</h2>
    <p v-if="subtitle" class="mt-1 text-sm text-mist">{{ subtitle }}</p>

    <div class="mt-6 flex justify-center">
      <SubDial
        :value="value"
        :primary="primary"
        :secondary="secondary"
        :label="dialLabel"
        :loading="loading"
      />
    </div>

    <ul v-if="items.length" class="mt-6 divide-y divide-line border-t border-line">
      <li v-for="item in items" :key="item.label">
        <router-link
          :to="item.to"
          class="-mx-2 flex items-start justify-between gap-4 rounded-lg px-2 py-3 transition-colors hover:bg-slate-700/40"
        >
          <div class="min-w-0">
            <p class="text-sm font-medium text-cream">{{ item.label }}</p>
            <p class="mt-0.5 text-xs text-mist">{{ item.hint }}</p>
          </div>
          <span class="text-sm font-semibold tabular-nums text-gold">{{ item.count }}</span>
        </router-link>
      </li>
    </ul>

    <p v-else-if="!loading" class="mt-6 border-t border-line pt-4 text-sm text-mist">
      {{ allGoodText }}
    </p>
  </section>
</template>