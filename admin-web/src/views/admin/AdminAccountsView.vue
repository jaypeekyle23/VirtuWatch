<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRoute } from 'vue-router'
import { currentUser } from '../../composables/useAuth'
import { showToast } from '../../composables/useToast'
import {
  listenToAllUsers,
  suspendAccount,
  reactivateAccount,
  updateUserRole,
  deleteAccountProfile,
} from '../../services/adminService'
import PageHeader from '../../components/PageHeader.vue'
import ConfirmDialog from '../../components/ConfirmDialog.vue'

const FILTERS = ['All', 'Active', 'Disabled', 'Admin', 'Merchant']
const ROLES = ['customer', 'merchant', 'admin']

const route = useRoute()

const users = ref([])
const loading = ref(true)
const errorMessage = ref('')
const searchQuery = ref('')
// Lets other pages link here pre-filtered, e.g. /admin/accounts?filter=Merchant
const selectedFilter = ref(FILTERS.includes(route.query.filter) ? route.query.filter : 'All')
let stopListening = null

onMounted(() => {
  stopListening = listenToAllUsers(
    (list) => {
      users.value = list
      loading.value = false
    },
    (err) => {
      console.error(err)
      errorMessage.value = 'Could not load accounts.'
      loading.value = false
    },
  )
})

onUnmounted(() => {
  if (stopListening) stopListening()
})

const filteredUsers = computed(() => {
  let list = [...users.value]

  if (selectedFilter.value === 'Active') {
    list = list.filter((u) => (u.accountStatus ?? 'active') === 'active')
  } else if (selectedFilter.value === 'Disabled') {
    list = list.filter((u) => u.accountStatus === 'suspended')
  } else if (selectedFilter.value === 'Admin') {
    list = list.filter((u) => u.role === 'admin')
  } else if (selectedFilter.value === 'Merchant') {
    list = list.filter((u) => u.role === 'merchant')
  }

  const q = searchQuery.value.trim().toLowerCase()
  if (q) {
    list = list.filter(
      (u) =>
        (u.username || '').toLowerCase().includes(q) ||
        (u.email || '').toLowerCase().includes(q),
    )
  }

  // Newest accounts first.
  list.sort((a, b) => {
    const aTime = a.createdAt?.toMillis?.() ?? 0
    const bTime = b.createdAt?.toMillis?.() ?? 0
    return bTime - aTime
  })

  return list
})

function clearAll() {
  searchQuery.value = ''
  selectedFilter.value = 'All'
}

// Up to two initials. Leading symbols like the "[" in "[NTC-S] Jane" are skipped.
function initials(user) {
  const name = (user.username || '').trim()
  if (!name) return '?'
  const letters = name
    .split(/\s+/)
    .map((part) => part.replace(/^[^\p{L}\p{N}]+/u, ''))
    .filter(Boolean)
    .map((part) => part[0])
    .slice(0, 2)
    .join('')
    .toUpperCase()
  return letters || '?'
}

function roleOf(user) {
  return user.role || 'customer'
}

function capitalize(text) {
  return text.charAt(0).toUpperCase() + text.slice(1)
}

function isActive(user) {
  return (user.accountStatus ?? 'active') === 'active'
}

function isSelf(user) {
  return user.id === currentUser.value?.uid
}

// Only a disabled account (or your own) gets a status; everyone else has none.
function statusLabel(user) {
  if (!isActive(user)) return 'Disabled'
  if (isSelf(user)) return 'You'
  return ''
}

// Disabled accounts are shown faded.
const dim = (user) => (isActive(user) ? '' : 'opacity-60')

const chipClass = (active) => [
  'rounded-full border px-4 py-2 text-sm transition-colors',
  active
    ? 'border-cream/70 bg-dial text-cream'
    : 'border-line text-mist hover:border-mist/50 hover:text-cream',
]

const COLUMNS =
  'grid grid-cols-[2.75rem_minmax(0,1fr)_auto_2rem] items-center gap-x-4 md:grid-cols-[2.75rem_minmax(0,1.2fr)_minmax(0,1.2fr)_7rem_6rem_2rem]'
const menuItem = 'block w-full px-4 py-2 text-left text-xs transition-colors hover:bg-dial'

function accountLabel(user) {
  return `${user.username || 'Unknown'} (${user.email || user.id})`
}

// --- Confirmation dialog ---
// type: 'toggle' (disable / enable), 'role' (change role), 'delete'
const dialog = ref(null)
const busy = ref(false)

function openToggle(user) {
  dialog.value = { type: 'toggle', user }
}

function openRole(user) {
  const firstOther = ROLES.find((r) => r !== roleOf(user))
  dialog.value = { type: 'role', user, newRole: firstOther, confirming: false }
}

function openDelete(user) {
  dialog.value = { type: 'delete', user }
}

function closeDialog() {
  if (busy.value) return
  dialog.value = null
}

