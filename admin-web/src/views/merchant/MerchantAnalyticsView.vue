<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { currentUser } from '../../composables/useAuth'
import { hero } from '../../composables/useHeroTransition'
import {
  listenToMyWatches,
  seedMyWatches,
  fetchEngagementStats,
} from '../../services/watchService'
import { remember, seed } from '../../utils/snapshotCache'
import { isListed } from '../../utils/catalogFilters'
import { isArReady } from '../../utils/arFit'
import { inventoryTotals, stockAlertCounts } from '../../utils/stock'
import PageHeader from '../../components/PageHeader.vue'

const RANK_PREVIEW = 8

// Coming back from a watch's page, the watches and stats start filled in (see
// utils/snapshotCache), so the ranked list is already on screen for the hero photo
// to land on. Both refresh below.
const statsKey = `engagement:${currentUser.value.uid}`
const seededWatches = seedMyWatches(currentUser.value.uid)
const seededStats = seed(statsKey)

const watches = ref(seededWatches ?? [])
const loading = ref(!seededWatches)
const errorMessage = ref('')
let stopListening = null

// Engagement stats are loaded separately because they need extra reads.
const stats = ref(seededStats)
const engagementLoading = ref(!seededStats)
const engagementError = ref(false)
let latestRequest = 0

const showAll = ref(false)
const showAllTryOns = ref(false)

onMounted(() => {
  stopListening = listenToMyWatches(
    currentUser.value.uid,
    (list) => {
      watches.value = list
      loading.value = false
    },
    (err) => {
      console.error(err)
      errorMessage.value = 'Could not load your watches.'
      loading.value = false
    },
  )
})

onUnmounted(() => {
  if (stopListening) stopListening()
})

// Reload engagement stats when the watches first load, and whenever the set of
// watches changes (a watch is added or deleted). Watching "loading" as well means
// the stats also load for a catalog that turns out to be empty, and "immediate"
// covers a page that starts with remembered watches.
watch(
  () => `${loading.value}|${watches.value.map((w) => w.id).join(',')}`,
  async () => {
    if (loading.value) return
    const requestId = ++latestRequest
    // Stats already on screen stay there while they refresh.
    if (!stats.value) engagementLoading.value = true
    engagementError.value = false
    try {
      const result = await fetchEngagementStats(watches.value.map((w) => w.id))
      if (requestId === latestRequest) {
        stats.value = result
        remember(statsKey, result)
      }
    } catch (e) {
      console.error(e)
      if (requestId === latestRequest) engagementError.value = true
    } finally {
      if (requestId === latestRequest) engagementLoading.value = false
    }
  },
  { immediate: true },
)

// ---------- Catalog overview ----------

const total = computed(() => watches.value.length)
const listed = computed(() => watches.value.filter(isListed).length)
// Same test the app uses (a model plus valid fit numbers), so the figure here matches
// the AR TRY-ON section below and what customers can actually try on.
const arWatches = computed(() => watches.value.filter(isArReady))
const arReady = computed(() => arWatches.value.length)

const catalogStats = computed(() => [
  { label: 'Watches', value: total.value },
  { label: 'Listed', value: listed.value },
  { label: 'Drafts', value: total.value - listed.value },
  { label: 'AR ready', value: arReady.value },
])

// ---------- Pricing and stock ----------

const prices = computed(() =>
  watches.value.map((w) => w.price).filter((p) => typeof p === 'number'),
)
const avgPrice = computed(() =>
  prices.value.length ? prices.value.reduce((a, b) => a + b, 0) / prices.value.length : null,
)
const minPrice = computed(() => (prices.value.length ? Math.min(...prices.value) : null))
const maxPrice = computed(() => (prices.value.length ? Math.max(...prices.value) : null))

function money(value) {
  if (value == null) return '–'
  return 'PHP ' + Math.round(value).toLocaleString('en-PH')
}

