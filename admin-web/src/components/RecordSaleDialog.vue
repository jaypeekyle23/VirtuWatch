<script setup>
import { ref, computed, watch as watchValue, nextTick, onMounted, onUnmounted } from 'vue'
import { recordSale, saleErrorMessage } from '../services/salesService'
import { stockOf } from '../utils/stock'
import {
  PAYMENT_METHODS,
  MAX_SALE_QUANTITY,
  MAX_BUYER_LENGTH,
  MAX_NOTES_LENGTH,
  saleTotal,
  formatMoney,
  toDayString,
  soldAtFromDay,
  validateSaleInput,
} from '../utils/sales'

// Lets a merchant record a sale that happened OFF the platform (VirtuWatch has no
// checkout), without leaving the page they are on. Saving writes the sale to the sales
// history and takes the units out of stock in one step (see recordSale).
//
// Emits 'saved' with { watch, quantity, total, stockLeft } once it is stored, and
// 'close' when it should go away (after saving, or on Cancel / Escape / a click outside).
const props = defineProps({
  // The watch being sold, or null while the dialog is closed.
  target: { type: Object, default: null },
})
const emit = defineEmits(['saved', 'close'])

const titleId = `record-sale-title-${Math.random().toString(36).slice(2)}`
const quantityEl = ref(null)

const open = computed(() => props.target !== null)

const quantityText = ref('1')
const priceText = ref('')
const day = ref('')
const paymentMethod = ref('Cash')
const buyerName = ref('')
const notes = ref('')

const saving = ref(false)
const error = ref('')
const submitted = ref(false) // field errors only show after the first Save attempt

const today = ref(toDayString(new Date()))

// A fresh, empty form each time the dialog opens, with the listed price filled in.
watchValue(
  () => props.target,
  async (target) => {
    if (!target) return
    const now = new Date()
    today.value = toDayString(now)
    quantityText.value = '1'
    priceText.value = typeof target.price === 'number' ? String(target.price) : ''
    day.value = today.value
    paymentMethod.value = 'Cash'
    buyerName.value = ''
    notes.value = ''
    error.value = ''
    saving.value = false
    submitted.value = false
    await nextTick()
    quantityEl.value?.focus()
    quantityEl.value?.select()
  },
)

// The watch's count, or null when the merchant never entered one.
const stock = computed(() => (props.target ? stockOf(props.target) : null))

const quantity = computed(() => (quantityText.value === '' ? NaN : Number(quantityText.value)))
const unitPrice = computed(() => {
  const text = priceText.value.replace(/,/g, '').trim()
  return text === '' ? NaN : Number(text)
})

const input = computed(() => ({
  quantity: quantity.value,
  unitPrice: unitPrice.value,
  soldAt: soldAtFromDay(day.value),
  paymentMethod: paymentMethod.value,
  buyerName: buyerName.value,
  notes: notes.value,
}))

const errors = computed(() => validateSaleInput(input.value, stock.value))
const hasErrors = computed(() => Object.keys(errors.value).length > 0)
const shown = (field) => (submitted.value ? errors.value[field] : '')

// What the merchant is about to record, in plain words.
const total = computed(() =>
  Number.isInteger(quantity.value) && Number.isFinite(unitPrice.value)
    ? saleTotal(unitPrice.value, quantity.value)
    : null,
)

const stockNote = computed(() => {
  if (stock.value === null) return "No stock count is on file, so stock won't change."
  if (stock.value === 0) return 'Out of stock. Update the stock first if you still have units.'
  const after = Number.isInteger(quantity.value) ? stock.value - quantity.value : null
  if (after === null || after < 0) return `${stock.value} in stock.`
  return `${stock.value} in stock, ${after} left after this sale.`
})

function onQuantityInput(event) {
  const digits = event.target.value.replace(/\D/g, '').slice(0, String(MAX_SALE_QUANTITY).length)
  quantityText.value = digits
  event.target.value = digits // so a rejected character never flashes in the box
}

// Digits and one decimal point only.
function onPriceInput(event) {
  const cleaned = event.target.value.replace(/[^\d.]/g, '')
  const [whole, ...rest] = cleaned.split('.')
  const value = rest.length ? `${whole}.${rest.join('').slice(0, 2)}` : whole
  priceText.value = value
  event.target.value = value
}

function setQuantity(value) {
  const max = stock.value !== null ? Math.min(stock.value, MAX_SALE_QUANTITY) : MAX_SALE_QUANTITY
  quantityText.value = String(Math.min(Math.max(value, 1), Math.max(max, 1)))
}

function requestClose() {
  if (!saving.value) emit('close')
}

