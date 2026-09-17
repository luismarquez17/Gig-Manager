// Gig Manager - PWA & Notification & Audio Manager

(function() {
  // ─── 1. AUDIO SYNTHESIS & SOUND EFFECTS ──────────────────────────────
  let audioCtx = null;

  function getAudioContext() {
    try {
      if (!audioCtx) {
        const AudioContext = window.AudioContext || window.webkitAudioContext;
        if (AudioContext) {
          audioCtx = new AudioContext();
        }
      }
      if (audioCtx && audioCtx.state === 'suspended') {
        audioCtx.resume();
      }
    } catch (e) {
      console.warn('AudioContext no disponible:', e);
    }
    return audioCtx;
  }

  // Pre-unlock audio on user gestures
  function unlockAudio() {
    const ctx = getAudioContext();
    if (ctx && ctx.state === 'suspended') {
      ctx.resume().catch(() => {});
    }
  }
  document.addEventListener('click', unlockAudio, { once: true });
  document.addEventListener('touchstart', unlockAudio, { once: true });
  document.addEventListener('keydown', unlockAudio, { once: true });

  function isSoundEnabled() {
    const setting = localStorage.getItem('gig_sound_enabled');
    return setting === null || setting === 'true' || setting === '1';
  }

  function setSoundEnabled(enabled) {
    localStorage.setItem('gig_sound_enabled', enabled ? 'true' : 'false');
    window.dispatchEvent(new CustomEvent('gig:sound_setting_changed', { detail: { enabled } }));
  }

  function toggleSoundPreference() {
    const current = isSoundEnabled();
    const next = !current;
    setSoundEnabled(next);
    if (next) {
      playNotificationSound('pop');
    }
    return next;
  }

  function playTone(freq, startTime, duration, type = 'sine', gainVal = 0.15) {
    const ctx = getAudioContext();
    if (!ctx) return;

    try {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();

      osc.type = type;
      osc.frequency.setValueAtTime(freq, startTime);

      // Volume envelope (smooth attack and exponential decay)
      gain.gain.setValueAtTime(0.001, startTime);
      gain.gain.exponentialRampToValueAtTime(gainVal, startTime + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, startTime + duration);

      osc.connect(gain);
      gain.connect(ctx.destination);

      osc.start(startTime);
      osc.stop(startTime + duration + 0.05);
    } catch (e) {
      console.warn('Error reproduciendo tono:', e);
    }
  }

  function playNotificationSound(soundType = 'default') {
    if (!isSoundEnabled()) return;

    const ctx = getAudioContext();
    if (!ctx) return;

    const now = ctx.currentTime;

    if (soundType === 'urgent' || soundType === 'error') {
      // 3 rápidas notas de alerta (G5 -> A5 -> C6)
      playTone(784.0, now, 0.12, 'triangle', 0.2);
      playTone(880.0, now + 0.10, 0.12, 'triangle', 0.22);
      playTone(1046.5, now + 0.20, 0.35, 'sine', 0.25);
    } else if (soundType === 'payment' || soundType === 'cash') {
      // Melodía tipo 'cha-ching'
      playTone(523.25, now, 0.09, 'sine', 0.18);
      playTone(659.25, now + 0.08, 0.09, 'sine', 0.18);
      playTone(783.99, now + 0.16, 0.12, 'triangle', 0.22);
      playTone(1046.5, now + 0.24, 0.45, 'sine', 0.25);
    } else if (soundType === 'pop') {
      // Pop suave para clicks o toggles
      playTone(587.33, now, 0.08, 'sine', 0.12);
    } else {
      // 'default' / 'success': Campana suave y elegante de 2 tonos
      playTone(659.25, now, 0.15, 'sine', 0.18);
      playTone(987.77, now + 0.12, 0.45, 'sine', 0.22);
    }
  }

  // ─── 2. SISTEMA DE NOTIFICACIONES DEL DISPOSITIVO (NATIVAS) ──────────
  function getNotificationPermission() {
    if (!('Notification' in window)) return 'unsupported';
    return Notification.permission;
  }

  async function requestNotificationPermission() {
    if (!('Notification' in window)) {
      if (typeof showToast === 'function') {
        showToast('Las notificaciones no están soportadas en este navegador.', 'error');
      }
      return 'unsupported';
    }

    try {
      const permission = await Notification.requestPermission();
      window.dispatchEvent(new CustomEvent('gig:notification_permission_changed', { detail: { permission } }));
      
      if (permission === 'granted') {
        playNotificationSound('default');
        sendDeviceNotification('¡Notificaciones Activadas! 🔔', 'Ahora recibirás avisos de eventos, pagos y alertas de Gig Manager en tu dispositivo.');
      }
      return permission;
    } catch (e) {
      console.error('Error solicitando permisos de notificación:', e);
      return 'denied';
    }
  }

  function sendDeviceNotification(title, message, options = {}) {
    if (!('Notification' in window) || Notification.permission !== 'granted') return;

    const defaultOptions = {
      body: message || 'Tienes una nueva actualización en Gig Manager',
      icon: '/icons/icon-192.png',
      badge: '/icons/badge-96.png',
      vibrate: [200, 100, 200],
      tag: 'gig-alert-' + Date.now(),
      data: {
        url: options.url || '/notifications'
      }
    };

    const finalOptions = Object.assign(defaultOptions, options);

    // Intentar con Service Worker primero (ideal para móviles y PWA)
    if ('serviceWorker' in navigator && navigator.serviceWorker.ready) {
      navigator.serviceWorker.ready.then((registration) => {
        if (registration && registration.showNotification) {
          registration.showNotification(title, finalOptions);
        } else {
          fallbackNotification(title, finalOptions);
        }
      }).catch(() => {
        fallbackNotification(title, finalOptions);
      });
    } else {
      fallbackNotification(title, finalOptions);
    }
  }

  function fallbackNotification(title, options) {
    try {
      const notif = new Notification(title, options);
      notif.onclick = function() {
        window.focus();
        if (options.data && options.data.url) {
          window.location.href = options.data.url;
        }
        notif.close();
      };
    } catch (e) {
      console.warn('Fallback notification falló:', e);
    }
  }

  // Alerta unificada: reproduce sonido, lanza notificación de sistema y muestra toast en pantalla
  function triggerNotificationAlert(title, message, type = 'default') {
    const soundType = (type === 'urgent' || type === 'error') ? 'urgent' : (type === 'payment' ? 'payment' : 'default');
    playNotificationSound(soundType);

    // Si el usuario no tiene la ventana enfocada o está en móvil, mandar notificación nativa
    if (document.hidden || !document.hasFocus()) {
      sendDeviceNotification(title, message, { url: '/notifications' });
    }

    if (typeof showToast === 'function') {
      showToast(`${title}: ${message}`, type === 'urgent' ? 'error' : 'success');
    }
  }

  // ─── 3. GESTOR PWA & INSTALACIÓN INTELIGENTE ─────────────────────────
  let deferredPrompt = null;

  function isStandalone() {
    return (
      window.matchMedia('(display-mode: standalone)').matches ||
      window.navigator.standalone === true ||
      document.referrer.includes('android-app://')
    );
  }

  function isIOS() {
    return /iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream;
  }

  window.addEventListener('beforeinstallprompt', (e) => {
    // Prevenir el banner por defecto del navegador para mostrar el nuestro con estilo nativo
    e.preventDefault();
    deferredPrompt = e;
    window.dispatchEvent(new CustomEvent('gig:install_prompt_available'));
    showInstallBanner();
  });

  window.addEventListener('appinstalled', () => {
    deferredPrompt = null;
    hideInstallBanner();
    if (typeof showToast === 'function') {
      showToast('¡Gig Manager se instaló correctamente! 📱', 'success');
    }
  });

  async function promptPWAInstall() {
    if (deferredPrompt) {
      deferredPrompt.prompt();
      const choiceResult = await deferredPrompt.userChoice;
      if (choiceResult.outcome === 'accepted') {
        console.log('El usuario aceptó instalar la PWA');
      }
      deferredPrompt = null;
      hideInstallBanner();
    } else if (isIOS()) {
      showIOSInstallModal();
    } else {
      if (typeof showToast === 'function') {
        showToast('Para instalar: abre el menú de tu navegador y selecciona "Instalar aplicación" o "Agregar a pantalla de inicio".', 'success');
      }
    }
  }

  function showInstallBanner() {
    if (isStandalone()) return;

    // Si fue descartado hace menos de 5 días, no molestar
    const dismissedAt = localStorage.getItem('gig_install_banner_dismissed');
    if (dismissedAt && (Date.now() - parseInt(dismissedAt, 10)) < (5 * 24 * 60 * 60 * 1000)) {
      return;
    }

    const banner = document.getElementById('pwa-install-banner');
    if (banner) {
      banner.style.display = 'flex';
      requestAnimationFrame(() => {
        banner.style.transform = 'translateY(0)';
        banner.style.opacity = '1';
      });
    }
  }

  function hideInstallBanner(permanent = false) {
    const banner = document.getElementById('pwa-install-banner');
    if (banner) {
      banner.style.transform = 'translateY(100%)';
      banner.style.opacity = '0';
      setTimeout(() => { banner.style.display = 'none'; }, 300);
    }
    if (permanent) {
      localStorage.setItem('gig_install_banner_dismissed', Date.now().toString());
    }
  }

  function showIOSInstallModal() {
    const modal = document.getElementById('pwa-ios-modal');
    if (modal) {
      modal.style.display = 'flex';
      requestAnimationFrame(() => {
        modal.style.opacity = '1';
      });
    }
  }

  function hideIOSInstallModal() {
    const modal = document.getElementById('pwa-ios-modal');
    if (modal) {
      modal.style.opacity = '0';
      setTimeout(() => { modal.style.display = 'none'; }, 250);
    }
  }

  // ─── 4. REGISTRO DE SERVICE WORKER ──────────────────────────────────
  function registerServiceWorker() {
    if ('serviceWorker' in navigator) {
      window.addEventListener('load', () => {
        navigator.serviceWorker.register('/service-worker.js')
          .then((registration) => {
            console.log('Gig Manager Service Worker registrado con éxito:', registration.scope);
          })
          .catch((error) => {
            console.warn('Error registrando Service Worker:', error);
          });
      });
    }
  }

  registerServiceWorker();

  // Exponer API global en `window` y `window.PWA`
  window.PWA = {
    isSoundEnabled,
    setSoundEnabled,
    toggleSoundPreference,
    playNotificationSound,
    getNotificationPermission,
    requestNotificationPermission,
    sendDeviceNotification,
    triggerNotificationAlert,
    promptPWAInstall,
    isStandalone,
    isIOS,
    showInstallBanner,
    hideInstallBanner,
    showIOSInstallModal,
    hideIOSInstallModal
  };

  // Atajos directos
  window.playNotificationSound = playNotificationSound;
  window.triggerNotificationAlert = triggerNotificationAlert;
  window.requestNotificationPermission = requestNotificationPermission;
  window.promptPWAInstall = promptPWAInstall;
  window.toggleSoundPreference = toggleSoundPreference;
  window.isSoundEnabled = isSoundEnabled;
  window.hideInstallBanner = hideInstallBanner;
  window.showIOSInstallModal = showIOSInstallModal;
  window.hideIOSInstallModal = hideIOSInstallModal;

  // Actualizar UI al cargar la página o navegar con Turbo
  function updateUIState() {
    // Si no está instalada y es iOS, podemos mostrar el banner si no fue descartado
    if (!isStandalone() && isIOS()) {
      showInstallBanner();
    }
  }

  document.addEventListener('DOMContentLoaded', updateUIState);
  document.addEventListener('turbo:load', updateUIState);

})();
