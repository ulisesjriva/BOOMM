import 'package:flutter/material.dart';
import 'package:boom/modulos/autenticacion/controladores/controlador_verificar_correo.dart';

import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/nucleo/componentes/fondo_decorativo_bloom.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_iniciar_sesion.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_registro.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_enlace_autenticacion.dart';
import 'package:boom/modulos/autenticacion/modelos/enlace_autenticacion.dart';

/// Pantalla que solicita al usuario abrir el enlace de confirmacion enviado a su correo.
class PantallaVerificarCorreo extends StatefulWidget {
  final String correo;
  final bool esProfesional;
  final ServicioRegistro servicio;
  final EnlaceAutenticacion? enlace;
  final ServicioEnlaceAutenticacion? servicioEnlace;

  const PantallaVerificarCorreo({
    super.key,
    required this.correo,
    this.esProfesional = false,
    this.servicio = const ServicioRegistro(),
    this.enlace,
    this.servicioEnlace,
  });

  const PantallaVerificarCorreo.desdeEnlace({
    super.key,
    required EnlaceAutenticacion enlace,
    this.servicioEnlace,
  }) : enlace = enlace,
       correo = '',
       esProfesional = false,
       servicio = const ServicioRegistro();

  @override
  State<PantallaVerificarCorreo> createState() =>
      _PantallaVerificarCorreoState();
}

class _PantallaVerificarCorreoState extends State<PantallaVerificarCorreo> {
  late final ControladorVerificarCorreo _controlador;

  String? get _mensajeEnlace => _controlador.mensajeEnlace;
  bool get _confirmadoDesdeEnlace => _controlador.confirmadoDesdeEnlace;
  bool get _estaComprobando => _controlador.estaComprobando;
  bool get _estaReenviando => _controlador.estaReenviando;
  int get _segundosReenvio => _controlador.segundosReenvio;

  @override
  void initState() {
    super.initState();
    _controlador = ControladorVerificarCorreo(
      servicio: widget.servicio,
      servicioEnlace: widget.servicioEnlace,
      iniciarEspera: widget.enlace == null,
    );
    _controlador.addListener(_actualizarVista);
  }

