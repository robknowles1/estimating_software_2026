import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["back"]

  copyToBack(event) {
    const sourceValue = event.target.value.trim()
    if (this.backTarget.value.trim() !== "") return
    if (sourceValue === "") return
    this.backTarget.value = event.target.value
  }
}
