<script setup>
import { reactive, ref, computed, nextTick, onMounted, onBeforeUnmount } from 'vue'
import { onBeforeRouteLeave, useRoute } from 'vue-router'
import {
  STYLE_OPTIONS,
  GENDER_OPTIONS,
  WATCH_COLORS,
  MAX_WATCH_COLORS,
  MAX_WATCH_PHOTOS,
} from '../constants/watchOptions'
import {
  requiredText,
  requiredPositiveNumber,
  optionalPositiveNumber,
  requiredStockCount,
  optionalStockCount,
} from '../utils/formValidators'
import { LOW_STOCK_THRESHOLD } from '../utils/stock'
import { uploadImage, uploadModel } from '../services/cloudinaryService'
import {
  AR_FIT_FIELDS,
  parseArFit,
  isSupportedModelUrl,
  fitText,
  validateFitField,
  parseFitJson,
} from '../utils/arFit'
import ConfirmDialog from './ConfirmDialog.vue'

const props = defineProps({
  initial: { type: Object, default: null }, // existing watch data when editing
  submitLabel: { type: String, default: 'Save' },
  saving: { type: Boolean, default: false },
  // Admin pages turn this on to show the AR fit editor. Firestore rules only let
  // an admin write arFit, so merchant pages must leave it off.
  showArFit: { type: Boolean, default: false },
})
const emit = defineEmits(['submit', 'cancel'])
const route = useRoute()

function str(value) {
  return value == null ? '' : String(value)
}

function numberOrNull(value) {
  const text = String(value).trim()
  return text === '' ? null : Number(text)
}

const form = reactive({
  name: str(props.initial?.name),
  brand: str(props.initial?.brand),
  price: str(props.initial?.price),
  stock: str(props.initial?.stock),
  styleCategory: props.initial?.styleCategory ?? 'Sport',
  targetGender: props.initial?.targetGender ?? '',
  caseDiameterMm: str(props.initial?.caseDiameterMm),
  caseThicknessMm: str(props.initial?.caseThicknessMm),
  lugToLugMm: str(props.initial?.lugToLugMm),
  bandWidthMm: str(props.initial?.bandWidthMm),
  bandMaterial: str(props.initial?.bandMaterial),
  caseMaterial: str(props.initial?.caseMaterial),
  movementType: str(props.initial?.movementType),
  waterResistance: str(props.initial?.waterResistance),
  // Only used when editing. When adding, the "Save as draft" / "Publish" buttons decide.
  // Watches saved before this field existed count as unlisted, matching isListed().
  listedInCatalog: props.initial?.listedInCatalog === true,
})

const isEditing = props.initial != null

// A new listing must have a stock count to be published. An older listing without
// one can still be edited and saved with the field blank (it shows no availability
// until a count is entered). Same rule as the mobile form.
const stockRequired = !isEditing || props.initial.stock != null
const wasListed = props.initial?.listedInCatalog === true

// ---------- Colors ----------

// Older watches may only have the single colorHex field.
const colorHexes = ref(
  props.initial?.colorHexes?.length
    ? [...props.initial.colorHexes]
    : props.initial?.colorHex
      ? [props.initial.colorHex]
      : [],
)

function isSelected(hex) {
  return colorHexes.value.some((c) => c.toUpperCase() === hex.toUpperCase())
}

// Click a swatch to add it (up to the max) or remove it.
// Nothing is preselected. A color is recommended before publishing, not required.
function toggleColor(hex) {
  attention.value = ''
  if (isSelected(hex)) {
    colorHexes.value = colorHexes.value.filter((c) => c.toUpperCase() !== hex.toUpperCase())
  } else if (colorHexes.value.length < MAX_WATCH_COLORS) {
    colorHexes.value = [...colorHexes.value, hex]
  }
}

function colorName(hex) {
  const match = WATCH_COLORS.find((c) => c.hex.toUpperCase() === hex.toUpperCase())
  return match ? match.name : hex
}

// A dark check on light swatches and a light check on dark ones.
function checkColor(hex) {
  const r = parseInt(hex.slice(1, 3), 16)
  const g = parseInt(hex.slice(3, 5), 16)
  const b = parseInt(hex.slice(5, 7), 16)
  return (r * 299 + g * 587 + b * 114) / 1000 > 150 ? '#0E1A2B' : '#F5F1E8'
}

// ---------- Photos ----------

// Each photo is { id, url, file }. Existing photos have file = null and
// url = the hosted address. Newly picked photos have a File and a local preview url.
let nextPhotoId = 0
const startingUrls = props.initial?.imageUrls?.length
  ? props.initial.imageUrls
  : props.initial?.imageUrl
    ? [props.initial.imageUrl]
    : []
const photos = ref(startingUrls.map((url) => ({ id: nextPhotoId++, url, file: null })))
const photoError = ref('')

// Each photo is uploaded as it is, so very large ones are turned away up front.
const MAX_PHOTO_MB = 5
const MAX_PHOTO_BYTES = MAX_PHOTO_MB * 1024 * 1024

