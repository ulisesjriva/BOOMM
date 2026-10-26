import 'package:flutter/material.dart';
import '../../tema/tema_psicobloom.dart';

/// Pantalla para establecer y confirmar la nueva contrasena tras abrir el enlace de recuperacion.
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
                // Regresa a la pantalla de inicio de sesion
                Navigator.pop(context);
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
                      Icons.key_rounded,
                      size: 36,
                      color: TemaPsicobloom.colorPrincipal,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
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
                  'Crea una contraseña segura para volver a entrar a tu cuenta.',
                  style: TextStyle(
                    fontSize: 15,
                    color: TemaPsicobloom.colorTextoSecundario,
                    height: 1.35,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Campo Nueva contrasena
                const Text(
                  'Nueva contraseña',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _controladorNuevaClave,
                  obscureText: !_mostrarNuevaClave,
                  decoration: InputDecoration(
                    hintText: 'Mínimo 6 caracteres',
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
                    if (valor.length < 6) {
                      return 'La contraseña debe contener al menos 6 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Campo Confirmar contrasena
                const Text(
                  'Confirmar contraseña',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _controladorConfirmarClave,
                  obscureText: !_mostrarConfirmarClave,
                  decoration: InputDecoration(
                    hintText: 'Repite tu nueva contraseña',
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
                const SizedBox(height: 32),

                // Boton Guardar contrasena
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
                      : const Text('Guardar contraseña'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
