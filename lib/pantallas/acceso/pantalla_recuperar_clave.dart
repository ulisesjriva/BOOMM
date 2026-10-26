import 'package:flutter/material.dart';
import '../../tema/tema_psicobloom.dart';
import '../../componentes/fondo_decorativo_bloom.dart';
import 'pantalla_nueva_clave.dart';

/// Pantalla para solicitar el enlace de recuperacion de contrasena mediante correo,
/// con la estetica visual completa y lienzo vectorial nativo.
class PantallaRecuperarClave extends StatefulWidget {
  const PantallaRecuperarClave({super.key});

  @override
  State<PantallaRecuperarClave> createState() => _PantallaRecuperarClaveState();
}

class _PantallaRecuperarClaveState extends State<PantallaRecuperarClave> {
  final _claveFormulario = GlobalKey<FormState>();
  final _controladorCorreo = TextEditingController();
  bool _estaEnviando = false;

  @override
  void dispose() {
    _controladorCorreo.dispose();
    super.dispose();
  }

  void _enviarEnlace() {
    if (!_claveFormulario.currentState!.validate()) {
      return;
    }

    setState(() {
      _estaEnviando = true;
    });

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() {
        _estaEnviando = false;
      });

      _mostrarConfirmacionEnvio(context, _controladorCorreo.text.trim());
    });
  }

  void _mostrarConfirmacionEnvio(BuildContext context, String correoDestino) {
    showDialog(
      context: context,
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
            Icons.mark_email_read_outlined,
            color: TemaPsicobloom.colorExito,
            size: 36,
          ),
        ),
        title: const Text(
          'Enlace solicitado',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: TemaPsicobloom.colorTexto,
          ),
        ),
        content: Text(
          'Se ha registrado la solicitud para el correo:\n$correoDestino\n\nCon Supabase Auth conectado, el sistema enviará un enlace que abre la pantalla de "Nueva contraseña".\n\n¿Deseas probar la pantalla de Nueva contraseña ahora?',
          style: const TextStyle(
            color: TemaPsicobloom.colorTexto,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Volver al inicio'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const PantallaNuevaClave(),
                ),
              );
            },
            child: const Text('Ver nueva contraseña'),
          ),
        ],
      ),
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

                        // Titulo y descripcion del proceso de recuperacion
                        const Text(
                          'Recuperar contraseña',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: TemaPsicobloom.colorTexto,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Escribe tu correo y te enviaremos un enlace para restablecer tu contraseña.',
                          style: TextStyle(
                            fontSize: 14.5,
                            color: TemaPsicobloom.colorTextoSecundario,
                            height: 1.35,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),

                        // Campo Correo electronico
                        const Text(
                          'Correo electrónico',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: TemaPsicobloom.colorTexto,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _controladorCorreo,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            hintText: 'tu@correo.com',
                            prefixIcon: Icon(Icons.mail_outline_rounded),
                          ),
                          validator: (valor) {
                            if (valor == null || valor.trim().isEmpty) {
                              return 'Por favor ingresa tu correo electrónico';
                            }
                            if (!valor.contains('@') || !valor.contains('.')) {
                              return 'Ingresa un formato de correo válido';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),

                        // Boton Enviar enlace con flecha
                        ElevatedButton(
                          onPressed: _estaEnviando ? null : _enviarEnlace,
                          child: _estaEnviando
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
                                    Text('Enviar enlace'),
                                    SizedBox(width: 8),
                                    Icon(Icons.arrow_forward_rounded, size: 20),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 24),

                        // Enlace Volver a iniciar sesion
                        Center(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Volver a iniciar sesión'),
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
