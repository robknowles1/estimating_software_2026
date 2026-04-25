import { Controller } from "@hotwired/stimulus"

// Evaluates simple arithmetic expressions (e.g. "6/28", "(12+4)/8") entered
// into the Qty field, replacing the raw expression with its decimal result on
// blur.  Any value that fails whitelist validation, causes an evaluation error,
// or produces a non-positive / non-finite result is left unchanged (silent
// no-op).  After writing the resolved value back to the field a native "input"
// event is dispatched so any data-action="input->..." listeners recalculate
// with the resolved decimal.
//
// The controller mounts directly on the <input> element itself (not a wrapping
// ancestor), so this.element is always the input.
//
// NOTE on line_item_calculator_controller: that controller provides a live
// price preview using quantityInput / unitCostInput / markupInput targets and
// extendedCostDisplay / sellPriceDisplay display targets.  Those targets do not
// exist on the current line item form (which uses a server-rendered burden
// calculator, not a client-side preview panel).  Wire line_item_calculator_controller
// when a client-side price preview panel is added to the form.
export default class extends Controller {
  evaluate() {
    const raw = this.element.value
    const trimmed = raw.trim()

    if (trimmed === "") return

    // Whitelist: digits, arithmetic operators, dots, parens, and literal spaces only.
    // Using a literal space (not \s) to exclude tabs, newlines, and other whitespace.
    if (!/^[\d +\-*/.()]+$/.test(trimmed)) return

    // Reject JS-only token sequences that the whitelist allows character-by-character
    // but would change semantics under Function(): "//" is a line comment, "/*"/"*/"
    // are block comments, and "**" is exponentiation (not arithmetic-only).
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

    // Round to 4 decimal places, then strip unnecessary trailing zeros.
    const rounded = Math.round(num * 10000) / 10000
    // A positive but tiny result (e.g. 1/100000) rounds to 0 at 4dp; reject it
    // rather than writing "0" back, which would fail the server's quantity > 0 check.
    if (rounded <= 0) return
    const formatted = parseFloat(rounded.toFixed(4)).toString()

    // Only update the field and notify dependents when the value actually changes.
    // A plain decimal like "1" evaluates to itself — no DOM mutation needed.
    if (trimmed !== formatted) {
      this.element.value = formatted
      // Notify any dependent controllers that the value has changed.
      this.element.dispatchEvent(new Event("input", { bubbles: true }))
    }
  }
}
