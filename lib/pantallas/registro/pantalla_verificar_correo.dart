import 'dart:async';

import 'package:flutter/material.dart';

import '../../nucleo/tema/tema_psicobloom.dart';
import '../../nucleo/componentes/fondo_decorativo_bloom.dart';
import '../acceso/pantalla_iniciar_sesion.dart';
import '../../servicios/servicio_registro.dart';

/// Pantalla que solicita al usuario abrir el enlace de confirmacion enviado a su correo.
class PantallaVerificarCorreo extends StatefulWidget {
  final String correo;
  final bool esProfesional;
  final ServicioRegistro servicio;

  const PantallaVerificarCorreo({
    super.key,
    required this.correo,
    this.esProfesional = false,
    this.servicio = const ServicioRegistro(),
  });

  @override
  State<PantallaVerificarCorreo> createState() =>
      _PantallaVerificarCorreoState();
}

class _PantallaVerificarCorreoState extends State<PantallaVerificarCorreo> {
  bool _estaComprobando = false;
  bool _estaReenviando = false;
  int _segundosReenvio = 0;
  Timer? _relojReenvio;

  @override
  void initState() {
    super.initState();
    _iniciarEsperaReenvio();
  }

  void _iniciarEsperaReenvio() {
    _relojReenvio?.cancel();
    _segundosReenvio = 60;
    _relojReenvio = Timer.periodic(const Duration(seconds: 1), (reloj) {
      if (!mounted) {
        reloj.cancel();
        return;
      }
      setState(() => _segundosReenvio--);
      if (_segundosReenvio <= 0) reloj.cancel();
    });
  }

  @override
  void dispose() {
    _relojReenvio?.cancel();
    super.dispose();
  }

  Future<void> _comprobarVerificacion() async {
    if (_estaComprobando || _estaReenviando) return;
    setState(() => _estaComprobando = true);
    try {
      final perfil = await widget.servicio.comprobarConfirmacion(widget.correo);
      if (!mounted) return;
      final mensaje = perfil == null
          ? 'Todavía no hay una sesión confirmada para este correo en esta aplicación. '
                'Abre el enlace de confirmación en el mismo emulador y vuelve a comprobar. '
                'Si lo abriste en otro dispositivo, eso no inicia la sesión aquí.'
          : 'Supabase confirmó el correo y devolvió tu perfil real.\n\n'
                'Nombre: ${perfil.nombre} ${perfil.apellido}\n'
                'Rol: ${perfil.rol}\n'
                'Estado de la cuenta: ${perfil.cuentaActiva ? "activa" : "desactivada"}\n'
                'Aprobación: ${perfil.aprobacion}';
      setState(() => _estaComprobando = false);
      await showDialog<void>(
        context: context,
        builder: (contextoDialogo) => AlertDialog(
          backgroundColor: TemaPsicobloom.colorSuperficie,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
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
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ServicioRegistro.explicarError(error))),
      );
    } finally {
      if (mounted) setState(() => _estaComprobando = false);
    }
  }

  Future<void> _reenviarEnlace() async {
    if (_estaReenviando || _estaComprobando || _segundosReenvio > 0) return;
    setState(() => _estaReenviando = true);
    try {
      await widget.servicio.reenviarEnlace(widget.correo);
      if (!mounted) return;
      setState(_iniciarEsperaReenvio);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Solicitud de reenvío aceptada. Revisa tu bandeja y spam; la entrega del correo aún debe comprobarse.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ServicioRegistro.explicarError(error))),
      );
    } finally {
      if (mounted) setState(() => _estaReenviando = false);
    }
  }

  void _irAIniciarSesion() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const PantallaIniciarSesion()),
      (ruta) => ruta.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
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
}
