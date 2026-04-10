import { Controller } from "@hotwired/stimulus"

// Provides real-time price preview for freeform line items (buy-out, alternate, other).
// Calculates: extended_cost = freeform_quantity × unit_cost
//             sell_price    = extended_cost × (1 + markup / 100)
// Material and labor items do not use freeform_quantity/unit_cost, so their preview
// displays "—". Accurate totals for all types come from the server-side burden calculator.
export default class extends Controller {
  static targets = [
    "quantityInput",
    "unitCostInput",
    "markupInput",
    "extendedCostDisplay",
    "sellPriceDisplay"
  ]

  connect() {
    this.calculate()
  }

  calculate() {
    const qty = parseFloat(this.hasQuantityInputTarget ? this.quantityInputTarget.value : 0) || 0
    const unitCost = parseFloat(this.hasUnitCostInputTarget ? this.unitCostInputTarget.value : 0) || 0
    const markup = parseFloat(this.hasMarkupInputTarget ? this.markupInputTarget.value : 0) || 0

    const extended = qty * unitCost
    const sell = extended * (1 + markup / 100)

    if (this.hasExtendedCostDisplayTarget) {
      this.extendedCostDisplayTarget.textContent = extended > 0 ? this.formatCurrency(extended) : "—"
    }

    if (this.hasSellPriceDisplayTarget) {
      this.sellPriceDisplayTarget.textContent = extended > 0 ? this.formatCurrency(sell) : "—"
    }
  }

  formatCurrency(amount) {
    return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(amount)
  }
}
