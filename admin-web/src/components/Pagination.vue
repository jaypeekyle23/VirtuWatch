<script setup>
import { computed } from 'vue'

// Previous / numbered pages / Next for a long list, plus a "Showing 13–23 of 23"
// line. Draws nothing when everything fits on one page.
const props = defineProps({
  page: { type: Number, required: true },
  totalPages: { type: Number, required: true },
  total: { type: Number, required: true },
  pageSize: { type: Number, required: true },
})
const emit = defineEmits(['update:page'])

const from = computed(() => (props.page - 1) * props.pageSize + 1)
const to = computed(() => Math.min(props.page * props.pageSize, props.total))

// The first and last pages and the ones next to the current page, with a gap
// marker wherever pages are skipped: 1 … 4 5 6 … 12
const items = computed(() => {
  const last = props.totalPages
  const wanted = new Set([1, last, props.page - 1, props.page, props.page + 1])
  const numbers = [...wanted].filter((n) => n >= 1 && n <= last).sort((a, b) => a - b)
  const result = []
  numbers.forEach((n, i) => {
    if (i > 0 && n - numbers[i - 1] > 1) result.push({ gap: true, key: `gap-${n}` })
    result.push({ gap: false, key: n, number: n })
  })
  return result
})

function go(number) {
  if (number < 1 || number > props.totalPages || number === props.page) return
  emit('update:page', number)
  // The new page starts at its first watch, not wherever the buttons were.
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  window.scrollTo({ top: 0, behavior: reduceMotion ? 'auto' : 'smooth' })
}

const pageButton =
  'inline-flex h-9 min-w-9 items-center justify-center border-b px-2.5 text-sm tabular-nums transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gold'
const idle = 'border-transparent text-mist hover:text-cream'
</script>

<template>
  <nav
    v-if="totalPages > 1"
    aria-label="Pagination"
    class="mt-10 flex flex-col items-center justify-between gap-4 border-t border-line pt-6 sm:flex-row"
  >
    <p class="text-sm text-mist" role="status">
      Showing <span class="tabular-nums text-cream">{{ from }}–{{ to }}</span> of
      <span class="tabular-nums text-cream">{{ total }}</span>
    </p>

    <div class="flex items-center gap-1">
      <button
        type="button"
        :class="[pageButton, 'border-transparent text-cream hover:text-gold disabled:cursor-not-allowed disabled:opacity-30 disabled:hover:text-cream']"
        :disabled="page <= 1"
        aria-label="Previous page"
        @click="go(page - 1)"
      >
        ‹
      </button>

      <template v-for="item in items" :key="item.key">
        <span v-if="item.gap" class="px-1 text-mist" aria-hidden="true">…</span>
        <button
          v-else
          type="button"
          :class="[
            pageButton,
            item.number === page ? 'border-gold font-medium text-gold' : idle,
          ]"
          :aria-label="`Page ${item.number}`"
          :aria-current="item.number === page ? 'page' : undefined"
          @click="go(item.number)"
        >
          {{ item.number }}
        </button>
      </template>

      <button
        type="button"
        :class="[pageButton, 'border-transparent text-cream hover:text-gold disabled:cursor-not-allowed disabled:opacity-30 disabled:hover:text-cream']"
        :disabled="page >= totalPages"
        aria-label="Next page"
        @click="go(page + 1)"
      >
        ›
      </button>
    </div>
  </nav>
</template>