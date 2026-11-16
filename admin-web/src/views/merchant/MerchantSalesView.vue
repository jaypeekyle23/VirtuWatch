<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { currentUser } from '../../composables/useAuth'
import { showToast } from '../../composables/useToast'
import { listenToMySales, voidSale, saleErrorMessage } from '../../services/salesService'
import {
  PAYMENT_METHODS,
  DATE_PRESETS,
  MAX_VOID_REASON_LENGTH,
  isVoided,
  filterSales,
  sortSalesNewestFirst,
  salesTotals,
  salesToCsv,
  presetRange,
  saleDate,
  toDayString,
  formatMoney,
} from '../../utils/sales'
import { pageCount } from '../../utils/catalogFilters'
import PageHeader from '../../components/PageHeader.vue'
import Pagination from '../../components/Pagination.vue'
import ConfirmDialog from '../../components/ConfirmDialog.vue'

const PAGE_SIZE = 20

const sales = ref([])
const loading = ref(true)
const errorMessage = ref('')
let stopListening = null

onMounted(() => {
  stopListening = listenToMySales(
    currentUser.value.uid,
    (list) => {
      sales.value = list
      loading.value = false
    },
    (err) => {
      console.error(err)
      errorMessage.value = 'Could not load your sales history.'
      loading.value = false
    },
  )
})

onUnmounted(() => {
  if (stopListening) stopListening()
})

// ---------- Search and filters ----------

const search = ref('')
const preset = ref('all') // 'all' | 'month' | 'last30' | 'year' | 'custom'
const from = ref('')
const to = ref('')
const paymentMethod = ref('')
const includeVoided = ref(false)
const page = ref(1)

function choosePreset(value) {
  preset.value = value
  const range = presetRange(value)
  from.value = range.from
  to.value = range.to
}

// Typing a date by hand leaves the quick ranges.
function onDateEdited() {
  preset.value = 'custom'
}

const filtersActive = computed(
  () => !!(search.value || from.value || to.value || paymentMethod.value || includeVoided.value),
)

function clearFilters() {
  search.value = ''
  paymentMethod.value = ''
  includeVoided.value = false
  choosePreset('all')
}

const visibleSales = computed(() =>
  sortSalesNewestFirst(
    filterSales(sales.value, {
      search: search.value,
      from: from.value,
      to: to.value,
      paymentMethod: paymentMethod.value,
      includeVoided: includeVoided.value,
    }),
  ),
)

// The headline numbers follow the filters, so "This month" shows this month's revenue.
const totals = computed(() => salesTotals(visibleSales.value))

const totalPages = computed(() => pageCount(visibleSales.value.length, PAGE_SIZE))
const currentPage = computed(() => Math.min(page.value, totalPages.value))
const pagedSales = computed(() => {
  const start = (currentPage.value - 1) * PAGE_SIZE
  return visibleSales.value.slice(start, start + PAGE_SIZE)
})

// Any change to what is shown goes back to page 1.
watch([search, from, to, paymentMethod, includeVoided], () => {
  page.value = 1
})

const subtitle = computed(() => {
  if (loading.value) return ''
  const all = sales.value.filter((s) => !isVoided(s)).length
  if (!all) return 'Sales you record will appear here.'
  return totals.value.count === all
    ? `${all} ${all === 1 ? 'sale' : 'sales'} recorded`
    : `${totals.value.count} of ${all} sales`
})

const stats = computed(() => [
  { label: 'Revenue', value: formatMoney(totals.value.revenue) },
  { label: 'Units sold', value: totals.value.units.toLocaleString('en-PH') },
  { label: 'Sales', value: totals.value.count.toLocaleString('en-PH') },
])

// ---------- Display helpers ----------

const dateFormat = new Intl.DateTimeFormat('en-PH', { year: 'numeric', month: 'short', day: 'numeric' })
function formatDay(sale) {
  const date = saleDate(sale)
  return date ? dateFormat.format(date) : '–'
}

// ---------- Export ----------

