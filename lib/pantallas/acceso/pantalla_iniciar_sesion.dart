import 'package:flutter/material.dart';
import '../../tema/tema_psicobloom.dart';
import '../../componentes/icono_google.dart';
import 'pantalla_recuperar_clave.dart';
import '../registro/pantalla_registro_paso_uno.dart';
import '../registro/pantalla_completar_perfil.dart';

/// Pantalla para el inicio de sesion de usuarios con correo/clave o mediante Google.
class PantallaIniciarSesion extends StatefulWidget {
  const PantallaIniciarSesion({super.key});

  @override
  State<PantallaIniciarSesion> createState() => _PantallaIniciarSesionState();
}

class _PantallaIniciarSesionState extends State<PantallaIniciarSesion> {
  final _claveFormulario = GlobalKey<FormState>();
  final _controladorCorreo = TextEditingController();
  final _controladorClave = TextEditingController();

  bool _mostrarClave = false;
  bool _estaCargando = false;

  @override
  void dispose() {
    _controladorCorreo.dispose();
    _controladorClave.dispose();
    super.dispose();
  }

  void _ejecutarInicioSesion() {
    if (!_claveFormulario.currentState!.validate()) {
      return;
    }

    setState(() {
      _estaCargando = true;
    });

    // Simulacion de validacion local antes de la conexion con Supabase Auth
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() {
        _estaCargando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: TemaPsicobloom.colorPrincipalOscuro,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Text(
            'Formulario válido para: ${_controladorCorreo.text.trim()}.\nLa verificación de credenciales con Supabase Auth se activará en la etapa de servicios.',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    });
  }

  void _continuarConGoogle() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TemaPsicobloom.colorSuperficie,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            IconoGoogle(tamano: 22),
            SizedBox(width: 10),
            Text(
              'Acceso con Google',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: TemaPsicobloom.colorTexto,
              ),
            ),
          ],
        ),
        content: const Text(
          'PsicoBloom utilizará el flujo seguro OAuth de Supabase. El sistema abrirá la ventana oficial de cuentas de Google sin solicitar tu contraseña dentro de la aplicación.\n\nEsta integración se conectará en la etapa de servicios.',
          style: TextStyle(
            color: TemaPsicobloom.colorTexto,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PantallaCompletarPerfil(
                    correoGoogle: 'ejemplo.usuario@gmail.com',
                    nombreSugerido: 'Carlos',
                  ),
                ),
              );
            },
            child: const Text('Ver pantalla completar perfil'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/imagenes/icono_psicobloom.png',
              width: 24,
              height: 24,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.local_florist_rounded,
                size: 20,
                color: TemaPsicobloom.colorPrincipal,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'PsicoBloom',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: TemaPsicobloom.colorTexto,
              ),
            ),
          ],
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
                const Text(
                  'Iniciar sesión',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Qué gusto verte de nuevo',
                  style: TextStyle(
                    fontSize: 15,
                    color: TemaPsicobloom.colorTextoSecundario,
                  ),
                ),
                const SizedBox(height: 28),

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
                      return 'Ingresa un formato de correo válido (ejemplo: usuario@correo.com)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Campo Contrasena
                const Text(
                  'Contraseña',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _controladorClave,
                  obscureText: !_mostrarClave,
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _mostrarClave
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _mostrarClave = !_mostrarClave;
                        });
                      },
                      tooltip: _mostrarClave
                          ? 'Ocultar contraseña'
                          : 'Mostrar contraseña',
                    ),
                  ),
                  validator: (valor) {
                    if (valor == null || valor.isEmpty) {
                      return 'Por favor ingresa tu contraseña';
                    }
                    if (valor.length < 6) {
                      return 'La contraseña debe tener al menos 6 caracteres';
                    }
                    return null;
                  },
                ),

                // Enlace a recuperar contrasena
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PantallaRecuperarClave(),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text('¿Olvidaste tu contraseña?'),
                  ),
                ),
                const SizedBox(height: 16),

                // Boton principal Iniciar sesion
                ElevatedButton(
                  onPressed: _estaCargando ? null : _ejecutarInicioSesion,
                  child: _estaCargando
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Iniciar sesión'),
                ),
                const SizedBox(height: 24),

                // Separador "o"
                Row(
                  children: [
                    const Expanded(
                      child: Divider(color: TemaPsicobloom.colorBorde, thickness: 1),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const Text(
                        'o',
                        style: TextStyle(
                          color: TemaPsicobloom.colorTextoSecundario,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const Expanded(
                      child: Divider(color: TemaPsicobloom.colorBorde, thickness: 1),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Boton Continuar con Google
                OutlinedButton(
                  onPressed: _continuarConGoogle,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: TemaPsicobloom.colorTexto,
                    side: const BorderSide(color: TemaPsicobloom.colorBorde, width: 1.2),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconoGoogle(tamano: 20),
                      SizedBox(width: 12),
                      Text(
                        'Continuar con Google',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: TemaPsicobloom.colorTexto,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Enlace a registro
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '¿No tienes una cuenta? ',
                      style: TextStyle(
                        color: TemaPsicobloom.colorTextoSecundario,
                        fontSize: 14,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const PantallaRegistroPasoUno(),
                          ),
                        );
                      },
                      child: const Text(
                        'Regístrate',
                        style: TextStyle(
                          color: TemaPsicobloom.colorPrincipal,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
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
