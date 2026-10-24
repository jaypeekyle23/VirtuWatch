<script setup>
import { ref, onUnmounted } from 'vue'
import { useRoute } from 'vue-router'
import AuthLayout from '../components/AuthLayout.vue'
import { resetPassword } from '../services/authService'

const RESEND_COOLDOWN_SECONDS = 30

const route = useRoute()

// The login page can pass along whatever the user already typed.
const email = ref(typeof route.query.email === 'string' ? route.query.email : '')
const errorMessage = ref('')
const loading = ref(false)
const sent = ref(false)
const cooldown = ref(0)
let cooldownTimer = null

onUnmounted(() => clearInterval(cooldownTimer))

function startCooldown() {
  cooldown.value = RESEND_COOLDOWN_SECONDS
  clearInterval(cooldownTimer)
  cooldownTimer = setInterval(() => {
    cooldown.value -= 1
    if (cooldown.value <= 0) clearInterval(cooldownTimer)
  }, 1000)
}

async function sendLink() {
  errorMessage.value = ''
  loading.value = true
  try {
    await resetPassword(email.value)
    sent.value = true
    startCooldown()
  } catch (e) {
    errorMessage.value = typeof e === 'string' ? e : 'Something went wrong. Please try again.'
  } finally {
    loading.value = false
  }
}

function resend() {
  if (cooldown.value > 0 || loading.value) return
  sendLink()
}

function useDifferentEmail() {
  sent.value = false
  errorMessage.value = ''
}
</script>

<template>
  <AuthLayout>
    <!-- Step 1: ask for the email -->
    <template v-if="!sent">
      <h1 class="text-2xl font-semibold text-cream">Reset your password</h1>
      <p class="mt-1 text-sm leading-relaxed text-mist">
        Enter the email for your account and we'll send you a link to choose a new password.
      </p>

      <form class="mt-8 space-y-5" @submit.prevent="sendLink">
        <p v-if="errorMessage" class="alert-error" role="alert">{{ errorMessage }}</p>

        <div>
          <label for="reset-email" class="label">Email</label>
          <input
            id="reset-email"
            v-model="email"
            type="email"
            required
            autocomplete="email"
            class="input"
          />
        </div>

        <button type="submit" :disabled="loading" class="btn-primary w-full">
          {{ loading ? 'Sending...' : 'Send reset link' }}
        </button>
      </form>

      <p class="mt-6 text-center text-sm">
        <router-link to="/login" class="text-gold hover:text-gold-light">
          Back to sign in
        </router-link>
      </p>
    </template>

    <!-- Step 2: confirmation -->
    <template v-else>
      <div
        class="flex h-12 w-12 items-center justify-center rounded-full bg-gold/15 text-gold"
        aria-hidden="true"
      >
        <svg
          class="h-6 w-6"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.75"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <rect x="3" y="5" width="18" height="14" rx="2" />
          <path d="M3 7l9 6 9-6" />
        </svg>
      </div>

      <h1 class="mt-5 text-2xl font-semibold text-cream">Check your email</h1>
      <p class="mt-2 text-sm leading-relaxed text-mist">
        We sent a password reset link to
        <span class="font-medium text-cream">{{ email.trim() }}</span>. Open it to choose a new
        password, then come back and sign in. If it doesn't arrive, check your spam folder.
      </p>

      <p v-if="errorMessage" class="alert-error mt-5" role="alert">{{ errorMessage }}</p>

      <div class="mt-6 space-y-3">
        <button
          type="button"
          :disabled="cooldown > 0 || loading"
          class="btn-secondary w-full"
          @click="resend"
        >
          {{
            loading ? 'Sending...' : cooldown > 0 ? `Resend in ${cooldown}s` : 'Resend email'
          }}
        </button>
        <button
          type="button"
          class="w-full py-1 text-center text-sm text-mist hover:text-cream"
          @click="useDifferentEmail"
        >
          Use a different email
        </button>
      </div>

      <p class="mt-6 text-center text-sm">
        <router-link to="/login" class="text-gold hover:text-gold-light">
          Back to sign in
        </router-link>
      </p>
    </template>
  </AuthLayout>
</template>