<script setup>
import { ref, computed, watch, nextTick, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { logout } from '../services/authService'
import { currentUser } from '../composables/useAuth'
import { logoSrc } from '../composables/useTheme'
import ConfirmDialog from './ConfirmDialog.vue'

const props = defineProps({
  roleLabel: { type: String, required: true },
  // Kept so existing layouts still work. The role label no longer changes color.
  roleTone: { type: String, default: 'merchant' },
  // [{ to, label, icon, exact?, activeFor? }]
  links: { type: Array, required: true },
})

const route = useRoute()
const router = useRouter()

const drawerOpen = ref(false)

// Simple line icons, drawn on a 24x24 grid.
const ICONS = {
  dashboard: ['M3 3h7v9H3z', 'M14 3h7v5h-7z', 'M14 12h7v9h-7z', 'M3 16h7v5H3z'],
  watch: [
    'M12 6a6 6 0 1 0 0 12 6 6 0 0 0 0-12Z',
    'M12 9v3l2 1',
    'M9 6l.7-4h4.6L15 6',
    'M9 18l.7 4h4.6l.7-4',
  ],
  users: [
    'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2',
    'M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8Z',
    'M22 21v-2a4 4 0 0 0-3-3.9',
    'M16 3.1a4 4 0 0 1 0 7.8',
  ],
  chart: ['M3 3v18h18', 'M7 15l4-4 3 3 5-6'],
  user: ['M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2', 'M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8Z'],
  logout: ['M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4', 'M16 17l5-5-5-5', 'M21 12H9'],
  menu: ['M4 6h16', 'M4 12h16', 'M4 18h16'],
  close: ['M6 6l12 12', 'M18 6L6 18'],
  panelClose: [
    'M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Z',
    'M9 3v18',
    'M16 15l-3-3 3-3',
  ],
  panelOpen: [
    'M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Z',
    'M9 3v18',
    'M14 9l3 3-3 3',
  ],
}

// A link is active on its own page and on everything beneath it, so
// "Watches" stays lit on a watch's detail and edit pages.
// exact: true limits it to the page itself (used for Dashboard).
function isActive(link) {
  if (link.exact) return route.path === link.to
  const prefixes = link.activeFor ?? [link.to]
  return prefixes.some((p) => route.path === p || route.path.startsWith(p + '/'))
}

const initial = computed(() => (currentUser.value?.username || '?').charAt(0).toUpperCase())

// Large screens only: the sidebar can be tucked away to give the page more room,
// and the choice is remembered. Small screens use the menu button and drawer.
const SIDEBAR_KEY = 'virtuwatch:sidebar-hidden'

function readSidebarHidden() {
  try {
    return localStorage.getItem(SIDEBAR_KEY) === '1'
  } catch {
    return false
  }
}

const sidebarHidden = ref(readSidebarHidden())
const hideButton = ref(null)
const showButton = ref(null)

// A hidden sidebar slides off screen but is still in the page, so on large screens
// it is made inert (no Tab, no screen reader). On small screens the same element is
// the drawer and must stay usable.
const desktopQuery = window.matchMedia('(min-width: 1024px)')
const isDesktop = ref(desktopQuery.matches)
function onDesktopChange(event) {
  isDesktop.value = event.matches
}

async function setSidebarHidden(hidden) {
  sidebarHidden.value = hidden
  try {
    localStorage.setItem(SIDEBAR_KEY, hidden ? '1' : '0')
  } catch {
    // Storage can be blocked (private mode). It just won't be remembered.
  }
  // The button that was just pressed disappears, so focus goes to its counterpart.
  await nextTick()
  ;(hidden ? showButton : hideButton).value?.focus({ preventScroll: true })
}

// Signing out asks first, so a stray click doesn't end the session.
const logoutOpen = ref(false)
const signingOut = ref(false)
const logoutError = ref('')

function askLogout() {
  logoutError.value = ''
  drawerOpen.value = false
  logoutOpen.value = true
}

function cancelLogout() {
  if (signingOut.value) return
  logoutOpen.value = false
}

async function confirmLogout() {
  signingOut.value = true
  logoutError.value = ''
  try {
    await logout()
    logoutOpen.value = false
    router.push('/login')
  } catch (e) {
    console.error(e)
    logoutError.value = 'Could not sign out. Please try again.'
  } finally {
    signingOut.value = false
  }
}

// Close the drawer after navigating, and on Escape.
watch(
  () => route.fullPath,
  () => {
    drawerOpen.value = false
  },
)

function onKeydown(event) {
  if (event.key === 'Escape') drawerOpen.value = false
}

onMounted(() => {
  window.addEventListener('keydown', onKeydown)
  desktopQuery.addEventListener('change', onDesktopChange)
})
onUnmounted(() => {
  window.removeEventListener('keydown', onKeydown)
  desktopQuery.removeEventListener('change', onDesktopChange)
})
</script>

<template>
  <div class="min-h-screen lg:flex">
    <!-- Dim backdrop behind the drawer on small screens -->
    <div
      v-if="drawerOpen"
      class="fixed inset-0 z-30 bg-black/60 lg:hidden"
      @click="drawerOpen = false"
    ></div>

    <aside
      id="app-sidebar"
      class="fixed inset-y-0 left-0 z-40 flex w-64 flex-col border-r border-line bg-case px-4 pb-4 pt-5 transition-[transform,margin-left] duration-200 ease-in-out motion-reduce:transition-none lg:sticky lg:left-auto lg:top-0 lg:h-screen lg:shrink-0 lg:translate-x-0 lg:duration-300"
      :class="[drawerOpen ? 'translate-x-0' : '-translate-x-full', { 'lg:-ml-64': sidebarHidden }]"
      :inert="sidebarHidden && isDesktop"
    >
      <!-- Hide the sidebar (large screens) -->
      <button
        ref="hideButton"
        type="button"
        class="absolute right-3 top-4 hidden rounded-lg p-2 text-mist transition-colors hover:bg-dial hover:text-cream focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gold lg:inline-flex"
        aria-label="Hide sidebar"
        title="Hide sidebar"
        aria-controls="app-sidebar"
        aria-expanded="true"
        @click="setSidebarHidden(true)"
      >
        <svg
          class="h-5 w-5"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.5"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <path v-for="(d, i) in ICONS.panelClose" :key="i" :d="d" />
        </svg>
      </button>

      <div class="px-2 pb-7">
        <img :src="logoSrc" alt="VirtuWatch" class="w-36" />
        <p class="eyebrow mt-4 text-gold">{{ roleLabel }}</p>
      </div>

      <!-- Hairline-divided rows, like the dashboard's lists -->
      <nav class="divide-y divide-line border-y border-line" aria-label="Main">
        <router-link
          v-for="link in links"
          :key="link.to"
          :to="link.to"
          class="relative flex items-center gap-3.5 px-3 py-4 text-[11px] font-medium uppercase tracking-[0.18em] transition-colors"
          :class="isActive(link) ? 'bg-dial/40 text-cream' : 'text-mist hover:text-cream'"
          :aria-current="isActive(link) ? 'page' : undefined"
        >
          <span v-if="isActive(link)" class="absolute inset-y-0 left-0 w-0.5 bg-gold"></span>
          <svg
            class="h-[18px] w-[18px] shrink-0"
            :class="isActive(link) ? 'text-gold' : ''"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.5"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden="true"
          >
            <path v-for="(d, i) in ICONS[link.icon]" :key="i" :d="d" />
          </svg>
          {{ link.label }}
        </router-link>
      </nav>

      <div class="flex-1"></div>

      <!-- Signed-in user -->
      <div>
        <div class="flex items-center gap-3 px-2">
          <img
            v-if="currentUser?.photoUrl"
            :src="currentUser.photoUrl"
            alt=""
            class="h-10 w-10 shrink-0 rounded-full object-cover"
          />
          <div
            v-else
            class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full border border-line bg-dial font-serif text-lg text-gold"
          >
            {{ initial }}
          </div>
          <div class="min-w-0">
            <p class="truncate font-serif text-lg leading-tight text-cream">
              {{ currentUser?.username }}
            </p>
            <p class="truncate text-xs text-mist">{{ currentUser?.email }}</p>
          </div>
        </div>

        <button
          type="button"
          class="mt-5 flex w-full items-center gap-3.5 border-t border-line px-3 pt-4 text-[11px] font-medium uppercase tracking-[0.18em] text-mist transition-colors hover:text-cream"
          @click="askLogout"
        >
          <svg
            class="h-[18px] w-[18px] shrink-0"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.5"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden="true"
          >
            <path v-for="(d, i) in ICONS.logout" :key="i" :d="d" />
          </svg>
          Sign out
        </button>
      </div>
    </aside>

    <div class="min-w-0 flex-1">
      <!-- Show the sidebar again (large screens, while it is hidden) -->
      <Transition
        enter-active-class="transition duration-300 ease-out motion-reduce:transition-none"
        enter-from-class="-translate-x-2 opacity-0"
        leave-active-class="transition duration-150 ease-in motion-reduce:transition-none"
        leave-to-class="opacity-0"
      >
        <button
          v-if="sidebarHidden"
          ref="showButton"
          type="button"
          class="fixed left-4 top-4 z-30 hidden rounded-lg border border-line bg-case p-2 text-mist hover:bg-dial hover:text-cream focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gold lg:inline-flex"
          aria-label="Show sidebar"
          title="Show sidebar"
          aria-controls="app-sidebar"
          aria-expanded="false"
          @click="setSidebarHidden(false)"
        >
          <svg
            class="h-5 w-5"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.5"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden="true"
          >
            <path v-for="(d, i) in ICONS.panelOpen" :key="i" :d="d" />
          </svg>
        </button>
      </Transition>

      <!-- Top bar, small screens only -->
      <header
        class="sticky top-0 z-20 flex h-14 items-center justify-between border-b border-line bg-case px-4 lg:hidden"
      >
        <img :src="logoSrc" alt="VirtuWatch" class="h-9 w-auto" />
        <button
          type="button"
          class="rounded-lg p-2 text-mist hover:bg-dial hover:text-cream"
          :aria-label="drawerOpen ? 'Close menu' : 'Open menu'"
          :aria-expanded="drawerOpen"
          @click="drawerOpen = !drawerOpen"
        >
          <svg
            class="h-6 w-6"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.5"
            stroke-linecap="round"
            aria-hidden="true"
          >
            <path v-for="(d, i) in drawerOpen ? ICONS.close : ICONS.menu" :key="i" :d="d" />
          </svg>
        </button>
      </header>

      <main
        class="px-5 py-8 sm:px-8 lg:py-10 lg:pr-12 lg:transition-[padding-left] lg:duration-300 lg:ease-in-out motion-reduce:transition-none"
        :class="sidebarHidden ? 'lg:pl-20' : 'lg:pl-12'"
      >
        <slot />
      </main>
    </div>

    <ConfirmDialog
      :open="logoutOpen"
      title="Sign out?"
      confirm-label="Sign out"
      busy-label="Signing out..."
      :busy="signingOut"
      :error="logoutError"
      @confirm="confirmLogout"
      @cancel="cancelLogout"
    >
      You'll need to sign in again to get back into your account.
    </ConfirmDialog>
  </div>
</template>