const dialogTitle = computed(() => {
  const d = dialog.value
  if (!d) return ''
  if (d.type === 'toggle') return isActive(d.user) ? 'Disable account?' : 'Enable account?'
  if (d.type === 'role') return d.confirming ? 'Are you sure?' : 'Change role'
  return 'Delete account?'
})

const dialogConfirmLabel = computed(() => {
  const d = dialog.value
  if (!d) return 'Confirm'
  if (d.type === 'toggle') return isActive(d.user) ? 'Disable' : 'Enable'
  if (d.type === 'role') return d.confirming ? 'Change role' : 'Continue'
  return 'Delete'
})

const dialogDanger = computed(() => {
  const d = dialog.value
  if (!d) return false
  return d.type === 'delete' || (d.type === 'toggle' && isActive(d.user))
})

// The role dialog has two steps: pick a role, then confirm it.
function onDialogConfirm() {
  const d = dialog.value
  if (d?.type === 'role' && !d.confirming) {
    d.confirming = true
    return
  }
  runDialogAction()
}

async function runDialogAction() {
  const d = dialog.value
  if (!d) return
  busy.value = true
  try {
    const label = accountLabel(d.user)
    if (d.type === 'toggle') {
      if (isActive(d.user)) {
        await suspendAccount(d.user.id, label)
        showToast('success', 'Account disabled.')
      } else {
        await reactivateAccount(d.user.id, label)
        showToast('success', 'Account re-enabled.')
      }
    } else if (d.type === 'role') {
      await updateUserRole(d.user.id, d.newRole, label, roleOf(d.user))
      showToast('success', `Role changed to ${capitalize(d.newRole)}.`)
    } else if (d.type === 'delete') {
      await deleteAccountProfile(d.user.id, label)
      showToast('success', 'Account profile deleted.')
    }
    dialog.value = null
  } catch (e) {
    console.error(e)
    dialog.value = null
    showToast('error', typeof e === 'string' ? e : 'That did not work. Please try again.')
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-[88rem]">
    <PageHeader title="Accounts" subtitle="View and manage every VirtuWatch account.">
      <template #actions>
        <router-link to="/admin/accounts/new" class="btn-primary">Add account</router-link>
      </template>
    </PageHeader>

    <p v-if="errorMessage" class="alert-error mt-6" role="alert">{{ errorMessage }}</p>

    <!-- Search: one hairline underneath -->
    <div class="relative mt-10 border-b border-line transition-colors focus-within:border-gold/60">
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
        v-model="searchQuery"
        type="text"
        placeholder="Search by name or email"
        aria-label="Search accounts"
        class="w-full bg-transparent py-3.5 pl-8 pr-2 text-sm text-cream outline-none placeholder:text-slate-500"
      />
    </div>

    <!-- Filters -->
    <div class="mt-5 flex flex-wrap items-center gap-2.5" role="group" aria-label="Filter accounts">
      <button
        v-for="filter in FILTERS"
        :key="filter"
        type="button"
        :class="chipClass(selectedFilter === filter)"
        :aria-pressed="selectedFilter === filter"
        @click="selectedFilter = filter"
      >
        {{ filter }}
      </button>

      <p v-if="!loading" class="ml-auto text-xs tabular-nums text-mist">
        {{ filteredUsers.length }} of {{ users.length }}
        {{ users.length === 1 ? 'account' : 'accounts' }}
      </p>
    </div>

    <!-- Loading skeleton -->
    <template v-if="loading">
      <p class="sr-only" role="status">Loading accounts</p>
      <div class="mt-8 divide-y divide-line border-y border-line" aria-hidden="true">
        <div v-for="n in 5" :key="n" class="flex items-center gap-4 py-4">
          <div class="h-11 w-11 animate-pulse rounded-full bg-dial"></div>
          <div class="flex-1 space-y-2">
            <div class="h-3.5 w-40 animate-pulse rounded bg-dial"></div>
            <div class="h-3 w-56 animate-pulse rounded bg-dial"></div>
          </div>
        </div>
      </div>
    </template>

    <div v-else-if="filteredUsers.length === 0" class="mt-8 border-y border-line py-16 text-center">
      <p class="text-cream">No accounts match your search or filter.</p>
      <button
        type="button"
        class="eyebrow mt-4 text-gold transition-colors hover:text-gold-light"
        @click="clearAll"
      >
        Clear search and filter
      </button>
    </div>

    <div v-else class="mt-8">
      <!-- Column headings: wide screens only -->
      <div :class="COLUMNS" class="hidden border-t border-line py-3 md:grid">
        <span></span>
        <span class="eyebrow">Name</span>
        <span class="eyebrow">Email</span>
        <span class="eyebrow">Role</span>
        <span class="eyebrow">Status</span>
        <span></span>
      </div>

      <ul class="divide-y divide-line border-y border-line">
        <li v-for="user in filteredUsers" :key="user.id" :class="COLUMNS" class="py-4">
          <img
            v-if="user.photoUrl"
            :src="user.photoUrl"
            alt=""
            class="h-11 w-11 rounded-full border border-line object-cover"
            :class="dim(user)"
          />
          <div
            v-else
            class="flex h-11 w-11 items-center justify-center rounded-full border border-line bg-dial text-sm tracking-wide text-cream/80"
            :class="dim(user)"
          >
            {{ initials(user) }}
          </div>

          <div class="min-w-0" :class="dim(user)">
            <p class="truncate text-[15px] font-medium text-cream">{{ user.username || 'Unknown' }}</p>
            <p class="truncate text-sm text-mist md:hidden">{{ user.email }}</p>
          </div>

          <p class="hidden truncate text-sm text-mist md:block" :class="dim(user)">
            {{ user.email }}
          </p>

          <div class="text-right md:text-left" :class="dim(user)">
            <p class="eyebrow text-cream">{{ roleOf(user) }}</p>
            <p v-if="statusLabel(user)" class="mt-0.5 text-[10px] uppercase tracking-[0.18em] text-mist md:hidden">
              {{ statusLabel(user) }}
            </p>
          </div>

          <p class="eyebrow hidden md:block" :class="dim(user)">{{ statusLabel(user) }}</p>

          <!-- Your own account has no actions, so you can't lock yourself out. -->
          <div v-if="!isSelf(user)" class="group/menu relative justify-self-end">
            <button
              type="button"
              class="rounded-md px-1.5 text-lg leading-none tracking-widest text-mist transition-colors hover:text-cream"
              :aria-label="`Actions for ${user.username || 'account'}`"
              aria-haspopup="menu"
            >
              ···
            </button>
            <div
              class="invisible absolute right-0 top-full z-10 pt-2 opacity-0 transition group-focus-within/menu:visible group-focus-within/menu:opacity-100 group-hover/menu:visible group-hover/menu:opacity-100"
            >
              <div class="w-40 rounded-lg border border-line bg-case py-1.5 shadow-lg shadow-black/40">
                <button type="button" :class="[menuItem, 'text-cream']" @click="openToggle(user)">
                  {{ isActive(user) ? 'Disable' : 'Enable' }}
                </button>
                <button type="button" :class="[menuItem, 'text-cream']" @click="openRole(user)">
                  Change role
                </button>
                <button type="button" :class="[menuItem, 'text-red-300']" @click="openDelete(user)">
                  Delete
                </button>
              </div>
            </div>
          </div>
          <span v-else></span>
        </li>
      </ul>
    </div>

    <ConfirmDialog
      :open="!!dialog"
      :title="dialogTitle"
      :confirm-label="dialogConfirmLabel"
      :danger="dialogDanger"
      :busy="busy"
      @confirm="onDialogConfirm"
      @cancel="closeDialog"
    >
      <!-- Disable / enable -->
      <template v-if="dialog?.type === 'toggle'">
        <template v-if="isActive(dialog.user)">
          <span class="font-medium text-cream">{{ dialog.user.username }}</span> will no longer be
          able to sign in until the account is enabled again.
        </template>
        <template v-else>
          <span class="font-medium text-cream">{{ dialog.user.username }}</span> will be able to
          sign in again.
        </template>
      </template>

      <!-- Change role, step 1: pick -->
      <template v-else-if="dialog?.type === 'role' && !dialog.confirming">
        <p>
          Choose a new role for
          <span class="font-medium text-cream">{{ dialog.user.username }}</span>. Current role:
          {{ capitalize(roleOf(dialog.user)) }}.
        </p>
        <div class="mt-4 space-y-2">
          <label
            v-for="role in ROLES.filter((r) => r !== roleOf(dialog.user))"
            :key="role"
            class="flex cursor-pointer items-center gap-3 rounded-lg border px-3.5 py-2.5 text-cream transition-colors"
            :class="dialog.newRole === role ? 'border-gold/50 bg-gold/10' : 'border-line'"
          >
            <input v-model="dialog.newRole" type="radio" :value="role" class="accent-gold" />
            {{ capitalize(role) }}
          </label>
        </div>
      </template>

      <!-- Change role, step 2: confirm -->
      <template v-else-if="dialog?.type === 'role' && dialog.confirming">
        Change <span class="font-medium text-cream">{{ dialog.user.username }}</span> from
        {{ capitalize(roleOf(dialog.user)) }} to {{ capitalize(dialog.newRole) }}? Their access
        changes right away.
      </template>

      <!-- Delete -->
      <template v-else-if="dialog?.type === 'delete'">
        This deletes the profile for
        <span class="font-medium text-cream">{{ dialog.user.username }}</span>
        ({{ dialog.user.email }}). They will no longer be able to use VirtuWatch. This can't be
        undone.
      </template>
    </ConfirmDialog>
  </div>
</template>