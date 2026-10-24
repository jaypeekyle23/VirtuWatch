<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { currentUser } from '../../composables/useAuth'
import { hero } from '../../composables/useHeroTransition'
import { listenToMyWatches, seedMyWatches } from '../../services/watchService'
import { isListed } from '../../utils/catalogFilters'
import { showToast } from '../../composables/useToast'
import {
  isOutOfStock,
  merchantStockLabel,
  needsStockAttention,
  compareByStockUrgency,
  stockAlertCounts,
} from '../../utils/stock'
import StockDialog from '../../components/StockDialog.vue'

// Coming back from a watch's page, this starts filled in (see utils/snapshotCache),
// so the page is already on screen for the hero photo to land on. It refreshes below.
const seededWatches = seedMyWatches(currentUser.value.uid)
const watches = ref(seededWatches ?? [])
const loading = ref(!seededWatches)
const errorMessage = ref('')
let stopListening = null

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

const greeting = computed(() => {
  const h = new Date().getHours()
  return h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening'
})

const stats = computed(() => [
  { label: 'Watches', value: watches.value.length },
  { label: 'Listed', value: watches.value.filter(isListed).length },
  { label: 'AR ready', value: watches.value.filter((w) => w.has3DModel === true).length },
])

const latestWatches = computed(() => watches.value.slice(0, 5))

// ---------- Stock alerts ----------
// Shown only while some watch is out of stock or running low. Lists the most urgent
// few (out of stock first, then the fewest left); selecting one opens the stock
// dialog, so a restock is two clicks. "View all" opens the catalog on just those watches.
const MAX_ALERTS = 4
const flagged = computed(() =>
  watches.value.filter(needsStockAttention).sort(compareByStockUrgency),
)
const alertCounts = computed(() => stockAlertCounts(flagged.value))
const alertSummary = computed(() =>
  [
    alertCounts.value.out > 0 ? `${alertCounts.value.out} out of stock` : '',
    alertCounts.value.low > 0 ? `${alertCounts.value.low} running low` : '',
  ]
    .filter(Boolean)
    .join(', '),
)

const stockTarget = ref(null)
function onStockSaved({ watch: saved }) {
  showToast('success', `Stock updated for "${saved.name}".`)
}

const thumbnail = (w) => w.imageUrls?.[0] || w.imageUrl || ''
const formatPrice = (p) => (p == null ? '' : 'PHP ' + Number(p).toLocaleString('en-PH'))
const size = (w) => (w.caseDiameterMm != null ? `${Number(w.caseDiameterMm).toFixed(1)}mm` : '')
</script>

