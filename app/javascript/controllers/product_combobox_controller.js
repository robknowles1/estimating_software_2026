import { Controller } from "@hotwired/stimulus"
import TomSelect from "tom-select"

export default class extends Controller {
  static values = {
    placeholder: String,
    noResults: String
  }

  connect() {
    this.tomSelect = new TomSelect(this.element, {
      create: false,
      placeholder: this.placeholderValue,
      render: {
        no_results: () => {
          const div = document.createElement("div")
          div.className = "no-results"
          div.textContent = this.noResultsValue
          return div
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
