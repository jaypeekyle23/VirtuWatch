<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import WatchForm from '../../components/WatchForm.vue'
import PageHeader from '../../components/PageHeader.vue'
import BackLink from '../../components/BackLink.vue'
import { addWatch } from '../../services/watchService'
import { showToast } from '../../composables/useToast'
import { listenToAllUsers } from '../../services/adminService'

const router = useRouter()

const users = ref([])
const usersLoading = ref(true)
const selectedMerchantId = ref('')
const merchantError = ref('')
const saving = ref(false)
const formRef = ref(null)
const errorMessage = ref('')
let stopListening = null

onMounted(() => {
  stopListening = listenToAllUsers(
    (list) => {
      users.value = list
      usersLoading.value = false
    },
    (err) => {
      console.error(err)
      errorMessage.value = 'Could not load merchant accounts.'
      usersLoading.value = false
    },
  )
})

onUnmounted(() => {
  if (stopListening) stopListening()
})

const merchants = computed(() =>
  users.value
    .filter((u) => u.role === 'merchant')
    .sort((a, b) => (a.username || '').localeCompare(b.username || '')),
)

async function handleSubmit(data) {
  errorMessage.value = ''
  merchantError.value = ''

  if (!selectedMerchantId.value) {
    merchantError.value = 'Please select which merchant this watch belongs to.'
    window.scrollTo({ top: 0, behavior: 'smooth' })
    return
  }

  saving.value = true
  try {
    await addWatch(data, selectedMerchantId.value)
    showToast(
      'success',
      data.listedInCatalog ? `Published "${data.name}".` : `Saved "${data.name}" as a draft.`,
    )
    formRef.value?.markSaved() // saved: leaving now is not "losing changes"
    router.push('/admin/watches')
  } catch (e) {
    errorMessage.value = typeof e === 'string' ? e : 'Could not save the watch. Please try again.'
    console.error(e)
    window.scrollTo({ top: 0, behavior: 'smooth' })
  } finally {
    saving.value = false
  }
}

function handleCancel() {
  router.push('/admin/watches')
}
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <BackLink to="/admin/watches">Watch management</BackLink>

    <PageHeader
      class="mt-3"
      title="Add a watch"
      subtitle="Choose the merchant it belongs to, then fill in the details. Fields marked * are needed to publish. A draft only needs a name."
    />

    <p v-if="errorMessage" class="alert-error mt-6" role="alert">{{ errorMessage }}</p>

    <p v-if="usersLoading" class="mt-8 text-sm text-mist" role="status">Loading merchants...</p>

    <div v-else-if="merchants.length === 0" class="panel mt-8 p-10 text-center">
      <p class="text-cream">No merchant accounts exist yet.</p>
      <p class="mt-1 text-sm text-mist">A watch needs a merchant to belong to. Create one first.</p>
      <router-link to="/admin/accounts/new" class="btn-primary mt-5">Add an account</router-link>
    </div>

    <template v-else>
      <section class="panel mt-8 p-6">
        <label for="merchant" class="label">
          Merchant <span class="text-gold" aria-hidden="true">*</span>
        </label>
        <select
          id="merchant"
          v-model="selectedMerchantId"
          class="input max-w-md"
          :class="merchantError ? 'border-red-400/60' : ''"
          :aria-invalid="!!merchantError"
          aria-required="true"
        >
          <option value="" disabled>Select a merchant</option>
          <option v-for="m in merchants" :key="m.id" :value="m.id">
            {{ m.username || 'Merchant' }}{{ m.email ? ` (${m.email})` : '' }}
          </option>
        </select>
        <p v-if="merchantError" class="mt-1.5 text-xs text-red-300">{{ merchantError }}</p>
        <p v-else class="mt-1.5 text-xs text-slate-500">
          The watch will be listed under this merchant.
        </p>
      </section>

      <div class="mt-6">
        <WatchForm
          ref="formRef"
          show-ar-fit
          :saving="saving"
          @submit="handleSubmit"
          @cancel="handleCancel"
        />
      </div>
    </template>
  </div>
</template>