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
      dropdownParent: "body",
      placeholder: this.placeholderValue,
      render: {
        no_results: (data) => {
          this.lastSearch = data.input
          const div = document.createElement("div")
          div.className = "no-results add-new-option"
          div.textContent = this.addOptionLabel(data.input)
          div.style.cursor = "pointer"
          div.style.padding = "8px 12px"
          div.addEventListener("mousedown", (event) => {
            event.preventDefault()
            event.stopPropagation()
            this.openInlineCreatePanel(data.input)
          })
          return div
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

  openInlineCreatePanel(typedName) {
    this.removeInlineCreatePanel()

    const dropdown = this.tomSelect.dropdown
    if (!dropdown) return

    this.lockDropdownOpen()

    const panel = document.createElement("div")
    panel.className = "inline-create-panel"
    panel.style.padding = "12px"
    panel.style.borderTop = "1px solid #e2e8f0"
    panel.style.background = "#f8fafc"
    panel.addEventListener("mousedown", (event) => event.stopPropagation())

    const nameLabel = document.createElement("label")
    nameLabel.textContent = this.nameLabelValue
    nameLabel.style.display = "block"
    nameLabel.style.fontSize = "12px"
    nameLabel.style.fontWeight = "500"
    nameLabel.style.marginBottom = "4px"
    panel.appendChild(nameLabel)

    const nameInput = document.createElement("input")
    nameInput.type = "text"
    nameInput.value = typedName
    nameInput.className = "inline-create-name"
    nameInput.style.width = "100%"
    nameInput.style.padding = "6px 8px"
    nameInput.style.marginBottom = "8px"
    nameInput.style.border = "1px solid #cbd5e1"
    nameInput.style.borderRadius = "4px"
    panel.appendChild(nameInput)

    const costLabel = document.createElement("label")
    costLabel.textContent = this.costLabelValue
    costLabel.style.display = "block"
    costLabel.style.fontSize = "12px"
    costLabel.style.fontWeight = "500"
    costLabel.style.marginBottom = "4px"
    panel.appendChild(costLabel)

    const costInput = document.createElement("input")
    costInput.type = "number"
    costInput.step = "0.01"
    costInput.min = "0"
    costInput.className = "inline-create-cost"
    costInput.style.width = "100%"
    costInput.style.padding = "6px 8px"
    costInput.style.marginBottom = "8px"
    costInput.style.border = "1px solid #cbd5e1"
    costInput.style.borderRadius = "4px"
    panel.appendChild(costInput)

    const errorContainer = document.createElement("div")
    errorContainer.className = "inline-create-errors"
    errorContainer.style.color = "#b91c1c"
    errorContainer.style.fontSize = "12px"
    errorContainer.style.marginBottom = "8px"
    errorContainer.style.display = "none"
    panel.appendChild(errorContainer)

    const buttonRow = document.createElement("div")
    buttonRow.style.display = "flex"
    buttonRow.style.gap = "8px"

    const confirmButton = document.createElement("button")
    confirmButton.type = "button"
    confirmButton.textContent = this.confirmButtonValue
    confirmButton.className = "inline-create-confirm"
    confirmButton.style.padding = "6px 12px"
    confirmButton.style.background = "#d97706"
    confirmButton.style.color = "white"
    confirmButton.style.border = "none"
    confirmButton.style.borderRadius = "4px"
    confirmButton.style.fontSize = "13px"
    confirmButton.style.fontWeight = "600"
    confirmButton.style.cursor = "pointer"
    confirmButton.addEventListener("click", (event) => {
      event.preventDefault()
      this.submitInlineCreate(nameInput.value, costInput.value, errorContainer, confirmButton)
    })
    buttonRow.appendChild(confirmButton)

    const cancelButton = document.createElement("button")
    cancelButton.type = "button"
    cancelButton.textContent = this.cancelButtonValue
    cancelButton.className = "inline-create-cancel"
    cancelButton.style.padding = "6px 12px"
    cancelButton.style.background = "white"
    cancelButton.style.color = "#475569"
    cancelButton.style.border = "1px solid #cbd5e1"
    cancelButton.style.borderRadius = "4px"
    cancelButton.style.fontSize = "13px"
    cancelButton.style.cursor = "pointer"
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

  // Replace tomSelect.close with a no-op while the inline panel is visible so
  // that blur events from the user clicking into the cost input do not collapse
  // the dropdown.  The original close is restored when the panel is removed.
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
    errorContainer.style.display = "none"
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
    heading.style.fontWeight = "600"
    heading.style.marginBottom = "4px"
    container.appendChild(heading)

    const list = document.createElement("ul")
    list.style.margin = "0"
    list.style.paddingLeft = "16px"
    messages.forEach((message) => {
      const li = document.createElement("li")
      li.textContent = message
      list.appendChild(li)
    })
    container.appendChild(list)
    container.style.display = "block"
  }
}
