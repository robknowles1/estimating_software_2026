import { Controller } from "@hotwired/stimulus"

// Provides catalog autocomplete for the line item description field.
// Debounces keypress, fetches /catalog_items/search?q=<value>, renders a
// dropdown, and pre-fills description, unit, and unit_cost on selection.
// Keyboard navigation: up/down arrows, Enter to select, Escape to dismiss.
export default class extends Controller {
  static targets = [
    "input",
    "dropdown",
    "catalogItemId",
    "unitInput",
    "unitCostInput"
  ]

  static values = {
    searchUrl: String,
    minLength: { type: Number, default: 2 },
    debounceMs: { type: Number, default: 250 }
  }

  connect() {
    this._debounceTimer = null
    this._results = []
    this._activeIndex = -1
    this._handleOutsideClick = this._onOutsideClick.bind(this)
    document.addEventListener("click", this._handleOutsideClick)
  }

  disconnect() {
    document.removeEventListener("click", this._handleOutsideClick)
    this._clearTimer()
  }

  // Called on keyup/input from the description field
  search(event) {
    // Allow keyboard navigation without re-fetching
    if (["ArrowDown", "ArrowUp", "Enter", "Escape"].includes(event.key)) return

    this._clearTimer()
    const query = this.inputTarget.value.trim()

    if (query.length < this.minLengthValue) {
      this._closeDropdown()
      return
    }

    this._debounceTimer = setTimeout(() => this._fetch(query), this.debounceMsValue)
  }

  // Keyboard navigation within the dropdown
  navigate(event) {
    if (!this._isDropdownOpen()) return

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this._moveFocus(1)
        break
      case "ArrowUp":
        event.preventDefault()
        this._moveFocus(-1)
        break
      case "Enter":
        event.preventDefault()
        if (this._activeIndex >= 0) {
          this._select(this._results[this._activeIndex])
        }
        break
      case "Escape":
        this._closeDropdown()
        break
    }
  }

  // Called when user clicks a dropdown option
  selectOption(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    this._select(this._results[index])
  }

  _fetch(query) {
    const url = `${this.searchUrlValue}?q=${encodeURIComponent(query)}`

    fetch(url, {
      headers: { "Accept": "application/json", "X-Requested-With": "XMLHttpRequest" },
      credentials: "same-origin"
    })
      .then(res => res.json())
      .then(data => {
        this._results = data
        this._activeIndex = -1
        this._renderDropdown()
      })
      .catch(() => this._closeDropdown())
  }

  _renderDropdown() {
    if (!this.hasDropdownTarget) return

    if (this._results.length === 0) {
      this._closeDropdown()
      return
    }

    const items = this._results.map((item, i) => {
      const costStr = item.default_unit_cost != null
        ? new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(item.default_unit_cost)
        : ""
      const unitStr = item.default_unit ? ` · ${item.default_unit}` : ""
      const subtext = [costStr, unitStr].filter(Boolean).join("")

      return `<li
        role="option"
        id="catalog-option-${i}"
        aria-selected="${i === this._activeIndex}"
        data-index="${i}"
        data-action="click->description-autocomplete#selectOption mouseenter->description-autocomplete#hoverOption"
        class="px-3 py-2 cursor-pointer text-sm hover:bg-amber-50 ${i === this._activeIndex ? 'bg-amber-50' : ''}"
      >
        <span class="font-medium text-slate-900">${this._escape(item.description)}</span>
        ${subtext ? `<span class="text-slate-400 text-xs ml-2">${this._escape(subtext)}</span>` : ""}
      </li>`
    }).join("")

    this.dropdownTarget.innerHTML = `<ul role="listbox" class="divide-y divide-slate-100">${items}</ul>`
    this.dropdownTarget.classList.remove("hidden")

    this.inputTarget.setAttribute("aria-expanded", "true")
    if (this._activeIndex >= 0) {
      this.inputTarget.setAttribute("aria-activedescendant", `catalog-option-${this._activeIndex}`)
    } else {
      this.inputTarget.removeAttribute("aria-activedescendant")
    }
  }

  hoverOption(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    this._activeIndex = index
    this._updateActiveStyles()
  }

  _select(item) {
    if (!item) return

    this.inputTarget.value = item.description

    if (this.hasUnitInputTarget) {
      this.unitInputTarget.value = item.default_unit || ""
    }
    if (this.hasUnitCostInputTarget) {
      this.unitCostInputTarget.value = item.default_unit_cost != null ? item.default_unit_cost : ""
      // Trigger the line-item-calculator to re-calculate preview
      this.unitCostInputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    }
    if (this.hasCatalogItemIdTarget) {
      this.catalogItemIdTarget.value = item.id
    }

    this._closeDropdown()
  }

  _moveFocus(delta) {
    this._activeIndex = Math.max(-1, Math.min(this._results.length - 1, this._activeIndex + delta))
    this._updateActiveStyles()

    if (this._activeIndex >= 0) {
      this.inputTarget.setAttribute("aria-activedescendant", `catalog-option-${this._activeIndex}`)
    } else {
      this.inputTarget.removeAttribute("aria-activedescendant")
    }
  }

  _updateActiveStyles() {
    if (!this.hasDropdownTarget) return
    this.dropdownTarget.querySelectorAll("[role=option]").forEach((el, i) => {
      el.setAttribute("aria-selected", i === this._activeIndex ? "true" : "false")
      el.classList.toggle("bg-amber-50", i === this._activeIndex)
    })
  }

  _closeDropdown() {
    if (this.hasDropdownTarget) {
      this.dropdownTarget.classList.add("hidden")
      this.dropdownTarget.innerHTML = ""
    }
    if (this.hasInputTarget) {
      this.inputTarget.setAttribute("aria-expanded", "false")
      this.inputTarget.removeAttribute("aria-activedescendant")
    }
    this._activeIndex = -1
  }

  _isDropdownOpen() {
    return this.hasDropdownTarget && !this.dropdownTarget.classList.contains("hidden")
  }

  _onOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this._closeDropdown()
    }
  }

  _clearTimer() {
    if (this._debounceTimer) {
      clearTimeout(this._debounceTimer)
      this._debounceTimer = null
    }
  }

  _escape(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