function onPhotosPicked(event) {
  photoError.value = ''
  const files = Array.from(event.target.files || [])
  event.target.value = '' // lets the same file be picked again later

  const remaining = MAX_WATCH_PHOTOS - photos.value.length
  const images = files.filter((f) => f.type.startsWith('image/'))
  const tooBig = images.filter((f) => f.size > MAX_PHOTO_BYTES)
  const accepted = images.filter((f) => f.size <= MAX_PHOTO_BYTES)

  // Everything that went wrong is reported together, so one problem doesn't hide another.
  const problems = []
  if (images.length < files.length) problems.push('Some files were skipped (images only).')
  if (tooBig.length === 1) {
    const mb = (tooBig[0].size / 1024 / 1024).toFixed(1)
    problems.push(
      `${tooBig[0].name} is ${mb}MB, over the ${MAX_PHOTO_MB}MB limit, so it was skipped. Please choose a smaller one.`,
    )
  } else if (tooBig.length > 1) {
    problems.push(
      `${tooBig.length} photos are over the ${MAX_PHOTO_MB}MB limit and were skipped. Please choose smaller ones.`,
    )
  }
  if (accepted.length > remaining) {
    problems.push(`You can add up to ${MAX_WATCH_PHOTOS} photos.`)
  }
  photoError.value = problems.join(' ')

  const added = accepted.slice(0, Math.max(remaining, 0)).map((file) => ({
    id: nextPhotoId++,
    url: URL.createObjectURL(file),
    file,
  }))
  photos.value = [...photos.value, ...added]
}

function removePhoto(id) {
  const photo = photos.value.find((p) => p.id === id)
  if (photo?.file) URL.revokeObjectURL(photo.url)
  photos.value = photos.value.filter((p) => p.id !== id)
}

// ---- Reordering: "Make cover" (button) and drag and drop ----
// The first photo is the cover. Both ways just change the order of `photos`; saving
// uses that order, and the unsaved-changes check notices it.

// A short message for screen readers whenever the order changes.
const photoAnnouncement = ref('')

async function announce(message) {
  photoAnnouncement.value = '' // so the same message twice in a row is still read out
  await nextTick()
  photoAnnouncement.value = message
}

// Puts a photo at a new position; the others shift over. False if nothing changed.
function movePhoto(id, toIndex) {
  const from = photos.value.findIndex((p) => p.id === id)
  if (from === -1) return false
  const to = Math.max(0, Math.min(toIndex, photos.value.length - 1))
  if (from === to) return false
  const next = [...photos.value]
  const [moved] = next.splice(from, 1)
  next.splice(to, 0, moved)
  photos.value = next
  return true
}

// Works with keyboard and touch. Any order can be built with it: make the photos
// the cover one after another, last to first.
async function makeCover(id) {
  const position = photos.value.findIndex((p) => p.id === id) + 1
  if (!movePhoto(id, 0)) return
  announce(`Photo ${position} is now the cover.`)
  // The photo's "Make cover" button has just turned into the "Cover" badge, so put
  // keyboard focus on the photo itself instead of losing it.
  await nextTick()
  document.getElementById(`wf-photo-${id}`)?.focus({ preventScroll: true })
}

// Drag and drop (mouse). The dragged photo takes the place of the one it is dropped on.
const draggingId = ref(null)
const dropIndex = ref(null)

function onDragStart(event, photo) {
  draggingId.value = photo.id
  if (event.dataTransfer) {
    event.dataTransfer.effectAllowed = 'move'
    event.dataTransfer.setData('text/plain', String(photo.id)) // Firefox needs this to start a drag
  }
}

function onDragOver(event, index) {
  if (draggingId.value === null) return // not one of our photos (e.g. a file from the desktop)
  event.preventDefault() // tells the browser this tile accepts a drop
  if (event.dataTransfer) event.dataTransfer.dropEffect = 'move'
  dropIndex.value = index
}

function endDrag() {
  draggingId.value = null
  dropIndex.value = null
}

function onDrop(event, index) {
  if (draggingId.value === null) return
  event.preventDefault()
  const id = draggingId.value
  endDrag()
  if (movePhoto(id, index)) announce(`Photo moved to position ${index + 1}.`)
}

onBeforeUnmount(() => {
  photos.value.forEach((p) => {
    if (p.file) URL.revokeObjectURL(p.url)
  })
})

// ---------- 3D model ----------

const MAX_MODEL_BYTES = 10 * 1024 * 1024
const modelFile = ref(null)
const existingModelUrl = ref(props.initial?.modelUrl ?? '')
const modelError = ref('')

function onModelPicked(event) {
  modelError.value = ''
  const file = event.target.files?.[0]
  event.target.value = ''
  if (!file) return

  const extension = file.name.split('.').pop().toLowerCase()
  if (extension !== 'glb' && extension !== 'gltf') {
    modelError.value = `Please select a .glb or .gltf file (you picked a .${extension} file).`
    return
  }
  if (file.size > MAX_MODEL_BYTES) {
    modelError.value = 'That model is over 10MB. Compress it (e.g. Draco) and try again.'
    return
  }
  modelFile.value = file
}

function removeModel() {
  modelFile.value = null
  existingModelUrl.value = ''
  modelError.value = ''
  // Fit numbers belong to one model file, so they go with it.
  clearFit()
}

// ---------- AR fit (admin only) ----------

// Prefilled only when the saved fit belongs to the model attached now
// (parseArFit checks that), so numbers measured for an old model are never
// carried over to a replacement.
const savedFit = props.showArFit ? parseArFit(props.initial) : null
const fit = reactive({
  holeCx: fitText(savedFit?.holeCx),
  holeHalfX: fitText(savedFit?.holeHalfX),
  holeHalfY: fitText(savedFit?.holeHalfY),
  // Blank means the default of 1.0.
  scale: savedFit && savedFit.scale !== 1 ? fitText(savedFit.scale) : '',
})

const hasModel = computed(() => !!modelFile.value || existingModelUrl.value !== '')
const fitAnyFilled = computed(() => AR_FIT_FIELDS.some((f) => fit[f.key].trim() !== ''))

