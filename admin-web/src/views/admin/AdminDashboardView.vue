<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { currentUser } from '../../composables/useAuth'
import {
  listenToAllUsers,
  listenToAllWatches,
  listenToRecentActivity,
} from '../../services/adminService'
import { isArReady, arStatus } from '../../utils/arFit'

const users = ref([])
const watches = ref([])
const activity = ref([])
const usersLoading = ref(true)
const watchesLoading = ref(true)
const activityLoading = ref(true)
const errorMessage = ref('')
const activityError = ref('')
let stopUsers = null
let stopWatches = null
let stopActivity = null

onMounted(() => {
  stopUsers = listenToAllUsers(
    (list) => {
      users.value = list
      usersLoading.value = false
    },
    (err) => {
      console.error(err)
      errorMessage.value = 'Could not load some dashboard data.'
      usersLoading.value = false
    },
  )
  stopWatches = listenToAllWatches(
    (list) => {
      watches.value = list
      watchesLoading.value = false
    },
    (err) => {
      console.error(err)
      errorMessage.value = 'Could not load some dashboard data.'
      watchesLoading.value = false
    },
  )
  stopActivity = listenToRecentActivity(
    (list) => {
      activity.value = list
      activityLoading.value = false
    },
    (err) => {
      console.error(err)
      activityError.value = 'Could not load recent activity.'
      activityLoading.value = false
    },
    10,
  )
})

onUnmounted(() => {
  if (stopUsers) stopUsers()
  if (stopWatches) stopWatches()
  if (stopActivity) stopActivity()
})

const greeting = computed(() => {
  const h = new Date().getHours()
  return h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening'
})

const needsArFit = computed(
  () => watches.value.filter((w) => arStatus(w) === 'needs-fit').length,
)

// An account with no status field is treated as active, same as the Accounts page.
const stats = computed(() => [
  { label: 'Watches', value: watches.value.length, to: '/admin/watches' },
  {
    label: 'AR ready',
    value: watches.value.filter(isArReady).length,
    // Models that are uploaded but cannot show in AR yet because the fit is missing.
    hint: needsArFit.value ? `${needsArFit.value} need AR fit` : undefined,
    to: '/admin/watches',
  },
  {
    label: 'Active users',
    value: users.value.filter((u) => (u.accountStatus ?? 'active') === 'active').length,
    to: '/admin/accounts?filter=Active',
  },
  {
    label: 'Merchants',
    value: users.value.filter((u) => u.role === 'merchant').length,
    to: '/admin/accounts?filter=Merchant',
  },
])

const links = [
  { label: 'Watches', to: '/admin/watches' },
  { label: 'Accounts', to: '/admin/accounts' },
  { label: 'Add account', to: '/admin/accounts/new' },
]

// --- Activity ---
// "5m ago", "3hr ago", etc. The timestamp is briefly null for an entry that
// was only just written, so that case reads as "Just now".
function relativeTime(timestamp) {
  if (!timestamp || typeof timestamp.toDate !== 'function') return 'Just now'
  const date = timestamp.toDate()
  const minutes = Math.floor((Date.now() - date.getTime()) / 60000)
  if (minutes < 1) return 'Just now'
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}hr ago`
  const days = Math.floor(hours / 24)
  if (days < 7) return `${days}d ago`
  return date.toLocaleDateString()
}

// One small outline icon per kind of event (24x24 grid).
const ICONS = {
  userPlus: [
    'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2',
    'M13 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z',
    'M19 8v6M22 11h-6',
  ],
  ban: ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z', 'M5.6 5.6l12.8 12.8'],
  check: ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z', 'M8 12l3 3 5-6'],
  swap: ['M4 8h14M14 4l4 4-4 4', 'M20 16H6M10 12l-4 4 4 4'],
  trash: ['M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3'],
  watch: ['M9 6l1-3h4l1 3M9 18l1 3h4l1-3', 'M12 18a6 6 0 1 0 0-12 6 6 0 0 0 0 12Z', 'M12 9v3l2 1.5'],
  dot: ['M12 13a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z'],
}

function iconFor(type) {
  switch (type) {
    case 'user_registered':
    case 'account_created':
      return ICONS.userPlus
    case 'account_disabled':
      return ICONS.ban
    case 'account_enabled':
      return ICONS.check
    case 'role_changed':
      return ICONS.swap
    case 'account_deleted':
    case 'account_self_deleted':
    case 'watch_deleted':
      return ICONS.trash
    case 'watch_added':
      return ICONS.watch
    default:
      return ICONS.dot
  }
}
</script>

<template>
  <div class="mx-auto max-w-[88rem]">
    <header>
      <h1 class="font-serif text-5xl font-medium leading-tight text-cream lg:text-6xl">
        {{ greeting }}, {{ currentUser?.username }}
      </h1>
      <p class="mt-3 text-sm text-mist">Manage VirtuWatch.</p>
    </header>

    <p v-if="errorMessage" class="alert-error mt-6" role="alert">{{ errorMessage }}</p>

    <!-- Headline numbers, separated by hairlines only -->
    <div class="mt-10 grid grid-cols-3 divide-x divide-line border-y border-line">
      <router-link
        v-for="s in stats"
        :key="s.label"
        :to="s.to"
        class="py-8 text-center transition-colors hover:bg-dial/40"
      >
        <p class="font-serif text-5xl font-medium tabular-nums text-cream">
          {{ usersLoading || watchesLoading ? '–' : s.value }}
        </p>
        <p class="eyebrow mt-3">{{ s.label }}</p>
      </router-link>
    </div>

    <div class="mt-12 grid gap-12 lg:grid-cols-[minmax(0,1fr)_21rem] xl:grid-cols-[minmax(0,1fr)_24rem]">
      <section>
        <h2 class="font-serif text-3xl font-medium text-cream">Recent activity</h2>

        <p v-if="activityLoading" class="mt-6 text-sm text-mist">Loading...</p>

        <p v-else-if="activityError" class="alert-error mt-6" role="alert">
          {{ activityError }}
        </p>

        <p v-else-if="activity.length === 0" class="mt-6 text-sm text-mist">
          Nothing has happened yet.
        </p>

        <ul v-else class="mt-5 divide-y divide-line border-y border-line">
          <li
            v-for="entry in activity"
            :key="entry.id"
            class="grid grid-cols-[1.25rem_minmax(0,1fr)_auto] items-start gap-x-4 py-4"
          >
            <svg
              class="mt-0.5 h-5 w-5 text-mist"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="1.5"
              stroke-linecap="round"
              stroke-linejoin="round"
              aria-hidden="true"
            >
              <path v-for="(d, i) in iconFor(entry.type)" :key="i" :d="d" />
            </svg>
            <p class="text-[15px] leading-snug text-cream">{{ entry.message }}</p>
            <p class="whitespace-nowrap pt-0.5 text-xs text-mist">
              {{ relativeTime(entry.timestamp) }}
            </p>
          </li>
        </ul>
      </section>

      <aside class="lg:border-l lg:border-line lg:pl-12">
        <h2 class="font-serif text-3xl font-medium text-cream">List a new watch</h2>
        <p class="mt-2 text-sm text-mist">Add photos, specs and a 3D model.</p>
        <router-link to="/admin/watches/new" class="btn-primary mt-6 w-full">Add watch</router-link>

        <nav class="mt-10 divide-y divide-line border-y border-line">
          <router-link
            v-for="l in links"
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
  </div>
</template>