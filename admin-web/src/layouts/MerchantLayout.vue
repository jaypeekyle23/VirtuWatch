<script setup>
import AppShell from '../components/AppShell.vue'

// activeFor keeps My Catalog lit on a watch's detail, edit and add pages too.
const links = [
  { to: '/merchant', label: 'Dashboard', icon: 'dashboard', exact: true },
  {
    to: '/merchant/catalog',
    label: 'My Catalog',
    icon: 'watch',
    activeFor: ['/merchant/catalog', '/merchant/watches'],
  },
  { to: '/merchant/analytics', label: 'Analytics', icon: 'chart' },
  { to: '/merchant/profile', label: 'Profile', icon: 'user' },
]
</script>

<template>
  <AppShell role-label="Merchant" role-tone="merchant" :links="links">
    <router-view />
  </AppShell>
</template>