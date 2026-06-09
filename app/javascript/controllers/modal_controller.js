import { Controller } from "@hotwired/stimulus"

// A reusable accessible modal dialog. Open/close is driven by toggling the
// "hidden" class on the dialog element. While open it: traps focus inside the
// dialog, moves focus to the first focusable field, closes on Escape, closes on
// a backdrop click, and returns focus to the element that opened it on close.
//
// Used by the proposal wizard's opening step "Add contact" modal. The modal
// form submits via Turbo Stream; a successful create replaces the contact field
// (which removes/re-renders the dialog markup) so the modal disappears as part
// of the stream — but we also expose `close` so Cancel / × / Escape / backdrop
// can dismiss without a round-trip.
export default class extends Controller {
  static targets = ["dialog"]

  connect() {
    this.boundKeydown = this.handleKeydown.bind(this)
    this.boundSubmitEnd = this.handleSubmitEnd.bind(this)
    this.element.addEventListener("turbo:submit-end", this.boundSubmitEnd)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
    this.element.removeEventListener("turbo:submit-end", this.boundSubmitEnd)
  }

  // On a successful inline submit the success Turbo Stream re-renders this dialog
  // markup closed/empty (it owns the open/closed state), while this JS handler
  // only detaches the keydown listener and restores focus to whatever opened the
  // modal — the two are not fighting over visibility. On failure the dialog stays
  // open (the stream re-renders the frame with errors) so we leave it untouched.
  handleSubmitEnd(event) {
    if (event.detail && event.detail.success) this.afterSuccess()
  }

  afterSuccess() {
    document.removeEventListener("keydown", this.boundKeydown)
    // The success stream replaces the contact field, so the original opener node
    // (the "+ Add contact" button) is now detached. Re-query the live button
    // within this controller's scope and return focus to it; fall back to the
    // contact select if the button is gone for any reason.
    const button = this.element.querySelector("[data-action~='modal#open']")
    const target = button || this.element.querySelector("#proposal_contact_id")
    if (target && typeof target.focus === "function") target.focus()
  }

  open(event) {
    if (event) event.preventDefault()
    this.opener = event ? event.currentTarget : document.activeElement
    this.dialogTarget.classList.remove("hidden")
    document.addEventListener("keydown", this.boundKeydown)
    // Move focus to the first focusable field inside the dialog.
    const first = this.focusableElements()[0]
    if (first) first.focus()
  }

  close(event) {
    if (event) event.preventDefault()
    this.dialogTarget.classList.add("hidden")
    document.removeEventListener("keydown", this.boundKeydown)
    if (this.opener && typeof this.opener.focus === "function") {
      this.opener.focus()
    }
  }

  // Close only when the click lands on the backdrop itself, not on the panel.
  backdropClose(event) {
    if (event.target === event.currentTarget) this.close(event)
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      this.close(event)
      return
    }
    if (event.key === "Tab") this.trapFocus(event)
  }

  trapFocus(event) {
    const focusable = this.focusableElements()
    if (focusable.length === 0) return

    const first = focusable[0]
    const last = focusable[focusable.length - 1]

    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  focusableElements() {
    const selector =
      "a[href], button:not([disabled]), input:not([disabled]):not([type='hidden']), " +
      "select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex='-1'])"
    return Array.from(this.dialogTarget.querySelectorAll(selector)).filter(
      (el) => el.offsetParent !== null
    )
  }
}
