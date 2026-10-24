<script setup>
import { computed } from 'vue'
import { StockStatus, stockOf, stockStatus, merchantStockLabel } from '../utils/stock'

// A watch's stock, in the colors the app uses: red when out, amber when low.
// Shows a dash when no count is on file.
//
//   default  "12 in stock", "Low: 2 left", "Out of stock" (list rows)
//   short    "Stock 12" (the footer of a card, where space is tight)
const props = defineProps({
  watch: { type: Object, required: true },
  short: { type: Boolean, default: false },
})

const status = computed(() => stockStatus(props.watch))

const text = computed(() => {
  if (status.value === StockStatus.UNTRACKED) return '–'
  return props.short ? `Stock ${stockOf(props.watch)}` : merchantStockLabel(props.watch)
})

const toneClass = computed(() => {
  switch (status.value) {
    case StockStatus.OUT:
      return 'text-red-300'
    case StockStatus.LOW:
      return 'text-amber-300'
    case StockStatus.IN_STOCK:
      return 'text-mist'
    default:
      return 'text-mist/60'
  }
})
</script>

<template>
  <span class="tabular-nums" :class="toneClass">{{ text }}</span>
</template>
