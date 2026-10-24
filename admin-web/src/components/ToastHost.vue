<script setup>
import { toasts, dismissToast, pauseToast, resumeToast } from '../composables/useToast'

// Draws the toasts from useToast. Mounted once, in App.vue.
const TONES = {
  success: {
    box: 'border-emerald-400/30',
    icon: 'bg-emerald-400/15 text-emerald-300',
    path: 'M5 12.5l4.5 4.5L19 7.5',
  },
  error: {
    box: 'border-red-400/40',
    icon: 'bg-red-400/15 text-red-300',
    path: 'M12 7.5v5.5M12 16.5h.01',
  },
}

function tone(kind) {
  return TONES[kind] ?? TONES.success
}
</script>

<template>
  <Teleport to="body">
    <!-- Above the confirmation dialogs (z-50), so an error is never hidden behind one. -->
    <div
      class="pointer-events-none fixed inset-x-0 bottom-0 z-[60] flex flex-col items-stretch gap-2 p-4 sm:items-end sm:p-6"
      role="region"
      aria-label="Notifications"
    >
      <TransitionGroup name="toast">
        <div
          v-for="toast in toasts"
          :key="toast.id"
          :role="toast.kind === 'error' ? 'alert' : 'status'"
          class="pointer-events-auto flex w-full max-w-sm items-start gap-3 rounded-xl border bg-dial px-4 py-3 shadow-xl shadow-black/40"
          :class="tone(toast.kind).box"
          @mouseenter="pauseToast(toast.id)"
          @mouseleave="resumeToast(toast.id)"
          @focusin="pauseToast(toast.id)"
          @focusout="resumeToast(toast.id)"
        >
          <span
            class="mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full"
            :class="tone(toast.kind).icon"
            aria-hidden="true"
          >
            <svg
              class="h-3.5 w-3.5"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2.5"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <path :d="tone(toast.kind).path" />
            </svg>
          </span>

          <p class="min-w-0 flex-1 text-sm leading-relaxed text-cream">{{ toast.text }}</p>

          <button
            type="button"
            class="-mr-1 shrink-0 rounded-md p-1 text-mist transition-colors hover:text-cream"
            aria-label="Dismiss notification"
            @click="dismissToast(toast.id)"
          >
            <svg
              class="h-4 w-4"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              aria-hidden="true"
            >
              <path d="M6 6l12 12M18 6L6 18" />
            </svg>
          </button>
        </div>
      </TransitionGroup>
    </div>
  </Teleport>
</template>

<style scoped>
.toast-enter-active,
.toast-leave-active {
  transition:
    opacity 0.2s ease,
    transform 0.2s ease;
}

.toast-enter-from {
  opacity: 0;
  transform: translateY(0.5rem);
}

.toast-leave-to {
  opacity: 0;
  transform: translateX(1rem);
}
</style>