// The three opening numbers are valid, and the size multiplier is blank or valid.
const fitComplete = computed(() =>
  AR_FIT_FIELDS.every((f) => validateFitField(fit[f.key], f.key, f.required) === null),
)

// The app cannot use a .gltf in AR, so no fit numbers will make it AR-ready.
const modelIsGltf = computed(() => {
  if (modelFile.value) return modelFile.value.name.toLowerCase().endsWith('.gltf')
  return existingModelUrl.value !== '' && !isSupportedModelUrl(existingModelUrl.value)
})

function clearFit() {
  AR_FIT_FIELDS.forEach((f) => (fit[f.key] = ''))
  pasteOpen.value = false
  pasteText.value = ''
  pasteError.value = ''
}

// The object stored on the watch, tied to the model url. Null when the fit is
// blank or incomplete, which means "no fit" (an existing one gets removed).
function buildArFit(modelUrl) {
  if (!props.showArFit || modelUrl === '' || !fitComplete.value) return null
  const scale = fit.scale.trim()
  return {
    modelUrl,
    holeCx: Number(fit.holeCx),
    holeHalfX: Number(fit.holeHalfX),
    holeHalfY: Number(fit.holeHalfY),
    ...(scale !== '' ? { scale: Number(scale) } : {}),
  }
}

// Paste JSON such as {"holeCx": -0.058, "holeHalfX": 0.226, "holeHalfY": 0.432}.
const pasteOpen = ref(false)
const pasteText = ref('')
const pasteError = ref('')

function applyPastedFit() {
  const parsed = parseFitJson(pasteText.value)
  if (!parsed) {
    pasteError.value = 'Could not read that. It needs numbers for holeCx, holeHalfX and holeHalfY.'
    return
  }
  fit.holeCx = fitText(parsed.holeCx)
  fit.holeHalfX = fitText(parsed.holeHalfX)
  fit.holeHalfY = fitText(parsed.holeHalfY)
  fit.scale = fitText(parsed.scale)
  pasteText.value = ''
  pasteError.value = ''
  pasteOpen.value = false
}

// ---------- Opened from a "Needs info" link ----------

// Links like .../edit?focus=lugToLugMm open the form already pointing at the field
// that needs filling in. The value is the field's id without the "wf-" prefix.
// `attention` briefly outlines a section whose focus ring would be hard to see.
const attention = ref('')
let attentionTimer = null

function focusField(key) {
  const el = document.getElementById(`wf-${key}`)
  if (!el) return
  const reduceMotion = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
  el.scrollIntoView?.({ behavior: reduceMotion ? 'auto' : 'smooth', block: 'center' })

  // A group of swatches is not focusable itself: focus its first button instead.
  const target = el.matches('input, select, textarea, button') ? el : el.querySelector('button')
  target?.focus({ preventScroll: true })

  if (key === 'colors') {
    attention.value = 'colors'
    clearTimeout(attentionTimer)
    attentionTimer = setTimeout(() => (attention.value = ''), 2500)
  }
}

onMounted(async () => {
  const key = typeof route?.query?.focus === 'string' ? route.query.focus : ''
  if (!key) return
  await nextTick()
  // One frame later, so the page's own scroll-to-top (after navigating) has already run.
  requestAnimationFrame(() => focusField(key))
})

onBeforeUnmount(() => clearTimeout(attentionTimer))

// ---------- Unsaved changes ----------

// A snapshot of everything the person can change, so we can tell whether the form
// differs from how it started. New photos and models are compared by identity,
// not by their contents.
function snapshot() {
  return JSON.stringify({
    form: { ...form },
    colors: colorHexes.value,
    photos: photos.value.map((p) => (p.file ? `new-${p.id}` : p.url)),
    model: modelFile.value
      ? `new-${modelFile.value.name}-${modelFile.value.size}`
      : existingModelUrl.value,
    fit: { ...fit },
  })
}
const startingSnapshot = ref(snapshot())
const isDirty = computed(() => snapshot() !== startingSnapshot.value)

// The page that owns this form calls this once the watch has been saved and it is
// about to navigate away. From then on the form counts as unchanged (until the person
// edits it again), so the redirect after a successful save never shows the prompt.
function markSaved() {
  startingSnapshot.value = snapshot()
}
defineExpose({ markSaved })

// Set when the person leaves the page, so an upload still running in the
// background stops instead of carrying on to save a watch they walked away from.
let leftPage = false

// Leaving the page (Cancel, a sidebar link, the back button) with unsaved changes
// asks first. The router waits for the answer before going anywhere.
//
// A save in progress never prompts. After a successful save the parent calls
// markSaved() before it navigates away.
const leaveOpen = ref(false)
let answerLeave = null // settles the waiting navigation: true = leave, false = stay

onBeforeRouteLeave(() => {
  if (!isDirty.value || props.saving) return true
  answerLeave?.(false) // a newer navigation replaces one that was still waiting
  leaveOpen.value = true
  return new Promise((resolve) => {
    answerLeave = resolve
  })
})

function keepEditing() {
  leaveOpen.value = false
  answerLeave?.(false)
  answerLeave = null
}

function discardChanges() {
  leaveOpen.value = false
  answerLeave?.(true)
  answerLeave = null
}

// Closing or reloading the tab. The browser shows its own generic message.
function warnBeforeClosing(event) {
  if (!isDirty.value || props.saving) return
  event.preventDefault()
  event.returnValue = ''
}

