// FlatPack's popover closes on an outside click and, when Turbo puts the
// permanent launcher back, connect() marks it closed. The iframe node stays.
// This puts the open panel back after the visit without focusing the close button.
// It also posts the host page into that iframe. It does not read the session cookie.
(function () {
  if (window.__recordingStudioAgentsLauncher) return
  window.__recordingStudioAgentsLauncher = true

  var launcherId = "recording_studio_agents_launcher"
  var reopen = false

  function launcher() {
    return document.getElementById(launcherId)
  }

  function part(name) {
    var node = launcher()
    if (!node) return null
    return node.querySelector("[data-flat-pack--floating-frame-target='" + name + "']")
  }

  function panelOpen() {
    var button = part("trigger")
    return button && button.getAttribute("aria-expanded") === "true"
  }

  function stimulus(element, identifier) {
    var app = window.Stimulus
    if (!app || !element || typeof app.getControllerForElementAndIdentifier !== "function") return null
    return app.getControllerForElementAndIdentifier(element, identifier)
  }

  function frame() {
    var node = launcher()
    if (!node) return null
    return node.querySelector("iframe")
  }

  function postContext() {
    var api = window.RecordingStudioAgentsPageContext
    var iframe = frame()
    if (!api || !iframe || !iframe.contentWindow) return
    api.deliver(iframe.contentWindow, window.location.origin, api.readHostPage())
  }

  function watchFrame() {
    var iframe = frame()
    if (!iframe || iframe.dataset.recordingStudioAgentsContext === "true") return
    iframe.dataset.recordingStudioAgentsContext = "true"
    iframe.addEventListener("load", postContext)
  }

  window.addEventListener("click", function (event) {
    var button = part("trigger")
    if (button && button.contains(event.target)) postContext()
    if (!panelOpen()) return
    var node = launcher()
    if (node.contains(event.target)) return
    var link = event.target.closest && event.target.closest("a[href]")
    if (!link || link.dataset.turbo === "false") return
    if (link.target && link.target !== "_self") return
    reopen = true
  }, true)

  document.addEventListener("turbo:before-visit", function () {
    if (panelOpen()) reopen = true
  })

  document.addEventListener("DOMContentLoaded", function () {
    watchFrame()
    postContext()
  })

  document.addEventListener("turbo:load", function () {
    watchFrame()
    postContext()
    if (!reopen) return
    var button = part("trigger")
    var sheet = part("panel")
    var node = launcher()
    if (!button || !sheet || !node) return
    reopen = false

    var floating = stimulus(node, "flat-pack--floating-frame")
    var popover = stimulus(sheet, "flat-pack--popover")
    if (floating) floating.open = true

    if (popover && typeof popover.open === "function") {
      if (!popover.isOpen) popover.open()
      return
    }

    if (button.getAttribute("aria-expanded") !== "true") button.click()
  })
})()
