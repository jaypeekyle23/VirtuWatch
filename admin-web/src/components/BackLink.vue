<script setup>
// A quiet "go back to the list" link for the top of detail and form pages.
defineProps({
  // A path, or a location object such as { path, query }.
  to: { type: [String, Object], required: true },
})
</script>

<template>
  <router-link
    :to="to"
    class="eyebrow inline-flex items-center gap-2 transition-colors hover:text-cream"
  >
    <svg
      class="h-4 w-4"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M15 6l-6 6 6 6" />
    </svg>
    <slot />
  </router-link>
</template>