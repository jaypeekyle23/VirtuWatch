<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { currentUser } from '../../composables/useAuth'
import { getWatch, deleteWatch } from '../../services/watchService'
import { seedWatch } from '../../utils/snapshotCache'
import { heroFrame } from '../../composables/useHeroTransition'
import { listLocation } from '../../router/listLocation'
import { showToast } from '../../composables/useToast'
import { WATCH_COLORS } from '../../constants/watchOptions'
import { isListed, missingWatchFields, fixLocation } from '../../utils/catalogFilters'
import { arStatus, parseArFit } from '../../utils/arFit'
import { StockStatus, stockStatus, merchantStockLabel } from '../../utils/stock'
import BackLink from '../../components/BackLink.vue'
import ConfirmDialog from '../../components/ConfirmDialog.vue'

const route = useRoute()
const router = useRouter()

// The same page serves both roles; only the links around it differ.
const isAdminView = route.path.startsWith('/admin')
const listPath = isAdminView ? '/admin/watches' : '/merchant/catalog'
// Back to the list as it was left, search and filters included.
const listTo = listLocation(listPath)
const editPath = `${isAdminView ? '/admin' : '/merchant'}/watches/${route.params.id}/edit`

// Opened from a list, the watch is already in memory. Showing it straight away
// lets the photo fly into place; the page still refreshes it from Firestore below.
// (A merchant only ever gets their own watches this way, same as the check below.)
function seededWatch() {
  const cached = seedWatch(route.params.id)
  if (!cached) return null
  const notYours = !isAdminView && cached.merchantId !== currentUser.value?.uid
  return notYours ? null : cached
}
const seeded = seededWatch()

const watch = ref(seeded)
const loading = ref(!seeded)
const notFound = ref(false)
const selectedPhoto = ref(0)

const deleteOpen = ref(false)
const deleting = ref(false)
const deleteError = ref('')

onMounted(async () => {
  try {
    const found = await getWatch(route.params.id)
    // Merchants can only open their own watches (admins can open any).
    const notYours = !isAdminView && found && found.merchantId !== currentUser.value?.uid
    if (!found || notYours) {
      notFound.value = true
    } else {
      watch.value = found
    }
  } catch (e) {
    console.error(e)
    // If the page is already showing the remembered watch, keep it.
    if (!watch.value) notFound.value = true
  } finally {
    loading.value = false
  }
})

const photos = computed(() => {
  const urls = watch.value?.imageUrls
  if (Array.isArray(urls) && urls.length) return urls
  return watch.value?.imageUrl ? [watch.value.imageUrl] : []
})

const colors = computed(() => {
  const w = watch.value
  if (!w) return []
  const hexes =
    Array.isArray(w.colorHexes) && w.colorHexes.length ? w.colorHexes : w.colorHex ? [w.colorHex] : []
  return hexes.slice(0, 3).map((hex) => {
    const match = WATCH_COLORS.find((c) => c.hex.toUpperCase() === hex.toUpperCase())
    return { hex, name: match ? match.name : hex }
  })
})

// "Dress · Women's · Silver / White"
const metaLine = computed(() =>
  [
    watch.value?.styleCategory,
    watch.value?.targetGender,
    colors.value.map((c) => c.name).join(' / '),
  ]
    .filter(Boolean)
    .join(' · '),
)

// Icon shapes for the listing checklist (24x24 grid).
const CHECK = 'M5 12l5 5 9-10'
const DASH = 'M6 12h12'

const missing = computed(() => (watch.value ? missingWatchFields(watch.value) : []))

// "12 in stock", "Low: 2 left" or "Out of stock". Null when no count is on file.
const stockLabel = computed(() => (watch.value ? merchantStockLabel(watch.value) : null))
const stockHealthy = computed(
  () => !!watch.value && stockStatus(watch.value) === StockStatus.IN_STOCK,
)

// One link per missing item, each opening the edit form on that field.
const missingLinks = computed(() =>
  missing.value.map((label) => ({
    label,
    text: label.toLowerCase(),
    to: fixLocation(editPath, label),
  })),
)

// Only rows that have a value are shown, same as the mobile app.
const specs = computed(() => {
  const w = watch.value
  if (!w) return []
  const rows = [
    ['Case diameter', w.caseDiameterMm != null ? `${w.caseDiameterMm}mm` : ''],
    ['Case thickness', w.caseThicknessMm != null ? `${w.caseThicknessMm}mm` : ''],
    ['Lug-to-lug', w.lugToLugMm != null ? `${w.lugToLugMm}mm` : ''],
    ['Band width', w.bandWidthMm != null ? `${w.bandWidthMm}mm` : ''],
    ['Band material', w.bandMaterial || ''],
    ['Case material', w.caseMaterial || ''],
    ['Movement', w.movementType || ''],
    ['Water resistance', w.waterResistance || ''],
  ]
  return rows.filter(([, value]) => value !== '')
})

