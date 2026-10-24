<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { currentUser } from '../../composables/useAuth'
import { catalogView } from '../../composables/useCatalogView'
import { hero } from '../../composables/useHeroTransition'
import { useCatalogQuery } from '../../composables/useCatalogQuery'
import { showToast } from '../../composables/useToast'
import {
  listenToMyWatches,
  seedMyWatches,
  deleteWatch,
  updateWatch,
} from '../../services/watchService'
import PageHeader from '../../components/PageHeader.vue'
import CatalogToolbar from '../../components/CatalogToolbar.vue'
import WatchGridCard from '../../components/WatchGridCard.vue'
import Pagination from '../../components/Pagination.vue'
import ConfirmDialog from '../../components/ConfirmDialog.vue'
import StockDialog from '../../components/StockDialog.vue'
import StockLabel from '../../components/StockLabel.vue'
import { stockAlertCounts } from '../../utils/stock'
import {
  PAGE_SIZE,
  pageCount,
  defaultFilters,
  filterWatches,
  sortWatches,
  missingWatchFields,
  fixLocation,
  isListed,
} from '../../utils/catalogFilters'

// Coming back from a watch's page, this starts filled in (see utils/snapshotCache),
// so the page is already on screen for the hero photo to land on. It refreshes below.
const seededWatches = seedMyWatches(currentUser.value.uid)
const watches = ref(seededWatches ?? [])
const loading = ref(!seededWatches)
const errorMessage = ref('')
let stopListening = null

// Toolbar state. It lives in the page address, so a filtered list survives opening
// a watch and coming back, and can be shared as a link.
const { search, sort, filters, needsInfoOnly, stockAlertOnly, page } = useCatalogQuery()

// The watch whose stock is being changed (null = dialog closed).
const stockTarget = ref(null)

// The watch currently being confirmed for deletion (null = dialog closed).
const deleteTarget = ref(null)
const deleting = ref(false)
const deleteError = ref('')

onMounted(() => {
  stopListening = listenToMyWatches(
    currentUser.value.uid,
    (list) => {
      watches.value = list
      loading.value = false
    },
    (err) => {
      console.error(err)
      errorMessage.value = 'Could not load your watches. Check the browser console for details.'
      loading.value = false
    },
  )
})

// Stop the live listener when leaving this page.
onUnmounted(() => {
  if (stopListening) stopListening()
})

// A "computed" value recalculates itself automatically whenever
// anything it uses (watches, search, filters, sort...) changes.
const brandOptions = computed(() =>
  [...new Set(watches.value.map((w) => w.brand).filter(Boolean))].sort(),
)

const incompleteCount = computed(
  () => watches.value.filter((w) => missingWatchFields(w).length > 0).length,
)

// Counted over the whole catalog, whatever filters are applied.
const stockAlerts = computed(() => stockAlertCounts(watches.value))

const visibleWatches = computed(() =>
  sortWatches(
    filterWatches(
      watches.value,
      filters.value,
      search.value,
      needsInfoOnly.value,
      stockAlertOnly.value,
    ),
    sort.value,
  ),
)

// Only one page of the (already searched, filtered and sorted) list is drawn.
const totalPages = computed(() => pageCount(visibleWatches.value.length))
const currentPage = computed(() => Math.min(page.value, totalPages.value))
const pagedWatches = computed(() => {
  const start = (currentPage.value - 1) * PAGE_SIZE
  return visibleWatches.value.slice(start, start + PAGE_SIZE)
})

// A page that no longer exists (a pasted link, or the last watch on the final page
// was deleted) moves back to the last real page. Waits for the watches to load,
// because an empty list has just one page.
watch([totalPages, loading], () => {
  if (!loading.value && page.value > totalPages.value) page.value = totalPages.value
})

const subtitle = computed(() => {
  const total = watches.value.length
  if (visibleWatches.value.length !== total) {
    return `${visibleWatches.value.length} of ${total} watches`
  }
  return `${total} ${total === 1 ? 'watch' : 'watches'}`
})

function clearAll() {
  search.value = ''
  filters.value = defaultFilters()
  needsInfoOnly.value = false
  stockAlertOnly.value = false
}

function onStockSaved({ watch: saved }) {
  showToast('success', `Stock updated for "${saved.name}".`)
}

function thumbnail(watch) {
  return watch.imageUrls?.[0] || watch.imageUrl || ''
}