onMounted(() => window.addEventListener('beforeunload', warnBeforeClosing))
onBeforeUnmount(() => {
  leftPage = true
  window.removeEventListener('beforeunload', warnBeforeClosing)
})

// ---------- Validation and submit ----------

const errors = reactive({})
const uploading = ref(false)
const uploadError = ref('')

// Red outline for a field that failed validation.
function errClass(key) {
  return errors[key] ? 'border-red-400/60 focus:border-red-400 focus:ring-red-400/25' : ''
}

// Drafts only need a name (anything typed into a number field must still be valid).
// A watch that will be visible to customers needs the full set of required fields.
function validate(willBeListed) {
  const found = {
    name: requiredText(form.name),
    price: willBeListed ? requiredPositiveNumber(form.price) : optionalPositiveNumber(form.price),
    // Like price, a draft can leave it blank, but anything typed must be valid.
    stock:
      willBeListed && stockRequired ? requiredStockCount(form.stock) : optionalStockCount(form.stock),
    lugToLugMm: willBeListed
      ? requiredPositiveNumber(form.lugToLugMm)
      : optionalPositiveNumber(form.lugToLugMm),
    caseDiameterMm: optionalPositiveNumber(form.caseDiameterMm),
    caseThicknessMm: optionalPositiveNumber(form.caseThicknessMm),
    bandWidthMm: optionalPositiveNumber(form.bandWidthMm),
  }
  // AR fit: all blank is fine. Once any box is filled, the three opening numbers are needed.
  if (props.showArFit && hasModel.value) {
    AR_FIT_FIELDS.forEach((f) => {
      found[f.key] = validateFitField(fit[f.key], f.key, f.required && fitAnyFilled.value)
    })
  }
  Object.keys(errors).forEach((key) => delete errors[key])
  Object.entries(found).forEach(([key, message]) => {
    if (message) errors[key] = message
  })
  return Object.keys(errors).length === 0
}

// action is 'draft' or 'publish' when adding, and 'save' when editing.
// Which button was pressed, so only that one shows "Saving..." / "Uploading...".
const lastAction = ref(null)

function willBeListed(action) {
  return isEditing ? form.listedInCatalog : action === 'publish'
}

function buttonLabel(action, idleLabel) {
  if (lastAction.value === action) {
    if (uploading.value) return 'Uploading...'
    if (props.saving) return 'Saving...'
  }
  return idleLabel
}

// ---- Soft warning before publishing with missing info ----
// Gender and color are not required, but customer recommendations rely on them.
const warningOpen = ref(false)
const missingList = ref([])
let pendingSubmit = null

const missingText = computed(() => missingList.value.join(' and '))

function missingForPublish() {
  const missing = []
  if (!form.targetGender) missing.push('gender')
  if (colorHexes.value.length === 0) missing.push('color')
  return missing
}

async function handleSubmit(action) {
  lastAction.value = action
  const listed = willBeListed(action)

  if (!validate(listed)) {
    // Jump to the first field that needs attention.
    await nextTick()
    const first = Object.keys(errors)[0]
    const el = document.getElementById(`wf-${first}`)
    el?.scrollIntoView({ behavior: 'smooth', block: 'center' })
    el?.focus({ preventScroll: true })
    return
  }

  // Only warn when the watch is about to become visible, not on every later edit.
  if (listed && !wasListed) {
    const missing = missingForPublish()
    if (missing.length > 0) {
      missingList.value = missing
      pendingSubmit = { listed }
      warningOpen.value = true
      return
    }
  }

  await save(listed)
}

async function confirmPublishAnyway() {
  warningOpen.value = false
  if (pendingSubmit) await save(pendingSubmit.listed)
  pendingSubmit = null
}

// "Go back and fix": close the dialog and take the person to the first missing field.
async function cancelWarning() {
  warningOpen.value = false
  pendingSubmit = null
  await nextTick()
  const target = missingList.value.includes('gender')
    ? document.getElementById('wf-gender')
    : document.getElementById('wf-colors')
  target?.scrollIntoView({ behavior: 'smooth', block: 'center' })
  // Both are groups of buttons: focus the first one.
  target?.querySelector('button')?.focus({ preventScroll: true })
}

async function save(listed) {
  uploadError.value = ''
  uploading.value = true

  try {
    // Upload new photos one at a time, in order. Each one becomes an ordinary hosted
    // photo the moment it uploads, so if something fails later, pressing the button
    // again only uploads what is still missing instead of everything twice.
    // (Looping on "any photo still waiting" also catches a photo added mid-upload.)
    let waiting
    while ((waiting = photos.value.find((p) => p.file))) {
      const hostedUrl = await uploadImage(waiting.file)
      if (leftPage) return
      URL.revokeObjectURL(waiting.url)
      waiting.url = hostedUrl
      waiting.file = null
    }
    const imageUrls = photos.value.map((p) => p.url)

    // Same for the 3D model.
    let modelUrl = existingModelUrl.value
    if (modelFile.value) {
      const uploadedFile = modelFile.value
      modelUrl = await uploadModel(uploadedFile)
      if (leftPage) return
      existingModelUrl.value = modelUrl
      if (modelFile.value === uploadedFile) modelFile.value = null
    }

    emit('submit', {
      name: form.name.trim(),
      brand: form.brand.trim(),
      // A draft may not have these yet. Publishing always has them (validated above).
      price: numberOrNull(form.price),
      stock: numberOrNull(form.stock),
      styleCategory: form.styleCategory,
      targetGender: form.targetGender || null,
      colorHex: colorHexes.value[0] ?? null,
      colorHexes: colorHexes.value,
      caseDiameterMm: numberOrNull(form.caseDiameterMm),
      caseThicknessMm: numberOrNull(form.caseThicknessMm),
      lugToLugMm: numberOrNull(form.lugToLugMm),
      bandWidthMm: numberOrNull(form.bandWidthMm),
      bandMaterial: form.bandMaterial.trim(),
      caseMaterial: form.caseMaterial.trim(),
      movementType: form.movementType.trim(),
      waterResistance: form.waterResistance.trim(),
      listedInCatalog: listed,
      has3DModel: modelUrl !== '',
      modelUrl,
      imageUrl: imageUrls[0] ?? '',
      imageUrls,
      // Only the admin form sends arFit. Null means "no fit"; the service removes
      // any saved one. Left out entirely, an edit never touches it.
      ...(props.showArFit ? { arFit: buildArFit(modelUrl) } : {}),
    })
  } catch (e) {
    uploadError.value = typeof e === 'string' ? e : 'Upload failed. Please try again.'
    console.error(e)
  } finally {
    uploading.value = false
  }
}

