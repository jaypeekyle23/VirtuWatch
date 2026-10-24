<script setup>
import { ref, watch, nextTick, onMounted, onUnmounted } from 'vue'

// One confirmation dialog for the whole app. Put the explanation in the default slot.
const props = defineProps({
  open: { type: Boolean, default: false },
  title: { type: String, required: true },
  confirmLabel: { type: String, default: 'Confirm' },
  busyLabel: { type: String, default: 'Working...' },
  cancelLabel: { type: String, default: 'Cancel' },
  // Red confirm button, for destructive actions.
  danger: { type: Boolean, default: false },
  busy: { type: Boolean, default: false },
  error: { type: String, default: '' },
})

const emit = defineEmits(['confirm', 'cancel'])

const titleId = `dialog-title-${Math.random().toString(36).slice(2)}`
const cancelButton = ref(null)

function requestCancel() {
  if (!props.busy) emit('cancel')
}

function onKeydown(event) {
  if (event.key === 'Escape' && props.open) requestCancel()
}

onMounted(() => window.addEventListener('keydown', onKeydown))
onUnmounted(() => window.removeEventListener('keydown', onKeydown))

// Start on Cancel, so a stray Enter press never confirms a destructive action.
watch(
  () => props.open,
  async (isOpen) => {
    if (isOpen) {
      await nextTick()
      cancelButton.value?.focus()
    }
  },
)
</script>

<template>
  <Teleport to="body">
    <div
      v-if="open"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/65 p-4"
      @click.self="requestCancel"
    >
      <div
        role="dialog"
        aria-modal="true"
        :aria-labelledby="titleId"
        class="w-full max-w-md rounded-xl border border-line bg-dial p-6 shadow-2xl shadow-black/50"
      >
        <h2 :id="titleId" class="text-lg font-semibold text-cream">{{ title }}</h2>

        <div class="mt-2 text-sm leading-relaxed text-mist">
          <slot />
        </div>

        <p v-if="error" class="alert-error mt-4" role="alert">{{ error }}</p>

        <div class="mt-6 flex justify-end gap-3">
          <button
            ref="cancelButton"
            type="button"
            class="btn-secondary"
            :disabled="busy"
            @click="requestCancel"
          >
            {{ cancelLabel }}
          </button>
          <button
            type="button"
            :class="danger ? 'btn-danger' : 'btn-primary'"
            :disabled="busy"
            @click="emit('confirm')"
          >
            {{ busy ? busyLabel : confirmLabel }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>