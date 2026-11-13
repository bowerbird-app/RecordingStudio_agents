// Page facts for the chat popup. The host posts data. The popup keeps the
// latest message from its parent and sends that data on the next chat request.
// Limits match RecordingStudioAgents::ChatKit::PageContext.
(function (root) {
  var TYPE = "recording-studio-agents:page-context"
  var LIMITS = { url: 2048, title: 300, selection: 2000, metadata: 2048 }
  var UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
  var latest = null

  function clip(value, limit) {
    if (typeof value !== "string") return ""
    return value.trim().slice(0, limit)
  }

  function pageId(value) {
    if (typeof value !== "string") return null
    var text = value.trim()
    return UUID.test(text) ? text : null
  }

  function sanitizeMetadata(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) return null
    if (Object.prototype.hasOwnProperty.call(value, "instructions")) return null
    var json = ""
    try {
      json = JSON.stringify(value)
    } catch (error) {
      return null
    }
    if (json.length > LIMITS.metadata) return null
    return value
  }

  function recordingId(doc) {
    if (!doc || typeof doc.querySelector !== "function") return ""
    var node = doc.querySelector("[data-recording-studio-agents-page-recording-id]")
    var fromNode = node && node.getAttribute && node.getAttribute("data-recording-studio-agents-page-recording-id")
    if (fromNode) return fromNode
    var meta = doc.querySelector("meta[name='recording-studio-agents-page-recording-id']")
    return (meta && meta.getAttribute && meta.getAttribute("content")) || ""
  }

  function readMetadata(doc) {
    if (!doc || typeof doc.querySelector !== "function") return null
    var node = doc.querySelector("[data-recording-studio-agents-page-metadata]")
    if (!node || !node.getAttribute) return null
    var raw = node.getAttribute("data-recording-studio-agents-page-metadata") || ""
    if (raw.length > LIMITS.metadata) return null
    try {
      return sanitizeMetadata(JSON.parse(raw))
    } catch (error) {
      return null
    }
  }

  function selectedText(selection) {
    if (selection != null) return selection
    if (typeof window === "undefined" || typeof window.getSelection !== "function") return ""
    return String(window.getSelection())
  }

  function readHostPage(doc, href, selection) {
    var page = doc || (typeof document === "undefined" ? null : document)
    var address = href || (typeof window !== "undefined" && window.location ? window.location.href : "")
    return {
      type: TYPE,
      url: clip(address, LIMITS.url),
      title: clip(page && page.title, LIMITS.title),
      page_recording_id: pageId(recordingId(page)),
      selection: clip(selectedText(selection), LIMITS.selection),
      metadata: readMetadata(page)
    }
  }

  function acceptMessage(event, origin, parent) {
    if (!event || event.origin !== origin) return null
    if (!parent || event.source !== parent) return null
    var data = event.data
    if (!data || data.type !== TYPE || typeof data !== "object") return null
    if (Object.prototype.hasOwnProperty.call(data, "instructions")) return null
    if (data.metadata && Object.prototype.hasOwnProperty.call(data.metadata, "instructions")) return null
    return {
      url: clip(data.url, LIMITS.url),
      title: clip(data.title, LIMITS.title),
      page_recording_id: pageId(data.page_recording_id),
      selection: clip(data.selection, LIMITS.selection),
      metadata: sanitizeMetadata(data.metadata)
    }
  }

  function deliver(frameWindow, origin, context) {
    if (!frameWindow || typeof frameWindow.postMessage !== "function") return
    if (typeof origin !== "string" || origin === "" || origin === "*") return
    frameWindow.postMessage(context, origin)
  }

  function showPage(context) {
    if (typeof document === "undefined") return
    var node = document.getElementById("recording-studio-agents-page-context")
    if (!node) return
    var label = context.title || context.url || ""
    node.hidden = label.length === 0
    node.textContent = label
  }

  function remember(event) {
    var accepted = acceptMessage(event, window.location.origin, window.parent)
    if (!accepted) return
    latest = accepted
    showPage(accepted)
  }

  root.RecordingStudioAgentsPageContext = {
    type: TYPE,
    limits: LIMITS,
    header: "X-Recording-Studio-Agents-Page",
    readHostPage: readHostPage,
    acceptMessage: acceptMessage,
    deliver: deliver,
    current: function () { return latest }
  }

  if (typeof document !== "undefined" && document.documentElement &&
      document.documentElement.getAttribute("data-recording-studio-agents-popup") === "true") {
    window.addEventListener("message", remember)
  }
})(typeof window === "undefined" ? globalThis : window)
