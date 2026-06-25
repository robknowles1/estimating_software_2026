import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this._timer = setTimeout(() => this.#dismiss(), 4000)
  }

  disconnect() {
    clearTimeout(this._timer)
  }

  dismiss() {
    this.#dismiss()
  }

  #dismiss() {
    clearTimeout(this._timer)
    this.element.style.transition = "opacity 0.3s ease"
    this.element.style.opacity = "0"
    setTimeout(() => this.element.remove(), 300)
  }
}
