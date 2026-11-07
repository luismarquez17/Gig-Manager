import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "panel", "messages", "input", "micBtn", "micIcon", "micStatus",
    "badge", "form", "sendBtn"
  ]

  connect() {
    this.history = []
    this.isListening = false
    this.initSpeechRecognition()
  }

  togglePanel() {
    if (!this.hasPanelTarget) return
    const isHidden = this.panelTarget.classList.contains("d-none") || this.panelTarget.style.display === "none"
    if (isHidden) {
      this.openPanel()
    } else {
      this.closePanel()
    }
  }

  openPanel() {
    this.panelTarget.classList.remove("d-none")
    this.panelTarget.style.display = "flex"
    setTimeout(() => {
      if (this.hasInputTarget) this.inputTarget.focus()
      this.scrollToBottom()
    }, 100)
  }

  closePanel() {
    this.panelTarget.classList.add("d-none")
    this.panelTarget.style.display = "none"
    if (this.isListening) {
      this.stopListening()
    }
  }

  // --- RECONOCIMIENTO DE VOZ (WEB SPEECH API) ---
  initSpeechRecognition() {
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition
    if (!SpeechRecognition) {
      this.speechSupported = false
      if (this.hasMicBtnTarget) {
        this.micBtnTarget.title = "Micrófono no soportado en este navegador. Usa el teclado."
      }
      return
    }

    this.speechSupported = true
    this.recognition = new SpeechRecognition()
    this.recognition.lang = "es-ES"
    this.recognition.interimResults = true
    this.recognition.maxAlternatives = 1

    this.recognition.onstart = () => {
      this.isListening = true
      this.updateMicUI(true)
    }

    this.recognition.onresult = (event) => {
      const transcript = Array.from(event.results)
        .map(result => result[0].transcript)
        .join("")

      if (this.hasInputTarget) {
        this.inputTarget.value = transcript
      }
    }

    this.recognition.onerror = (event) => {
      console.warn("[GigAI SpeechRecognition] Error:", event.error)
      this.stopListening()
    }

    this.recognition.onend = () => {
      this.isListening = false
      this.updateMicUI(false)
      // Si capturó texto completo, enviar automáticamente tras pequeña pausa
      if (this.hasInputTarget && this.inputTarget.value.trim().length > 3) {
        this.sendMessage()
      }
    }
  }

  toggleMic(event) {
    if (event) event.preventDefault()
    if (!this.speechSupported) {
      alert("El reconocimiento de voz por navegador no está habilitado en este dispositivo. Puedes escribir tu orden directamente.")
      return
    }

    if (this.isListening) {
      this.stopListening()
    } else {
      this.startListening()
    }
  }

  startListening() {
    if (!this.recognition) return
    try {
      if (this.hasInputTarget) this.inputTarget.value = ""
      this.recognition.start()
    } catch (e) {
      console.warn("Could not start recognition:", e)
    }
  }

  stopListening() {
    if (!this.recognition) return
    try {
      this.recognition.stop()
    } catch (e) {}
    this.isListening = false
    this.updateMicUI(false)
  }

  updateMicUI(listening) {
    if (!this.hasMicBtnTarget) return
    if (listening) {
      this.micBtnTarget.classList.add("btn-danger", "pulse-mic")
      this.micBtnTarget.classList.remove("btn-light", "btn-secondary")
      if (this.hasMicStatusTarget) {
        this.micStatusTarget.textContent = "🎙️ Escuchando... habla ahora"
        this.micStatusTarget.style.display = "block"
      }
    } else {
      this.micBtnTarget.classList.remove("btn-danger", "pulse-mic")
      this.micBtnTarget.classList.add("btn-light")
      if (this.hasMicStatusTarget) {
        this.micStatusTarget.style.display = "none"
      }
    }
  }

  // --- ENVÍO DE MENSAJES Y CHAT ---
  sendPrompt(event) {
    if (event) event.preventDefault()
    this.sendMessage()
  }

  handleKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.sendMessage()
    }
  }

  quickPrompt(event) {
    const text = event.currentTarget.dataset.prompt
    if (!text) return
    if (this.hasInputTarget) {
      this.inputTarget.value = text
    }
    this.sendMessage()
  }

  async sendMessage() {
    if (!this.hasInputTarget) return
    const text = this.inputTarget.value.trim()
    if (!text) return

    // Limpiar input y agregar mensaje del usuario en pantalla
    this.inputTarget.value = ""
    this.appendMessage("user", text)
    this.scrollToBottom()

    // Mostrar indicador de carga
    const loadingId = this.showLoading()

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
      const response = await fetch("/ai_copilot/message", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        body: JSON.stringify({
          message: text,
          history: this.history
        })
      })

      const data = await response.json()
      this.removeLoading(loadingId)

      // Guardar en historial
      this.history.push({ role: "user", content: text })
      if (data.reply) {
        this.history.push({ role: "model", content: data.reply })
        this.appendMessage("model", data.reply, data.cards)
      }

      // Si se autorizó o rechazó un pago y estamos en la vista de notificaciones o pagos, refrescar suavemente
      if (data.actions_taken && data.actions_taken.some(a => ['approve_payment', 'reject_payment'].includes(a.tool))) {
        const path = window.location.pathname
        if (path.includes("/notifications") || path.includes("/employee_payments") || path.includes("/caja")) {
          setTimeout(() => { window.location.reload() }, 1800)
        }
      }
    } catch (error) {
      this.removeLoading(loadingId)
      this.appendMessage("model", "⚠️ Ocurrió un error al contactar al Copiloto. Por favor verifica tu conexión o configuración de Gemini.")
      console.error("[GigAI Copilot Error]", error)
    }

    this.scrollToBottom()
  }

  // --- DIAGNÓSTICO RÁPIDO & ACCIÓN DE 1 CLIC ---
  async runDiagnostic(event) {
    if (event) event.preventDefault()
    this.openPanel()
    this.appendMessage("user", "🔍 Diagnóstico de mi Caja y Operaciones")
    const loadingId = this.showLoading("Analizando caja, cobros y shows...")

    try {
      const response = await fetch("/ai_copilot/diagnostic", {
        headers: { "Accept": "application/json" }
      })
      const data = await response.json()
      this.removeLoading(loadingId)

      let replyHtml = `💰 <strong>Saldo actual en Caja:</strong> $${data.cash_balance.toFixed(2)} USD<br><br>`
      if (data.healthy) {
        replyHtml += `✅ <strong>¡Excelente!</strong> Tu caja está al día y no tienes alertas pendientes.`
      } else {
        replyHtml += `<strong>Alertas detectadas (${data.diagnostic_items.length}):</strong><br>`
        data.diagnostic_items.forEach(item => {
          replyHtml += `• <strong>${item.title}:</strong> ${item.description}<br>`
        })
      }

      this.appendMessage("model", replyHtml, null, data.diagnostic_items)
    } catch (e) {
      this.removeLoading(loadingId)
      this.appendMessage("model", "No se pudo completar el diagnóstico en este momento.")
    }
    this.scrollToBottom()
  }

  async executeQuickAction(event) {
    const key = event.currentTarget.dataset.actionKey
    if (!key) return

    event.currentTarget.disabled = true
    event.currentTarget.innerHTML = "⏳ Ejecutando..."

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
      const response = await fetch("/ai_copilot/quick_action", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        body: JSON.stringify({ action_key: key })
      })

      const data = await response.json()
      if (data.success) {
        this.appendMessage("model", data.message)
        // Notificar visualmente si estamos en la página de caja
        if (window.location.pathname.includes("/caja")) {
          setTimeout(() => { window.location.reload() }, 1800)
        }
      } else {
        alert(data.message || "No se pudo realizar la acción.")
      }
    } catch (e) {
      alert("Error de conexión al ejecutar la acción.")
    }
    this.scrollToBottom()
  }

  // --- RENDERIZADO VISUAL ---
  appendMessage(role, text, cards = [], diagnosticItems = []) {
    if (!this.hasMessagesTarget) return

    const msgDiv = document.createElement("div")
    msgDiv.style.marginBottom = "14px"
    msgDiv.style.display = "flex"
    msgDiv.style.flexDirection = "column"
    msgDiv.style.alignItems = role === "user" ? "flex-end" : "flex-start"

    const bubble = document.createElement("div")
    bubble.style.maxWidth = "88%"
    bubble.style.padding = "10px 14px"
    bubble.style.borderRadius = role === "user" ? "16px 16px 2px 16px" : "16px 16px 16px 2px"
    bubble.style.fontSize = "0.9rem"
    bubble.style.lineHeight = "1.4"
    bubble.style.boxShadow = "0 2px 8px rgba(0,0,0,0.06)"

    if (role === "user") {
      bubble.style.background = "linear-gradient(135deg, #2563eb, #1d4ed8)"
      bubble.style.color = "#ffffff"
      bubble.textContent = text
    } else {
      bubble.style.background = "var(--card-bg, #ffffff)"
      bubble.style.color = "var(--text-color, #1e293b)"
      bubble.style.border = "1px solid var(--border-color, #e2e8f0)"
      // Permitir formato básico
      bubble.innerHTML = this.formatMarkdown(text)
    }

    msgDiv.appendChild(bubble)

    // Renderizar tarjetas interactivas de acciones ejecutadas
    if (cards && cards.length > 0) {
      cards.forEach(card => {
        const cardEl = this.buildCardElement(card)
        msgDiv.appendChild(cardEl)
      })
    }

    // Renderizar botones de acción para diagnóstico
    if (diagnosticItems && diagnosticItems.length > 0) {
      diagnosticItems.forEach(item => {
        if (item.action_key || item.prompt) {
          const btn = document.createElement("button")
          btn.className = "btn btn-sm mt-2"
          btn.style.background = item.type === 'pending_worker_approval' 
            ? "linear-gradient(135deg, #10b981, #059669)" 
            : "linear-gradient(135deg, #8b5cf6, #6366f1)"
          btn.style.color = "#fff"
          btn.style.fontWeight = "700"
          btn.style.borderRadius = "8px"
          btn.style.padding = "6px 12px"
          btn.style.border = "none"
          btn.style.fontSize = "0.78rem"

          if (item.prompt) {
            btn.dataset.action = "click->ai-copilot#quickPrompt"
            btn.dataset.prompt = item.prompt
          } else {
            btn.dataset.action = "click->ai-copilot#executeQuickAction"
            btn.dataset.actionKey = item.action_key
          }

          btn.innerHTML = `${item.action_label}`
          msgDiv.appendChild(btn)
        }
      })
    }

    this.messagesTarget.appendChild(msgDiv)
  }

  buildCardElement(card) {
    const cardEl = document.createElement("div")
    cardEl.style.width = "88%"
    cardEl.style.marginTop = "8px"
    cardEl.style.padding = "10px 12px"
    cardEl.style.borderRadius = "10px"

    if (card.type === 'payment_approved') {
      cardEl.style.background = "rgba(16, 185, 129, 0.08)"
      cardEl.style.border = "1px solid rgba(16, 185, 129, 0.3)"
    } else if (card.type === 'payment_rejected') {
      cardEl.style.background = "rgba(239, 68, 68, 0.08)"
      cardEl.style.border = "1px solid rgba(239, 68, 68, 0.3)"
    } else {
      cardEl.style.background = "rgba(37, 99, 235, 0.06)"
      cardEl.style.border = "1px solid rgba(37, 99, 235, 0.2)"
    }

    cardEl.style.fontSize = "0.85rem"

    let detailsHtml = card.details ? `<div style="color: #64748b; font-size: 0.78rem; margin-top: 3px;">${card.details}</div>` : ""
    let urlHtml = card.url ? `<a href="${card.url}" style="display: inline-block; margin-top: 6px; font-weight: 700; color: #2563eb; text-decoration: underline;">Ver detalle &rarr;</a>` : ""

    cardEl.innerHTML = `
      <div style="display: flex; justify-content: space-between; align-items: center;">
        <strong style="color: #1e293b;">${card.title}</strong>
        <span style="font-weight: 800; color: #16a34a;">${card.amount || ''}</span>
      </div>
      ${detailsHtml}
      ${urlHtml}
    `
    return cardEl
  }

  showLoading(text = "Pensando...") {
    const id = "loading-" + Date.now()
    const loadingDiv = document.createElement("div")
    loadingDiv.id = id
    loadingDiv.style.marginBottom = "14px"
    loadingDiv.style.display = "flex"
    loadingDiv.style.alignItems = "center"
    loadingDiv.style.gap = "8px"
    loadingDiv.style.color = "#64748b"
    loadingDiv.style.fontSize = "0.82rem"
    loadingDiv.innerHTML = `
      <div class="spinner-border spinner-border-sm text-primary" role="status"></div>
      <span>${text}</span>
    `
    this.messagesTarget.appendChild(loadingDiv)
    this.scrollToBottom()
    return id
  }

  removeLoading(id) {
    const el = document.getElementById(id)
    if (el) el.remove()
  }

  formatMarkdown(text) {
    if (!text) return ""
    return text
      .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.*?)\*/g, '<em>$1</em>')
      .replace(/\n/g, '<br>')
  }

  scrollToBottom() {
    if (!this.hasMessagesTarget) return
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }
}
