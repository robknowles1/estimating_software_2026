import { Controller } from "@hotwired/stimulus"

// Evaluates simple arithmetic expressions (e.g. "6/28", "(12+4)/8") entered
// into the Qty field, replacing the raw expression with its decimal result on
// blur.  Any value that fails whitelist validation, causes an evaluation error,
// or produces a non-positive / non-finite result is left unchanged (silent
// no-op).  After writing the resolved value back to the field a native "input"
// event is dispatched so any data-action="input->..." listeners (e.g.
// line_item_calculator_controller) recalculate with the resolved decimal.
export default class extends Controller {
  // The controller mounts on the <div> wrapping the Qty input.  The
  // data-action="blur->formula-input#evaluate" descriptor is on the <input>
  // itself, so Stimulus delegates the blur event here; event.target is always
  // the input element.

  evaluate(event) {
    const input = event.target
    const raw = input.value
    const trimmed = raw.trim()

    if (trimmed === "") return

    // Whitelist: digits, arithmetic operators, dots, parens, whitespace only.
    if (!/^[\d\s+\-*/.()]+$/.test(trimmed)) return

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
    const formatted = parseFloat(rounded.toFixed(4)).toString()

    // Only update the field and notify dependents when the value actually changes.
    // A plain decimal like "1" evaluates to itself — no DOM mutation needed.
    if (trimmed !== formatted) {
      input.value = formatted
      // Notify any dependent controllers that the value has changed.
      input.dispatchEvent(new Event("input", { bubbles: true }))
    }
  }
}
