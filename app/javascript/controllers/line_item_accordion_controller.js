import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "chevron"]

  toggle() {
    this.formTarget.classList.toggle("hidden")
    this.chevronTarget.classList.toggle("rotate-90")
  }

  stopPropagation(event) {
    event.stopPropagation()
  }
}
