<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import PageHeader from '../../components/PageHeader.vue'
import BackLink from '../../components/BackLink.vue'
import { createAccountForRole } from '../../services/adminService'
import { showToast } from '../../composables/useToast'
import { STYLE_OPTIONS } from '../../constants/watchOptions'

// Same labels and descriptions as the mobile app's Add account screen.
const ROLES = [
  {
    value: 'customer',
    label: 'Regular user',
    description: 'Browse, measure wrist, scan outfit and use AR try-on.',
  },
  {
    value: 'merchant',
    label: 'Merchant',
    description: 'Manage their own watch catalog and 3D assets.',
  },
  {
    value: 'admin',
    label: 'Admin',
    description: 'Full system access. Use with caution.',
  },
]

const router = useRouter()

const name = ref('')
const email = ref('')
const password = ref('')
const showPassword = ref(false)
const role = ref('customer')
// Mobile starts customer accounts with "Classic" ticked.
const selectedStyles = ref(['Classic'])

const errorMessage = ref('')
const saving = ref(false)

function toggleStyle(style) {
  if (selectedStyles.value.includes(style)) {
    selectedStyles.value = selectedStyles.value.filter((s) => s !== style)
  } else {
    selectedStyles.value = [...selectedStyles.value, style]
  }
}

function chipClass(active) {
  return [
    'rounded-full border px-4 py-2 text-sm transition-colors',
    active
      ? 'border-cream/70 bg-dial text-cream'
      : 'border-line text-mist hover:border-mist/50 hover:text-cream',
  ]
}

async function handleSubmit() {
  errorMessage.value = ''

  if (name.value.trim() === '') {
    errorMessage.value = 'Please enter a name.'
    return
  }
  if (password.value.length < 6) {
    errorMessage.value = 'The password must be at least 6 characters.'
    return
  }

  saving.value = true
  try {
    await createAccountForRole({
      email: email.value,
      password: password.value,
      username: name.value,
      role: role.value,
      stylePreferences: role.value === 'customer' ? selectedStyles.value : [],
    })
    showToast('success', `Account created. A verification email was sent to ${email.value.trim()}.`)
    router.push('/admin/accounts')
  } catch (e) {
    console.error(e)
    errorMessage.value =
      typeof e === 'string' ? e : 'Could not create the account. Please try again.'
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-[88rem]">
    <BackLink to="/admin/accounts">Accounts</BackLink>

    <PageHeader
      class="mt-3"
      title="Add account"
      subtitle="They'll get a verification email and must verify it before their first sign in."
    />

    <form class="mt-10" @submit.prevent="handleSubmit">
      <p v-if="errorMessage" class="alert-error mb-6" role="alert">{{ errorMessage }}</p>

      <div class="grid items-start gap-x-16 gap-y-8 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
        <!-- Left: who they are -->
        <section class="border-t border-line pt-6">
          <h2 class="eyebrow">Details</h2>

          <div class="mt-5 space-y-6">
            <div class="grid gap-6 sm:grid-cols-2 sm:gap-x-8">
              <div>
                <label for="name" class="field-label">Full name</label>
                <input
                  id="name"
                  v-model="name"
                  type="text"
                  required
                  autocomplete="off"
                  class="field"
                  placeholder="Enter full name"
                />
              </div>
              <div>
                <label for="email" class="field-label">Email address</label>
                <input
                  id="email"
                  v-model="email"
                  type="email"
                  required
                  autocomplete="off"
                  class="field"
                  placeholder="Enter email"
                />
              </div>
            </div>

            <div>
              <label for="password" class="field-label">Temporary password</label>
              <div class="relative">
                <input
                  id="password"
                  v-model="password"
                  :type="showPassword ? 'text' : 'password'"
                  required
                  autocomplete="new-password"
                  class="field pr-14"
                  placeholder="Set a temporary password"
                />
                <button
                  type="button"
                  class="absolute inset-y-0 right-0 text-sm text-mist hover:text-cream"
                  :aria-pressed="showPassword"
                  @click="showPassword = !showPassword"
                >
                  {{ showPassword ? 'Hide' : 'Show' }}
                </button>
              </div>
              <p class="mt-2 text-xs text-mist/80">
                At least 6 characters. Share it with them securely.
              </p>
            </div>
          </div>
        </section>

        <!-- Right: what they can do -->
        <div class="space-y-8">
          <section class="border-t border-line pt-6">
            <h2 id="role-label" class="eyebrow">Account role</h2>
            <div role="radiogroup" aria-labelledby="role-label" class="mt-3">
              <label
                v-for="option in ROLES"
                :key="option.value"
                class="flex cursor-pointer items-center justify-between gap-4 border-b border-line py-3.5 last:border-b-0 has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-gold"
              >
                <input
                  v-model="role"
                  type="radio"
                  name="role"
                  :value="option.value"
                  class="sr-only"
                />
                <span class="min-w-0">
                  <span class="block text-[15px] text-cream">{{ option.label }}</span>
                  <span class="mt-0.5 block text-xs text-mist">{{ option.description }}</span>
                </span>
                <svg
                  v-if="role === option.value"
                  class="h-5 w-5 shrink-0 text-gold"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  aria-hidden="true"
                >
                  <path d="M5 12.5l4.5 4.5L19 7.5" />
                </svg>
              </label>
            </div>
          </section>

          <section v-if="role === 'customer'" class="border-t border-line pt-6">
            <h2 id="style-label" class="eyebrow">Style preferences</h2>
            <div
              role="group"
              aria-labelledby="style-label"
              class="mt-5 flex flex-wrap gap-2.5"
            >
              <button
                v-for="style in STYLE_OPTIONS"
                :key="style"
                type="button"
                :aria-pressed="selectedStyles.includes(style)"
                :class="chipClass(selectedStyles.includes(style))"
                @click="toggleStyle(style)"
              >
                {{ style }}
              </button>
            </div>
          </section>
        </div>
      </div>

      <div class="mt-10 flex justify-end gap-3 border-t border-line pt-6">
        <router-link to="/admin/accounts" class="btn-secondary">Cancel</router-link>
        <button type="submit" :disabled="saving" class="btn-primary min-w-40">
          {{ saving ? 'Creating...' : 'Create account' }}
        </button>
      </div>
    </form>
  </div>
</template>