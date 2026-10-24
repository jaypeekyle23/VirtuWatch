<script setup>
import { computed } from 'vue'
import { missingWatchFields, fixLocation, isListed } from '../utils/catalogFilters'
import { hero } from '../composables/useHeroTransition'
import { isArReady } from '../utils/arFit'
import { StockStatus, stockOf, stockStatus } from '../utils/stock'
import StockLabel from './StockLabel.vue'

const props = defineProps({
  watch: { type: Object, required: true },
  detailPath: { type: String, required: true },
  editPath: { type: String, required: true },
  // Admin pages pass these in; the merchant catalog leaves them out.
  merchantName: { type: String, default: '' },
  showListToggle: { type: Boolean, default: false },
  // Adds "Update stock" to the actions menu. The merchant catalog turns this on.
  showStockAction: { type: Boolean, default: false },
})

defineEmits(['toggle-listed', 'update-stock', 'delete'])

const thumbnail = computed(() => props.watch.imageUrls?.[0] || props.watch.imageUrl || '')
const missing = computed(() => missingWatchFields(props.watch))

// The "Needs info" link opens the edit form on the first missing field.
const fixTo = computed(() => fixLocation(props.editPath, missing.value[0]))

// A low or out-of-stock watch gets a badge on its photo; an out-of-stock photo is
// also dimmed. Any other watch is drawn as before.
const stock = computed(() => stockStatus(props.watch))
const stockBadge = computed(() => {
  if (stock.value === StockStatus.OUT) return 'Out of stock'
  if (stock.value !== StockStatus.LOW) return ''
  const count = stockOf(props.watch)
  return count === 1 ? 'Only 1 left' : `Only ${count} left`
})

const price = computed(() =>
  props.watch.price == null ? '' : 'PHP ' + Number(props.watch.price).toLocaleString('en-PH'),
)
const size = computed(() =>
  props.watch.caseDiameterMm == null ? '' : `${Number(props.watch.caseDiameterMm).toFixed(1)}mm`,
)

const menuItem = 'block w-full px-4 py-2 text-left text-xs transition-colors hover:bg-dial'
</script>

<template>
  <div
    class="group flex flex-col overflow-hidden rounded-xl bg-dial transition duration-200 hover:-translate-y-0.5"
  >
    <!-- overflow-hidden + an absolutely placed image keep every photo box square. -->
    <router-link :to="detailPath" class="relative block aspect-square overflow-hidden bg-case">
      <img
        v-if="thumbnail"
        v-bind="hero(watch.id)"
        :src="thumbnail"
        :alt="watch.name"
        class="absolute inset-0 h-full w-full object-cover transition-transform duration-300 group-hover:scale-[1.03]"
      />
      <div v-else class="flex h-full w-full items-center justify-center text-sm text-slate-500">
        No photo
      </div>

      <!-- Dim an out-of-stock photo so it reads as unavailable. -->
      <div
        v-if="stock === StockStatus.OUT"
        class="pointer-events-none absolute inset-0 bg-black/40"
        aria-hidden="true"
      ></div>

      <span
        v-if="stockBadge"
        class="absolute bottom-3 left-3 rounded-md px-2 py-1 text-[10px] font-bold uppercase tracking-[0.12em]"
        :class="stock === StockStatus.OUT ? 'bg-red-700 text-white' : 'bg-amber-400 text-black/85'"
      >
        {{ stockBadge }}
      </span>

      <span
        v-if="isArReady(watch)"
        class="absolute left-3 top-3 rounded-full bg-ink/80 px-2.5 py-1 text-[10px] font-medium uppercase tracking-[0.18em] text-gold backdrop-blur-sm"
      >
        AR
      </span>
    </router-link>

    <div class="flex flex-1 flex-col p-4">
      <p class="eyebrow truncate text-[10px]">{{ watch.brand || 'No brand' }}</p>

      <!-- Always two lines tall, so prices and footers line up across a row. -->
      <router-link
        :to="detailPath"
        class="mt-1 line-clamp-2 min-h-10 text-sm font-medium leading-5 text-cream transition-colors hover:text-gold"
      >
        {{ watch.name }}
      </router-link>

      <p v-if="merchantName" class="mt-1 truncate text-xs text-mist">{{ merchantName }}</p>

      <p class="mt-3 text-sm tabular-nums">
        <span class="font-semibold text-cream">{{ price || '–' }}</span>
        <span v-if="size" class="text-mist"> · {{ size }}</span>
      </p>

      <!-- mt-auto pins the footer to the bottom, so cards in a row line up. -->
      <div class="mt-auto pt-4">
        <div class="flex items-center justify-between gap-2 border-t border-line pt-3">
          <div class="flex min-w-0 items-center gap-3">
            <span class="eyebrow" :class="isListed(watch) ? 'text-cream' : 'text-mist/70'">
              {{ isListed(watch) ? 'Listed' : 'Draft' }}
            </span>
            <router-link
              v-if="missing.length"
              :to="fixTo"
              :title="`Missing: ${missing.join(', ')}. Select to add it.`"
              :aria-label="`Add missing ${missing.join(', ').toLowerCase()} for ${watch.name}`"
              class="truncate text-[10px] font-medium uppercase tracking-[0.18em] text-gold transition-colors hover:text-gold-light"
            >
              Needs info
            </router-link>
          </div>

          <StockLabel
            v-if="stock !== StockStatus.UNTRACKED"
            :watch="watch"
            short
            class="ml-auto min-w-0 truncate text-right text-[11px] font-semibold"
          />

          <!-- Actions menu: opens on hover or keyboard focus, no extra state needed. -->
          <div class="group/menu relative shrink-0">
            <button
              type="button"
              class="rounded-md px-1.5 text-lg leading-none tracking-widest text-mist transition-colors hover:text-cream"
              aria-label="More actions"
              aria-haspopup="menu"
            >
              ···
            </button>
            <div
              class="invisible absolute bottom-full right-0 z-10 pb-2 opacity-0 transition group-focus-within/menu:visible group-focus-within/menu:opacity-100 group-hover/menu:visible group-hover/menu:opacity-100"
            >
              <div class="w-36 rounded-lg border border-line bg-case py-1.5 shadow-lg shadow-black/40">
                <button
                  v-if="showListToggle"
                  type="button"
                  :class="[menuItem, 'text-cream']"
                  @click="$emit('toggle-listed', watch)"
                >
                  {{ isListed(watch) ? 'Unlist' : 'List' }}
                </button>
                <router-link :to="editPath" :class="[menuItem, 'text-cream']">Edit</router-link>
                <button
                  v-if="showStockAction"
                  type="button"
                  :class="[menuItem, 'text-cream']"
                  @click="$emit('update-stock', watch)"
                >
                  Update stock
                </button>
                <button
                  type="button"
                  :class="[menuItem, 'text-red-300']"
                  @click="$emit('delete', watch)"
                >
                  Delete
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>