<template>
  <div class="mx-auto max-w-[88rem]">
    <header>
      <h1 class="font-serif text-5xl font-medium leading-tight text-cream lg:text-6xl">
        {{ greeting }}, {{ currentUser?.username }}
      </h1>
      <p class="mt-3 text-sm text-mist">Manage your catalog.</p>
    </header>

    <p v-if="errorMessage" class="alert-error mt-6" role="alert">{{ errorMessage }}</p>

    <!-- Headline numbers, separated by hairlines only -->
    <div class="mt-10 grid grid-cols-3 divide-x divide-line border-y border-line">
      <router-link
        v-for="s in stats"
        :key="s.label"
        to="/merchant/catalog"
        class="py-8 text-center transition-colors hover:bg-dial/40"
      >
        <p class="font-serif text-5xl font-medium tabular-nums text-cream">
          {{ loading ? '–' : s.value }}
        </p>
        <p class="eyebrow mt-3">{{ s.label }}</p>
      </router-link>
    </div>

    <!-- Stock alerts -->
    <section v-if="!loading && flagged.length" class="mt-12">
      <div class="flex items-baseline justify-between gap-4">
        <h2 class="font-serif text-3xl font-medium text-cream">Stock alerts</h2>
        <router-link
          :to="{ path: '/merchant/catalog', query: { stockAlert: '1' } }"
          class="eyebrow text-cream transition-colors hover:text-gold"
        >
          View all
        </router-link>
      </div>
      <p class="mt-1 text-sm text-mist">{{ alertSummary }}</p>

      <ul class="mt-5 divide-y divide-line border-y border-line">
        <li v-for="watch in flagged.slice(0, MAX_ALERTS)" :key="watch.id">
          <button
            type="button"
            class="flex w-full items-center gap-4 py-4 text-left transition-colors hover:bg-dial/40"
            :aria-label="`Update stock for ${watch.name}`"
            @click="stockTarget = watch"
          >
            <svg
              class="h-[18px] w-[18px] shrink-0"
              :class="isOutOfStock(watch) ? 'text-red-300' : 'text-amber-300'"
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
            <span class="min-w-0 flex-1 truncate text-[15px] font-medium text-cream">
              {{ watch.name || 'Unnamed watch' }}
            </span>
            <span
              class="text-sm font-semibold tabular-nums"
              :class="isOutOfStock(watch) ? 'text-red-300' : 'text-amber-300'"
            >
              {{ merchantStockLabel(watch) }}
            </span>
            <span class="eyebrow w-16 text-right text-cream">Update</span>
          </button>
        </li>
      </ul>
      <p v-if="flagged.length > MAX_ALERTS" class="mt-3 text-xs text-mist">
        + {{ flagged.length - MAX_ALERTS }} more in My catalog
      </p>
    </section>

    <div class="mt-12 grid gap-12 lg:grid-cols-[minmax(0,1fr)_21rem] xl:grid-cols-[minmax(0,1fr)_24rem]">
      <section>
        <div class="flex items-baseline justify-between gap-4">
          <h2 class="font-serif text-3xl font-medium text-cream">Latest watches</h2>
          <router-link
            v-if="latestWatches.length"
            to="/merchant/catalog"
            class="eyebrow text-cream transition-colors hover:text-gold"
          >
            View all
          </router-link>
        </div>

        <p v-if="loading" class="mt-6 text-sm text-mist">Loading...</p>

        <p v-else-if="!latestWatches.length" class="mt-6 text-sm text-mist">
          You haven't listed any watches yet.
        </p>

        <ul v-else class="mt-5 divide-y divide-line border-y border-line">
          <li v-for="watch in latestWatches" :key="watch.id">
            <router-link
              :to="`/merchant/watches/${watch.id}`"
              class="grid grid-cols-[3.5rem_minmax(0,1fr)_auto] items-center gap-x-5 py-4 transition-colors hover:bg-dial/40 md:grid-cols-[3.5rem_minmax(0,1fr)_9rem_5rem_5rem]"
            >
              <img
                v-if="thumbnail(watch)"
                v-bind="hero(watch.id)"
                :src="thumbnail(watch)"
                :alt="watch.name"
                class="h-14 w-14 rounded-md object-cover"
              />
              <div v-else class="h-14 w-14 rounded-md bg-dial"></div>

              <div class="min-w-0">
                <p class="eyebrow truncate text-[10px]">{{ watch.brand || 'No brand' }}</p>
                <p class="mt-0.5 truncate text-[15px] font-medium text-cream">{{ watch.name }}</p>
                <p class="mt-0.5 truncate text-xs tabular-nums text-mist md:hidden">
                  {{ formatPrice(watch.price) }}
                </p>
              </div>

              <p class="hidden text-sm tabular-nums text-cream md:block">
                {{ formatPrice(watch.price) }}
              </p>
              <p class="hidden text-sm tabular-nums text-mist md:block">{{ size(watch) }}</p>

              <span
                class="eyebrow text-right"
                :class="isListed(watch) ? 'text-cream' : 'text-mist/70'"
              >
                {{ isListed(watch) ? 'Listed' : 'Draft' }}
              </span>
            </router-link>
          </li>
        </ul>
      </section>

      <aside class="lg:border-l lg:border-line lg:pl-12">
        <h2 class="font-serif text-3xl font-medium text-cream">List a new watch</h2>
        <p class="mt-2 text-sm text-mist">Add photos, specs and a 3D model.</p>
        <router-link to="/merchant/watches/new" class="btn-primary mt-6 w-full">
          Add watch
        </router-link>

        <nav class="mt-10 divide-y divide-line border-y border-line">
          <router-link
            v-for="l in [
              { to: '/merchant/catalog', label: 'My catalog' },
              { to: '/merchant/analytics', label: 'Analytics' },
            ]"
            :key="l.to"
            :to="l.to"
            class="eyebrow flex items-center justify-between py-4 transition-colors hover:text-cream"
          >
            {{ l.label }}
            <span aria-hidden="true">→</span>
          </router-link>
        </nav>
      </aside>
    </div>

    <StockDialog :target="stockTarget" @saved="onStockSaved" @close="stockTarget = null" />
  </div>
</template>