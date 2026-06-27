import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // No formatear al conectar para no molestar al cargar
  }

  format(event) {
    this.formatValue(event.target)
  }

  formatValue(input) {
    const selectionStart = input.selectionStart
    const oldLength = input.value.length
    
    input.value = this.formatAmount(input.value)
    
    // Ajustar cursor al final
    const newLength = input.value.length
    input.setSelectionRange(newLength, newLength)
  }

  formatAmount(value) {
    let text = value.toString().trim().replace(/,/g, '')
    
    // Si está vacío, devolvemos 0.00
    if (text === '') {
      return '0.00'
    }
    
    // Eliminar todo lo que no sea número (ni siquiera punto)
    text = text.replace(/[^\d]/g, '')
    
    // Si no hay dígitos después de limpiar
    if (text === '') {
      return '0.00'
    }
    
    // Comportamiento tipo POS/Terminal:
    // - Si el usuario escribe 1234, se convierte a 12.34 (últimos 2 dígitos = decimales)
    // - Si el usuario escribe 123, se convierte a 1.23
    // - Si el usuario escribe 1, se convierte a 0.01
    
    // Quitar ceros a la izquierda
    text = text.replace(/^0+/, '') || '0'
    
    // Si tiene menos de 3 dígitos, rellenar con ceros a la izquierda para dividir
    // Pero solo si no es "0"
    let integerPart, decimalPart
    
    if (text === '0') {
      return '0.00'
    }
    
    // Asegurar al menos 3 dígitos para dividir correctamente
    const padded = text.padStart(3, '0')
    const len = padded.length
    
    // Los últimos 2 dígitos son decimales
    if (len <= 2) {
      integerPart = '0'
      decimalPart = padded.padStart(2, '0')
    } else {
      integerPart = padded.slice(0, len - 2)
      decimalPart = padded.slice(len - 2)
    }
    
    // Quitar ceros a la izquierda del integer
    integerPart = integerPart.replace(/^0+/, '') || '0'
    
    return `${integerPart}.${decimalPart}`
  }
}
