<script setup>
import { ref, computed, watch } from 'vue'
import { currentUser } from '../../composables/useAuth'
import { updateUsername, updatePhotoUrl, changePassword } from '../../services/authService'
import { uploadImage } from '../../services/cloudinaryService'
import PageHeader from '../../components/PageHeader.vue'
import ThemeModePicker from '../../components/ThemeModePicker.vue'

const MAX_PHOTO_BYTES = 5 * 1024 * 1024

const initial = computed(() => (currentUser.value?.username || '?').charAt(0).toUpperCase())

const roleLabel = computed(() => {
  const role = currentUser.value?.role || ''
  return role.charAt(0).toUpperCase() + role.slice(1)
})

// createdAt is a Firestore Timestamp, so it has to be converted to a Date first.
const memberSince = computed(() => {
  const created = currentUser.value?.createdAt
  if (!created || typeof created.toDate !== 'function') return 'Unknown'
  return created.toDate().toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  })
})

// ---------- Display name ----------
const nameInput = ref(currentUser.value?.username || '')
const nameError = ref('')
const nameSuccess = ref('')
const nameSaving = ref(false)

// Save only becomes available once there is a real change to save.
const nameChanged = computed(() => {
  const trimmed = nameInput.value.trim()
  return trimmed !== '' && trimmed !== (currentUser.value?.username || '')
})

watch(nameInput, () => {
  nameSuccess.value = ''
  nameError.value = ''
})

async function saveName() {
  nameError.value = ''
  nameSuccess.value = ''
  nameSaving.value = true
  try {
    const savedName = await updateUsername(nameInput.value)
    // Update the local copy too, so the page and sidebar change right away.
    currentUser.value = { ...currentUser.value, username: savedName }
    nameInput.value = savedName
    nameSuccess.value = 'Name updated.'
  } catch (e) {
    nameError.value = typeof e === 'string' ? e : 'Could not save your name. Please try again.'
  } finally {
    nameSaving.value = false
  }
}

// ---------- Photo ----------
const photoInput = ref(null)
const photoError = ref('')
const photoUploading = ref(false)

function choosePhoto() {
  photoError.value = ''
  photoInput.value?.click()
}

async function handlePhotoSelected(event) {
  const file = event.target.files?.[0]
  // Clear the input so picking the same file again still triggers this.
  event.target.value = ''
  if (!file) return

  if (!file.type.startsWith('image/')) {
    photoError.value = 'Please choose an image file.'
    return
  }
  if (file.size > MAX_PHOTO_BYTES) {
    photoError.value = 'That image is over 5MB. Please choose a smaller one.'
    return
  }

  photoError.value = ''
  photoUploading.value = true
  try {
    const url = await uploadImage(file)
    await updatePhotoUrl(url)
    currentUser.value = { ...currentUser.value, photoUrl: url }
  } catch (e) {
    photoError.value = typeof e === 'string' ? e : 'Could not update your photo. Please try again.'
  } finally {
    photoUploading.value = false
  }
}

// ---------- Password ----------
const currentPassword = ref('')
const newPassword = ref('')
const confirmPassword = ref('')
const showPasswords = ref(false)
const passwordError = ref('')
const passwordSuccess = ref('')
const passwordSaving = ref(false)

