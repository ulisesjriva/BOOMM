import 'dart:async';

import 'package:flutter/material.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/nucleo/componentes/fondo_decorativo_bloom.dart';
import 'package:boom/modulos/autenticacion/modelos/enlace_autenticacion.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_enlace_autenticacion.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_iniciar_sesion.dart';

/// Pantalla para establecer y confirmar la nueva contrasena tras abrir el enlace de recuperacion,
/// con lienzo vectorial nativo y estetica corporativa completa.
class PantallaNuevaClave extends StatefulWidget {
  final EnlaceAutenticacion? enlace;

  const PantallaNuevaClave({super.key, this.enlace});

  @override
  State<PantallaNuevaClave> createState() => _PantallaNuevaClaveState();
}

class _PantallaNuevaClaveState extends State<PantallaNuevaClave> {
  final _claveFormulario = GlobalKey<FormState>();
  final _controladorNuevaClave = TextEditingController();
  final _controladorConfirmarClave = TextEditingController();

  final _servicioEnlace = ServicioEnlaceAutenticacion();
  bool _enlaceValidado = false;
  bool _estaValidando = false;
  String? _mensajeEnlace;
  bool _mostrarNuevaClave = false;
  bool _mostrarConfirmarClave = false;
  bool _estaGuardando = false;

  @override
  void dispose() {
    _controladorNuevaClave.dispose();
    _controladorConfirmarClave.dispose();
    unawaited(_servicioEnlace.cerrar());
    super.dispose();
  }

  bool get _ocupado => _estaGuardando || _estaValidando;

  void _irAlLogin() {
    Navigator.of(context).pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(builder: (_) => const PantallaIniciarSesion()),
      (_) => false,
    );
  }

  Future<void> _validarEnlace() async {
    if (_ocupado || _enlaceValidado) return;
    final enlace = widget.enlace;
    if (enlace == null || enlace.tipo != TipoEnlaceAutenticacion.recuperacion) {
      setState(
        () => _mensajeEnlace =
            'Abre un enlace de recuperación válido desde tu correo.',
      );
      return;
    }
    setState(() => _estaValidando = true);
    try {
      await _servicioEnlace.validarRecuperacion(enlace);
      if (!mounted) return;
      setState(() {
        _enlaceValidado = true;
        _mensajeEnlace =
            'Enlace validado. Ya puedes crear una contraseña nueva.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _mensajeEnlace = ServicioEnlaceAutenticacion.explicarError(error),
      );
    } finally {
      if (mounted) setState(() => _estaValidando = false);
    }
  }

  Future<void> _guardarNuevaContrasena() async {
    if (_ocupado ||
        !_enlaceValidado ||
        !(_claveFormulario.currentState?.validate() ?? false))
      return;
    final clave = _controladorNuevaClave.text;
    FocusScope.of(context).unfocus();
    setState(() => _estaGuardando = true);
    try {
      await _servicioEnlace.guardarClave(clave);
      if (!mounted) return;
      _controladorNuevaClave.clear();
      _controladorConfirmarClave.clear();
      setState(() => _enlaceValidado = false);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (contextoDialogo) => AlertDialog(
          backgroundColor: TemaPsicobloom.colorSuperficie,
          icon: const Icon(
            Icons.check_circle_outline_rounded,
            color: TemaPsicobloom.colorExito,
            size: 42,
          ),
          title: const Text('Contraseña actualizada'),
          content: const Text(
            'Supabase guardó tu nueva contraseña. Inicia sesión para continuar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(contextoDialogo),
              child: const Text('Iniciar sesión'),
            ),
          ],
        ),
      );
      if (mounted) _irAlLogin();
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _mensajeEnlace = ServicioEnlaceAutenticacion.explicarError(error),
      );
    } finally {
      if (mounted) setState(() => _estaGuardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: FondoDecorativoBloom(
          mostrarHojas: true,
          mostrarCorazones: true,
          child: SafeArea(
            child: Column(
              children: [
                // Barra superior transparente con boton de regreso
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: TemaPsicobloom.colorTexto,
                      onPressed: _ocupado ? null : _irAlLogin,
                      tooltip: 'Regresar',
                    ),
                  ),
                ),

                // Contenido con formulario
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 8.0,
                    ),
                    child: Form(
                      key: _claveFormulario,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 10),

                          // Mascota oficial de PsicoBloom
                          Center(
                            child: Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: TemaPsicobloom.colorPrincipal
                                        .withValues(alpha: 0.12),
                                    blurRadius: 18,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/imagenes/icono_psicobloom.png',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(
                                      Icons.local_florist_rounded,
                                      size: 64,
                                      color: TemaPsicobloom.colorPrincipal,
                                    ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Titulo y subtitulo
                          const Text(
                            'Nueva contraseña',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: TemaPsicobloom.colorTexto,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Valida el enlace de tu correo y crea una contraseña nueva.',
                            style: TextStyle(
                              fontSize: 14.5,
                              color: TemaPsicobloom.colorTextoSecundario,
                              height: 1.35,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),

                          if (_mensajeEnlace != null) ...[
                            Text(_mensajeEnlace!, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                          ],
                          if (!_enlaceValidado) ...[
                            OutlinedButton(
                              onPressed: _ocupado ? null : _validarEnlace,
                              child: Text(
                                _estaValidando
                                    ? 'Validando…'
                                    : 'Validar enlace de recuperación',
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],

                          // Campo Nueva contrasena
                          const Text(
                            'Nueva contraseña',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: TemaPsicobloom.colorTexto,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _controladorNuevaClave,
                            enabled: _enlaceValidado && !_ocupado,
                            obscureText: !_mostrarNuevaClave,
                            decoration: InputDecoration(
                              hintText: '••••••••',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _mostrarNuevaClave
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _mostrarNuevaClave = !_mostrarNuevaClave;
                                  });
                                },
                                tooltip: _mostrarNuevaClave
                                    ? 'Ocultar contraseña'
                                    : 'Mostrar contraseña',
                              ),
                            ),
                            validator: ServicioEnlaceAutenticacion.validarClave,
                          ),
                          const SizedBox(height: 4),
                          const Padding(
                            padding: EdgeInsets.only(left: 4.0),
                            child: Text(
                              'Mínimo 11 caracteres: mayúscula, minúscula, número y símbolo',
                              style: TextStyle(
                                fontSize: 12,
                                color: TemaPsicobloom.colorTextoSecundario,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Campo Confirmar contrasena
                          const Text(
                            'Confirmar contraseña',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: TemaPsicobloom.colorTexto,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _controladorConfirmarClave,
                            enabled: _enlaceValidado && !_ocupado,
                            obscureText: !_mostrarConfirmarClave,
                            decoration: InputDecoration(
                              hintText: '••••••••',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _mostrarConfirmarClave
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _mostrarConfirmarClave =
                                        !_mostrarConfirmarClave;
                                  });
                                },
                                tooltip: _mostrarConfirmarClave
                                    ? 'Ocultar contraseña'
                                    : 'Mostrar contraseña',
                              ),
                            ),
                            validator: (valor) {
                              if (valor == null || valor.isEmpty) {
                                return 'Por favor confirma tu nueva contraseña';
                              }
                              if (valor != _controladorNuevaClave.text) {
                                return 'Las contraseñas no coinciden';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 28),

                          // Boton Guardar contrasena con flecha
                          ElevatedButton(
                            onPressed: _ocupado || !_enlaceValidado
                                ? null
                                : _guardarNuevaContrasena,
                            child: _estaGuardando
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('Guardar contraseña'),
                                      SizedBox(width: 8),
                                      Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
