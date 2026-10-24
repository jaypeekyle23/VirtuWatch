const CLOUD_NAME = 'o9fetve3'
const UPLOAD_PRESET = 'virtuwatch_uploads'

// Cloudinary's free plan caps raw (non-image) uploads at 10MB.
const MAX_MODEL_BYTES = 10 * 1024 * 1024

async function upload(file, resourceType) {
  const formData = new FormData()
  formData.append('file', file)
  formData.append('upload_preset', UPLOAD_PRESET)

  let response
  try {
    response = await fetch(
      `https://api.cloudinary.com/v1_1/${CLOUD_NAME}/${resourceType}/upload`,
      { method: 'POST', body: formData },
    )
  } catch {
    throw 'Could not upload. Check your connection and try again.'
  }

  if (!response.ok) {
    let reason = `HTTP ${response.status}`
    try {
      const body = await response.json()
      if (body?.error?.message) reason = body.error.message
    } catch {
      // Body wasn't JSON; keep the status code.
    }
    throw `Upload failed: ${reason}`
  }

  const data = await response.json()
  if (!data.secure_url) throw 'Upload succeeded but no URL was returned.'
  return data.secure_url
}

// Uploads an image File and returns its hosted URL.
export function uploadImage(file) {
  return upload(file, 'image')
}

// Uploads a .glb or .gltf File and returns its hosted URL.
export function uploadModel(file) {
  const extension = file.name.split('.').pop().toLowerCase()
  if (extension !== 'glb' && extension !== 'gltf') {
    throw `Please select a .glb or .gltf 3D model file (you picked a .${extension} file).`
  }
  if (file.size > MAX_MODEL_BYTES) {
    throw 'That model is over 10MB. Compress it (e.g. Draco) and try again.'
  }
  return upload(file, 'raw')
}