async function savePassword() {
  passwordError.value = ''
  passwordSuccess.value = ''

  if (newPassword.value.length < 6) {
    passwordError.value = 'Your new password must be at least 6 characters.'
    return
  }
  if (newPassword.value !== confirmPassword.value) {
    passwordError.value = 'The new passwords do not match.'
    return
  }
  if (newPassword.value === currentPassword.value) {
    passwordError.value = 'Your new password must be different from the current one.'
    return
  }

  passwordSaving.value = true
  try {
    await changePassword(currentPassword.value, newPassword.value)
    currentPassword.value = ''
    newPassword.value = ''
    confirmPassword.value = ''
    passwordSuccess.value = 'Your password has been updated.'
  } catch (e) {
    passwordError.value =
      typeof e === 'string' ? e : 'Could not change your password. Please try again.'
  } finally {
    passwordSaving.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-[88rem]">
    <PageHeader title="Profile" subtitle="Your account details and sign-in settings." />

    <!-- Identity: full width, so long names and emails wrap instead of being cut off -->
    <div
      class="mt-10 grid items-start gap-x-16 gap-y-8 border-t border-line pt-8 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]"
    >
      <div class="flex items-center gap-6">
        <img
          v-if="currentUser?.photoUrl"
          :src="currentUser.photoUrl"
          alt="Your profile photo"
          class="h-24 w-24 shrink-0 rounded-full border border-line object-cover transition-opacity"
          :class="{ 'opacity-50': photoUploading }"
        />
        <div
          v-else
          class="flex h-24 w-24 shrink-0 items-center justify-center rounded-full border border-line bg-dial font-serif text-4xl text-gold transition-opacity"
          :class="{ 'opacity-50': photoUploading }"
        >
          {{ initial }}
        </div>

        <div class="min-w-0">
          <h2
            class="font-serif text-4xl font-medium leading-tight text-cream [overflow-wrap:anywhere]"
          >
            {{ currentUser?.username }}
          </h2>
          <p class="mt-1 text-sm text-mist [overflow-wrap:anywhere]">{{ currentUser?.email }}</p>
          <button
            type="button"
            :disabled="photoUploading"
            class="eyebrow mt-3 text-cream transition-colors hover:text-gold disabled:opacity-50"
            @click="choosePhoto"
          >
            {{ photoUploading ? 'Uploading...' : 'Change photo' }}
          </button>
        </div>
      </div>
      <input
        ref="photoInput"
        type="file"
        accept="image/*"
        class="hidden"
        @change="handlePhotoSelected"
      />

      <section>
        <h2 class="eyebrow">Account</h2>
        <p class="mt-3 font-serif text-3xl font-medium text-cream">{{ roleLabel }}</p>
        <p class="mt-1 text-sm text-mist">Member since {{ memberSince }}</p>
      </section>
    </div>
    <p v-if="photoError" class="alert-error mt-4" role="alert">{{ photoError }}</p>

    <div class="mt-10 grid items-start gap-x-16 gap-y-10 xl:grid-cols-2">
      <!-- Left column: display name, then appearance -->
      <div class="space-y-10">
        <!-- Display name -->
        <form class="border-t border-line pt-6" @submit.prevent="saveName">
          <h2 class="eyebrow">Display name</h2>
          <p class="mt-4 text-sm text-mist">This is how your name appears across VirtuWatch.</p>

          <label for="display-name" class="field-label mt-6">Name</label>
          <div class="flex items-end gap-6">
            <input
              id="display-name"
              v-model="nameInput"
              type="text"
              required
              autocomplete="name"
              class="field min-w-0 flex-1"
            />
            <button type="submit" class="btn-primary shrink-0" :disabled="!nameChanged || nameSaving">
              {{ nameSaving ? 'Saving...' : 'Save' }}
            </button>
          </div>
          <p v-if="nameError" class="alert-error mt-4" role="alert">{{ nameError }}</p>
          <p v-if="nameSuccess" class="mt-4 text-sm text-gold" role="status">{{ nameSuccess }}</p>
        </form>

        <!-- Appearance: saved on this device only, like the mobile app -->
        <section class="border-t border-line pt-6">
          <h2 class="eyebrow">Appearance</h2>
          <p class="mt-4 text-sm text-mist">Choose how VirtuWatch looks on this device.</p>
          <div class="mt-5">
            <ThemeModePicker />
          </div>
        </section>
      </div>

      <!-- Password -->
      <form class="border-t border-line pt-6" @submit.prevent="savePassword">
        <h2 class="eyebrow">Password</h2>
        <p class="mt-4 text-sm text-mist">
          Use at least 6 characters. You'll need your current password to change it.
        </p>

        <p v-if="passwordError" class="alert-error mt-5" role="alert">{{ passwordError }}</p>
        <p v-if="passwordSuccess" class="mt-5 text-sm text-gold" role="status">
          {{ passwordSuccess }}
        </p>

        <div class="mt-6 space-y-6">
          <div>
            <label for="current-password" class="field-label">Current password</label>
            <input
              id="current-password"
              v-model="currentPassword"
              :type="showPasswords ? 'text' : 'password'"
              required
              autocomplete="current-password"
              class="field"
            />
          </div>
          <div>
            <label for="new-password" class="field-label">New password</label>
            <input
              id="new-password"
              v-model="newPassword"
              :type="showPasswords ? 'text' : 'password'"
              required
              autocomplete="new-password"
              class="field"
            />
          </div>
          <div>
            <label for="confirm-password" class="field-label">Confirm new password</label>
            <input
              id="confirm-password"
              v-model="confirmPassword"
              :type="showPasswords ? 'text' : 'password'"
              required
              autocomplete="new-password"
              class="field"
            />
          </div>
        </div>

        <div class="mt-8 flex flex-wrap items-center justify-between gap-4">
          <label class="flex items-center gap-2 text-sm text-mist">
            <input v-model="showPasswords" type="checkbox" class="h-4 w-4 accent-gold" />
            Show passwords
          </label>
          <button type="submit" :disabled="passwordSaving" class="btn-primary">
            {{ passwordSaving ? 'Updating...' : 'Update password' }}
          </button>
        </div>
      </form>
    </div>
  </div>
</template>