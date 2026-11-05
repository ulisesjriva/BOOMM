import 'package:flutter/material.dart';
import '../../nucleo/tema/tema_psicobloom.dart';
import '../../nucleo/componentes/fondo_decorativo_bloom.dart';
import '../../servicios/servicio_recuperacion_clave.dart';

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
  final _servicio = const ServicioRecuperacionClave();
  bool _estaEnviando = false;

  @override
  void dispose() {
    _controladorCorreo.dispose();
    super.dispose();
  }

  Future<void> _enviarEnlace() async {
    if (_estaEnviando || !(_claveFormulario.currentState?.validate() ?? false)) {
      return;
    }
    final correo = _controladorCorreo.text.trim();
    FocusScope.of(context).unfocus();
    setState(() => _estaEnviando = true);
    try {
      await _servicio.solicitarEnlace(correo);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (contextoDialogo) => AlertDialog(
          backgroundColor: TemaPsicobloom.colorSuperficie,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          icon: const Icon(
            Icons.mark_email_read_outlined,
            color: TemaPsicobloom.colorPrincipal,
            size: 36,
          ),
          title: const Text('Solicitud recibida'),
          content: Text(
            'Si existe una cuenta asociada a $correo, recibirás un correo para '
            'restablecer tu contraseña. Revisa también la carpeta de spam.\n\n'
            'Abre el mensaje más reciente, valida el enlace en la página de '
            'PsicoBloom y guarda una contraseña nueva. Después vuelve a la '
            'aplicación e inicia sesión.',
            style: const TextStyle(height: 1.4),
          ),
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
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ServicioRecuperacionClave.explicarError(error)),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _estaEnviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_estaEnviando,
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
                      onPressed: _estaEnviando ? null : () => Navigator.pop(context),
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
                                    color: TemaPsicobloom.colorPrincipal.withValues(alpha: 0.12),
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
                            enabled: !_estaEnviando,
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
                              onPressed: _estaEnviando ? null : () => Navigator.pop(context),
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
      ),
    );
  }
}