function formatPrice(price) {
  if (price == null) return ''
  return 'PHP ' + Number(price).toLocaleString('en-PH')
}

function watchLabel() {
  const w = watch.value
  return w.brand ? `${w.brand} ${w.name}` : w.name
}

function cancelDelete() {
  if (deleting.value) return
  deleteOpen.value = false
}

async function confirmDelete() {
  deleting.value = true
  deleteError.value = ''
  try {
    await deleteWatch(route.params.id, watchLabel())
    showToast('success', `Deleted "${watchLabel()}".`)
    router.push(listTo)
  } catch (e) {
    console.error(e)
    deleteError.value = 'Could not delete the watch. Please try again.'
    deleting.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-[88rem]">
    <BackLink :to="listTo">{{ isAdminView ? 'Watch management' : 'My catalog' }}</BackLink>

    <!-- Loading skeleton -->
    <template v-if="loading">
      <p class="sr-only" role="status">Loading watch</p>
      <div class="mt-8 grid gap-10 lg:grid-cols-2" aria-hidden="true">
        <div class="aspect-square animate-pulse rounded-xl bg-dial"></div>
        <div class="space-y-4">
          <div class="h-3 w-24 animate-pulse rounded bg-dial"></div>
          <div class="h-12 w-3/4 animate-pulse rounded bg-dial"></div>
          <div class="h-6 w-32 animate-pulse rounded bg-dial"></div>
          <div class="mt-8 h-64 animate-pulse rounded bg-dial"></div>
        </div>
      </div>
    </template>

    <div v-else-if="notFound" class="mt-8 border-y border-line py-16 text-center">
      <p class="font-serif text-2xl text-cream">This watch could not be found.</p>
      <router-link
        :to="listTo"
        class="eyebrow mt-4 inline-block text-gold transition-colors hover:text-gold-light"
      >
        {{ isAdminView ? 'Back to watch management' : 'Back to catalog' }}
      </router-link>
    </div>

    <div v-else class="mt-8 grid items-start gap-10 lg:grid-cols-2 xl:gap-16">
      <!-- Photos -->
      <div class="lg:sticky lg:top-10">
        <div
          v-bind="heroFrame"
          class="relative aspect-square overflow-hidden rounded-xl bg-case"
        >
          <!-- A blurred copy of the photo fills the frame, so photos of any shape blend in. -->
          <img
            v-if="photos.length"
            :src="photos[selectedPhoto]"
            alt=""
            aria-hidden="true"
            class="absolute inset-0 h-full w-full scale-125 object-cover opacity-70 blur-2xl"
          />
          <img
            v-if="photos.length"
            :src="photos[selectedPhoto]"
            :alt="watch.name"
            class="absolute inset-0 h-full w-full object-contain"
          />
          <div v-else class="flex h-full items-center justify-center text-slate-500">No photos</div>

          <span
            v-if="photos.length > 1"
            class="absolute bottom-3 right-3 rounded-full bg-ink/80 px-2.5 py-1 text-[11px] tabular-nums tracking-wider text-cream backdrop-blur-sm"
          >
            {{ selectedPhoto + 1 }} / {{ photos.length }}
          </span>
        </div>

        <div v-if="photos.length > 1" class="mt-3 flex flex-wrap gap-2.5">
          <button
            v-for="(url, index) in photos"
            :key="url + index"
            type="button"
            class="h-16 w-16 overflow-hidden rounded-md border bg-case transition"
            :class="
              index === selectedPhoto
                ? 'border-gold'
                : 'border-transparent opacity-60 hover:opacity-100'
            "
            :aria-label="`Show photo ${index + 1}`"
            :aria-current="index === selectedPhoto"
            @click="selectedPhoto = index"
          >
            <img :src="url" alt="" class="h-full w-full object-cover" />
          </button>
        </div>
      </div>

      <!-- Details -->
      <div>
        <p v-if="watch.brand" class="eyebrow">{{ watch.brand }}</p>
        <h1 class="mt-3 font-serif text-5xl font-medium leading-tight text-cream">
          {{ watch.name }}
        </h1>
        <p v-if="watch.price != null" class="mt-4 text-lg font-semibold tabular-nums text-cream">
          {{ formatPrice(watch.price) }}
        </p>

        <div v-if="metaLine || colors.length" class="mt-4 flex items-center gap-3 text-sm text-mist">
          <span v-if="colors.length" class="flex -space-x-1" aria-hidden="true">
            <span
              v-for="c in colors"
              :key="c.hex"
              class="h-3.5 w-3.5 rounded-full border border-line"
              :style="{ backgroundColor: c.hex }"
            ></span>
          </span>
          <span>{{ metaLine }}</span>
        </div>

        <!-- Listing -->
        <section class="mt-10 border-t border-line pt-6">
          <h2 class="eyebrow">Listing</h2>
          <p class="mt-4 font-serif text-3xl font-medium text-cream">
            {{ isListed(watch) ? 'Listed' : 'Draft' }}
          </p>
          <p class="mt-1 text-sm text-mist">
            {{ isListed(watch) ? 'Visible to customers in the catalog.' : 'Not visible to customers yet.' }}
          </p>

          <ul class="mt-5 space-y-2.5 text-sm text-cream">
            <li class="flex items-center gap-3">
              <svg class="h-4 w-4 shrink-0 text-mist" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <path :d="arStatus(watch) === 'ready' ? CHECK : DASH" />
              </svg>
              <span v-if="arStatus(watch) === 'ready'">AR try-on is available</span>
              <span v-else-if="arStatus(watch) === 'needs-fit'">
                <template v-if="isAdminView">
                  3D model uploaded, but it needs AR fit.
                  <router-link
                    :to="{ path: editPath, query: { focus: 'holeCx' } }"
                    class="text-gold underline underline-offset-2 transition-colors hover:text-gold-light"
                    >Add it</router-link
                  >
                </template>
                <template v-else>3D model uploaded, AR fit pending review</template>
              </span>
              <span v-else-if="arStatus(watch) === 'unsupported'">
                The 3D model is not a .glb, so AR try-on is unavailable
              </span>
              <span v-else>No 3D model, so AR try-on is unavailable</span>
            </li>
            <li v-if="isAdminView && parseArFit(watch)" class="flex items-start gap-3">
              <svg class="mt-0.5 h-4 w-4 shrink-0 text-mist" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <path d="M12 3l8 4.5v9L12 21l-8-4.5v-9L12 3Z" />
              </svg>
              <span class="tabular-nums text-mist">
                Centre {{ parseArFit(watch).holeCx }}, half-thickness {{ parseArFit(watch).holeHalfX }}, half-width {{ parseArFit(watch).holeHalfY }}, scale {{ parseArFit(watch).scale }}
              </span>
            </li>
            <li class="flex items-center gap-3">
              <svg class="h-4 w-4 shrink-0 text-mist" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <path :d="stockHealthy ? CHECK : DASH" />
              </svg>
              <span v-if="stockLabel" class="tabular-nums">{{ stockLabel }}</span>
              <span v-else>
                No stock count yet.
                <router-link
                  :to="fixLocation(editPath, 'Stock')"
                  class="text-gold underline underline-offset-2 transition-colors hover:text-gold-light"
                  >Add one</router-link
                >
              </span>
            </li>
            <li class="flex items-start gap-3">
              <svg class="mt-0.5 h-4 w-4 shrink-0 text-mist" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <path :d="missing.length ? DASH : CHECK" />
              </svg>
              <span v-if="!missing.length">Key details are filled in</span>
              <span v-else>
                Missing
                <span v-for="(item, i) in missingLinks" :key="item.label">
                  <router-link
                    :to="item.to"
                    class="text-gold underline underline-offset-2 transition-colors hover:text-gold-light"
                    >{{ item.text }}</router-link
                  ><template v-if="i < missingLinks.length - 2">, </template
                  ><template v-else-if="i === missingLinks.length - 2"> and </template> </span
                >. Select one to fill it in, so recommendations and fit checks work.
              </span>
            </li>
          </ul>
        </section>

        <!-- Specs -->
        <section class="mt-8 border-t border-line pt-6">
          <h2 class="eyebrow">Specifications</h2>
          <dl v-if="specs.length" class="mt-5 space-y-3.5 text-sm">
            <div v-for="[label, value] in specs" :key="label" class="flex justify-between gap-6">
              <dt class="text-mist">{{ label }}</dt>
              <dd class="text-right text-cream">{{ value }}</dd>
            </div>
          </dl>
          <p v-else class="mt-4 text-sm text-mist">No specifications added yet.</p>
        </section>

        <!-- Actions -->
        <div class="mt-10 flex items-center gap-3">
          <router-link :to="editPath" class="btn-primary flex-1 sm:flex-none sm:px-10">
            Edit details
          </router-link>
          <button
            type="button"
            class="inline-flex h-10 w-10 items-center justify-center rounded-lg border border-red-400/40 text-red-300 transition-colors hover:bg-red-400/10"
            aria-label="Delete watch"
            title="Delete watch"
            @click="deleteOpen = true"
          >
            <svg class="h-[18px] w-[18px]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3" />
            </svg>
          </button>
        </div>
      </div>
    </div>

    <ConfirmDialog
      :open="deleteOpen"
      title="Delete this watch?"
      confirm-label="Delete"
      busy-label="Deleting..."
      danger
      :busy="deleting"
      :error="deleteError"
      @confirm="confirmDelete"
      @cancel="cancelDelete"
    >
      <span class="font-medium text-cream">{{ watch?.name }}</span> will be permanently removed,
      and it will disappear from customers' saved lists. This can't be undone.
    </ConfirmDialog>
  </div>
</template>