// ---------- Layout helpers ----------

const genderChoices = [
  { value: '', label: 'Not specified' },
  ...GENDER_OPTIONS.map((g) => ({ value: g, label: g })),
]

function chipClass(active) {
  return [
    'rounded-full border px-4 py-2 text-sm transition-colors',
    active
      ? 'border-cream/70 bg-dial text-cream'
      : 'border-line text-mist hover:border-mist/50 hover:text-cream',
  ]
}

// Shown as two columns of underlined fields, in the same order as the mobile app.
const specFields = [
  { key: 'caseDiameterMm', label: 'Case diameter (mm)', placeholder: '42', numeric: true },
  { key: 'caseThicknessMm', label: 'Case thickness (mm)', placeholder: '13.5', numeric: true },
  {
    key: 'lugToLugMm',
    label: 'Lug-to-lug (mm)',
    placeholder: '46.5',
    numeric: true,
    required: true,
    hint: "Used to check how the watch fits a customer's wrist.",
  },
  { key: 'bandWidthMm', label: 'Band width (mm)', placeholder: '22', numeric: true },
  { key: 'bandMaterial', label: 'Band material', placeholder: 'e.g. Stainless steel' },
  { key: 'caseMaterial', label: 'Case material', placeholder: 'e.g. Stainless steel' },
  { key: 'movementType', label: 'Movement', placeholder: 'e.g. Automatic, Quartz' },
  { key: 'waterResistance', label: 'Water resistance', placeholder: 'e.g. 100m' },
]
</script>