// Inventory value is price x units on hand, not the sum of the prices (see
// inventoryTotals in utils/stock.js). A watch with no stock count yet is left out, and
// the note under the figure says how many were skipped, so the total is never silently
// understated. Same as the app's analytics tab.
const inventory = computed(() => inventoryTotals(watches.value))
const inventoryValue = computed(() => (inventory.value.valued > 0 ? inventory.value.value : null))
const alerts = computed(() => stockAlertCounts(watches.value))

const priceRows = computed(() => [
  { label: 'Units in stock', value: inventory.value.units.toLocaleString('en-PH') },
  { label: 'Out of stock', value: String(alerts.value.out) },
  { label: 'Running low', value: String(alerts.value.low) },
  { label: 'Average price', value: money(avgPrice.value) },
  { label: 'Lowest price', value: money(minPrice.value) },
  { label: 'Highest price', value: money(maxPrice.value) },
])

// ---------- Style breakdown ----------

const styleBreakdown = computed(() => {
  const counts = {}
  for (const w of watches.value) {
    const style = w.styleCategory || 'Unspecified'
    counts[style] = (counts[style] ?? 0) + 1
  }
  return Object.entries(counts)
    .map(([style, count]) => ({ style, count, share: total.value ? (count / total.value) * 100 : 0 }))
    .sort((a, b) => b.count - a.count)
})

// ---------- Engagement ----------

const totalViews = computed(() =>
  stats.value ? Object.values(stats.value.viewedCounts).reduce((a, b) => a + b, 0) : 0,
)

const engagementStats = computed(() => [
  { label: 'Total saves', value: stats.value?.totalSaves ?? 0 },
  { label: 'Customers who saved', value: stats.value?.uniqueSaverCount ?? 0 },
  { label: 'Watch views', value: totalViews.value },
])

// Watches ranked by saves, then by views.
const ranked = computed(() => {
  if (!stats.value) return []
  const saved = stats.value.savedCounts
  const viewed = stats.value.viewedCounts
  return [...watches.value].sort(
    (a, b) =>
      (saved[b.id] ?? 0) - (saved[a.id] ?? 0) || (viewed[b.id] ?? 0) - (viewed[a.id] ?? 0),
  )
})

const visibleRanked = computed(() =>
  showAll.value ? ranked.value : ranked.value.slice(0, RANK_PREVIEW),
)

function thumbnail(w) {
  return w.imageUrls?.[0] || w.imageUrl || ''
}

// ---------- AR try-on ----------

// Only AR-ready watches are listed. The rest can never have a try-on count.
const triedOnCount = computed(() =>
  stats.value ? arWatches.value.filter((w) => (stats.value.tryOnCounts[w.id] ?? 0) > 0).length : 0,
)

const tryOnStats = computed(() => [
  { label: 'Try-ons', value: stats.value?.totalTryOns ?? 0 },
  { label: 'Customers', value: stats.value?.uniqueTryOnerCount ?? 0 },
  { label: 'Photos', value: stats.value?.totalPhotos ?? 0 },
])

// AR-ready watches ranked by try-ons, then by distinct customers.
const rankedTryOns = computed(() => {
  if (!stats.value) return []
  const tryOns = stats.value.tryOnCounts
  const tryOners = stats.value.tryOnerCounts
  return [...arWatches.value].sort(
    (a, b) =>
      (tryOns[b.id] ?? 0) - (tryOns[a.id] ?? 0) || (tryOners[b.id] ?? 0) - (tryOners[a.id] ?? 0),
  )
})

const visibleRankedTryOns = computed(() =>
  showAllTryOns.value ? rankedTryOns.value : rankedTryOns.value.slice(0, RANK_PREVIEW),
)
</script>

