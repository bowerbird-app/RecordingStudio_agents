function csrfHeaders(headers) {
  const csrf = document.querySelector("meta[name='csrf-token']")?.content
  const next = new Headers(headers || {})
  if (csrf) next.set("X-CSRF-Token", csrf)
  next.set("Content-Type", "application/json")
  const pageContext = window.RecordingStudioAgentsPageContext
  const current = pageContext && pageContext.current()
  if (current) next.set(pageContext.header, JSON.stringify(current))
  return next
}

function mergeChatkitOptions(base, extra) {
  if (!extra || typeof extra !== "object" || Array.isArray(extra)) return base
  const merged = (base && typeof base === "object" && !Array.isArray(base)) ? { ...base } : {}
  Object.keys(extra).forEach((key) => {
    const next = extra[key]
    const current = merged[key]
    const bothObjects = next && current && typeof next === "object" && typeof current === "object" && !Array.isArray(next) && !Array.isArray(current)
    merged[key] = bothObjects ? mergeChatkitOptions(current, next) : next
  })
  return merged
}

function mountChatkit(frame) {
  const hostOptions = frame.dataset.options ? JSON.parse(frame.dataset.options) : {}

  customElements.whenDefined("openai-chatkit").then(() => {
    const chatOptions = mergeChatkitOptions({}, hostOptions)
    chatOptions.api = {
      url: frame.dataset.endpoint,
      domainKey: frame.dataset.domainKey,
      fetch: (url, requestOptions) => fetch(url, {
        ...requestOptions,
        headers: csrfHeaders(requestOptions && requestOptions.headers),
        credentials: "same-origin"
      })
    }
    frame.setOptions(chatOptions)
  })
}

document.querySelectorAll("[data-recording-studio-agents-chatkit]").forEach(mountChatkit)
