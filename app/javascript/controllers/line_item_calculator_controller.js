import { Controller } from "@hotwired/stimulus"

// Provides real-time extended cost and sell price calculation in line item forms.
// For material/labor items: shows extended cost only (sell price from server burden calc).
// For buy-out/alternate items: shows extended_cost and sell_price = cost × (1 + markup/100).
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
