<script setup>
// The title block at the top of every page. Buttons go in the "actions" slot.
defineProps({
  title: { type: String, required: true },
  subtitle: { type: String, default: '' },
})
</script>

<template>
  <header class="flex flex-wrap items-end justify-between gap-4">
    <div class="min-w-0">
      <h1 class="font-serif text-5xl font-medium leading-tight text-cream lg:text-6xl">
        {{ title }}
      </h1>
      <p v-if="subtitle" class="mt-3 text-sm text-mist">{{ subtitle }}</p>
    </div>
    <div v-if="$slots.actions" class="flex flex-wrap items-center gap-3">
      <slot name="actions" />
    </div>
  </header>
</template>