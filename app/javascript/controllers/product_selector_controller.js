import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "form"]
  static values  = { products: Array }

  fill() {
    const productId = parseInt(this.selectTarget.value)
    const product   = this.productsValue.find(p => p.id === productId)
    if (!product) return

    const form = this.formTarget
    const set  = (name, val) => {
      const el = form.querySelector(`[name="line_item[${name}]"]`)
      if (el && (val !== null && val !== undefined)) el.value = val
    }

    set("unit", product.unit)
    ;["exterior","interior","interior2","back","drawers","pulls","hinges","slides","locks"].forEach(slot => {
      set(`${slot}_description`, product[`${slot}_description`] || "")
      set(`${slot}_unit_price`,  product[`${slot}_unit_price`]  || "")
      set(`${slot}_qty`,         product[`${slot}_qty`]         || "")
    })
    set("banding_description", product.banding_description || "")
    set("banding_unit_price",  product.banding_unit_price  || "")
    set("other_material_cost", product.other_material_cost || "")
    ;["detail","mill","assembly","customs","finish","install"].forEach(cat => {
      set(`${cat}_hrs`, product[`${cat}_hrs`] || "")
    })
    set("equipment_hrs",  product.equipment_hrs  || "")
    set("equipment_rate", product.equipment_rate || "")

    // Pre-fill description with product name if currently blank
    const descEl = form.querySelector(`[name="line_item[description]"]`)
    if (descEl && !descEl.value) {
      descEl.value = product.name || ""
    }
  }
}
