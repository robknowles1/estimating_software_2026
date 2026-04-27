import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  initialize() {
    this.handleKeydown = this.handleKeydown.bind(this)
  }

  connect() {
    this.element.addEventListener("keydown", this.handleKeydown)
  }

  disconnect() {
    this.element.removeEventListener("keydown", this.handleKeydown)
  }

  handleKeydown(event) {
    if (event.key !== "Enter") return

    const target = event.target
    if (!target) return

    const tag = target.tagName
    if (tag === "TEXTAREA" || tag === "BUTTON") return
    if (tag === "INPUT" && target.type === "submit") return
    if (target.dataset.allowEnter === "true") return

    const fields = Array.from(
      this.element.querySelectorAll("input, select, textarea, button")
    ).filter((el) => !el.disabled && el.offsetParent !== null && el.tabIndex !== -1)

    const idx = fields.indexOf(target)
    if (idx === -1) return

    event.preventDefault()

    const next = fields[idx + 1]
    if (next) {
      next.focus()
      return
    }

    const submit = this.element.querySelector("input[type='submit'], button[type='submit']")
    if (submit) submit.focus()
  }
}