  void _actualizarVista() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controlador.removeListener(_actualizarVista);
    _controlador.dispose();
    super.dispose();
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _comprobarVerificacion() async {
    if (_estaComprobando || _estaReenviando) {
      return;
    }
    final perfil = await _controlador.comprobarConfirmacion(widget.correo);
    if (!mounted) {
      return;
    }
    final error = _controlador.mensajeError;
    if (error != null) {
      _mostrarError(error);
      return;
    }
    final mensaje = perfil == null
        ? 'Todavía no hay una sesión confirmada para este correo en esta aplicación. '
              'Si confirmaste desde la página web, vuelve a iniciar sesión con tu correo y contraseña. '
              'La confirmación externa no inicia una sesión en este dispositivo.'
        : 'Supabase confirmó el correo y devolvió tu perfil real.\n\n'
              'Nombre: ${perfil.nombre} ${perfil.apellido}\n'
              'Rol: ${perfil.rol}\n'
              'Estado de la cuenta: ${perfil.cuentaActiva ? "activa" : "desactivada"}\n'
              'Aprobación: ${perfil.aprobacion}';
    await showDialog<void>(
      context: context,
      builder: (contextoDialogo) => AlertDialog(
        backgroundColor: TemaPsicobloom.colorSuperficie,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          perfil == null
              ? 'Confirmación pendiente en esta aplicación'
              : 'Correo y perfil comprobados',
        ),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contextoDialogo),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _reenviarEnlace() async {
    if (_estaReenviando || _estaComprobando || _segundosReenvio > 0) {
      return;
    }
    final aceptado = await _controlador.reenviarEnlace(widget.correo);
    if (!mounted) {
      return;
    }
    if (aceptado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Solicitud de reenvío aceptada. Revisa tu bandeja y spam; la entrega del correo aún debe comprobarse.',
          ),
        ),
      );
    } else {
      final error = _controlador.mensajeError;
      if (error != null) {
        _mostrarError(error);
      }
    }
  }

  void _irAIniciarSesion() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const PantallaIniciarSesion()),
      (ruta) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.enlace != null) return _construirDesdeEnlace();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FondoDecorativoBloom(
        mostrarHojas: true,
        mostrarCorazones: true,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 20.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),

                // Ilustracion o contenedor con icono de correo
                Center(
                  child: Container(
                    width: 90,
                    height: 90,
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: TemaPsicobloom.colorLavanda,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.mark_email_unread_outlined,
                      size: 46,
                      color: TemaPsicobloom.colorPrincipal,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                const Text(
                  'Revisa tu correo',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorTexto,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Revisa el mensaje de confirmación en el correo indicado. Si la dirección ya tenía una cuenta, Supabase puede no enviar un mensaje nuevo:',
                  style: const TextStyle(
                    fontSize: 15,
                    color: TemaPsicobloom.colorTextoSecundario,
                    height: 1.35,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  widget.correo,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorPrincipalOscuro,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Tarjeta explicativa sobre el proceso
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: TemaPsicobloom.colorSuperficie,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: TemaPsicobloom.colorBorde),
                  ),
                  child: Column(
                    children: [
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.touch_app_outlined,
                            color: TemaPsicobloom.colorPrincipal,
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Haz clic en el enlace del mensaje para activar tu cuenta antes de iniciar sesión.',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: TemaPsicobloom.colorTexto,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (widget.esProfesional) ...[
                        const Divider(
                          height: 20,
                          color: TemaPsicobloom.colorBorde,
                        ),
                        const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.admin_panel_settings_outlined,
                              color: TemaPsicobloom.colorAdvertencia,
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Aviso: Tu cuenta profesional requerirá validación de credenciales por el administrador antes de recibir citas.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: TemaPsicobloom.colorTexto,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 36),

                // Boton principal Comprobar verificacion
                ElevatedButton(
                  onPressed: _estaComprobando || _estaReenviando
                      ? null
                      : _comprobarVerificacion,
                  child: _estaComprobando
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Ya verifiqué mi correo'),
                ),
                const SizedBox(height: 14),

                // Boton Reenviar enlace
                OutlinedButton(
                  onPressed:
                      _estaReenviando ||
                          _estaComprobando ||
                          _segundosReenvio > 0
                      ? null
                      : _reenviarEnlace,
                  child: Text(
                    _estaReenviando
                        ? 'Solicitando reenvío...'
                        : _segundosReenvio > 0
                        ? 'Reenviar en ${_segundosReenvio}s'
                        : 'Reenviar enlace',
                  ),
                ),
                const SizedBox(height: 20),

                // Enlace Volver a iniciar sesion
                Center(
                  child: TextButton(
                    onPressed: _irAIniciarSesion,
                    child: const Text('Volver a iniciar sesión'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmarDesdeEnlace() async {
    await _controlador.confirmarEnlace(widget.enlace);
  }

  Widget _construirDesdeEnlace() {
    final esValido =
        widget.enlace?.tipo == TipoEnlaceAutenticacion.confirmacion;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: TemaPsicobloom.colorFondo,
        body: FondoDecorativoBloom(
          mostrarHojas: true,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      _confirmadoDesdeEnlace
                          ? Icons.mark_email_read_outlined
                          : Icons.mark_email_unread_outlined,
                      size: 70,
                      color: TemaPsicobloom.colorPrincipal,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _confirmadoDesdeEnlace
                          ? 'Tu correo está confirmado'
                          : esValido
                          ? 'Confirma tu correo'
                          : 'Enlace no válido',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _mensajeEnlace ??
                          (esValido
                              ? 'Pulsa el botón para confirmar tu correo con Supabase. Después podrás iniciar sesión.'
                              : 'Abre el enlace más reciente del correo o solicita uno nuevo desde la aplicación.'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (esValido && !_confirmadoDesdeEnlace)
                      ElevatedButton(
                        onPressed: _estaComprobando
                            ? null
                            : _confirmarDesdeEnlace,
                        child: Text(
                          _estaComprobando
                              ? 'Confirmando…'
                              : 'Confirmar mi correo',
                        ),
                      ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _estaComprobando ? null : _irAIniciarSesion,
                      child: const Text('Volver a iniciar sesión'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
