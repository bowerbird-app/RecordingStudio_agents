import { Controller } from "@hotwired/stimulus"

// Polls the step list and updates each collapse in place.
export default class extends Controller {
  static values = {
    url: String,
    active: Boolean
  }

  connect() {
    if (!this.activeValue) return

    this.refresh()
    this.timer = window.setInterval(() => this.refresh(), 1000)
  }

  disconnect() {
    this.stop()
  }

  stop() {
    if (this.timer) window.clearInterval(this.timer)
    this.timer = null
  }

  async refresh() {
    if (this.loading) return

    this.loading = true
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "text/html" }
      })
      if (!response.ok) return

      const parsed = new DOMParser().parseFromString(await response.text(), "text/html")
      const frame = parsed.querySelector("#playground-steps-frame")
      if (!frame) return

      this.applyError(frame)
      this.applySteps(frame.querySelector("#playground-results"))
      if (frame.dataset.watching !== "true") this.stop()
    } finally {
      this.loading = false
    }
  }

  applyError(frame) {
    const incoming = frame.querySelector("[data-playground-error]")
    const current = document.getElementById("playground-error")
    if (!incoming || !current || current.innerHTML === incoming.innerHTML) return

    current.innerHTML = incoming.innerHTML
  }

  applySteps(incoming) {
    if (!incoming) return

    const incomingList = incoming.querySelector("[data-playground-step-list]")
    if (!incomingList) return

    const currentList = this.element.querySelector("[data-playground-step-list]")
    if (!currentList) {
      this.element.appendChild(document.importNode(incomingList, true))
      return
    }

    incomingList.querySelectorAll("[data-controller='flat-pack--collapse']").forEach((next) => {
      const content = next.querySelector("[data-flat-pack--collapse-target='content']")
      const existingContent = content && this.element.querySelector(`#${CSS.escape(content.id)}`)
      if (!existingContent) {
        currentList.appendChild(document.importNode(next, true))
        return
      }

      this.updateCollapse(existingContent.closest("[data-controller='flat-pack--collapse']"), next)
    })
  }

  updateCollapse(current, next) {
    if (!current) return

    const currentLabel = current.querySelector("[data-flat-pack--collapse-target='trigger'] > span")
    const nextLabel = next.querySelector("[data-flat-pack--collapse-target='trigger'] > span")
    if (currentLabel && nextLabel && currentLabel.innerHTML !== nextLabel.innerHTML) {
      currentLabel.innerHTML = nextLabel.innerHTML
    }

    const currentContent = current.querySelector("[data-flat-pack--collapse-target='content']")
    const nextContent = next.querySelector("[data-flat-pack--collapse-target='content']")
    if (!currentContent || !nextContent || currentContent.innerHTML === nextContent.innerHTML) return

    const open = current.querySelector("[data-flat-pack--collapse-target='trigger']")?.getAttribute("aria-expanded") === "true"
    currentContent.innerHTML = nextContent.innerHTML
    if (!open) return

    currentContent.hidden = false
    currentContent.style.maxHeight = `${currentContent.scrollHeight}px`
  }
}
