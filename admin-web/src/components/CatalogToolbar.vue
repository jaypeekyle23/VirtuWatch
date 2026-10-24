<script setup>
import { ref, computed } from 'vue'
import { STYLE_OPTIONS, GENDER_OPTIONS } from '../constants/watchOptions'
import { SORT_OPTIONS, defaultFilters, activeFilterCount } from '../utils/catalogFilters'

defineProps({
  brandOptions: { type: Array, default: () => [] },
  incompleteCount: { type: Number, default: 0 },
  // How many watches are out of stock and running low. The "stock alert" notice only
  // appears when a page passes this (the merchant catalog does; admin pages don't).
  stockAlerts: { type: Object, default: () => ({ out: 0, low: 0 }) },
})

// Each of these is a two-way value shared with the parent page (v-model).
const search = defineModel('search', { default: '' })
const sort = defineModel('sort', { default: 'newest' })
const filters = defineModel('filters', { default: () => defaultFilters() })
const needsInfoOnly = defineModel('needsInfoOnly', { default: false })
const stockAlertOnly = defineModel('stockAlertOnly', { default: false })
// 'grid' or 'list'
const view = defineModel('view', { default: 'grid' })

const showFilters = ref(false)
const activeCount = computed(() => activeFilterCount(filters.value))

function viewButtonClass(mode) {
  return view.value === mode ? 'text-gold' : 'text-mist hover:text-cream'
}

function setFilter(key, value) {
  filters.value = { ...filters.value, [key]: value }
}

function resetFilters() {
  filters.value = defaultFilters()
}
</script>

