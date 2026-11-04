import 'package:flutter/material.dart';
import '../../nucleo/tema/tema_psicobloom.dart';
import '../../nucleo/componentes/fondo_decorativo_bloom.dart';

/// Pantalla para establecer y confirmar la nueva contrasena tras abrir el enlace de recuperacion,
/// con lienzo vectorial nativo y estetica corporativa completa.
class PantallaNuevaClave extends StatefulWidget {
  const PantallaNuevaClave({super.key});

  @override
  State<PantallaNuevaClave> createState() => _PantallaNuevaClaveState();
}

class _PantallaNuevaClaveState extends State<PantallaNuevaClave> {
  final _claveFormulario = GlobalKey<FormState>();
  final _controladorNuevaClave = TextEditingController();
  final _controladorConfirmarClave = TextEditingController();

  bool _mostrarNuevaClave = false;
  bool _mostrarConfirmarClave = false;
  bool _estaGuardando = false;

  @override
  void dispose() {
    _controladorNuevaClave.dispose();
    _controladorConfirmarClave.dispose();
    super.dispose();
  }

  void _guardarNuevaContrasena() {
    if (!_claveFormulario.currentState!.validate()) {
      return;
    }

    setState(() {
      _estaGuardando = true;
    });

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() {
        _estaGuardando = false;
      });

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: TemaPsicobloom.colorSuperficie,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          icon: Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: TemaPsicobloom.colorFondoExito,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              color: TemaPsicobloom.colorExito,
              size: 38,
            ),
          ),
          title: const Text(
            'Contraseña actualizada',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
          content: const Text(
            'Tu contraseña ha sido restablecida con éxito. Ya puedes ingresar con tu nueva clave.',
            style: TextStyle(
              color: TemaPsicobloom.colorTexto,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Cierra dialogo
                Navigator.pop(context); // Regresa a inicio de sesion
              },
              child: const Text('Iniciar sesión'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Regresar',
                  ),
                ),
              ),

              // Contenido con formulario
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
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
                                  color: TemaPsicobloom.colorPrincipal.withOpacity(0.12),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/imagenes/icono_psicobloom.png',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => const Icon(
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
                          'Crea una contraseña para volver a entrar.',
                          style: TextStyle(
                            fontSize: 14.5,
                            color: TemaPsicobloom.colorTextoSecundario,
                            height: 1.35,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),

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
                          obscureText: !_mostrarNuevaClave,
                          decoration: InputDecoration(
                            hintText: '••••••••',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
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
                          validator: (valor) {
                            if (valor == null || valor.isEmpty) {
                              return 'Por favor ingresa tu nueva contraseña';
                            }
                            if (valor.length < 8) {
                              return 'La contraseña debe tener mínimo 8 caracteres';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 4),
                        const Padding(
                          padding: EdgeInsets.only(left: 4.0),
                          child: Text(
                            'Mínimo 8 caracteres',
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
                          obscureText: !_mostrarConfirmarClave,
                          decoration: InputDecoration(
                            hintText: '••••••••',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _mostrarConfirmarClave
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                              onPressed: () {
                                setState(() {
                                  _mostrarConfirmarClave = !_mostrarConfirmarClave;
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
                          onPressed: _estaGuardando ? null : _guardarNuevaContrasena,
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
                                    Icon(Icons.arrow_forward_rounded, size: 20),
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
    );
  }
}
