import { Controller } from "@hotwired/stimulus"
import TomSelect from "tom-select"

export default class extends Controller {
  static targets = ["control", "hiddenField"]
  static values = {
    materials: Array,
    placeholder: String,
    emptyState: String
  }

  connect() {
    this.tomSelect = new TomSelect(this.controlTarget, {
      valueField: "id",
      labelField: "label",
      searchField: ["label"],
      options: this.materialsValue,
      placeholder: this.placeholderValue,
      create: false,
      dropdownParent: document.body,
      render: {
        no_results: () => {
          const div = document.createElement("div")
          div.className = "no-results"
          div.textContent = this.emptyStateValue
          return div
        }
      },
      onChange: (value) => {
        if (value && this.hasHiddenFieldTarget) {
          this.hiddenFieldTarget.value = value
          this.controlTarget.closest("form").requestSubmit()
        }
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
