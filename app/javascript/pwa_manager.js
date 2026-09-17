// Gig Manager - PWA & Notification & Audio Manager

(function() {
  // ─── 1. AUDIO SYNTHESIS & SOUND EFFECTS (Web Audio API) ─────────────
  let audioCtx = null;

  function getAudioContext() {
    try {
      if (!audioCtx) {
        const AudioContextClass = window.AudioContext || window.webkitAudioContext;
        if (AudioContextClass) {
          audioCtx = new AudioContextClass();
        }
      }
      if (audioCtx && audioCtx.state === 'suspended') {
        audioCtx.resume().catch(() => {});
      }
    } catch (e) {
      console.warn('AudioContext no disponible:', e);
    }
    return audioCtx;
  }

  // Pre-unlock audio on any user interaction
  function unlockAudio() {
    const ctx = getAudioContext();
    if (ctx && ctx.state === 'suspended') {
      ctx.resume().catch(() => {});
    }
  }
  ['click', 'touchstart', 'touchend', 'keydown', 'mousedown'].forEach((evt) => {
    document.addEventListener(evt, unlockAudio, { passive: true });
  });

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
      if (typeof showToast === 'function') {
        showToast('🔊 Efectos de sonido activados', 'success');
      }
    } else {
      if (typeof showToast === 'function') {
        showToast('🔇 Efectos de sonido silenciados', 'error');
      }
    }
    return next;
  }

  function playTone(freq, startTime, duration, type = 'sine', gainVal = 0.25) {
    const ctx = getAudioContext();
    if (!ctx) return;

    try {
      if (ctx.state === 'suspended') {
        ctx.resume();
      }

      const osc = ctx.createOscillator();
      const gain = ctx.createGain();

      osc.type = type;
      osc.frequency.setValueAtTime(freq, startTime);

      // Smooth attack and exponential release envelope
      gain.gain.setValueAtTime(0.0001, startTime);
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

    if (ctx.state === 'suspended') {
      ctx.resume().then(() => doPlaySound(ctx, soundType)).catch(() => {});
    } else {
      doPlaySound(ctx, soundType);
    }
  }

  function doPlaySound(ctx, soundType) {
    const now = ctx.currentTime;

    if (soundType === 'urgent' || soundType === 'error') {
      // 3 rápidas notas de alerta (G5 -> A5 -> C6)
      playTone(784.0, now, 0.12, 'triangle', 0.28);
      playTone(880.0, now + 0.11, 0.12, 'triangle', 0.30);
      playTone(1046.5, now + 0.22, 0.38, 'sine', 0.35);
    } else if (soundType === 'payment' || soundType === 'cash') {
      // Melodía de cobro / éxito
      playTone(523.25, now, 0.09, 'sine', 0.22);
      playTone(659.25, now + 0.08, 0.09, 'sine', 0.25);
      playTone(783.99, now + 0.16, 0.12, 'triangle', 0.28);
      playTone(1046.5, now + 0.24, 0.45, 'sine', 0.32);
    } else if (soundType === 'pop') {
      // Pop suave para clicks o toggles
      playTone(587.33, now, 0.08, 'sine', 0.20);
    } else {
      // 'default' / 'success': Campana suave y nítida de 2 tonos
      playTone(659.25, now, 0.14, 'sine', 0.25);
      playTone(987.77, now + 0.12, 0.48, 'sine', 0.30);
    }
  }

  // ─── 2. SISTEMA DE NOTIFICACIONES DEL DISPOSITIVO ────────────────────
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

    if (Notification.permission === 'granted') {
      playNotificationSound('default');
      if (typeof showToast === 'function') {
        showToast('✅ Las notificaciones ya están activadas en este equipo.', 'success');
      }
      sendDeviceNotification('¡Gig Manager Notificaciones! 🔔', 'Este equipo ya tiene los avisos del sistema activados.');
      return 'granted';
    }

    try {
      const permission = await Notification.requestPermission();
      window.dispatchEvent(new CustomEvent('gig:notification_permission_changed', { detail: { permission } }));
      
      if (permission === 'granted') {
        playNotificationSound('default');
        if (typeof showToast === 'function') {
          showToast('🎉 ¡Notificaciones del sistema activadas!', 'success');
        }
        sendDeviceNotification('¡Notificaciones Activadas! 🔔', 'Ahora recibirás avisos de eventos, pagos y alertas de Gig Manager.');
      } else if (permission === 'denied') {
        if (typeof showToast === 'function') {
          showToast('⚠️ Permiso denegado. Habilítalo en los ajustes o candado 🔒 de tu navegador.', 'error');
        }
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

    // Intentar con Service Worker primero (PWA / background)
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

  // Alerta unificada
  function triggerNotificationAlert(title, message, type = 'default', forceDeviceNotification = false) {
    const soundType = (type === 'urgent' || type === 'error') ? 'urgent' : (type === 'payment' ? 'payment' : 'default');
    playNotificationSound(soundType);

    // Mostrar Toast en pantalla
    if (typeof showToast === 'function') {
      showToast(`${title}: ${message}`, type === 'urgent' ? 'error' : 'success');
    }

    // Enviar notificación del sistema
    if (forceDeviceNotification || document.hidden || !document.hasFocus() || ('Notification' in window && Notification.permission === 'granted')) {
      sendDeviceNotification(title, message, { url: '/notifications' });
    }
  }

  // ─── 3. GESTOR PWA & INSTALACIÓN MULTIPLATAFORMA ────────────────────
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
    } else {
      // Mostrar modal instructivo con pestañas según el dispositivo (PC, iPhone, Android)
      showInstallGuideModal();
    }
  }

  function showInstallBanner() {
    if (isStandalone()) return;

    const dismissedAt = localStorage.getItem('gig_install_banner_dismissed');
    if (dismissedAt && (Date.now() - parseInt(dismissedAt, 10)) < (3 * 24 * 60 * 60 * 1000)) {
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

  function showInstallGuideModal() {
    const modal = document.getElementById('pwa-install-guide-modal') || document.getElementById('pwa-ios-modal');
    if (modal) {
      modal.style.display = 'flex';
      requestAnimationFrame(() => {
        modal.style.opacity = '1';
      });
    }
  }

  function hideInstallGuideModal() {
    const modal = document.getElementById('pwa-install-guide-modal') || document.getElementById('pwa-ios-modal');
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
    showInstallGuideModal,
    hideInstallGuideModal
  };

  // Asignaciones globales directas
  window.playNotificationSound = playNotificationSound;
  window.triggerNotificationAlert = triggerNotificationAlert;
  window.requestNotificationPermission = requestNotificationPermission;
  window.promptPWAInstall = promptPWAInstall;
  window.toggleSoundPreference = toggleSoundPreference;
  window.isSoundEnabled = isSoundEnabled;
  window.hideInstallBanner = hideInstallBanner;
  window.showIOSInstallModal = showInstallGuideModal;
  window.hideIOSInstallModal = hideInstallGuideModal;
  window.showInstallGuideModal = showInstallGuideModal;
  window.hideInstallGuideModal = hideInstallGuideModal;

  function updateUIState() {
    if (!isStandalone() && isIOS()) {
      showInstallBanner();
    }
  }

  document.addEventListener('DOMContentLoaded', updateUIState);
  document.addEventListener('turbo:load', updateUIState);

})();
