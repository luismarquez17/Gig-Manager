import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "card", "downloadBtn", "copyBtn"]

  connect() {
    // Controller connected
  }

  open(event) {
    if (event) event.preventDefault()
    if (this.hasModalTarget) {
      this.modalTarget.style.display = "block"
      document.body.style.overflow = "hidden"
    }
  }

  close(event) {
    if (event) event.preventDefault()
    if (this.hasModalTarget) {
      this.modalTarget.style.display = "none"
      document.body.style.overflow = ""
    }
  }

  async ensureHtml2Canvas() {
    if (window.html2canvas) return window.html2canvas
    if (window.loadHtml2Canvas) return await window.loadHtml2Canvas()

    return new Promise((resolve, reject) => {
      const script = document.createElement("script")
      script.src = "https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"
      script.crossOrigin = "anonymous"
      script.onload = () => resolve(window.html2canvas)
      script.onerror = () => reject(new Error("No se pudo cargar html2canvas"))
      document.head.appendChild(script)
    })
  }

  async download(event) {
    if (event) event.preventDefault()
    const card = this.hasCardTarget ? this.cardTarget : this.element.querySelector('[id^="gig-flashcard-"]')
    if (!card) return

    const btn = this.hasDownloadBtnTarget ? this.downloadBtnTarget : event?.currentTarget
    const originalText = btn ? btn.innerHTML : ""

    if (btn) {
      btn.disabled = true
      btn.style.opacity = "0.7"
      btn.innerHTML = "<span>⏳ Generando imagen...</span>"
    }

    try {
      const html2canvas = await this.ensureHtml2Canvas()
      const canvas = await html2canvas(card, {
        scale: 2.5,
        useCORS: true,
        backgroundColor: "#0f172a",
        logging: false
      })

      const imageURL = canvas.toDataURL("image/png")
      const link = document.createElement("a")
      link.href = imageURL
      link.download = `Flashcard_Show_${Date.now()}.png`
      document.body.appendChild(link)
      link.click()
      document.body.removeChild(link)

      if (btn) {
        btn.innerHTML = "<span>✅ ¡Foto Guardada!</span>"
        setTimeout(() => {
          btn.innerHTML = originalText
          btn.disabled = false
          btn.style.opacity = "1"
        }, 2200)
      }
    } catch (err) {
      console.error("Error al descargar flashcard:", err)
      alert("Hubo un error al generar la imagen.")
      if (btn) {
        btn.innerHTML = originalText
        btn.disabled = false
        btn.style.opacity = "1"
      }
    }
  }
}
