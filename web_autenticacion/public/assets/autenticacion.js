'use strict';

(() => {
  const porId = (id) => document.getElementById(id);
  const titulo = porId('titulo');
  const descripcion = porId('descripcion');
  const estado = porId('estado');
  const verificar = porId('verificar');
  const continuarApp = porId('continuar-app');
  const formulario = porId('formulario-clave');
  const abrirApp = porId('abrir-app');
  const ayuda = porId('ayuda-app');
  const esAndroid = /Android/i.test(navigator.userAgent);
  const parametros = new URLSearchParams(location.hash.slice(1));
  let tokenHash = parametros.get('token_hash') || '';
  const tipo = parametros.get('tipo');
  const esRecuperacion = tipo === 'recovery';
  const esConfirmacion = tipo === 'signup';
  let cliente = null;
  let procesando = false;
  let recuperacionVerificada = false;
  let idRecuperacion = null;

  // Retirar credenciales de la barra y de la entrada actual del historial.
  // No conservarlas en localStorage, sessionStorage, cookies ni registros.
  if (location.hash || location.search) {
    history.replaceState(null, '', location.pathname);
  }

  function mostrarEstado(mensaje, clase = '') {
    estado.textContent = mensaje;
    estado.className = `estado ${clase}`;
    estado.hidden = false;
  }

  function prepararAperturaApp() {
    if (esAndroid) {
      abrirApp.hidden = false;
      ayuda.hidden = false;
    }
  }

  function obtenerCliente() {
    if (cliente) return cliente;
    const config = window.CONFIGURACION_PSICOBLOOM;
    const clave = config?.clavePublica?.trim() || '';
    let esAnon = false;
    if (clave.startsWith('eyJ')) {
      try {
        const segmento = clave.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
        esAnon = JSON.parse(atob(segmento)).role === 'anon';
      } catch (_) { /* Una clave con formato incorrecto no se utiliza. */ }
    }
    if (!config || config.urlSupabase !== 'https://hteasqflwhfvlckubvio.supabase.co' ||
        !(esAnon || clave.startsWith('sb_publishable_'))) {
      throw new Error('configuracion_pendiente');
    }
    if (!window.supabase?.createClient) throw new Error('cliente_no_disponible');
    cliente = window.supabase.createClient(config.urlSupabase, clave, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
        storageKey: 'psicobloom-verificacion-web',
      },
    });
    return cliente;
  }

  function enlaceInvalido(error) {
    return error?.code === 'otp_expired' ||
      /token has expired or is invalid/i.test(error?.message || '');
  }

  function explicarError(error) {
    if (error?.message === 'configuracion_pendiente') {
      return 'La página todavía no está configurada para completar esta solicitud. Inténtalo más tarde.';
    }
    if (enlaceInvalido(error)) {
      return 'El enlace venció, ya fue utilizado o dejó de ser válido. Solicita uno nuevo desde PsicoBloom.';
    }
    if (error?.code === 'weak_password') {
      return 'Supabase rechazó la contraseña. Usa al menos 11 caracteres con mayúscula, minúscula, número y símbolo.';
    }
    if (error?.code === 'same_password') {
      return 'Elige una contraseña diferente de la anterior.';
    }
    if (error?.status === 429) {
      return 'Hay demasiadas solicitudes. Espera unos minutos antes de volver a intentarlo.';
    }
    if (error?.status === 401 || error?.status === 403) {
      return 'No se pudo autorizar la solicitud. Abre un enlace nuevo desde tu correo.';
    }
    return 'No se pudo completar la solicitud. Comprueba tu conexión. Si el enlace ya se utilizó, solicita uno nuevo.';
  }

  async function cerrarSesionWeb() {
    if (!cliente) return;
    try {
      await cliente.auth.signOut({ scope: 'local' });
    } catch (_) {
      // La sesion web no se persiste ni se transfiere a la app.
    }
    cliente = null;
  }

  if ((!esConfirmacion && !esRecuperacion) || !tokenHash || tokenHash.length > 2048) {
    tokenHash = '';
    titulo.textContent = 'Necesitas el enlace de tu correo';
    descripcion.textContent = 'Abre el mensaje más reciente de PsicoBloom y pulsa su enlace de confirmación o recuperación.';
    mostrarEstado('Esta dirección no contiene un enlace de autenticación válido.');
    prepararAperturaApp();
    return;
  }

  titulo.textContent = esRecuperacion ? 'Recupera tu acceso' : 'Confirma tu correo';
  descripcion.textContent = esRecuperacion
    ? 'Primero comprobaremos el enlace. Después podrás crear una nueva contraseña en este navegador.'
    : 'Confirma que este correo te pertenece para poder iniciar sesión en PsicoBloom.';
  verificar.textContent = esRecuperacion ? 'Validar enlace de recuperación' : 'Confirmar mi correo';
  verificar.hidden = false;

  // Android puede abrir la app mediante un Intent dirigido a su paquete.
  // Se entrega el token de un solo uso, no una sesion ni un verificador PKCE.
  // Si la app no esta instalada, Chrome conserva la alternativa HTTPS.
  if (esAndroid) {
    const parametrosApp = new URLSearchParams({ tipo, token_hash: tokenHash });
    const alternativa = `https://psicobloom-7201a.web.app/autenticacion.html#${parametrosApp}`;
    continuarApp.href = `intent://psicobloom-7201a.web.app/autenticacion.html?${parametrosApp}#Intent;scheme=https;package=com.example.boom;S.browser_fallback_url=${encodeURIComponent(alternativa)};end`;
    continuarApp.hidden = false;
  }

  // La validacion ocurre tras la accion del usuario, nunca al cargar la pagina.
  verificar.addEventListener('click', async () => {
    if (procesando || !tokenHash) return;
    procesando = true;
    verificar.disabled = true;
    continuarApp.hidden = true;
    mostrarEstado('Comprobando el enlace…');
    try {
      const auth = obtenerCliente().auth;
      const { data, error } = await auth.verifyOtp({
        token_hash: tokenHash,
        type: esRecuperacion ? 'recovery' : 'email',
      });
      if (error) throw error;
      if (!data?.user?.id || !data?.session?.access_token) {
        throw new Error('respuesta_incompleta');
      }
      tokenHash = '';
      verificar.hidden = true;
      if (esRecuperacion) {
        recuperacionVerificada = true;
        idRecuperacion = data.user.id;
        titulo.textContent = 'Crea tu nueva contraseña';
        descripcion.textContent = 'El enlace fue validado. Completa ambos campos para guardar el cambio.';
        mostrarEstado('Enlace de recuperación validado.', 'exito');
        formulario.hidden = false;
        porId('nueva-clave').focus();
      } else {
        if (!data.user.email_confirmed_at) throw new Error('correo_no_confirmado');
        await cerrarSesionWeb();
        titulo.textContent = 'Tu correo está confirmado';
        descripcion.textContent = 'Ya puedes volver a PsicoBloom e iniciar sesión con tu correo y contraseña. Tus permisos dependen del perfil de tu cuenta.';
        mostrarEstado('Supabase confirmó tu correo correctamente.', 'exito');
        prepararAperturaApp();
      }
    } catch (error) {
      mostrarEstado(explicarError(error), 'error');
      if (enlaceInvalido(error)) {
        tokenHash = '';
        verificar.hidden = true;
      }
      await cerrarSesionWeb();
    } finally {
      procesando = false;
      verificar.disabled = false;
      if (tokenHash && esAndroid) continuarApp.hidden = false;
    }
  });

  formulario.addEventListener('submit', async (evento) => {
    evento.preventDefault();
    if (procesando || !recuperacionVerificada || !cliente || !idRecuperacion) return;
    const nueva = porId('nueva-clave');
    const confirmar = porId('confirmar-clave');
    if (!formulario.reportValidity()) return;
    if (!/[a-z]/.test(nueva.value) || !/[A-Z]/.test(nueva.value) ||
        !/[0-9]/.test(nueva.value) || !/[!-/:-@\[-`{-~]/.test(nueva.value)) {
      mostrarEstado('Incluye una mayúscula, una minúscula, un número y un símbolo, por ejemplo ! o @.', 'error');
      return;
    }
    if (nueva.value !== confirmar.value) {
      mostrarEstado('Las contraseñas no coinciden.', 'error');
      confirmar.focus();
      return;
    }
    procesando = true;
    porId('guardar').disabled = true;
    nueva.disabled = true;
    confirmar.disabled = true;
    mostrarEstado('Guardando la nueva contraseña…');
    try {
      const { data, error } = await cliente.auth.updateUser({ password: nueva.value });
      if (error) throw error;
      if (data?.user?.id !== idRecuperacion) throw new Error('respuesta_incompleta');
      nueva.value = '';
      confirmar.value = '';
      recuperacionVerificada = false;
      idRecuperacion = null;
      await cerrarSesionWeb();
      formulario.hidden = true;
      titulo.textContent = 'Contraseña actualizada';
      descripcion.textContent = 'Vuelve a PsicoBloom e inicia sesión con tu nueva contraseña.';
      mostrarEstado('Supabase guardó tu nueva contraseña.', 'exito');
      prepararAperturaApp();
    } catch (error) {
      mostrarEstado(explicarError(error), 'error');
    } finally {
      procesando = false;
      porId('guardar').disabled = false;
      nueva.disabled = false;
      confirmar.disabled = false;
    }
  });
})();