<template>
  <div class="mx-auto max-w-[88rem]">
    <PageHeader title="Analytics" subtitle="How customers are responding to your catalog." />

    <p v-if="errorMessage" class="alert-error mt-6" role="alert">{{ errorMessage }}</p>

    <p v-else-if="loading" class="mt-8 text-sm text-mist" role="status">Loading...</p>

    <template v-else>
      <!-- Catalog -->
      <section class="mt-10 border-t border-line pt-6">
        <h2 class="eyebrow">Catalog</h2>
        <dl class="mt-6 grid grid-cols-2 gap-6 pb-8 sm:grid-cols-4">
          <div v-for="s in catalogStats" :key="s.label">
            <dd class="font-serif text-5xl font-medium tabular-nums text-cream">{{ s.value }}</dd>
            <dt class="mt-1 text-sm text-mist">{{ s.label }}</dt>
          </div>
        </dl>
      </section>

      <!-- Pricing and styles, side by side -->
      <div class="grid border-t border-line lg:grid-cols-2">
        <section class="py-8 lg:pr-12">
          <h2 class="eyebrow">Pricing</h2>

          <p class="mt-6 font-serif text-5xl font-medium tabular-nums text-cream">
            {{ money(inventoryValue) }}
          </p>
          <p class="mt-1 text-sm text-mist">Total inventory value (price × stock)</p>
          <p v-if="inventory.untracked > 0" class="mt-2 text-xs text-amber-300">
            {{
              inventory.untracked === 1
                ? '1 watch has no stock count and is not included.'
                : `${inventory.untracked} watches have no stock count and are not included.`
            }}
          </p>

          <dl class="mt-8 space-y-3 text-sm">
            <div v-for="r in priceRows" :key="r.label" class="flex justify-between gap-4">
              <dt class="text-mist">{{ r.label }}</dt>
              <dd class="tabular-nums text-cream">{{ r.value }}</dd>
            </div>
          </dl>
        </section>

        <section class="border-t border-line py-8 lg:border-l lg:border-t-0 lg:pl-12">
          <h2 class="eyebrow">Styles</h2>

          <p v-if="styleBreakdown.length === 0" class="mt-6 text-sm text-mist">No watches yet.</p>

          <ul v-else class="mt-6 space-y-5">
            <li v-for="row in styleBreakdown" :key="row.style">
              <div class="flex justify-between gap-4 text-sm">
                <span class="text-cream">{{ row.style }}</span>
                <span class="tabular-nums text-mist">
                  {{ row.count }} · {{ Math.round(row.share) }}%
                </span>
              </div>
              <div class="mt-2 h-[3px] overflow-hidden rounded-full bg-slate-700">
                <div class="h-full rounded-full bg-gold-fill" :style="{ width: row.share + '%' }"></div>
              </div>
            </li>
          </ul>
        </section>
      </div>

      <!-- Engagement -->
      <section class="border-t border-line pt-6">
        <h2 class="eyebrow">Engagement</h2>

        <p v-if="engagementLoading" class="mt-6 text-sm text-mist" role="status">
          Loading engagement data...
        </p>

        <p v-else-if="engagementError || !stats" class="alert-error mt-6" role="alert">
          Could not load engagement data. Try refreshing the page.
        </p>

        <div v-else-if="stats.totalSaves === 0" class="mt-6 border-y border-line py-14 text-center">
          <p class="font-serif text-2xl text-cream">No customer activity yet.</p>
          <p class="mt-2 text-sm text-mist">
            Saved and viewed counts appear here once customers start engaging with your catalog.
          </p>
        </div>

        <template v-else>
          <div class="mt-6 grid grid-cols-3 divide-x divide-line border-y border-line">
            <div v-for="s in engagementStats" :key="s.label" class="py-8 text-center">
              <p class="font-serif text-5xl font-medium tabular-nums text-cream">{{ s.value }}</p>
              <p class="eyebrow mt-3">{{ s.label }}</p>
            </div>
          </div>

          <table class="mt-10 w-full text-left text-sm">
            <thead>
              <tr class="border-b border-line text-mist">
                <th class="eyebrow w-12 py-3 pr-2 font-medium">#</th>
                <th class="eyebrow py-3 font-medium">Watch</th>
                <th class="w-24 py-3 text-right font-medium" title="Saved">
                  <svg
                    class="ml-auto h-4 w-4"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.5"
                    stroke-linejoin="round"
                    aria-hidden="true"
                  >
                    <path
                      d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1-1.1a5.5 5.5 0 0 0-7.8 7.8l1 1L12 21l7.8-7.6 1-1a5.5 5.5 0 0 0 0-7.8Z"
                    />
                  </svg>
                  <span class="sr-only">Saved</span>
                </th>
                <th class="w-24 py-3 text-right font-medium" title="Viewed">
                  <svg
                    class="ml-auto h-4 w-4"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.5"
                    stroke-linejoin="round"
                    aria-hidden="true"
                  >
                    <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8Z" />
                    <circle cx="12" cy="12" r="3" />
                  </svg>
                  <span class="sr-only">Viewed</span>
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-line border-b border-line">
              <tr v-for="(w, i) in visibleRanked" :key="w.id" class="transition-colors hover:bg-dial/40">
                <td class="py-3 pr-2 tabular-nums text-slate-500">{{ i + 1 }}</td>
                <td class="py-3">
                  <router-link
                    :to="`/merchant/watches/${w.id}`"
                    class="group flex min-w-0 items-center gap-4"
                  >
                    <img
                      v-if="thumbnail(w)"
                      v-bind="hero(w.id)"
                      :src="thumbnail(w)"
                      alt=""
                      class="h-10 w-10 shrink-0 rounded-md object-cover"
                    />
                    <div v-else class="h-10 w-10 shrink-0 rounded-md bg-dial"></div>
                    <span class="truncate text-cream transition-colors group-hover:text-gold">
                      {{ w.name || 'Unnamed watch' }}
                    </span>
                  </router-link>
                </td>
                <td class="py-3 text-right tabular-nums text-cream">
                  {{ stats.savedCounts[w.id] ?? 0 }}
                </td>
                <td class="py-3 text-right tabular-nums text-mist">
                  {{ stats.viewedCounts[w.id] ?? 0 }}
                </td>
              </tr>
            </tbody>
          </table>

          <button
            v-if="ranked.length > RANK_PREVIEW"
            type="button"
            class="eyebrow mt-5 text-gold transition-colors hover:text-gold-light"
            @click="showAll = !showAll"
          >
            {{ showAll ? 'Show fewer' : `Show all ${ranked.length} watches` }}
          </button>

          <p class="mt-6 text-xs leading-relaxed text-mist/70">
            Saved = customers who currently have the watch saved. Viewed = distinct customers who
            have viewed it.
          </p>
        </template>
      </section>

      <!-- AR try-on -->
      <section class="border-t border-line pt-6">
        <h2 class="eyebrow">AR try-on</h2>

        <p v-if="engagementLoading" class="mt-6 text-sm text-mist" role="status">
          Loading try-on data...
        </p>

        <p v-else-if="engagementError || !stats" class="alert-error mt-6" role="alert">
          Could not load try-on data. Try refreshing the page.
        </p>

        <div v-else-if="arWatches.length === 0" class="mt-6 border-y border-line py-14 text-center">
          <p class="font-serif text-2xl text-cream">None of your watches is AR ready yet.</p>
          <p class="mt-2 text-sm text-mist">
            Once a watch has a 3D model and fit numbers, customers can try it on and the results
            show here.
          </p>
        </div>

        <div v-else-if="stats.totalTryOns === 0" class="mt-6 border-y border-line py-14 text-center">
          <p class="font-serif text-2xl text-cream">No try-ons yet.</p>
          <p class="mt-2 text-sm text-mist">
            They will appear here once customers try your AR-ready watches on.
          </p>
        </div>

        <template v-else>
          <div class="mt-6 grid grid-cols-3 divide-x divide-line border-y border-line">
            <div v-for="s in tryOnStats" :key="s.label" class="py-8 text-center">
              <p class="font-serif text-5xl font-medium tabular-nums text-cream">{{ s.value }}</p>
              <p class="eyebrow mt-3">{{ s.label }}</p>
            </div>
          </div>

          <dl class="mt-8 max-w-md space-y-3 text-sm">
            <div class="flex justify-between gap-4">
              <dt class="text-mist">Photos shared</dt>
              <dd class="tabular-nums text-cream">{{ stats.totalShares }}</dd>
            </div>
            <div class="flex justify-between gap-4">
              <dt class="text-mist">AR-ready watches tried on</dt>
              <dd class="tabular-nums text-cream">{{ triedOnCount }} of {{ arWatches.length }}</dd>
            </div>
          </dl>

          <table class="mt-10 w-full text-left text-sm">
            <thead>
              <tr class="border-b border-line text-mist">
                <th class="eyebrow w-12 py-3 pr-2 font-medium">#</th>
                <th class="eyebrow py-3 font-medium">Watch</th>
                <th class="w-24 py-3 text-right font-medium" title="Try-ons">
                  <svg
                    class="ml-auto h-4 w-4"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.5"
                    stroke-linejoin="round"
                    aria-hidden="true"
                  >
                    <path d="M12 2.5 3.5 7v10L12 21.5 20.5 17V7L12 2.5Z" />
                    <path d="M3.5 7 12 11.5 20.5 7M12 11.5v10" />
                  </svg>
                  <span class="sr-only">Try-ons</span>
                </th>
                <th class="w-24 py-3 text-right font-medium" title="Customers">
                  <svg
                    class="ml-auto h-4 w-4"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.5"
                    stroke-linejoin="round"
                    aria-hidden="true"
                  >
                    <circle cx="12" cy="8" r="4" />
                    <path d="M4 21c0-4.4 3.6-8 8-8s8 3.6 8 8" />
                  </svg>
                  <span class="sr-only">Customers</span>
                </th>
                <th class="w-24 py-3 text-right font-medium" title="Photos">
                  <svg
                    class="ml-auto h-4 w-4"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.5"
                    stroke-linejoin="round"
                    aria-hidden="true"
                  >
                    <path
                      d="M4 7h3l1.5-2.5h7L17 7h3a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V8a1 1 0 0 1 1-1Z"
                    />
                    <circle cx="12" cy="13" r="3.5" />
                  </svg>
                  <span class="sr-only">Photos</span>
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-line border-b border-line">
              <tr
                v-for="(w, i) in visibleRankedTryOns"
                :key="w.id"
                class="transition-colors hover:bg-dial/40"
              >
                <td class="py-3 pr-2 tabular-nums text-slate-500">{{ i + 1 }}</td>
                <td class="py-3">
                  <router-link
                    :to="`/merchant/watches/${w.id}`"
                    class="group flex min-w-0 items-center gap-4"
                  >
                    <img
                      v-if="thumbnail(w)"
                      v-bind="hero(w.id)"
                      :src="thumbnail(w)"
                      alt=""
                      class="h-10 w-10 shrink-0 rounded-md object-cover"
                    />
                    <div v-else class="h-10 w-10 shrink-0 rounded-md bg-dial"></div>
                    <span class="truncate text-cream transition-colors group-hover:text-gold">
                      {{ w.name || 'Unnamed watch' }}
                    </span>
                  </router-link>
                </td>
                <td class="py-3 text-right tabular-nums text-cream">
                  {{ stats.tryOnCounts[w.id] ?? 0 }}
                </td>
                <td class="py-3 text-right tabular-nums text-mist">
                  {{ stats.tryOnerCounts[w.id] ?? 0 }}
                </td>
                <td class="py-3 text-right tabular-nums text-mist">
                  {{ stats.photoCounts[w.id] ?? 0 }}
                </td>
              </tr>
            </tbody>
          </table>

          <button
            v-if="rankedTryOns.length > RANK_PREVIEW"
            type="button"
            class="eyebrow mt-5 text-gold transition-colors hover:text-gold-light"
            @click="showAllTryOns = !showAllTryOns"
          >
            {{ showAllTryOns ? 'Show fewer' : `Show all ${rankedTryOns.length} watches` }}
          </button>

          <p class="mt-6 text-xs leading-relaxed text-mist/70">
            Try-ons = every time a customer tried the watch on in AR (a repeat counts again).
            Customers = distinct customers who tried it on. Photos = try-on photos captured. Only
            AR-ready watches are listed.
          </p>
        </template>
      </section>
    </template>
  </div>
</template>