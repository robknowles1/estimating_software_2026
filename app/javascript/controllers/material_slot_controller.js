import { Controller } from "@hotwired/stimulus"
import TomSelect from "tom-select"

export default class extends Controller {
  static values = {
    inlineCreateUrl: String,
    placeholder: String,
    addOptionTemplate: String,
    nameLabel: String,
    costLabel: String,
    confirmButton: String,
    cancelButton: String,
    errorHeading: String,
    unexpectedError: String,
    networkError: String
  }

  connect() {
    this.lastSearch = ""

    this.tomSelect = new TomSelect(this.element, {
      create: false,
      placeholder: this.placeholderValue,
      render: {
        no_results: (data) => {
          this.lastSearch = data.input
          const button = document.createElement("button")
          button.type = "button"
          button.className = "no-results add-new-option block w-full text-left px-3 py-2 text-sm text-amber-700 hover:bg-amber-50 focus:bg-amber-50 focus:outline-none focus:ring-2 focus:ring-amber-500 cursor-pointer bg-transparent border-0"
          button.textContent = this.addOptionLabel(data.input)

          let suppressClick = false
          const handleActivate = (event) => {
            event.preventDefault()
            event.stopPropagation()
            if (event.type === "click" && suppressClick) {
              suppressClick = false
              return
            }
            if (event.type === "mousedown") {
              suppressClick = true
            }
            this.openInlineCreatePanel(data.input)
          }

          // <button> natively dispatches click on Enter/Space, so no explicit
          // keydown listener is needed for keyboard activation.
          button.addEventListener("mousedown", handleActivate)
          button.addEventListener("click", handleActivate)
          return button
        }
      }
    })
  }

  disconnect() {
    this.removeInlineCreatePanel()
    if (this.tomSelect) {
      this.tomSelect.destroy()
      this.tomSelect = null
    }
  }

  addOptionLabel(name) {
    const template = this.addOptionTemplateValue || "Add '%{name}'"
    return template.replace("%{name}", name)
  }

  inlineCreateFieldIdPrefix() {
    return this.element.id || this.element.name || `material-slot-${this.idSuffix ||= Math.random().toString(36).slice(2, 10)}`
  }

  openInlineCreatePanel(typedName) {
    this.removeInlineCreatePanel()

    const dropdown = this.tomSelect.dropdown
    if (!dropdown) return

    this.lockDropdownOpen()

    const idPrefix = this.inlineCreateFieldIdPrefix()
    const nameInputId = `${idPrefix}-inline-create-name`
    const costInputId = `${idPrefix}-inline-create-cost`

    const panel = document.createElement("div")
    panel.className = "inline-create-panel p-3 border-t border-slate-200 bg-slate-50"
    panel.addEventListener("mousedown", (event) => event.stopPropagation())

    const nameLabel = document.createElement("label")
    nameLabel.htmlFor = nameInputId
    nameLabel.textContent = this.nameLabelValue
    nameLabel.className = "block text-xs font-medium mb-1"
    panel.appendChild(nameLabel)

    const nameInput = document.createElement("input")
    nameInput.type = "text"
    nameInput.id = nameInputId
    nameInput.value = typedName
    nameInput.className = "inline-create-name inline-create-input w-full px-2 py-1.5 mb-2 border border-slate-300 rounded text-sm focus:outline-none focus:ring-2 focus:ring-amber-500 focus:border-amber-500"
    panel.appendChild(nameInput)

    const costLabel = document.createElement("label")
    costLabel.htmlFor = costInputId
    costLabel.textContent = this.costLabelValue
    costLabel.className = "block text-xs font-medium mb-1"
    panel.appendChild(costLabel)

    const costInput = document.createElement("input")
    costInput.type = "number"
    costInput.id = costInputId
    costInput.step = "0.01"
    costInput.min = "0"
    costInput.className = "inline-create-cost inline-create-input w-full px-2 py-1.5 mb-2 border border-slate-300 rounded text-sm focus:outline-none focus:ring-2 focus:ring-amber-500 focus:border-amber-500"
    panel.appendChild(costInput)

    const errorContainer = document.createElement("div")
    errorContainer.className = "inline-create-errors hidden text-red-700 text-xs mb-2"
    panel.appendChild(errorContainer)

    const buttonRow = document.createElement("div")
    buttonRow.className = "flex gap-2"

    const confirmButton = document.createElement("button")
    confirmButton.type = "button"
    confirmButton.textContent = this.confirmButtonValue
    confirmButton.className = "inline-create-confirm px-3 py-1.5 bg-amber-600 hover:bg-amber-700 text-white border-0 rounded text-sm font-semibold cursor-pointer disabled:opacity-50"
    confirmButton.addEventListener("click", (event) => {
      event.preventDefault()
      this.submitInlineCreate(nameInput.value, costInput.value, errorContainer, confirmButton)
    })
    buttonRow.appendChild(confirmButton)

    const cancelButton = document.createElement("button")
    cancelButton.type = "button"
    cancelButton.textContent = this.cancelButtonValue
    cancelButton.className = "inline-create-cancel px-3 py-1.5 bg-white text-slate-600 border border-slate-300 rounded text-sm cursor-pointer hover:bg-slate-50"
    cancelButton.addEventListener("click", (event) => {
      event.preventDefault()
      this.removeInlineCreatePanel()
      this.tomSelect.setTextboxValue("")
      this.tomSelect.close()
    })
    buttonRow.appendChild(cancelButton)

    panel.appendChild(buttonRow)

    dropdown.appendChild(panel)
    this.inlineCreatePanel = panel
    this.tomSelect.open()
  }

