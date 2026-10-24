<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { catalogView } from '../../composables/useCatalogView'
import { hero } from '../../composables/useHeroTransition'
import { useCatalogQuery } from '../../composables/useCatalogQuery'
import { showToast } from '../../composables/useToast'
import {
  listenToAllWatches,
  listenToAllUsers,
  seedAllWatches,
  seedAllUsers,
} from '../../services/adminService'
import { deleteWatch, updateWatch } from '../../services/watchService'
import PageHeader from '../../components/PageHeader.vue'
import CatalogToolbar from '../../components/CatalogToolbar.vue'
import WatchGridCard from '../../components/WatchGridCard.vue'
import Pagination from '../../components/Pagination.vue'
import Chip from '../../components/Chip.vue'
import { isArReady, arStatus } from '../../utils/arFit'
import ConfirmDialog from '../../components/ConfirmDialog.vue'
import StockLabel from '../../components/StockLabel.vue'
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

// Coming back from a watch's page, these start filled in (see utils/snapshotCache),
// so the page is already on screen for the hero photo to land on. They refresh below.
const seededWatches = seedAllWatches()
const watches = ref(seededWatches ?? [])
const users = ref(seedAllUsers() ?? [])
const loading = ref(!seededWatches)
const errorMessage = ref('')
let stopWatches = null
let stopUsers = null

// Toolbar state. It lives in the page address, so a filtered list survives opening
// a watch and coming back, and can be shared as a link.
const { search, sort, filters, needsInfoOnly, stockAlertOnly, page } = useCatalogQuery()

// The watch currently being confirmed for deletion (null = dialog closed).
const deleteTarget = ref(null)
const deleting = ref(false)
const deleteError = ref('')

onMounted(() => {
  stopWatches = listenToAllWatches(
    (list) => {
      watches.value = list
      loading.value = false
    },
    (err) => {
      console.error(err)
      errorMessage.value = 'Could not load watches. Check the browser console for details.'
      loading.value = false
    },
  )
  // Only used to show each watch's merchant name.
  stopUsers = listenToAllUsers(
    (list) => {
      users.value = list
    },
    (err) => console.error(err),
  )
})

onUnmounted(() => {
  if (stopWatches) stopWatches()
  if (stopUsers) stopUsers()
})

const merchantNames = computed(() => {
  const map = {}
  for (const u of users.value) map[u.id] = u.username || u.email || 'Unknown'
  return map
})

function merchantName(watch) {
  if (!watch.merchantId) return '–'
  return merchantNames.value[watch.merchantId] ?? 'Unknown merchant'
}

const brandOptions = computed(() =>
  [...new Set(watches.value.map((w) => w.brand).filter(Boolean))].sort(),
)

const incompleteCount = computed(
  () => watches.value.filter((w) => missingWatchFields(w).length > 0).length,
)

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
  return `${total} ${total === 1 ? 'watch' : 'watches'} across all merchants`
})

function clearAll() {
  search.value = ''
  filters.value = defaultFilters()
  needsInfoOnly.value = false
  stockAlertOnly.value = false
}

function thumbnail(watch) {
  return watch.imageUrls?.[0] || watch.imageUrl || ''
}

function formatPrice(price) {
  if (price == null) return '–'
  return '₱' + Number(price).toLocaleString('en-PH')
}

