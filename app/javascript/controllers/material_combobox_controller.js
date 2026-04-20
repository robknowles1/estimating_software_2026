import { Controller } from "@hotwired/stimulus"
import TomSelect from "tom-select"

export default class extends Controller {
  static targets = ["select", "hiddenField"]
  static values = {
    materials: Array,
    placeholder: String,
    emptyState: String
  }

  connect() {
    this.tomSelect = new TomSelect(this.selectTarget, {
      valueField: "id",
      labelField: "label",
      searchField: ["label"],
      options: this.materialsValue,
      placeholder: this.placeholderValue,
      create: false,
      noResultsText: this.emptyStateValue,
      onItemAdd: (value) => {
        if (this.hasHiddenFieldTarget) {
          this.hiddenFieldTarget.value = value
        }
        this.selectTarget.closest("form").requestSubmit()
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
