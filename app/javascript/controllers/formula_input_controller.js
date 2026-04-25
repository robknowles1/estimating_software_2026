import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  evaluate() {
    const raw = this.element.value
    const trimmed = raw.trim()

    if (trimmed === "") return

    if (!/^[\d +\-*/.()]+$/.test(trimmed)) return

    if (/\/\/|\/\*|\*\/|\*\*/.test(trimmed)) return

    let result
    try {
      // eslint-disable-next-line no-new-func
      result = Function("return " + trimmed)()
    } catch (_e) {
      return
    }

    const num = Number(result)
    if (!isFinite(num) || isNaN(num) || num <= 0) return

    const rounded = Math.round(num * 10000) / 10000
    // Reject sub-4dp results (e.g. 1/100000) so we don't write "0" and fail the server's quantity > 0 check.
    if (rounded <= 0) return
    const formatted = parseFloat(rounded.toFixed(4)).toString()

    if (trimmed !== formatted) {
      this.element.value = formatted
      this.element.dispatchEvent(new Event("input", { bubbles: true }))
    }
  }
}
