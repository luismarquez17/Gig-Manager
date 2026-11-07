import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "panel", "messages", "input", "micBtn", "micIcon", "micStatus",
    "badge", "form", "sendBtn", "voiceToggleBtn", "voiceToggleIcon", "speakingBar",
    "voiceSettingsBtn", "voiceSettingsPanel", "voiceSelect"
  ]

  connect() {
    this.history = []
    this.isListening = false
    this.isSpeaking = false
    this.isSending = false
    this.silenceTimer = null
    this.lastInputWasVoice = false
    this.voiceOutputEnabled = localStorage.getItem("gigai_voice_output") !== "false"
    this.initSpeechRecognition()
    this.initSpeechSynthesis()
    this.updateVoiceToggleUI()
  }

  disconnect() {
    this.clearSilenceTimer()
    this.stopListening()
    this.stopSpeaking()
    document.body.classList.remove("gigai-panel-open")
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
    this.element.classList.add("panel-open")
    if (window.innerWidth <= 768) {
      document.body.classList.add("gigai-panel-open")
    }
    this.panelTarget.classList.remove("d-none")
    this.panelTarget.style.display = "flex"
    this.panelTarget.scrollTop = 0
    setTimeout(() => {
      if (this.hasInputTarget && window.innerWidth > 768) {
        this.inputTarget.focus()
      }
      this.scrollToBottom()
    }, 100)
  }

  closePanel() {
    this.clearSilenceTimer()
    this.element.classList.remove("panel-open")
    document.body.classList.remove("gigai-panel-open")
    this.panelTarget.classList.add("d-none")
    this.panelTarget.style.display = "none"
    if (this.isListening) {
      this.stopListening()
    }
    this.stopSpeaking()
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
    this.recognition.continuous = true
    this.recognition.maxAlternatives = 1

    this.recognition.onstart = () => {
      this.stopSpeaking() // Silenciar a la IA de inmediato si el usuario presiona el micrófono
      this.isListening = true
      this.clearSilenceTimer()
      this.updateMicUI(true, "🎙️ Escuchando... habla con confianza")
    }

    this.recognition.onresult = (event) => {
      let transcript = ""
      for (let i = 0; i < event.results.length; i++) {
        transcript += event.results[i][0].transcript
      }
      transcript = transcript.trim()

      if (this.hasInputTarget && transcript) {
        this.inputTarget.value = transcript
      }

      if (transcript) {
        this.updateMicStatusText(`🎙️ "${transcript}" (se enviará en 3s de silencio...)`)
        // Reiniciar el temporizador de silencio: si pasan 3.5 segundos sin hablar, enviar automáticamente
        this.resetSilenceTimer()
      }
    }

    this.recognition.onerror = (event) => {
      console.warn("[GigAI SpeechRecognition] Error:", event.error)
      if (event.error === "no-speech") {
        return // Pausa momentánea, no cortar abruptamente
      }
      this.clearSilenceTimer()
      this.stopListening()
    }

    this.recognition.onend = () => {
      this.isListening = false
      this.updateMicUI(false)
      this.clearSilenceTimer()

      // Si el navegador terminó la sesión por su cuenta y hay texto no enviado
      if (!this.isSending && this.lastInputWasVoice && this.hasInputTarget) {
        const text = this.inputTarget.value.trim()
        if (text.length > 0) {
          this.sendMessage()
        }
      }
    }
  }

  resetSilenceTimer() {
    this.clearSilenceTimer()
    this.silenceTimer = setTimeout(() => {
      if (this.isListening && !this.isSending) {
        const text = this.hasInputTarget ? this.inputTarget.value.trim() : ""
        if (text.length > 0) {
          this.lastInputWasVoice = true
          this.stopListening()
          this.sendMessage()
        }
      }
    }, 3500)
  }

  clearSilenceTimer() {
    if (this.silenceTimer) {
      clearTimeout(this.silenceTimer)
      this.silenceTimer = null
    }
  }

  toggleMic(event) {
    if (event) {
      event.preventDefault()
      event.stopPropagation()
    }
    if (!this.speechSupported) {
      alert("El reconocimiento de voz por navegador no está habilitado en este dispositivo. Puedes escribir tu orden directamente.")
      return
    }

    if (this.isListening) {
      this.clearSilenceTimer()
      const hasText = this.hasInputTarget && this.inputTarget.value.trim().length > 0
      this.stopListening()
      if (hasText && !this.isSending) {
        this.lastInputWasVoice = true
        this.sendMessage()
      }
    } else {
      this.startListening()
    }
  }

  startListening() {
    if (!this.recognition) return
    this.clearSilenceTimer()
    this.stopSpeaking()

    // Limpiar input previo para que la nueva frase empiece de cero y no se haga cada vez más larga
    if (this.hasInputTarget) {
      this.inputTarget.value = ""
    }

    try {
      this.recognition.start()
    } catch (e) {
      // Si la instancia ya estaba corriendo por un error de estado previo, detener y reiniciar
      try {
        this.recognition.stop()
        setTimeout(() => {
          try { this.recognition.start() } catch (err) {}
        }, 150)
      } catch (err) {}
    }
  }

  stopListening() {
    this.clearSilenceTimer()
    if (this.recognition) {
      try {
        this.recognition.stop()
      } catch (e) {}
    }
    this.isListening = false
    this.updateMicUI(false)
  }

  updateMicUI(listening, customText = null) {
    if (!this.hasMicBtnTarget) return
    if (listening) {
      this.micBtnTarget.classList.add("btn-danger", "pulse-mic")
      this.micBtnTarget.classList.remove("btn-light", "btn-secondary")
      if (this.hasMicStatusTarget) {
        this.micStatusTarget.style.display = "flex"
      }
      this.updateMicStatusText(customText || "🎙️ Escuchando... habla con confianza")
    } else {
      this.micBtnTarget.classList.remove("btn-danger", "pulse-mic")
      this.micBtnTarget.classList.add("btn-light")
      if (this.hasMicStatusTarget) {
        this.micStatusTarget.style.display = "none"
      }
      this.updateMicStatusText("🎙️ Escuchando tu voz... habla con confianza")
    }
  }

  updateMicStatusText(text) {
    if (!this.hasMicStatusTarget) return
    const textEl = this.micStatusTarget.querySelector(".gigai-mic-recording-text")
    if (textEl) {
      textEl.textContent = text
    } else {
      this.micStatusTarget.textContent = text
    }
  }

  // --- ENVÍO DE MENSAJES Y CHAT ---
  sendPrompt(event) {
    if (event) {
      event.preventDefault()
      event.stopPropagation()
    }
    this.sendMessage()
  }

  handleKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      event.stopPropagation()
      this.sendMessage()
    }
  }

  quickPrompt(event) {
    if (event) {
      event.preventDefault()
      event.stopPropagation()
    }
    const text = event.currentTarget.dataset.prompt
    if (!text) return
    this.clearSilenceTimer()
    if (this.isListening) {
      this.stopListening()
    }
    if (this.hasInputTarget) {
      this.inputTarget.value = text
    }
    this.sendMessage()
  }

  async sendMessage() {
    // 🛡️ Mutex de seguridad: Si ya hay un envío en curso, ignorar llamadas concurrentes para evitar mensajes dobles
    if (this.isSending) return
    if (!this.hasInputTarget) return

    const text = this.inputTarget.value.trim()
    if (!text) return

    this.isSending = true
    this.clearSilenceTimer()

    // Si el micrófono seguía encendido, detenerlo de inmediato
    if (this.isListening) {
      this.stopListening()
    }

    // Deshabilitar botón enviar temporalmente para feedback visual y prevenir doble clic
    if (this.hasSendBtnTarget) {
      this.sendBtnTarget.disabled = true
      this.sendBtnTarget.style.opacity = "0.55"
      this.sendBtnTarget.style.pointerEvents = "none"
    }

    const wasVoice = this.lastInputWasVoice
    this.lastInputWasVoice = false
    this.stopSpeaking()

    // Limpiar input de inmediato para evitar que cualquier evento posterior reenvíe el texto
    this.inputTarget.value = ""

    // Agregar mensaje del usuario en pantalla
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
        const { bubble } = this.appendMessage("model", data.reply, data.cards)

        // Reproducir por voz si la orden vino por micrófono o la voz está activada
        if (wasVoice || this.voiceOutputEnabled) {
          this.speakText(data.reply, bubble)
        }
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
    } finally {
      this.isSending = false
      if (this.hasSendBtnTarget) {
        this.sendBtnTarget.disabled = false
        this.sendBtnTarget.style.opacity = "1"
        this.sendBtnTarget.style.pointerEvents = "auto"
      }
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

      let reply = `💰 **Saldo actual en Caja:** $${data.cash_balance.toFixed(2)} USD\n\n`
      if (data.healthy) {
        reply += `✅ **¡Excelente!** Tu caja está al día y no tienes alertas pendientes.`
      } else {
        reply += `**Alertas detectadas (${data.diagnostic_items.length}):**\n`
        data.diagnostic_items.forEach(item => {
          reply += `• **${item.title}:** ${item.description}\n`
        })
      }

      this.appendMessage("model", reply, null, data.diagnostic_items)
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
    if (!this.hasMessagesTarget) return { msgDiv: null, bubble: null }

    const msgDiv = document.createElement("div")
    msgDiv.style.marginBottom = "14px"
    msgDiv.style.display = "flex"
    msgDiv.style.flexDirection = "column"
    msgDiv.style.alignItems = role === "user" ? "flex-end" : "flex-start"
    msgDiv.style.width = "100%"

    let bubble = null

    if (role === "user") {
      bubble = document.createElement("div")
      bubble.className = "gigai-bubble-user"
      bubble.textContent = text
      msgDiv.appendChild(bubble)
      this.messagesTarget.appendChild(msgDiv)
      this.scrollToBottom()
    } else {
      const row = document.createElement("div")
      row.className = "gigai-bubble-row-model"

      const avatar = document.createElement("div")
      avatar.className = "gigai-bubble-avatar-mini"
      avatar.textContent = "🤖"
      row.appendChild(avatar)

      bubble = document.createElement("div")
      bubble.className = "gigai-bubble-model"

      const textContainer = document.createElement("div")
      textContainer.className = "gigai-bubble-text-content"
      // Renderizado inmediato y normal en pantalla
      textContainer.innerHTML = this.formatMarkdown(text)
      bubble.appendChild(textContainer)

      // Botón para reproducir audio del mensaje
      const actionsBar = document.createElement("div")
      actionsBar.className = "gigai-bubble-footer-actions"
      const speakBtn = document.createElement("button")
      speakBtn.type = "button"
      speakBtn.className = "gigai-bubble-action-btn"
      speakBtn.title = "Escuchar respuesta por voz"
      speakBtn.innerHTML = "<span>🔊</span> <span>Escuchar</span>"
      speakBtn.addEventListener("click", () => this.speakText(text, bubble))
      actionsBar.appendChild(speakBtn)
      bubble.appendChild(actionsBar)

      row.appendChild(bubble)
      msgDiv.appendChild(row)

      // Contenedor para tarjetas interactivas
      if (cards && Array.isArray(cards) && cards.length > 0) {
        const cardsContainer = document.createElement("div")
        cardsContainer.className = "gigai-cards-container"
        cards.forEach(card => {
          if (card) {
            const cardEl = this.buildCardElement(card)
            cardsContainer.appendChild(cardEl)
          }
        })
        msgDiv.appendChild(cardsContainer)
      }

      this.messagesTarget.appendChild(msgDiv)
      this.scrollToBottom()
    }

    // Renderizar botones de acción para diagnóstico si existen
    if (diagnosticItems && diagnosticItems.length > 0) {
      diagnosticItems.forEach(item => {
        if (item && (item.action_key || item.prompt)) {
          const btn = document.createElement("button")
          btn.className = "btn btn-sm mt-2"
          btn.style.marginLeft = "36px"
          btn.style.background = item.type === 'pending_worker_approval' 
            ? "linear-gradient(135deg, #10b981, #059669)" 
            : "linear-gradient(135deg, #8b5cf6, #6366f1)"
          btn.style.color = "#fff"
          btn.style.fontWeight = "700"
          btn.style.borderRadius = "999px"
          btn.style.padding = "6px 14px"
          btn.style.border = "none"
          btn.style.fontSize = "0.78rem"
          btn.style.boxShadow = "0 2px 8px rgba(0,0,0,0.1)"

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

    this.scrollToBottom()
    return { msgDiv, bubble }
  }

  buildCardElement(card) {
    if (!card) return document.createElement("div")
    const cardEl = document.createElement("div")
    cardEl.style.width = "calc(100% - 36px)"
    cardEl.style.maxWidth = "400px"
    cardEl.style.marginLeft = "36px"
    cardEl.style.boxSizing = "border-box"
    cardEl.style.marginTop = "8px"
    cardEl.style.padding = "12px 14px"
    cardEl.style.borderRadius = "14px"
    cardEl.style.wordBreak = "break-word"

    let amountColor = "#16a34a"

    if (card.type === 'payment_approved') {
      cardEl.style.background = "rgba(16, 185, 129, 0.08)"
      cardEl.style.border = "1.5px solid rgba(16, 185, 129, 0.3)"
      amountColor = "#16a34a"
    } else if (card.type === 'payment_rejected') {
      cardEl.style.background = "rgba(239, 68, 68, 0.08)"
      cardEl.style.border = "1.5px solid rgba(239, 68, 68, 0.3)"
      amountColor = "#dc2626"
    } else if (card.type === 'comparative_report') {
      cardEl.style.background = "rgba(99, 102, 241, 0.08)"
      cardEl.style.border = "1.5px solid rgba(99, 102, 241, 0.35)"
      amountColor = "#4f46e5"
    } else if (card.type === 'inventory_status') {
      cardEl.style.background = "rgba(14, 165, 233, 0.08)"
      cardEl.style.border = "1.5px solid rgba(14, 165, 233, 0.3)"
      amountColor = "#0284c7"
    } else if (card.type === 'workshop_status') {
      cardEl.style.background = "rgba(245, 158, 11, 0.08)"
      cardEl.style.border = "1.5px solid rgba(245, 158, 11, 0.35)"
      amountColor = "#d97706"
    } else if (card.type === 'packages_upsells') {
      cardEl.style.background = "rgba(168, 85, 247, 0.08)"
      cardEl.style.border = "1.5px solid rgba(168, 85, 247, 0.35)"
      amountColor = "#9333ea"
    } else {
      cardEl.style.background = "rgba(37, 99, 235, 0.06)"
      cardEl.style.border = "1.5px solid rgba(37, 99, 235, 0.2)"
      amountColor = "#2563eb"
    }

    cardEl.style.fontSize = "0.85rem"

    let detailsHtml = card.details ? `<div style="color: #64748b; font-size: 0.78rem; margin-top: 4px;">${card.details}</div>` : ""
    let urlHtml = card.url ? `<a href="${card.url}" style="display: inline-block; margin-top: 8px; font-weight: 700; color: #2563eb; text-decoration: underline;">Ver detalle &rarr;</a>` : ""

    cardEl.innerHTML = `
      <div style="display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 4px;">
        <strong style="color: #1e293b; min-width: 0; word-break: break-word;">${card.title || 'Detalle'}</strong>
        <span style="font-weight: 800; color: ${amountColor}; flex-shrink: 0;">${card.amount || ''}</span>
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
    loadingDiv.innerHTML = `
      <div class="gigai-bubble-avatar-mini">🤖</div>
      <div class="gigai-typing-loader">
        <span class="gigai-typing-dot"></span>
        <span class="gigai-typing-dot"></span>
        <span class="gigai-typing-dot"></span>
      </div>
      <span style="font-size: 0.76rem; color: #64748b; font-weight: 600;">${text}</span>
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

    // 1. Escapar HTML para evitar etiquetas rotas o que se coman texto
    let html = text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")

    // 2. Encabezados Markdown
    html = html.replace(/^###\s+(.*?)$/gm, '<div style="font-weight: 800; font-size: 0.96rem; margin: 8px 0 4px 0; color: inherit;">$1</div>')
    html = html.replace(/^##\s+(.*?)$/gm, '<div style="font-weight: 800; font-size: 1.02rem; margin: 10px 0 4px 0; color: inherit;">$1</div>')
    html = html.replace(/^#\s+(.*?)$/gm, '<div style="font-weight: 800; font-size: 1.08rem; margin: 12px 0 6px 0; color: inherit;">$1</div>')

    // 3. Negrita y Cursiva
    html = html.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
    html = html.replace(/\*(.*?)\*/g, '<em>$1</em>')

    // 4. Bloques de código en línea
    html = html.replace(/`([^`]+)`/g, '<code style="background: rgba(0,0,0,0.06); padding: 1px 4px; border-radius: 4px; font-size: 0.88em; font-family: monospace;">$1</code>')

    // 5. Viñetas limpias
    html = html.replace(/^[•\-\*]\s+(.*?)$/gm, '<div style="display: flex; gap: 6px; margin: 3px 0; align-items: baseline;"><span style="color: #6366f1; font-weight: 800; font-size: 0.9rem;">•</span><span>$1</span></div>')

    // 6. Saltos de línea
    html = html.replace(/\n\n+/g, '<div style="height: 6px;"></div>')
    html = html.replace(/\n/g, '<br>')

    return html
  }

  scrollToBottom() {
    if (this.hasPanelTarget) {
      this.panelTarget.scrollTop = 0
    }
    if (!this.hasMessagesTarget) return
    const el = this.messagesTarget
    el.scrollTop = el.scrollHeight
    requestAnimationFrame(() => {
      if (el) el.scrollTop = el.scrollHeight
      if (this.hasPanelTarget) this.panelTarget.scrollTop = 0
    })
  }

  // --- SÍNTESIS DE VOZ (TEXT-TO-SPEECH WEB SPEECH API) ---
  initSpeechSynthesis() {
    if (!("speechSynthesis" in window)) {
      this.ttsSupported = false
      if (this.hasVoiceToggleBtnTarget) {
        this.voiceToggleBtnTarget.style.display = "none"
      }
      return
    }

    this.ttsSupported = true
    this.selectedVoice = null
    this.loadVoices()

    if (window.speechSynthesis.onvoiceschanged !== undefined) {
      window.speechSynthesis.onvoiceschanged = () => this.loadVoices()
    }
  }

  loadVoices() {
    if (!("speechSynthesis" in window)) return
    const voices = window.speechSynthesis.getVoices()
    if (!voices || voices.length === 0) return

    // Buscar voces en español
    const esVoices = voices.filter(v => v.lang && v.lang.toLowerCase().startsWith("es"))

    // Poblar el menú desplegable de selección de voz
    this.populateVoiceSelect(voices, esVoices)

    // 1. Si el usuario ya eligió una voz previamente en este dispositivo, usarla
    const savedVoiceName = localStorage.getItem("gigai_selected_voice")
    if (savedVoiceName) {
      const match = voices.find(v => v.name === savedVoiceName)
      if (match) {
        this.selectedVoice = match
        if (this.hasVoiceSelectTarget) this.voiceSelectTarget.value = match.name
        return
      }
    }

    // 2. Si no hay voz guardada, elegir la voz más natural en español disponible
    const preferredNames = [
      "google español", "paulina", "mónica", "monica", "jorge", "diego", "penélope", 
      "luciana", "angélica", "carlos", "soledad", "alva", "elena", "paloma"
    ]

    let bestVoice = esVoices.find(v => 
      preferredNames.some(p => v.name.toLowerCase().includes(p))
    )

    if (!bestVoice) {
      bestVoice = esVoices.find(v => v.lang.includes("es-419") || v.lang.includes("es-MX") || v.lang.includes("es-ES") || v.lang.includes("es-US"))
    }

    if (!bestVoice && esVoices.length > 0) {
      bestVoice = esVoices[0]
    }

    if (!bestVoice && voices.length > 0) {
      bestVoice = voices[0]
    }

    this.selectedVoice = bestVoice
    if (this.selectedVoice && this.hasVoiceSelectTarget) {
      this.voiceSelectTarget.value = this.selectedVoice.name
    }
  }

  populateVoiceSelect(allVoices, esVoices) {
    if (!this.hasVoiceSelectTarget) return
    const select = this.voiceSelectTarget
    select.innerHTML = ""

    if (esVoices.length > 0) {
      const optGroupEs = document.createElement("optgroup")
      optGroupEs.label = "Voces en Español (Recomendadas)"
      esVoices.forEach(voice => {
        const opt = document.createElement("option")
        opt.value = voice.name
        opt.textContent = `${voice.name} (${voice.lang})`
        optGroupEs.appendChild(opt)
      })
      select.appendChild(optGroupEs)
    }

    const otherVoices = allVoices.filter(v => !v.lang || !v.lang.toLowerCase().startsWith("es"))
    if (otherVoices.length > 0) {
      const optGroupOther = document.createElement("optgroup")
      optGroupOther.label = "Otras Voces del Sistema"
      otherVoices.forEach(voice => {
        const opt = document.createElement("option")
        opt.value = voice.name
        opt.textContent = `${voice.name} (${voice.lang})`
        optGroupOther.appendChild(opt)
      })
      select.appendChild(optGroupOther)
    }

    if (this.selectedVoice) {
      select.value = this.selectedVoice.name
    }
  }

  onVoiceSelected(event) {
    const voiceName = event.target.value
    if (!voiceName) return
    const voices = window.speechSynthesis.getVoices()
    const voice = voices.find(v => v.name === voiceName)
    if (voice) {
      this.selectedVoice = voice
      localStorage.setItem("gigai_selected_voice", voice.name)
      this.speakText("Voz cambiada con éxito. Soy tu copiloto de Gig Manager.")
    }
  }

  testSelectedVoice(event) {
    if (event) event.preventDefault()
    if (!this.selectedVoice) return
    this.speakText("Hola, soy tu copiloto de Gig Manager. Todo el dinero entra al Fondo General y tus finanzas están al día.")
  }

  toggleVoiceSettings(event) {
    if (event) event.preventDefault()
    if (!this.hasVoiceSettingsPanelTarget) return
    const isHidden = this.voiceSettingsPanelTarget.style.display === "none"
    this.voiceSettingsPanelTarget.style.display = isHidden ? "block" : "none"
  }

  speakText(rawText, bubble = null) {
    if (!this.ttsSupported || !this.voiceOutputEnabled || !rawText) return

    // Cancelar cualquier audio anterior
    window.speechSynthesis.cancel()

    // Limpiar texto para pronunciación natural y conversacional:
    let text = rawText
      .replace(/```[\s\S]*?```/g, "")
      .replace(/`([^`]+)`/g, "$1")
      .replace(/\[([^\]]+)\]\([^\)]+\)/g, "$1")
      .replace(/[*_~#]/g, "")
      .replace(/^[•\-\*]\s+/gm, "")
      .replace(/^\s*\d+\.\s+/gm, "")
      .replace(/---/g, "")

    // Pronunciar montos de dinero naturalmente: $100.00 USD -> 100 dólares
    text = text.replace(/\$([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:USD)?/gi, (match, p1) => {
      const cleanNum = p1.replace(/,/g, "")
      return `${cleanNum} dólares`
    })

    // Quitar emojis para pronunciación limpia
    text = text.replace(/[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F600}-\u{1F64F}\u{1F680}-\u{1F6FF}]/gu, "")

    // Normalizar pausas y espacios
    text = text.replace(/\n+/g, ". ").replace(/\s{2,}/g, " ").trim()
    if (!text) return

    const utterance = new SpeechSynthesisUtterance(text)
    if (this.selectedVoice) {
      utterance.voice = this.selectedVoice
      utterance.lang = this.selectedVoice.lang || "es-ES"
    } else {
      utterance.lang = "es-ES"
    }

    utterance.rate = 1.05
    utterance.pitch = 1.0

    const highlightBubble = (active) => {
      if (bubble) {
        if (active) bubble.classList.add("gigai-bubble-speaking")
        else bubble.classList.remove("gigai-bubble-speaking")
      }
      if (!active && this.hasMessagesTarget) {
        this.messagesTarget.querySelectorAll(".gigai-bubble-speaking").forEach(b => b.classList.remove("gigai-bubble-speaking"))
      }
    }

    utterance.onstart = () => {
      this.isSpeaking = true
      this.showSpeakingBar()
      highlightBubble(true)
      this.scrollToBottom()
    }

    utterance.onend = () => {
      this.isSpeaking = false
      this.hideSpeakingBar()
      highlightBubble(false)
      this.scrollToBottom()
    }

    utterance.onerror = (e) => {
      console.warn("[GigAI SpeechSynthesis] Error:", e)
      this.isSpeaking = false
      this.hideSpeakingBar()
      highlightBubble(false)
    }

    window.speechSynthesis.speak(utterance)
  }

  stopSpeaking() {
    if ("speechSynthesis" in window) {
      window.speechSynthesis.cancel()
    }
    this.isSpeaking = false
    this.hideSpeakingBar()
    if (this.hasMessagesTarget) {
      this.messagesTarget.querySelectorAll(".gigai-bubble-speaking").forEach(b => b.classList.remove("gigai-bubble-speaking"))
    }
  }

  toggleVoiceOutput(event) {
    if (event) event.preventDefault()
    this.voiceOutputEnabled = !this.voiceOutputEnabled
    localStorage.setItem("gigai_voice_output", this.voiceOutputEnabled.toString())

    if (!this.voiceOutputEnabled && this.isSpeaking) {
      this.stopSpeaking()
    }

    this.updateVoiceToggleUI()
  }

  toggleVoiceResponse(event) {
    this.toggleVoiceOutput(event)
  }

  updateVoiceToggleUI() {
    if (!this.hasVoiceToggleBtnTarget) return
    if (this.voiceOutputEnabled) {
      this.voiceToggleBtnTarget.title = "Voz de respuesta: Activada (clic para silenciar)"
      if (this.hasVoiceToggleIconTarget) {
        this.voiceToggleIconTarget.textContent = "🔊"
      }
      this.voiceToggleBtnTarget.classList.remove("muted")
    } else {
      this.voiceToggleBtnTarget.title = "Voz de respuesta: Silenciada (clic para activar)"
      if (this.hasVoiceToggleIconTarget) {
        this.voiceToggleIconTarget.textContent = "🔇"
      }
      this.voiceToggleBtnTarget.classList.add("muted")
    }
  }

  showSpeakingBar() {
    if (this.hasSpeakingBarTarget) {
      this.speakingBarTarget.style.display = "flex"
      this.scrollToBottom()
    }
  }

  hideSpeakingBar() {
    if (this.hasSpeakingBarTarget) {
      this.speakingBarTarget.style.display = "none"
      this.scrollToBottom()
    }
  }
}
