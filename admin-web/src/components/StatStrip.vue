<script setup>
// One panel of headline numbers, divided by hairlines.
// items: [{ label, value, hint?, to? }]. An item with "to" becomes a link.
defineProps({
  items: { type: Array, required: true },
  loading: { type: Boolean, default: false },
})
</script>

<template>
  <!--
    The container's background shows through the 1px gaps between cells,
    which is what draws the hairline dividers.
  -->
  <div
    class="grid grid-cols-1 gap-px overflow-hidden rounded-xl border border-line bg-line sm:[grid-template-columns:repeat(var(--n),minmax(0,1fr))]"
    :style="{ '--n': items.length }"
  >
    <component
      :is="item.to ? 'router-link' : 'div'"
      v-for="item in items"
      :key="item.label"
      :to="item.to"
      class="bg-dial px-6 py-5 transition-colors"
      :class="item.to ? 'hover:bg-slate-700/60' : ''"
    >
      <p class="text-sm text-mist">{{ item.label }}</p>
      <p class="mt-2 text-4xl font-semibold tabular-nums text-cream">
        {{ loading ? '–' : item.value }}
      </p>
      <p v-if="item.hint" class="mt-1 text-xs text-mist">{{ item.hint }}</p>
    </component>
  </div>
</template>