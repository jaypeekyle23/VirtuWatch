<script setup>
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import WatchForm from '../../components/WatchForm.vue'
import PageHeader from '../../components/PageHeader.vue'
import BackLink from '../../components/BackLink.vue'
import { listLocation } from '../../router/listLocation'
import { getWatch, updateWatch } from '../../services/watchService'
import { showToast } from '../../composables/useToast'

const route = useRoute()
const router = useRouter()

// Back to the list as it was left, search and filters included.
const listTo = listLocation('/admin/watches')

const watchData = ref(null)
const loading = ref(true)
const notFound = ref(false)
const saving = ref(false)
const formRef = ref(null)
const errorMessage = ref('')

onMounted(async () => {
  try {
    // Unlike the merchant version, admins can edit any merchant's watch,
    // so there is no ownership check here.
    const found = await getWatch(route.params.id)
    if (!found) {
      notFound.value = true
    } else {
      watchData.value = found
    }
  } catch (e) {
    console.error(e)
    notFound.value = true
  } finally {
    loading.value = false
  }
})

async function handleSubmit(data) {
  errorMessage.value = ''
  saving.value = true
  try {
    await updateWatch(route.params.id, data)
    showToast('success', `Saved changes to "${data.name}".`)
    formRef.value?.markSaved() // saved: leaving now is not "losing changes"
    router.push(listTo)
  } catch (e) {
    errorMessage.value = typeof e === 'string' ? e : 'Could not save changes. Please try again.'
    console.error(e)
    window.scrollTo({ top: 0, behavior: 'smooth' })
  } finally {
    saving.value = false
  }
}

function handleCancel() {
  router.push(listTo)
}
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <BackLink :to="listTo">Watch management</BackLink>

    <PageHeader
      class="mt-3"
      title="Edit watch"
      :subtitle="watchData?.name || 'Update the details customers will see.'"
    />

    <!-- Loading skeleton -->
    <template v-if="loading">
      <p class="sr-only" role="status">Loading watch</p>
      <div class="mt-8 grid gap-6 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]" aria-hidden="true">
        <div class="panel h-96 animate-pulse"></div>
        <div class="panel h-96 animate-pulse"></div>
      </div>
    </template>

    <div v-else-if="notFound" class="panel mt-8 p-10 text-center">
      <p class="text-cream">This watch could not be found.</p>
      <router-link :to="listTo" class="btn-secondary mt-4">
        Back to watch management
      </router-link>
    </div>

    <template v-else>
      <p v-if="errorMessage" class="alert-error mt-6" role="alert">{{ errorMessage }}</p>

      <div class="mt-8">
        <WatchForm
          ref="formRef"
          :initial="watchData"
          show-ar-fit
          submit-label="Save changes"
          :saving="saving"
          @submit="handleSubmit"
          @cancel="handleCancel"
        />
      </div>
    </template>
  </div>
</template>