import { Controller } from "@hotwired/stimulus"

// Adds and removes rows of a Rails fields_for nested-attributes list without a
// full page reload. New rows are cloned from a <template> whose fields use the
// placeholder index "NEW_RECORD"; on add we swap in a unique timestamp so each
// new row submits as a distinct nested record. Removing an existing (persisted)
// row sets its hidden _destroy flag and hides it; removing a brand-new row just
// detaches it from the DOM.
export default class extends Controller {
  static targets = ["container", "template", "row", "destroyFlag"]

  add(event) {
    event.preventDefault()
    const html = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, Date.now().toString())
    this.containerTarget.insertAdjacentHTML("beforeend", html)
  }

  remove(event) {
    event.preventDefault()
    const row = event.target.closest("[data-nested-list-target='row']")
    if (!row) return

    const destroyField = row.querySelector("[data-nested-list-target='destroyFlag']")
    const idField = row.querySelector("input[name*='[id]']")

    if (idField && idField.value) {
      // Persisted record: mark for destruction and hide.
      if (destroyField) destroyField.value = "1"
      row.classList.add("hidden")
    } else {
      // New, unsaved row: remove outright.
      row.remove()
    }
  }
}
