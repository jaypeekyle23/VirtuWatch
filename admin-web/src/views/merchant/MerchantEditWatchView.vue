<script setup>
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import WatchForm from '../../components/WatchForm.vue'
import PageHeader from '../../components/PageHeader.vue'
import BackLink from '../../components/BackLink.vue'
import { listLocation } from '../../router/listLocation'
import { getWatch, updateWatch } from '../../services/watchService'
import { showToast } from '../../composables/useToast'
import { currentUser } from '../../composables/useAuth'

const route = useRoute()
const router = useRouter()

// Back to the list as it was left, search and filters included.
const listTo = listLocation('/merchant/catalog')

const watchData = ref(null)
const loading = ref(true)
const notFound = ref(false)
const saving = ref(false)
const formRef = ref(null)
const errorMessage = ref('')

onMounted(async () => {
  try {
    const found = await getWatch(route.params.id)
    // Only the owning merchant can edit a watch.
    if (!found || found.merchantId !== currentUser.value.uid) {
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
  <div class="mx-auto max-w-[88rem]">
    <BackLink :to="listTo">My catalog</BackLink>

    <PageHeader
      class="mt-3"
      title="Edit watch"
      :subtitle="watchData?.name || 'Update the details customers will see.'"
    />

    <!-- Loading skeleton -->
    <template v-if="loading">
      <p class="sr-only" role="status">Loading watch</p>
      <div class="mt-10 grid gap-16 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]" aria-hidden="true">
        <div class="h-96 animate-pulse rounded-xl bg-dial"></div>
        <div class="h-96 animate-pulse rounded-xl bg-dial"></div>
      </div>
    </template>

    <div v-else-if="notFound" class="mt-10 border-y border-line py-16 text-center">
      <p class="font-serif text-2xl text-cream">This watch could not be found.</p>
      <router-link
        :to="listTo"
        class="eyebrow mt-4 inline-block text-gold transition-colors hover:text-gold-light"
      >
        Back to catalog
      </router-link>
    </div>

    <template v-else>
      <p v-if="errorMessage" class="alert-error mt-6" role="alert">{{ errorMessage }}</p>

      <div class="mt-10">
        <WatchForm
          ref="formRef"
          :initial="watchData"
          submit-label="Save changes"
          :saving="saving"
          @submit="handleSubmit"
          @cancel="handleCancel"
        />
      </div>
    </template>
  </div>
</template>