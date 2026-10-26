import 'package:flutter/material.dart';
import '../../tema/tema_psicobloom.dart';
import 'pantalla_nueva_clave.dart';

/// Pantalla para solicitar el enlace de recuperacion de contrasena mediante correo.
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
              Navigator.pop(context); // Cierra dialogo
              Navigator.pop(context); // Vuelve a inicio de sesion
            },
            child: const Text('Volver al inicio'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Cierra dialogo
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
      backgroundColor: TemaPsicobloom.colorFondo,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Regresar',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Form(
            key: _claveFormulario,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: TemaPsicobloom.colorLavanda,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_reset_rounded,
                      size: 38,
                      color: TemaPsicobloom.colorPrincipal,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
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
                  'Te enviaremos un enlace a tu correo para restablecer tu contraseña y volver a ingresar.',
                  style: TextStyle(
                    fontSize: 15,
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
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
                const SizedBox(height: 8),
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
                const SizedBox(height: 28),

                // Boton Enviar enlace
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
                      : const Text('Enviar enlace'),
                ),
                const SizedBox(height: 20),

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
    );
  }
}
