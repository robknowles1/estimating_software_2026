import { Controller } from "@hotwired/stimulus"
import TomSelect from "tom-select"

export default class extends Controller {
  static targets = ["control", "hiddenField"]
  static values = {
    placeholder: String,
    emptyState: String
  }

  connect() {
    this.tomSelect = new TomSelect(this.controlTarget, {
      create: false,
      dropdownParent: document.body,
      placeholder: this.placeholderValue,
      render: {
        no_results: () => {
          const div = document.createElement("div")
          div.className = "no-results"
          div.textContent = this.emptyStateValue
          return div
        }
      },
      onItemAdd: (value) => {
        if (this.hasHiddenFieldTarget) {
          this.hiddenFieldTarget.value = value
        }
        this.controlTarget.closest("form").requestSubmit()
      }
    })
  }

  disconnect() {
    if (this.tomSelect) {
      this.tomSelect.destroy()
      this.tomSelect = null
    }
  }
}