<template>
  <form novalidate @submit.prevent="handleSubmit(isEditing ? 'save' : 'draft')">
    <p v-if="Object.keys(errors).length" class="alert-error mb-6" role="alert">
      Please fix the highlighted fields.
    </p>

    <div class="grid items-start gap-x-16 gap-y-8 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
      <!-- Left: the text fields -->
      <div class="space-y-8">
        <section class="border-t border-line pt-6">
          <h2 class="eyebrow">Details</h2>

          <div class="mt-5 space-y-6">
            <div>
              <label for="wf-name" class="field-label">
                Watch name <span class="text-gold" aria-hidden="true">*</span>
              </label>
              <input
                id="wf-name"
                v-model="form.name"
                type="text"
                class="field"
                :class="errClass('name')"
                :aria-invalid="!!errors.name"
                aria-required="true"
                placeholder="e.g. Seiko Prospex SPB143J1"
              />
              <p v-if="errors.name" class="mt-1.5 text-xs text-red-300">{{ errors.name }}</p>
            </div>

            <div>
              <label for="wf-brand" class="field-label">Brand</label>
              <input
                id="wf-brand"
                v-model="form.brand"
                type="text"
                class="field"
                placeholder="e.g. Seiko"
              />
            </div>

            <div class="grid gap-6 sm:grid-cols-2 sm:gap-x-8">
              <div>
                <label for="wf-price" class="field-label">
                  Price (PHP) <span class="text-gold" aria-hidden="true">*</span>
                </label>
                <input
                  id="wf-price"
                  v-model="form.price"
                  type="text"
                  inputmode="decimal"
                  class="field"
                  :class="errClass('price')"
                  :aria-invalid="!!errors.price"
                  aria-required="true"
                  placeholder="15000"
                />
                <p v-if="errors.price" class="mt-1.5 text-xs text-red-300">{{ errors.price }}</p>
              </div>
              <div>
                <label for="wf-stock" class="field-label">
                  Stock <span v-if="stockRequired" class="text-gold" aria-hidden="true">*</span>
                </label>
                <input
                  id="wf-stock"
                  v-model="form.stock"
                  type="text"
                  inputmode="numeric"
                  autocomplete="off"
                  maxlength="5"
                  class="field"
                  :class="errClass('stock')"
                  :aria-invalid="!!errors.stock"
                  :aria-required="stockRequired ? 'true' : undefined"
                  placeholder="5"
                />
                <p v-if="errors.stock" class="mt-1.5 text-xs text-red-300">{{ errors.stock }}</p>
              </div>
            </div>
            <p class="-mt-2 text-xs text-mist/80">
              Customers see this count. At {{ LOW_STOCK_THRESHOLD }} or fewer it shows "Only N
              left", and at 0 "Out of stock".
            </p>
          </div>
        </section>

        <section class="border-t border-line pt-6">
          <h2 id="wf-style-label" class="eyebrow">Style</h2>
          <div
            id="wf-style"
            role="group"
            aria-labelledby="wf-style-label"
            class="mt-5 flex flex-wrap gap-2.5"
          >
            <button
              v-for="s in STYLE_OPTIONS"
              :key="s"
              type="button"
              :aria-pressed="form.styleCategory === s"
              :class="chipClass(form.styleCategory === s)"
              @click="form.styleCategory = s"
            >
              {{ s }}
            </button>
          </div>
        </section>

        <section class="border-t border-line pt-6">
          <h2 id="wf-gender-label" class="eyebrow">Target gender</h2>
          <div
            id="wf-gender"
            role="group"
            aria-labelledby="wf-gender-label"
            class="mt-5 flex flex-wrap gap-2.5"
          >
            <button
              v-for="g in genderChoices"
              :key="g.value"
              type="button"
              :aria-pressed="form.targetGender === g.value"
              :class="chipClass(form.targetGender === g.value)"
              @click="form.targetGender = g.value"
            >
              {{ g.label }}
            </button>
          </div>
          <p class="mt-3 text-xs text-mist/80">
            Used for customer recommendations. Recommended before publishing.
          </p>
        </section>

        <section class="border-t border-line pt-6">
          <h2 class="eyebrow">Specifications</h2>
          <div class="mt-5 grid gap-6 sm:grid-cols-2 sm:gap-x-8">
            <div v-for="f in specFields" :key="f.key">
              <label :for="`wf-${f.key}`" class="field-label">
                {{ f.label }}
                <span v-if="f.required" class="text-gold" aria-hidden="true">*</span>
              </label>
              <input
                :id="`wf-${f.key}`"
                v-model="form[f.key]"
                type="text"
                :inputmode="f.numeric ? 'decimal' : undefined"
                class="field"
                :class="errClass(f.key)"
                :aria-invalid="!!errors[f.key]"
                :aria-required="f.required ? 'true' : undefined"
                :placeholder="f.placeholder"
              />
              <p v-if="errors[f.key]" class="mt-1.5 text-xs text-red-300">{{ errors[f.key] }}</p>
              <p v-else-if="f.hint" class="mt-1.5 text-xs text-mist/80">{{ f.hint }}</p>
            </div>
          </div>
        </section>
      </div>

      <!-- Right: photos, 3D model, colors, listing -->
      <div class="space-y-8">
        <section class="border-t border-line pt-6">
          <div class="flex items-baseline justify-between gap-4">
            <h2 class="eyebrow">Photos</h2>
            <span class="text-xs tabular-nums text-mist">{{ photos.length }} / {{ MAX_WATCH_PHOTOS }}</span>
          </div>
          <p class="mt-3 text-sm text-mist">
            Up to {{ MAX_WATCH_PHOTOS }} photos, {{ MAX_PHOTO_MB }}MB each. The first photo is the cover.
            <template v-if="photos.length > 1">Drag to reorder, or choose Make cover.</template>
          </p>
          <p class="sr-only" role="status">{{ photoAnnouncement }}</p>

          <div class="mt-5 grid grid-cols-3 gap-3">
            <div
              v-for="(photo, i) in photos"
              :id="`wf-photo-${photo.id}`"
              :key="photo.id"
              tabindex="-1"
              :draggable="photos.length > 1"
              class="relative aspect-square overflow-hidden rounded-lg bg-case outline-none transition focus-visible:ring-2 focus-visible:ring-gold"
              :class="[
                photos.length > 1 ? 'cursor-grab active:cursor-grabbing' : '',
                draggingId === photo.id ? 'opacity-40' : '',
                draggingId !== null && draggingId !== photo.id && dropIndex === i
                  ? 'ring-2 ring-gold'
                  : '',
              ]"
              @dragstart="onDragStart($event, photo)"
              @dragover="onDragOver($event, i)"
              @drop="onDrop($event, i)"
              @dragend="endDrag"
            >
              <img
                :src="photo.url"
                alt=""
                draggable="false"
                class="absolute inset-0 h-full w-full object-cover"
              />
              <span
                v-if="i === 0"
                class="absolute bottom-2 left-2 rounded-full bg-ink/80 px-2.5 py-1 text-[10px] font-medium uppercase tracking-[0.18em] text-cream backdrop-blur-sm"
              >
                Cover
              </span>
              <button
                v-else
                type="button"
                class="absolute bottom-2 left-2 rounded-full bg-ink/80 px-2.5 py-1 text-[10px] font-medium uppercase tracking-[0.18em] text-cream backdrop-blur-sm transition-colors hover:bg-gold hover:text-ink focus-visible:bg-gold focus-visible:text-ink"
                :aria-label="`Make photo ${i + 1} the cover`"
                @click="makeCover(photo.id)"
              >
                Make cover
              </button>
              <button
                type="button"
                class="absolute right-2 top-2 flex h-6 w-6 items-center justify-center rounded-full bg-ink/80 text-cream backdrop-blur-sm transition-colors hover:bg-red-600"
                :aria-label="`Remove photo ${i + 1}`"
                @click="removePhoto(photo.id)"
              >
                <svg class="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">
                  <path d="M6 6l12 12M18 6L6 18" />
                </svg>
              </button>
            </div>

            <label
              v-if="photos.length < MAX_WATCH_PHOTOS"
              class="flex aspect-square cursor-pointer flex-col items-center justify-center gap-2 rounded-lg border border-line text-mist transition-colors focus-within:border-gold hover:border-mist/50 hover:text-cream"
            >
              <svg class="h-6 w-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true">
                <path d="M12 5v14M5 12h14" />
              </svg>
              <span class="text-[10px] font-medium uppercase tracking-[0.18em]">Add</span>
              <input type="file" accept="image/*" multiple class="sr-only" @change="onPhotosPicked" />
            </label>
          </div>

          <p v-if="photoError" class="mt-3 text-sm text-red-300">{{ photoError }}</p>
        </section>

        <section class="border-t border-line pt-6">
          <h2 class="eyebrow">3D model</h2>

          <div class="mt-5 flex items-center gap-4">
            <svg class="h-6 w-6 shrink-0 text-mist" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <path d="M12 3l8 4.5v9L12 21l-8-4.5v-9L12 3Z" />
              <path d="M12 12l8-4.5M12 12v9M12 12L4 7.5" />
            </svg>
            <div class="min-w-0 flex-1">
              <p class="truncate text-[15px] text-cream">
                {{ modelFile ? modelFile.name : existingModelUrl ? '3D model attached' : 'No 3D model' }}
              </p>
              <p class="mt-0.5 text-xs text-mist">
                A .glb or .gltf file, up to 10MB, enables AR try-on.
              </p>
            </div>
            <button
              v-if="modelFile || existingModelUrl"
              type="button"
              class="eyebrow shrink-0 text-cream transition-colors hover:text-gold"
              @click="removeModel"
            >
              Remove
            </button>
            <label
              v-else
              class="eyebrow shrink-0 cursor-pointer text-cream transition-colors focus-within:outline-2 focus-within:outline-gold hover:text-gold"
            >
              Attach
              <input type="file" accept=".glb,.gltf" class="sr-only" @change="onModelPicked" />
            </label>
          </div>

          <p v-if="modelError" class="mt-3 text-sm text-red-300">{{ modelError }}</p>
        </section>

        <section v-if="showArFit && hasModel" class="border-t border-line pt-6">
          <h2 class="eyebrow">AR fit</h2>
          <p class="mt-4 text-xs text-mist">
            Measured strap-opening numbers for this exact model file, in the model's own units.
            Leave all blank to keep the watch out of AR. Removing the model clears them.
          </p>

          <div class="mt-5 grid gap-6 sm:grid-cols-2 sm:gap-x-8">
            <div
              v-for="f in AR_FIT_FIELDS"
              :key="f.key"
              :class="f.key === 'holeCx' || f.key === 'scale' ? 'sm:col-span-2' : ''"
            >
              <label :for="`wf-${f.key}`" class="field-label">{{ f.label }}</label>
              <input
                :id="`wf-${f.key}`"
                v-model="fit[f.key]"
                type="text"
                autocomplete="off"
                class="field"
                :class="errClass(f.key)"
                :aria-invalid="!!errors[f.key]"
                :placeholder="f.hint"
              />
              <p v-if="errors[f.key]" class="mt-1.5 text-xs text-red-300">{{ errors[f.key] }}</p>
            </div>
          </div>

          <div class="mt-5 flex items-center justify-between gap-4">
            <p class="text-xs text-mist" role="status">
              <template v-if="modelIsGltf">
                A .gltf cannot be shown in AR. Attach a .glb file to enable try-on.
              </template>
              <template v-else-if="fitComplete">AR-ready once saved.</template>
              <template v-else>Not in AR yet: fit incomplete.</template>
            </p>
            <button
              type="button"
              class="eyebrow shrink-0 text-cream transition-colors hover:text-gold"
              :aria-expanded="pasteOpen"
              @click="pasteOpen = !pasteOpen"
            >
              Paste JSON
            </button>
          </div>

          <div v-if="pasteOpen" class="mt-4">
            <label for="wf-fit-json" class="field-label">AR fit JSON</label>
            <textarea
              id="wf-fit-json"
              v-model="pasteText"
              rows="4"
              spellcheck="false"
              class="input font-mono text-xs"
              placeholder='{"holeCx": -0.058, "holeHalfX": 0.226, "holeHalfY": 0.432}'
            ></textarea>
            <p v-if="pasteError" class="mt-1.5 text-xs text-red-300">{{ pasteError }}</p>
            <div class="mt-3 flex gap-2">
              <button type="button" class="btn-primary btn-xs" @click="applyPastedFit">Apply</button>
              <button type="button" class="btn-secondary btn-xs" @click="pasteOpen = false">
                Cancel
              </button>
            </div>
          </div>
        </section>

        <section
          class="border-t border-line pt-6 transition-shadow duration-300"
          :class="attention === 'colors' ? 'rounded-lg ring-2 ring-gold/60 ring-offset-8 ring-offset-ink' : ''"
        >
          <div class="flex items-baseline justify-between gap-4">
            <h2 class="eyebrow">Colors</h2>
            <span class="text-xs tabular-nums text-mist">{{ colorHexes.length }} / {{ MAX_WATCH_COLORS }}</span>
          </div>

          <ul v-if="colorHexes.length" class="mt-4 flex flex-wrap gap-2.5">
            <li
              v-for="(hex, i) in colorHexes"
              :key="hex"
              class="flex items-center gap-2 rounded-full border border-cream/70 bg-dial py-1.5 pl-3 pr-1.5 text-sm text-cream"
            >
              <span class="h-3 w-3 rounded-full border border-line" :style="{ backgroundColor: hex }"></span>
              <span>{{ colorName(hex) }}<span v-if="i === 0" class="text-mist"> · Primary</span></span>
              <button
                type="button"
                class="rounded-full p-1 text-mist transition-colors hover:text-cream"
                :aria-label="`Remove ${colorName(hex)}`"
                @click="toggleColor(hex)"
              >
                <svg class="h-3 w-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" aria-hidden="true">
                  <path d="M6 6l12 12M18 6L6 18" />
                </svg>
              </button>
            </li>
          </ul>

          <p class="mt-4 text-sm text-mist">
            Pick up to {{ MAX_WATCH_COLORS }}. The first one you pick is the primary color.
            Recommended before publishing.
          </p>

          <div
            id="wf-colors"
            class="mt-5 flex flex-wrap gap-x-4 gap-y-4"
            role="group"
            aria-label="Watch colors"
          >
            <button
              v-for="c in WATCH_COLORS"
              :key="c.hex"
              type="button"
              :title="c.name"
              :aria-label="c.name"
              :aria-pressed="isSelected(c.hex)"
              class="flex w-16 flex-col items-center gap-1.5"
              @click="toggleColor(c.hex)"
            >
              <span
                class="flex h-11 w-11 items-center justify-center rounded-full border transition-shadow"
                :class="
                  isSelected(c.hex)
                    ? 'border-transparent ring-2 ring-cream/80 ring-offset-2 ring-offset-ink'
                    : 'border-line hover:ring-2 hover:ring-mist/40'
                "
                :style="{ backgroundColor: c.hex }"
              >
                <svg
                  v-if="isSelected(c.hex)"
                  class="h-4 w-4"
                  viewBox="0 0 24 24"
                  fill="none"
                  :stroke="checkColor(c.hex)"
                  stroke-width="3"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  aria-hidden="true"
                >
                  <path d="M5 12.5l4.5 4.5L19 7.5" />
                </svg>
              </span>
              <span class="text-[11px]" :class="isSelected(c.hex) ? 'text-cream' : 'text-mist'">
                {{ c.name }}
              </span>
            </button>
          </div>
        </section>

        <!-- Editing: a switch. Adding: the buttons below decide. -->
        <section v-if="isEditing" class="border-t border-line pt-6">
          <h2 class="eyebrow">Listing</h2>
          <div class="mt-5 flex items-center justify-between gap-4">
            <div>
              <p id="listed-label" class="text-[15px] text-cream">Listed in catalog</p>
              <p class="mt-1 text-sm text-mist">
                Unlisted watches stay saved as drafts that customers can't see.
              </p>
            </div>
            <button
              type="button"
              role="switch"
              aria-labelledby="listed-label"
              :aria-checked="form.listedInCatalog"
              class="relative h-7 w-12 shrink-0 rounded-full transition-colors"
              :class="form.listedInCatalog ? 'bg-gold/80' : 'bg-slate-600'"
              @click="form.listedInCatalog = !form.listedInCatalog"
            >
              <span
                class="absolute left-0.5 top-0.5 h-6 w-6 rounded-full transition-transform"
                :class="form.listedInCatalog ? 'translate-x-5 bg-gold-light theme-light:bg-white' : 'translate-x-0 bg-cream theme-light:bg-white'"
              ></span>
            </button>
          </div>
        </section>

        <section v-else class="border-t border-line pt-6">
          <h2 class="eyebrow">Listing</h2>
          <p class="mt-4 text-sm text-mist">
            New watches stay hidden from customers until you publish them. Save as draft
            only needs a name, so you can finish the rest later.
          </p>
        </section>
      </div>
    </div>

    <p v-if="uploadError" class="alert-error mt-6" role="alert">{{ uploadError }}</p>

    <!-- Action bar: stays in view however long the form is. -->
    <div
      class="sticky bottom-0 z-10 mt-10 flex items-center justify-end gap-6 border-t border-line bg-ink/95 py-4 backdrop-blur"
    >
      <button
        type="button"
        class="eyebrow transition-colors hover:text-cream disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="saving || uploading"
        @click="emit('cancel')"
      >
        Cancel
      </button>
      <template v-if="isEditing">
        <button type="submit" class="btn-primary min-w-40" :disabled="saving || uploading">
          {{ buttonLabel('save', submitLabel) }}
        </button>
      </template>
      <template v-else>
        <button
          type="button"
          class="btn-secondary min-w-32"
          :disabled="saving || uploading"
          @click="handleSubmit('draft')"
        >
          {{ buttonLabel('draft', 'Save as draft') }}
        </button>
        <button
          type="button"
          class="btn-primary min-w-32"
          :disabled="saving || uploading"
          @click="handleSubmit('publish')"
        >
          {{ buttonLabel('publish', 'Publish') }}
        </button>
      </template>
    </div>

    <ConfirmDialog
      :open="warningOpen"
      title="Publish with missing info?"
      confirm-label="Publish anyway"
      cancel-label="Go back and fix"
      @confirm="confirmPublishAnyway"
      @cancel="cancelWarning"
    >
      This watch has no {{ missingText }} yet. Customers will see it right away, but
      recommendations and the chatbot work best when this is filled in.
    </ConfirmDialog>

    <ConfirmDialog
      :open="leaveOpen"
      title="Discard changes?"
      confirm-label="Discard changes"
      cancel-label="Keep editing"
      danger
      @confirm="discardChanges"
      @cancel="keepEditing"
    >
      <template v-if="isEditing">
        You have unsaved changes to this watch. If you leave now, they will be lost.
      </template>
      <template v-else>
        This watch hasn't been saved yet. If you leave now, everything you entered will be
        lost. Use Save as draft to keep it for later.
      </template>
    </ConfirmDialog>
  </form>
</template>