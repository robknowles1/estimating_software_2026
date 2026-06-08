import { Controller } from "@hotwired/stimulus"

// Previews images selected in a multi-file photo input before the form is saved.
// Renders a thumbnail per selected file into the previews target. Only JPEG/PNG
// are accepted (the input also enforces this via its accept attribute and the
// server validates content type on save).
export default class extends Controller {
  static targets = ["input", "previews"]

  preview() {
    this.previewsTarget.innerHTML = ""

    Array.from(this.inputTarget.files).forEach((file) => {
      if (!file.type.match(/^image\/(jpeg|png)$/)) return

      const img = document.createElement("img")
      img.className = "w-16 h-16 object-cover rounded border border-slate-200"
      img.src = URL.createObjectURL(file)
      img.onload = () => URL.revokeObjectURL(img.src)
      this.previewsTarget.appendChild(img)
    })
  }
}
