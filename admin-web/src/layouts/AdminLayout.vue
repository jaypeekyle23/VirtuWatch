<script setup>
import AppShell from '../components/AppShell.vue'

const links = [
  { to: '/admin', label: 'Dashboard', icon: 'dashboard', exact: true },
  { to: '/admin/watches', label: 'Watches', icon: 'watch' },
  { to: '/admin/accounts', label: 'Accounts', icon: 'users' },
  { to: '/admin/profile', label: 'Profile', icon: 'user' },
]
</script>

<template>
  <AppShell role-label="Admin" role-tone="admin" :links="links">
    <router-view />
  </AppShell>
</template>