  // Patch out close() to prevent blur on cost input collapsing the dropdown; restored in unlockDropdownOpen.
  lockDropdownOpen() {
    if (!this.tomSelect || this.dropdownLocked) return
    this.originalClose = this.tomSelect.close.bind(this.tomSelect)
    this.tomSelect.close = () => {}
    this.dropdownLocked = true
  }

  unlockDropdownOpen() {
    if (!this.tomSelect || !this.dropdownLocked) return
    this.tomSelect.close = this.originalClose
    this.dropdownLocked = false
  }

  removeInlineCreatePanel() {
    if (this.inlineCreatePanel && this.inlineCreatePanel.parentNode) {
      this.inlineCreatePanel.parentNode.removeChild(this.inlineCreatePanel)
    }
    this.inlineCreatePanel = null
    this.unlockDropdownOpen()
  }

  async submitInlineCreate(name, cost, errorContainer, confirmButton) {
    errorContainer.classList.add("hidden")
    errorContainer.innerHTML = ""
    confirmButton.disabled = true

    const csrfMeta = document.querySelector('meta[name="csrf-token"]')
    const csrfToken = csrfMeta ? csrfMeta.content : ""

    try {
      const response = await fetch(this.inlineCreateUrlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify({ material: { name: name, cost: cost } })
      })

      if (response.status === 201) {
        const data = await response.json()
        this.tomSelect.addOption({ value: String(data.id), text: data.display })
        this.tomSelect.setValue(String(data.id))
        this.removeInlineCreatePanel()
        this.tomSelect.close()
      } else if (response.status === 422) {
        const data = await response.json()
        this.renderErrors(errorContainer, data.errors || [])
      } else {
        this.renderErrors(errorContainer, [this.unexpectedErrorValue])
      }
    } catch (error) {
      this.renderErrors(errorContainer, [this.networkErrorValue])
    } finally {
      confirmButton.disabled = false
    }
  }

  renderErrors(container, messages) {
    container.innerHTML = ""
    if (messages.length === 0) return

    const heading = document.createElement("div")
    heading.textContent = this.errorHeadingValue
    heading.className = "font-semibold mb-1"
    container.appendChild(heading)

    const list = document.createElement("ul")
    list.className = "m-0 pl-4 list-disc"
    messages.forEach((message) => {
      const li = document.createElement("li")
      li.textContent = message
      list.appendChild(li)
    })
    container.appendChild(list)
    container.classList.remove("hidden")
  }
}