function watchLabel(watch) {
  return watch.brand ? `${watch.brand} ${watch.name}` : watch.name
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
    await deleteWatch(watch.id, watchLabel(watch))
    deleteTarget.value = null
    showToast('success', `Deleted "${watchLabel(watch)}".`)
  } catch (e) {
    console.error(e)
    deleteError.value = 'Could not delete the watch. Please try again.'
  } finally {
    deleting.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-7xl">
    <PageHeader title="Watch Management" :subtitle="subtitle">
      <template #actions>
        <router-link to="/admin/watches/new" class="btn-primary">Add watch</router-link>
      </template>
    </PageHeader>

    <p v-if="errorMessage" class="alert-error mt-6" role="alert">{{ errorMessage }}</p>

    <!-- Loading skeleton -->
    <template v-if="loading">
      <p class="sr-only" role="status">Loading watches</p>
      <div
        class="mt-8 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5"
        aria-hidden="true"
      >
        <div v-for="n in 10" :key="n" class="panel h-72 animate-pulse"></div>
      </div>
    </template>

    <!-- No watches anywhere -->
    <div v-else-if="!errorMessage && watches.length === 0" class="panel mt-8 p-10 text-center">
      <p class="text-lg font-semibold text-cream">There are no watches yet</p>
      <p class="mt-1 text-sm text-mist">Add a watch for one of your merchants to get started.</p>
      <router-link to="/admin/watches/new" class="btn-primary mt-5">Add a watch</router-link>
    </div>

    <template v-else-if="!errorMessage">
      <div class="mt-8">
        <CatalogToolbar
          v-model:search="search"
          v-model:sort="sort"
          v-model:filters="filters"
          v-model:needs-info-only="needsInfoOnly"
          v-model:view="catalogView"
          :brand-options="brandOptions"
          :incomplete-count="incompleteCount"
        />
      </div>

      <div v-if="visibleWatches.length === 0" class="panel mt-6 p-10 text-center">
        <p class="text-cream">No watches match your search or filters.</p>
        <button type="button" class="btn-secondary mt-4" @click="clearAll">
          Clear search and filters
        </button>
      </div>

      <!-- Grid view -->
      <div
        v-else-if="catalogView === 'grid'"
        class="mt-6 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5"
      >
        <WatchGridCard
          v-for="watch in pagedWatches"
          :key="watch.id"
          :watch="watch"
          :detail-path="`/admin/watches/${watch.id}`"
          :edit-path="`/admin/watches/${watch.id}/edit`"
          :merchant-name="merchantName(watch)"
          show-list-toggle
          @toggle-listed="toggleListed"
          @delete="askDelete"
        />
      </div>

      <!-- List view -->
      <div v-else class="panel mt-6 overflow-x-auto">
        <table class="w-full text-left text-sm">
          <thead class="border-b border-line text-xs text-mist">
            <tr>
              <th class="px-4 py-3 font-medium">Watch</th>
              <th class="px-4 py-3 font-medium">Merchant</th>
              <th class="px-4 py-3 font-medium">Brand</th>
              <th class="px-4 py-3 font-medium">Price</th>
              <th class="px-4 py-3 font-medium">Stock</th>
              <th class="px-4 py-3 font-medium">Status</th>
              <th class="px-4 py-3 text-right font-medium">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-line">
            <tr
              v-for="watch in pagedWatches"
              :key="watch.id"
              class="transition-colors hover:bg-slate-700/30"
            >
              <td class="px-4 py-3">
                <router-link
                  :to="`/admin/watches/${watch.id}`"
                  class="group flex items-center gap-3"
                >
                  <img
                    v-if="thumbnail(watch)"
                    v-bind="hero(watch.id)"
                    :src="thumbnail(watch)"
                    :alt="watch.name"
                    class="h-12 w-12 shrink-0 rounded-lg object-cover"
                  />
                  <div v-else class="h-12 w-12 shrink-0 rounded-lg bg-slate-700"></div>
                  <span class="font-medium text-cream transition-colors group-hover:text-gold">
                    {{ watch.name }}
                  </span>
                </router-link>
              </td>
              <td class="px-4 py-3 text-mist">{{ merchantName(watch) }}</td>
              <td class="px-4 py-3 text-mist">{{ watch.brand || '–' }}</td>
              <td class="px-4 py-3 font-medium tabular-nums text-gold">
                {{ formatPrice(watch.price) }}
              </td>
              <td class="px-4 py-3 text-sm"><StockLabel :watch="watch" /></td>
              <td class="px-4 py-3">
                <div class="flex flex-wrap gap-1.5">
                  <Chip :tone="isListed(watch) ? 'success' : 'neutral'">
                    {{ isListed(watch) ? 'Listed' : 'Draft' }}
                  </Chip>
                  <Chip v-if="isArReady(watch)" tone="gold">AR</Chip>
                  <router-link
                    v-else-if="arStatus(watch) === 'needs-fit'"
                    :to="{ path: `/admin/watches/${watch.id}/edit`, query: { focus: 'holeCx' } }"
                    title="3D model attached, but AR fit is missing. Select to add it."
                    :aria-label="`Add AR fit for ${watch.name}`"
                    class="rounded-full transition hover:brightness-125 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gold"
                  >
                    <Chip tone="warn">Needs AR fit</Chip>
                  </router-link>
                  <router-link
                    v-if="missingWatchFields(watch).length"
                    :to="fixLocation(`/admin/watches/${watch.id}/edit`, missingWatchFields(watch)[0])"
                    :title="`Missing: ${missingWatchFields(watch).join(', ')}. Select to add it.`"
                    :aria-label="`Add missing ${missingWatchFields(watch).join(', ').toLowerCase()} for ${watch.name}`"
                    class="rounded-full transition hover:brightness-125 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gold"
                  >
                    <Chip tone="warn">Needs info</Chip>
                  </router-link>
                </div>
              </td>
              <td class="px-4 py-3">
                <div class="flex items-center justify-end gap-2">
                  <button
                    type="button"
                    class="btn-secondary btn-xs"
                    @click="toggleListed(watch)"
                  >
                    {{ isListed(watch) ? 'Unlist' : 'List' }}
                  </button>
                  <router-link :to="`/admin/watches/${watch.id}/edit`" class="btn-secondary btn-xs">
                    Edit
                  </router-link>
                  <button
                    type="button"
                    class="rounded-lg px-2.5 py-1 text-xs text-red-300 transition-colors hover:bg-red-400/10"
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
      <span class="font-medium text-cream">{{ deleteTarget?.name }}</span>
      ({{ deleteTarget ? merchantName(deleteTarget) : '' }}) will be permanently removed, and it
      will disappear from customers' saved lists. This can't be undone.
    </ConfirmDialog>
  </div>
</template>