<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import WatchForm from '../../components/WatchForm.vue'
import PageHeader from '../../components/PageHeader.vue'
import BackLink from '../../components/BackLink.vue'
import { addWatch } from '../../services/watchService'
import { showToast } from '../../composables/useToast'

const router = useRouter()

const saving = ref(false)
const formRef = ref(null)
const errorMessage = ref('')

async function handleSubmit(data) {
  errorMessage.value = ''
  saving.value = true
  try {
    await addWatch(data)
    showToast(
      'success',
      data.listedInCatalog ? `Published "${data.name}".` : `Saved "${data.name}" as a draft.`,
    )
    formRef.value?.markSaved() // saved: leaving now is not "losing changes"
    router.push('/merchant/catalog')
  } catch (e) {
    errorMessage.value = typeof e === 'string' ? e : 'Could not save the watch. Please try again.'
    console.error(e)
    window.scrollTo({ top: 0, behavior: 'smooth' })
  } finally {
    saving.value = false
  }
}

function handleCancel() {
  router.push('/merchant/catalog')
}
</script>

<template>
  <div class="mx-auto max-w-[88rem]">
    <BackLink to="/merchant/catalog">My catalog</BackLink>

    <PageHeader
      class="mt-3"
      title="Add a watch"
      subtitle="Fill in what customers will see. Fields marked * are needed to publish. A draft only needs a name."
    />

    <p v-if="errorMessage" class="alert-error mt-6" role="alert">{{ errorMessage }}</p>

    <div class="mt-10">
      <WatchForm
        ref="formRef"
        :saving="saving"
        @submit="handleSubmit"
        @cancel="handleCancel"
      />
    </div>
  </div>
</template>