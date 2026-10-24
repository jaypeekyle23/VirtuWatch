<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import AuthLayout from '../components/AuthLayout.vue'
import { loginWithEmail } from '../services/authService'
import { currentUser } from '../composables/useAuth'

const router = useRouter()

const email = ref('')
const password = ref('')
const showPassword = ref(false)
const errorMessage = ref('')
const loading = ref(false)

async function handleSubmit() {
  errorMessage.value = ''
  loading.value = true
  try {
    const profile = await loginWithEmail(email.value, password.value)
    // Set this right away so the router guard knows we're signed in.
    currentUser.value = profile
    router.push(profile.role === 'admin' ? '/admin' : '/merchant')
  } catch (e) {
    errorMessage.value = typeof e === 'string' ? e : 'Something went wrong. Please try again.'
  } finally {
    loading.value = false
  }
}

// Carries whatever email was typed over to the reset page.
function goToForgotPassword() {
  const typed = email.value.trim()
  router.push({
    name: 'forgot-password',
    query: typed ? { email: typed } : {},
  })
}
</script>

<template>
  <AuthLayout>
    <h1 class="text-2xl font-semibold text-cream">Sign in</h1>
    <p class="mt-1 text-sm text-mist">For admin and merchant accounts.</p>

    <form class="mt-8 space-y-5" @submit.prevent="handleSubmit">
      <p v-if="errorMessage" class="alert-error" role="alert">{{ errorMessage }}</p>

      <div>
        <label for="email" class="label">Email</label>
        <input
          id="email"
          v-model="email"
          type="email"
          required
          autocomplete="email"
          class="input"
        />
      </div>

      <div>
        <div class="flex items-baseline justify-between">
          <label for="password" class="label">Password</label>
          <button
            type="button"
            class="mb-1.5 text-sm text-gold hover:text-gold-light"
            @click="goToForgotPassword"
          >
            Forgot password?
          </button>
        </div>
        <div class="relative">
          <input
            id="password"
            v-model="password"
            :type="showPassword ? 'text' : 'password'"
            required
            autocomplete="current-password"
            class="input pr-16"
          />
          <button
            type="button"
            class="absolute inset-y-0 right-0 px-3.5 text-sm text-mist hover:text-cream"
            :aria-pressed="showPassword"
            @click="showPassword = !showPassword"
          >
            {{ showPassword ? 'Hide' : 'Show' }}
          </button>
        </div>
      </div>

      <button type="submit" :disabled="loading" class="btn-primary w-full">
        {{ loading ? 'Signing in...' : 'Sign in' }}
      </button>
    </form>
  </AuthLayout>
</template>