async function save() {
  if (saving.value) return
  submitted.value = true
  if (hasErrors.value) return

  saving.value = true
  error.value = ''
  try {
    const result = await recordSale(props.target.id, input.value)
    emit('saved', {
      watch: props.target,
      quantity: quantity.value,
      total: result.total,
      stockLeft: result.stockLeft,
    })
    emit('close')
  } catch (e) {
    console.error(e)
    error.value = saleErrorMessage(e, 'Could not record the sale. Please try again.')
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
        class="max-h-[92vh] w-full max-w-md overflow-y-auto rounded-xl border border-line bg-dial p-6 shadow-2xl shadow-black/50"
        novalidate
        @submit.prevent="save"
      >
        <h2 :id="titleId" class="font-serif text-2xl font-medium text-cream">Record a sale</h2>
        <p class="mt-1 line-clamp-2 text-sm text-mist">{{ target.name || 'Unnamed watch' }}</p>
        <p class="mt-3 text-xs leading-relaxed text-mist/80">
          For a sale that already happened outside VirtuWatch. It is added to your sales
          history and taken out of stock.
        </p>

        <!-- Quantity -->
        <div class="mt-6">
          <label for="rs-quantity" class="field-label">Quantity sold</label>
          <div class="flex items-center gap-3">
            <button
              type="button"
              class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full border border-line text-xl leading-none text-mist transition-colors hover:text-cream disabled:opacity-40"
              aria-label="One less"
              :disabled="saving || !(quantity > 1)"
              @click="setQuantity((quantity || 1) - 1)"
            >
              −
            </button>
            <input
              id="rs-quantity"
              ref="quantityEl"
              :value="quantityText"
              type="text"
              inputmode="numeric"
              autocomplete="off"
              class="w-20 border-b border-line bg-transparent py-1 text-center font-serif text-3xl tabular-nums text-cream outline-none transition-colors focus:border-gold/70"
              :aria-invalid="!!shown('quantity')"
              :disabled="saving"
              @input="onQuantityInput"
            />
            <button
              type="button"
              class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full border border-line text-xl leading-none text-mist transition-colors hover:text-cream disabled:opacity-40"
              aria-label="One more"
              :disabled="saving || (stock !== null && quantity >= stock) || quantity >= MAX_SALE_QUANTITY"
              @click="setQuantity((quantity || 0) + 1)"
            >
              +
            </button>
          </div>
          <p class="mt-2 text-xs text-mist" role="status">{{ stockNote }}</p>
          <p v-if="shown('quantity')" class="mt-1 text-xs text-red-300">{{ shown('quantity') }}</p>
        </div>

        <!-- Price and total -->
        <div class="mt-5">
          <label for="rs-price" class="field-label">Price per unit (PHP)</label>
          <input
            id="rs-price"
            :value="priceText"
            type="text"
            inputmode="decimal"
            autocomplete="off"
            class="field tabular-nums"
            placeholder="0"
            :aria-invalid="!!shown('unitPrice')"
            :disabled="saving"
            @input="onPriceInput"
          />
          <p v-if="shown('unitPrice')" class="mt-1 text-xs text-red-300">{{ shown('unitPrice') }}</p>
          <p v-else class="mt-1 text-xs text-mist">
            Filled in from your listing. Change it if you sold at a discount.
          </p>
          <p class="mt-3 flex items-baseline justify-between border-t border-line pt-3 text-sm">
            <span class="text-mist">Total</span>
            <span class="font-serif text-2xl tabular-nums text-cream">
              {{ total === null ? '–' : formatMoney(total) }}
            </span>
          </p>
        </div>

        <!-- Date and payment -->
        <div class="mt-5 grid grid-cols-2 gap-5">
          <div>
            <label for="rs-date" class="field-label">Date sold</label>
            <input
              id="rs-date"
              v-model="day"
              type="date"
              :max="today"
              class="field"
              :aria-invalid="!!shown('soldAt')"
              :disabled="saving"
            />
            <p v-if="shown('soldAt')" class="mt-1 text-xs text-red-300">{{ shown('soldAt') }}</p>
          </div>
          <div>
            <label for="rs-payment" class="field-label">Paid via</label>
            <select
              id="rs-payment"
              v-model="paymentMethod"
              class="field"
              :aria-invalid="!!shown('paymentMethod')"
              :disabled="saving"
            >
              <option v-for="method in PAYMENT_METHODS" :key="method" :value="method" class="bg-dial">
                {{ method }}
              </option>
            </select>
          </div>
        </div>

        <!-- Optional details -->
        <div class="mt-5">
          <label for="rs-buyer" class="field-label">Buyer (optional)</label>
          <input
            id="rs-buyer"
            v-model="buyerName"
            type="text"
            autocomplete="off"
            :maxlength="MAX_BUYER_LENGTH"
            class="field"
            placeholder="Name of the buyer"
            :disabled="saving"
          />
        </div>
        <div class="mt-5">
          <label for="rs-notes" class="field-label">Notes (optional)</label>
          <textarea
            id="rs-notes"
            v-model="notes"
            rows="2"
            :maxlength="MAX_NOTES_LENGTH"
            class="field resize-none"
            placeholder="Reference number, meet-up details, etc."
            :disabled="saving"
          ></textarea>
        </div>

        <p v-if="error" class="alert-error mt-5" role="alert">{{ error }}</p>

        <div class="mt-6 flex justify-end gap-3">
          <button type="button" class="btn-secondary" :disabled="saving" @click="requestClose">
            Cancel
          </button>
          <button type="submit" class="btn-primary" :disabled="saving || stock === 0">
            {{ saving ? 'Saving...' : 'Record sale' }}
          </button>
        </div>
      </form>
    </div>
  </Teleport>
</template>
