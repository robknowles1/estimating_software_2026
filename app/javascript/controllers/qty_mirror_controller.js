import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["back"]

  copyToBack(event) {
    const sourceValue = event.target.value.trim()
    if (sourceValue === "") return
    if (this.backTarget.value.trim() !== "") return
    this.backTarget.value = event.target.value
  }
}