<template>
  <div class="space-y-5">
    <!-- Stock alert notice: watches that are out of stock or running low -->
    <div
      v-if="stockAlerts.out + stockAlerts.low > 0"
      class="flex flex-wrap items-center justify-between gap-3 border-y border-line py-3 text-sm"
    >
      <span class="flex items-center gap-2 font-medium text-cream">
        <svg
          class="h-4 w-4 shrink-0"
          :class="stockAlerts.out > 0 ? 'text-red-300' : 'text-amber-300'"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.75"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <path d="M12 4l9 16H3L12 4Z" />
          <path d="M12 10v4M12 17.5v.01" />
        </svg>
        {{
          [
            stockAlerts.out > 0 ? `${stockAlerts.out} out of stock` : '',
            stockAlerts.low > 0 ? `${stockAlerts.low} running low` : '',
          ]
            .filter(Boolean)
            .join(', ')
        }}
      </span>
      <button
        type="button"
        class="eyebrow text-gold transition-colors hover:text-gold-light"
        @click="stockAlertOnly = !stockAlertOnly"
      >
        {{ stockAlertOnly ? 'Show all' : 'Show only these' }}
      </button>
    </div>

    <!-- "Needs info" notice -->
    <div
      v-if="incompleteCount > 0"
      class="flex flex-wrap items-center justify-between gap-3 border-y border-line py-3 text-sm text-mist"
    >
      <span>
        {{ incompleteCount }} {{ incompleteCount === 1 ? 'watch is' : 'watches are' }}
        missing gender, color, lug-to-lug or stock info.
      </span>
      <button
        type="button"
        class="eyebrow text-gold transition-colors hover:text-gold-light"
        @click="needsInfoOnly = !needsInfoOnly"
      >
        {{ needsInfoOnly ? 'Show all' : 'Show only these' }}
      </button>
    </div>

    <!-- One hairline under search, sort, filters and the view toggle -->
    <div
      class="flex flex-wrap items-center gap-x-6 gap-y-1 border-b border-line transition-colors focus-within:border-gold/60"
    >
      <div class="relative min-w-[220px] flex-1">
        <svg
          class="pointer-events-none absolute left-0 top-1/2 h-4 w-4 -translate-y-1/2 text-mist"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.5"
          stroke-linecap="round"
          aria-hidden="true"
        >
          <circle cx="11" cy="11" r="7" />
          <path d="M20 20l-3.5-3.5" />
        </svg>
        <input
          v-model="search"
          type="text"
          placeholder="Search by name, brand, or style"
          aria-label="Search watches"
          class="w-full bg-transparent py-3.5 pl-8 pr-2 text-sm text-cream outline-none placeholder:text-slate-500"
        />
      </div>

      <select
        v-model="sort"
        aria-label="Sort watches"
        class="cursor-pointer bg-transparent py-3.5 text-[11px] font-medium uppercase tracking-[0.18em] text-mist outline-none transition-colors hover:text-cream focus-visible:text-cream"
      >
        <option v-for="o in SORT_OPTIONS" :key="o.value" :value="o.value" class="bg-dial text-cream">
          {{ o.label }}
        </option>
      </select>

      <button
        type="button"
        class="flex items-center gap-2 py-3.5 text-[11px] font-medium uppercase tracking-[0.18em] transition-colors hover:text-cream"
        :class="showFilters || activeCount > 0 ? 'text-cream' : 'text-mist'"
        :aria-expanded="showFilters"
        @click="showFilters = !showFilters"
      >
        Filters
        <span
          v-if="activeCount > 0"
          class="rounded-full bg-gold-fill px-1.5 text-[10px] font-semibold tracking-normal text-on-gold"
        >
          {{ activeCount }}
        </span>
      </button>

      <!-- Grid / list toggle -->
      <div class="flex items-center gap-1" role="group" aria-label="View">
        <button
          type="button"
          title="Grid view"
          aria-label="Grid view"
          :aria-pressed="view === 'grid'"
          class="rounded-md p-2 transition-colors"
          :class="viewButtonClass('grid')"
          @click="view = 'grid'"
        >
          <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true">
            <rect x="4" y="4" width="6" height="6" rx="1" />
            <rect x="14" y="4" width="6" height="6" rx="1" />
            <rect x="4" y="14" width="6" height="6" rx="1" />
            <rect x="14" y="14" width="6" height="6" rx="1" />
          </svg>
        </button>
        <button
          type="button"
          title="List view"
          aria-label="List view"
          :aria-pressed="view === 'list'"
          class="rounded-md p-2 transition-colors"
          :class="viewButtonClass('list')"
          @click="view = 'list'"
        >
          <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true">
            <path d="M4 6h16M4 12h16M4 18h16" />
          </svg>
        </button>
      </div>
    </div>

    <!-- Filters panel -->
    <div v-if="showFilters" class="space-y-5 border-b border-line pb-6">
      <div class="grid grid-cols-2 gap-4 md:grid-cols-4">
        <div>
          <label for="filter-style" class="label">Style</label>
          <select
            id="filter-style"
            :value="filters.style"
            class="input"
            @change="setFilter('style', $event.target.value)"
          >
            <option value="All">All</option>
            <option v-for="s in STYLE_OPTIONS" :key="s" :value="s">{{ s }}</option>
          </select>
        </div>

        <div>
          <label for="filter-gender" class="label">Gender</label>
          <select
            id="filter-gender"
            :value="filters.gender"
            class="input"
            @change="setFilter('gender', $event.target.value)"
          >
            <option value="All">All</option>
            <option v-for="g in GENDER_OPTIONS" :key="g" :value="g">{{ g }}</option>
          </select>
        </div>

        <div>
          <label for="filter-brand" class="label">Brand</label>
          <select
            id="filter-brand"
            :value="filters.brand"
            class="input"
            @change="setFilter('brand', $event.target.value)"
          >
            <option value="All">All</option>
            <option v-for="b in brandOptions" :key="b" :value="b">{{ b }}</option>
          </select>
        </div>

        <div>
          <label for="filter-status" class="label">Listing status</label>
          <select
            id="filter-status"
            :value="filters.listingStatus"
            class="input"
            @change="setFilter('listingStatus', $event.target.value)"
          >
            <option value="All">All</option>
            <option value="Active">Active (listed)</option>
            <option value="Draft">Draft (unlisted)</option>
          </select>
        </div>
      </div>

      <div class="flex flex-wrap items-end gap-4">
        <div>
          <label for="filter-min" class="label">Min price (₱)</label>
          <input
            id="filter-min"
            :value="filters.minPrice"
            type="number"
            min="0"
            class="input w-32"
            @input="setFilter('minPrice', $event.target.value)"
          />
        </div>
        <div>
          <label for="filter-max" class="label">Max price (₱)</label>
          <input
            id="filter-max"
            :value="filters.maxPrice"
            type="number"
            min="0"
            class="input w-32"
            @input="setFilter('maxPrice', $event.target.value)"
          />
        </div>

        <label class="flex items-center gap-2 pb-2.5 text-sm text-cream">
          <input
            type="checkbox"
            :checked="filters.arOnly"
            class="h-4 w-4 accent-gold"
            @change="setFilter('arOnly', $event.target.checked)"
          />
          With 3D model only
        </label>

        <label class="flex items-center gap-2 pb-2.5 text-sm text-cream">
          <input
            type="checkbox"
            :checked="filters.inStockOnly"
            class="h-4 w-4 accent-gold"
            @change="setFilter('inStockOnly', $event.target.checked)"
          />
          In stock only
        </label>

        <button
          type="button"
          class="ml-auto pb-2.5 text-sm text-gold hover:text-gold-light"
          @click="resetFilters"
        >
          Reset filters
        </button>
      </div>
    </div>
  </div>
</template>