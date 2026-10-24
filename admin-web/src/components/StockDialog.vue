<script setup>
import { ref, computed, watch as watchValue, nextTick, onMounted, onUnmounted } from 'vue'
import { updateWatch } from '../services/watchService'
import { MAX_STOCK, stockOf, merchantStockLabel } from '../utils/stock'

// Lets a merchant change one watch's stock count without opening the full edit
// form. Port of showStockDialog in lib/widgets/stock_badge.dart.
//
// The dialog saves by itself. It emits 'saved' once the new count is stored, and
// 'close' when it should go away (after saving, or on Cancel / Escape / a click outside).
const props = defineProps({
  // The watch being edited, or null while the dialog is closed.
  target: { type: Object, default: null },
})
const emit = defineEmits(['saved', 'close'])

const titleId = `stock-dialog-title-${Math.random().toString(36).slice(2)}`
const inputEl = ref(null)
const text = ref('')
const saving = ref(false)
const error = ref('')

const open = computed(() => props.target !== null)

// A fresh count each time the dialog opens. A watch with no count starts at 0.
watchValue(
  () => props.target,
  async (target) => {
    if (!target) return
    text.value = String(stockOf(target) ?? 0)
    error.value = ''
    saving.value = false
    await nextTick()
    inputEl.value?.focus()
    inputEl.value?.select()
  },
)

// Digits only, at most five of them, same as the app's number box.
function onInput(event) {
  const digits = event.target.value.replace(/\D/g, '').slice(0, String(MAX_STOCK).length)
  text.value = digits
  event.target.value = digits // so a rejected character never flashes in the box
}

const count = computed(() => (text.value === '' ? null : Number(text.value)))

function setCount(value) {
  text.value = String(Math.min(Math.max(value, 0), MAX_STOCK))
}

// "Low: 2 left" and so on, so the merchant sees what customers will be told.
const preview = computed(() => (count.value === null ? null : merchantStockLabel({ stock: count.value })))

function requestClose() {
  if (!saving.value) emit('close')
}

async function save() {
  if (count.value === null || saving.value) return
  saving.value = true
  error.value = ''
  try {
    await updateWatch(props.target.id, { stock: count.value })
    emit('saved', { watch: props.target, stock: count.value })
    emit('close')
  } catch (e) {
    console.error(e)
    error.value = 'Could not save the new count. Please try again.'
  } finally {
    saving.value = false
  }
}

function onKeydown(event) {
  if (event.key === 'Escape' && open.value) requestClose()
}

onMounted(() => window.addEventListener('keydown', onKeydown))
onUnmounted(() => window.removeEventListener('keydown', onKeydown))
</script>

<template>
  <Teleport to="body">
    <div
      v-if="open"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/65 p-4"
      @click.self="requestClose"
    >
      <form
        role="dialog"
        aria-modal="true"
        :aria-labelledby="titleId"
        class="w-full max-w-sm rounded-xl border border-line bg-dial p-6 shadow-2xl shadow-black/50"
        novalidate
        @submit.prevent="save"
      >
        <h2 :id="titleId" class="font-serif text-2xl font-medium text-cream">Update stock</h2>
        <p class="mt-1 line-clamp-2 text-sm text-mist">{{ target.name || 'Unnamed watch' }}</p>

        <div class="mt-6 flex items-center justify-center gap-3">
          <button
            type="button"
            class="flex h-10 w-10 items-center justify-center rounded-full border border-line text-xl leading-none text-mist transition-colors hover:text-cream disabled:opacity-40"
            aria-label="One less"
            :disabled="saving || (count ?? 0) <= 0"
            @click="setCount((count ?? 0) - 1)"
          >
            −
          </button>
          <input
            ref="inputEl"
            :value="text"
            type="text"
            inputmode="numeric"
            autocomplete="off"
            aria-label="Units in stock"
            class="w-24 border-b border-line bg-transparent py-1 text-center font-serif text-4xl tabular-nums text-cream outline-none transition-colors focus:border-gold/70"
            :disabled="saving"
            @input="onInput"
          />
          <button
            type="button"
            class="flex h-10 w-10 items-center justify-center rounded-full border border-line text-xl leading-none text-mist transition-colors hover:text-cream disabled:opacity-40"
            aria-label="One more"
            :disabled="saving || (count ?? 0) >= MAX_STOCK"
            @click="setCount((count ?? 0) + 1)"
          >
            +
          </button>
        </div>

        <p class="mt-3 h-4 text-center text-xs text-mist" role="status">{{ preview }}</p>

        <div class="mt-2 text-center">
          <button
            type="button"
            class="eyebrow text-gold transition-colors hover:text-gold-light disabled:opacity-40"
            :disabled="saving"
            @click="setCount(0)"
          >
            Mark as out of stock
          </button>
        </div>

        <p v-if="error" class="alert-error mt-4" role="alert">{{ error }}</p>

        <div class="mt-6 flex justify-end gap-3">
          <button type="button" class="btn-secondary" :disabled="saving" @click="requestClose">
            Cancel
          </button>
          <button type="submit" class="btn-primary" :disabled="saving || count === null">
            {{ saving ? 'Saving...' : 'Save' }}
          </button>
        </div>
      </form>
    </div>
  </Teleport>
</template>
