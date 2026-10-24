import { createRouter, createWebHistory } from 'vue-router'
import { currentUser, authReady } from '../composables/useAuth'
import { installHeroTransition, scrollForHero } from './heroTransition'
import { rememberListLocation } from './listLocation'
import LoginView from '../views/LoginView.vue'
import ForgotPasswordView from '../views/ForgotPasswordView.vue'
import AdminDashboardView from '../views/admin/AdminDashboardView.vue'
import AdminLayout from '../layouts/AdminLayout.vue'
import AdminAccountsView from '../views/admin/AdminAccountsView.vue'
import AdminCreateAccountView from '../views/admin/AdminCreateAccountView.vue'
import AdminWatchesView from '../views/admin/AdminWatchesView.vue'
import AdminAddWatchView from '../views/admin/AdminAddWatchView.vue'
import AdminEditWatchView from '../views/admin/AdminEditWatchView.vue'
import MerchantLayout from '../layouts/MerchantLayout.vue'
import MerchantDashboardView from '../views/merchant/MerchantDashboardView.vue'
import MerchantCatalogView from '../views/merchant/MerchantCatalogView.vue'
import MerchantAddWatchView from '../views/merchant/MerchantAddWatchView.vue'
import MerchantEditWatchView from '../views/merchant/MerchantEditWatchView.vue'
import MerchantAnalyticsView from '../views/merchant/MerchantAnalyticsView.vue'
import ProfileView from '../views/shared/ProfileView.vue'
import WatchDetailView from '../views/shared/WatchDetailView.vue'

const routes = [
  { path: '/login', name: 'login', component: LoginView, meta: { title: 'Sign in' } },
  { path: '/forgot-password', name: 'forgot-password', component: ForgotPasswordView, meta: { title: 'Reset password' } },
  {
    path: '/admin',
    component: AdminLayout,
    meta: { role: 'admin' },
    children: [
      { path: '', name: 'admin-dashboard', component: AdminDashboardView, meta: { title: 'Dashboard' } },
      { path: 'watches', name: 'admin-watches', component: AdminWatchesView, meta: { title: 'Watches', heroList: true } },
      { path: 'watches/new', name: 'admin-add-watch', component: AdminAddWatchView, meta: { title: 'Add watch' } },
      { path: 'watches/:id', name: 'admin-watch-detail', component: WatchDetailView, meta: { title: 'Watch details' } },
      { path: 'watches/:id/edit', name: 'admin-edit-watch', component: AdminEditWatchView, meta: { title: 'Edit watch' } },
      { path: 'accounts', name: 'admin-accounts', component: AdminAccountsView, meta: { title: 'Accounts' } },
      { path: 'accounts/new', name: 'admin-create-account', component: AdminCreateAccountView, meta: { title: 'Create account' } },
      { path: 'profile', name: 'admin-profile', component: ProfileView, meta: { title: 'Profile' } },
    ],
  },
  {
    path: '/merchant',
    component: MerchantLayout,
    meta: { role: 'merchant' },
    children: [
      { path: '', name: 'merchant-dashboard', component: MerchantDashboardView, meta: { title: 'Dashboard', heroList: true } },
      { path: 'catalog', name: 'merchant-catalog', component: MerchantCatalogView, meta: { title: 'My Catalog', heroList: true } },
      { path: 'watches/new', name: 'merchant-add-watch', component: MerchantAddWatchView, meta: { title: 'Add watch' } },
      { path: 'watches/:id', name: 'merchant-watch-detail', component: WatchDetailView, meta: { title: 'Watch details' } },
      { path: 'watches/:id/edit', name: 'merchant-edit-watch', component: MerchantEditWatchView, meta: { title: 'Edit watch' } },
      { path: 'analytics', name: 'merchant-analytics', component: MerchantAnalyticsView, meta: { title: 'Analytics', heroList: true } },
      { path: 'profile', name: 'merchant-profile', component: ProfileView, meta: { title: 'Profile' } },
    ],
  },
  { path: '/:pathMatch(.*)*', redirect: '/login' },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior(to, from, savedPosition) {
    // Back/forward buttons return to where the person was.
    if (savedPosition) return savedPosition
    // Coming back from a watch: make sure its card is in view for the photo to land on.
    const heroScroll = scrollForHero()
    if (heroScroll !== null) return heroScroll
    // Otherwise a new page starts at the top.
    if (to.path === from.path) return false
    return { top: 0 }
  },
})

installHeroTransition(router)
router.afterEach(rememberListLocation)

// Each route names its page in meta.title. The tab, the browser history and
// screen readers all pick the new page up from document.title.
const APP_NAME = 'VirtuWatch'

router.afterEach((to, from, failure) => {
  // A cancelled navigation (e.g. "keep editing" on the unsaved changes prompt)
  // leaves the person on the old page, so the title stays as it is.
  if (failure) return
  document.title = to.meta.title ? `${to.meta.title} · ${APP_NAME}` : APP_NAME
})

function homeFor(role) {
  return role === 'admin' ? '/admin' : '/merchant'
}

router.beforeEach(async (to) => {
  await authReady
  const user = currentUser.value

  if (to.meta.role) {
    if (!user) return '/login'
    if (user.role !== to.meta.role) return homeFor(user.role)
  }

  if (to.name === 'login' && user) return homeFor(user.role)
})

export default router