function formatPrice(price) {
  if (price == null) return '–'
  return 'PHP ' + Number(price).toLocaleString('en-PH')
}

// Lists or unlists a watch in the customer catalog.
//
// Optimistic: the card flips straight away and nothing waits for the server.
// Firestore applies the change on this device first and confirms it afterwards.
// If the server turns it down (a permissions problem, say), Firestore puts the
// card back by itself, and the toast below replaces the "listed" one to say so.
// The shared key means flipping a watch back and forth shows only the latest toast.
function toggleListed(watch) {
  const nowListed = !isListed(watch)
  const key = `listing:${watch.id}`
  showToast(
    'success',
    nowListed
      ? `"${watch.name}" is now listed in the catalog.`
      : `"${watch.name}" was unlisted from the catalog.`,
    { key },
  )
  updateWatch(watch.id, { listedInCatalog: nowListed }).catch((e) => {
    console.error(e)
    showToast(
      'error',
      `Could not ${nowListed ? 'list' : 'unlist'} "${watch.name}", so it was put back. Please try again.`,
      { key },
    )
  })
}

function askDelete(watch) {
  deleteError.value = ''
  deleteTarget.value = watch
}

function cancelDelete() {
  if (deleting.value) return
  deleteTarget.value = null
}

async function confirmDelete() {
  const watch = deleteTarget.value
  if (!watch) return
  deleting.value = true
  deleteError.value = ''
  try {
    const label = watch.brand ? `${watch.brand} ${watch.name}` : watch.name
    await deleteWatch(watch.id, label)
    deleteTarget.value = null
    showToast('success', `Deleted "${label}".`)
  } catch (e) {
    console.error(e)
    deleteError.value = 'Could not delete the watch. Please try again.'
  } finally {
    deleting.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-[88rem]">
    <PageHeader title="My Catalog" :subtitle="subtitle">
      <template #actions>
        <router-link to="/merchant/watches/new" class="btn-primary">Add watch</router-link>
      </template>
    </PageHeader>

    <p v-if="errorMessage" class="alert-error mt-6" role="alert">{{ errorMessage }}</p>

    <!-- Loading skeleton -->
    <template v-if="loading">
      <p class="sr-only" role="status">Loading your watches</p>
      <div
        class="mt-10 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5"
        aria-hidden="true"
      >
        <div v-for="n in 10" :key="n" class="h-80 animate-pulse rounded-xl bg-dial"></div>
      </div>
    </template>

    <!-- Nothing listed yet -->
    <div
      v-else-if="!errorMessage && watches.length === 0"
      class="mt-10 border-y border-line py-20 text-center"
    >
      <p class="font-serif text-3xl text-cream">Your catalog is empty</p>
      <p class="mt-2 text-sm text-mist">Add your first watch and customers can start trying it on.</p>
      <router-link to="/merchant/watches/new" class="btn-primary mt-6">
        Add your first watch
      </router-link>
    </div>

    <template v-else-if="!errorMessage">
      <div class="mt-8">
        <CatalogToolbar
          v-model:search="search"
          v-model:sort="sort"
          v-model:filters="filters"
          v-model:needs-info-only="needsInfoOnly"
          v-model:stock-alert-only="stockAlertOnly"
          v-model:view="catalogView"
          :brand-options="brandOptions"
          :incomplete-count="incompleteCount"
          :stock-alerts="stockAlerts"
        />
      </div>

      <div v-if="visibleWatches.length === 0" class="mt-8 border-y border-line py-16 text-center">
        <p class="text-cream">No watches match your search or filters.</p>
        <button
          type="button"
          class="eyebrow mt-4 text-gold transition-colors hover:text-gold-light"
          @click="clearAll"
        >
          Clear search and filters
        </button>
      </div>

      <!-- Grid view -->
      <div
        v-else-if="catalogView === 'grid'"
        class="mt-8 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5"
      >
        <WatchGridCard
          v-for="watch in pagedWatches"
          :key="watch.id"
          :watch="watch"
          :detail-path="`/merchant/watches/${watch.id}`"
          :edit-path="`/merchant/watches/${watch.id}/edit`"
          show-list-toggle
          show-stock-action
          @toggle-listed="toggleListed"
          @update-stock="stockTarget = $event"
          @delete="askDelete"
        />
      </div>

      <!-- List view -->
      <div v-else class="mt-8 overflow-x-auto">
        <table class="w-full text-left text-sm">
          <thead class="border-y border-line">
            <tr class="eyebrow">
              <th class="px-4 py-3 font-medium">Watch</th>
              <th class="px-4 py-3 font-medium">Brand</th>
              <th class="px-4 py-3 font-medium">Style</th>
              <th class="px-4 py-3 font-medium">Price</th>
              <th class="px-4 py-3 font-medium">Stock</th>
              <th class="px-4 py-3 font-medium">Status</th>
              <th class="px-4 py-3 text-right font-medium">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-line border-b border-line">
            <tr
              v-for="watch in pagedWatches"
              :key="watch.id"
              class="transition-colors hover:bg-dial/40"
            >
              <td class="px-4 py-3">
                <router-link
                  :to="`/merchant/watches/${watch.id}`"
                  class="group flex items-center gap-4"
                >
                  <img
                    v-if="thumbnail(watch)"
                    v-bind="hero(watch.id)"
                    :src="thumbnail(watch)"
                    :alt="watch.name"
                    class="h-12 w-12 shrink-0 rounded-md object-cover"
                  />
                  <div v-else class="h-12 w-12 shrink-0 rounded-md bg-dial"></div>
                  <span class="font-medium text-cream transition-colors group-hover:text-gold">
                    {{ watch.name }}
                  </span>
                </router-link>
              </td>
              <td class="px-4 py-3 text-mist">{{ watch.brand || '–' }}</td>
              <td class="px-4 py-3 text-mist">{{ watch.styleCategory || '–' }}</td>
              <td class="px-4 py-3 font-medium tabular-nums text-cream">
                {{ formatPrice(watch.price) }}
              </td>
              <td class="px-4 py-3 text-sm"><StockLabel :watch="watch" /></td>
              <td class="px-4 py-3">
                <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
                  <span class="eyebrow" :class="isListed(watch) ? 'text-cream' : 'text-mist/70'">
                    {{ isListed(watch) ? 'Listed' : 'Draft' }}
                  </span>
                  <span v-if="watch.has3DModel" class="eyebrow text-gold">AR</span>
                  <router-link
                    v-if="missingWatchFields(watch).length"
                    :to="fixLocation(`/merchant/watches/${watch.id}/edit`, missingWatchFields(watch)[0])"
                    :title="`Missing: ${missingWatchFields(watch).join(', ')}. Select to add it.`"
                    :aria-label="`Add missing ${missingWatchFields(watch).join(', ').toLowerCase()} for ${watch.name}`"
                    class="eyebrow text-gold transition-colors hover:text-gold-light"
                  >
                    Needs info
                  </router-link>
                </div>
              </td>
              <td class="px-4 py-3">
                <div class="flex items-center justify-end gap-5">
                  <button
                    type="button"
                    class="eyebrow transition-colors hover:text-cream"
                    @click="toggleListed(watch)"
                  >
                    {{ isListed(watch) ? 'Unlist' : 'List' }}
                  </button>
                  <router-link
                    :to="`/merchant/watches/${watch.id}/edit`"
                    class="eyebrow transition-colors hover:text-cream"
                  >
                    Edit
                  </router-link>
                  <button
                    type="button"
                    class="eyebrow transition-colors hover:text-cream"
                    @click="stockTarget = watch"
                  >
                    Stock
                  </button>
                  <button
                    type="button"
                    class="eyebrow transition-colors hover:text-red-300"
                    @click="askDelete(watch)"
                  >
                    Delete
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <Pagination
        v-if="visibleWatches.length > 0"
        :page="currentPage"
        :total-pages="totalPages"
        :total="visibleWatches.length"
        :page-size="PAGE_SIZE"
        @update:page="page = $event"
      />
    </template>

    <StockDialog :target="stockTarget" @saved="onStockSaved" @close="stockTarget = null" />

    <ConfirmDialog
      :open="!!deleteTarget"
      title="Delete this watch?"
      confirm-label="Delete"
      busy-label="Deleting..."
      danger
      :busy="deleting"
      :error="deleteError"
      @confirm="confirmDelete"
      @cancel="cancelDelete"
    >
      <span class="font-medium text-cream">{{ deleteTarget?.name }}</span> will be permanently
      removed. This can't be undone.
    </ConfirmDialog>
  </div>
</template>