function exportCsv() {
  if (!visibleSales.value.length) return
  const blob = new Blob([salesToCsv(visibleSales.value)], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = `virtuwatch-sales-${toDayString(new Date())}.csv`
  document.body.appendChild(link)
  link.click()
  link.remove()
  URL.revokeObjectURL(url)
  showToast('success', `Exported ${visibleSales.value.length} ${visibleSales.value.length === 1 ? 'sale' : 'sales'}.`)
}

// ---------- Voiding ----------

const voidTarget = ref(null)
const voidReason = ref('')
const voiding = ref(false)
const voidError = ref('')

function askVoid(sale) {
  voidReason.value = ''
  voidError.value = ''
  voidTarget.value = sale
}

function cancelVoid() {
  if (voiding.value) return
  voidTarget.value = null
}

async function confirmVoid() {
  voiding.value = true
  voidError.value = ''
  try {
    const { restored } = await voidSale(voidTarget.value.id, voidReason.value)
    showToast(
      'success',
      restored ? 'Sale voided. The units are back in stock.' : 'Sale voided.',
    )
    voidTarget.value = null
  } catch (e) {
    console.error(e)
    voidError.value = saleErrorMessage(e, 'Could not void the sale. Please try again.')
  } finally {
    voiding.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-[88rem]">
    <PageHeader title="Sales history" :subtitle="subtitle">
      <template #actions>
        <button
          type="button"
          class="btn-secondary"
          :disabled="!visibleSales.length"
          @click="exportCsv"
        >
          Export CSV
        </button>
        <router-link to="/merchant/catalog" class="btn-primary">Record a sale</router-link>
      </template>
    </PageHeader>

    <p v-if="errorMessage" class="alert-error mt-6" role="alert">{{ errorMessage }}</p>

    <p v-else-if="loading" class="mt-10 text-sm text-mist">Loading...</p>

    <!-- Nothing recorded yet -->
    <div v-else-if="!sales.length" class="mt-10 border-y border-line py-16 text-center">
      <p class="font-serif text-2xl text-cream">No sales recorded yet</p>
      <p class="mx-auto mt-2 max-w-md text-sm text-mist">
        VirtuWatch doesn't take payments, so when you sell a watch (in person, by message or
        online), record it from your catalog. It is saved here and the stock goes down
        with it.
      </p>
      <router-link to="/merchant/catalog" class="btn-primary mt-6">Go to my catalog</router-link>
    </div>

    <template v-else>
      <!-- Headline numbers for what is filtered -->
      <div class="mt-10 grid grid-cols-3 divide-x divide-line border-y border-line">
        <div v-for="s in stats" :key="s.label" class="px-2 py-8 text-center">
          <p class="font-serif text-3xl font-medium tabular-nums text-cream sm:text-5xl">
            {{ s.value }}
          </p>
          <p class="eyebrow mt-3">{{ s.label }}</p>
        </div>
      </div>
      <p v-if="totals.voided > 0" class="mt-3 text-xs text-mist">
        {{ totals.voided }} voided {{ totals.voided === 1 ? 'sale is' : 'sales are' }} shown below
        and left out of these totals.
      </p>

      <!-- Search and filters -->
      <div class="mt-8 space-y-5">
        <div class="flex flex-wrap items-end gap-x-6 gap-y-4">
          <div class="min-w-[14rem] flex-1">
            <label for="sales-search" class="field-label">Search</label>
            <input
              id="sales-search"
              v-model="search"
              type="search"
              autocomplete="off"
              class="field"
              placeholder="Watch, brand, buyer or note"
            />
          </div>
          <div>
            <label for="sales-from" class="field-label">From</label>
            <input
              id="sales-from"
              v-model="from"
              type="date"
              :max="to || undefined"
              class="field"
              @input="onDateEdited"
            />
          </div>
          <div>
            <label for="sales-to" class="field-label">To</label>
            <input
              id="sales-to"
              v-model="to"
              type="date"
              :min="from || undefined"
              class="field"
              @input="onDateEdited"
            />
          </div>
          <div>
            <label for="sales-payment" class="field-label">Paid via</label>
            <select id="sales-payment" v-model="paymentMethod" class="field">
              <option value="" class="bg-dial">Any method</option>
              <option v-for="m in PAYMENT_METHODS" :key="m" :value="m" class="bg-dial">{{ m }}</option>
            </select>
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-x-6 gap-y-3">
          <div class="flex flex-wrap items-center gap-x-5 gap-y-2" role="group" aria-label="Date range">
            <button
              v-for="p in DATE_PRESETS"
              :key="p.value"
              type="button"
              class="eyebrow transition-colors hover:text-cream"
              :class="preset === p.value ? '!text-gold' : ''"
              :aria-pressed="preset === p.value"
              @click="choosePreset(p.value)"
            >
              {{ p.label }}
            </button>
          </div>
          <label class="flex items-center gap-2 text-xs text-mist">
            <input v-model="includeVoided" type="checkbox" class="accent-[var(--color-gold)]" />
            Show voided sales
          </label>
          <button
            v-if="filtersActive"
            type="button"
            class="eyebrow text-gold transition-colors hover:text-gold-light"
            @click="clearFilters"
          >
            Clear filters
          </button>
        </div>
      </div>

      <!-- Filters match nothing -->
      <div v-if="!visibleSales.length" class="mt-8 border-y border-line py-16 text-center">
        <p class="text-cream">No sales match your search or filters.</p>
        <button
          type="button"
          class="eyebrow mt-4 text-gold transition-colors hover:text-gold-light"
          @click="clearFilters"
        >
          Clear filters
        </button>
      </div>

      <!-- The history -->
      <div v-else class="mt-8 overflow-x-auto">
        <table class="w-full text-left text-sm">
          <thead class="border-y border-line">
            <tr class="eyebrow">
              <th class="px-4 py-3 font-medium">Date</th>
              <th class="px-4 py-3 font-medium">Watch</th>
              <th class="px-4 py-3 text-right font-medium">Qty</th>
              <th class="px-4 py-3 text-right font-medium">Unit price</th>
              <th class="px-4 py-3 text-right font-medium">Total</th>
              <th class="px-4 py-3 font-medium">Paid via</th>
              <th class="px-4 py-3 font-medium">Buyer</th>
              <th class="px-4 py-3 text-right font-medium"><span class="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody class="divide-y divide-line border-b border-line">
            <tr
              v-for="sale in pagedSales"
              :key="sale.id"
              class="align-top transition-colors hover:bg-dial/40"
              :class="isVoided(sale) ? 'opacity-60' : ''"
            >
              <td class="whitespace-nowrap px-4 py-3 text-mist">{{ formatDay(sale) }}</td>
              <td class="px-4 py-3">
                <div class="flex items-center gap-4">
                  <img
                    v-if="sale.watchImageUrl"
                    :src="sale.watchImageUrl"
                    alt=""
                    class="h-12 w-12 shrink-0 rounded-md object-cover"
                  />
                  <div v-else class="h-12 w-12 shrink-0 rounded-md bg-dial"></div>
                  <div class="min-w-0">
                    <p class="eyebrow truncate text-[10px]">{{ sale.watchBrand || 'No brand' }}</p>
                    <p class="mt-0.5 font-medium text-cream">{{ sale.watchName }}</p>
                  </div>
                </div>
              </td>
              <td class="px-4 py-3 text-right tabular-nums text-cream">{{ sale.quantity }}</td>
              <td class="whitespace-nowrap px-4 py-3 text-right tabular-nums text-mist">
                {{ formatMoney(sale.unitPrice) }}
              </td>
              <td
                class="whitespace-nowrap px-4 py-3 text-right font-medium tabular-nums text-cream"
                :class="isVoided(sale) ? 'line-through' : ''"
              >
                {{ formatMoney(sale.totalAmount) }}
              </td>
              <td class="whitespace-nowrap px-4 py-3 text-mist">{{ sale.paymentMethod }}</td>
              <td class="max-w-[16rem] px-4 py-3">
                <p class="truncate text-cream">{{ sale.buyerName || '–' }}</p>
                <p v-if="sale.notes" class="mt-0.5 truncate text-xs text-mist" :title="sale.notes">
                  {{ sale.notes }}
                </p>
                <p v-if="isVoided(sale) && sale.voidReason" class="mt-0.5 truncate text-xs text-red-300" :title="sale.voidReason">
                  Void reason: {{ sale.voidReason }}
                </p>
              </td>
              <td class="whitespace-nowrap px-4 py-3 text-right">
                <span v-if="isVoided(sale)" class="eyebrow text-red-300">Voided</span>
                <button
                  v-else
                  type="button"
                  class="eyebrow transition-colors hover:text-red-300"
                  :aria-label="`Void the sale of ${sale.watchName}`"
                  @click="askVoid(sale)"
                >
                  Void
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <Pagination
        v-if="visibleSales.length > 0"
        :page="currentPage"
        :total-pages="totalPages"
        :total="visibleSales.length"
        :page-size="PAGE_SIZE"
        @update:page="page = $event"
      />
    </template>

    <ConfirmDialog
      :open="!!voidTarget"
      title="Void this sale?"
      confirm-label="Void sale"
      busy-label="Voiding..."
      danger
      :busy="voiding"
      :error="voidError"
      @confirm="confirmVoid"
      @cancel="cancelVoid"
    >
      <p>
        <span class="font-medium text-cream">{{ voidTarget?.quantity }} ×
        {{ voidTarget?.watchName }}</span> will stay in your history, marked as voided, and
        leave your totals. Any units it took out of stock go back in. This can't be undone.
      </p>
      <label for="void-reason" class="field-label mt-4">Reason (optional)</label>
      <input
        id="void-reason"
        v-model="voidReason"
        type="text"
        autocomplete="off"
        :maxlength="MAX_VOID_REASON_LENGTH"
        class="field"
        placeholder="e.g. Recorded twice by mistake"
        :disabled="voiding"
      />
    </ConfirmDialog>
  </div>
</template>
