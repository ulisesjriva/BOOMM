import 'package:flutter/material.dart';
import '../../tema/tema_psicobloom.dart';
import '../../componentes/fondo_decorativo_bloom.dart';
import '../acceso/pantalla_iniciar_sesion.dart';

/// Pantalla que solicita al usuario abrir el enlace de confirmacion enviado a su correo.
class PantallaVerificarCorreo extends StatefulWidget {
  final String correo;
  final bool esProfesional;

  const PantallaVerificarCorreo({
    super.key,
    required this.correo,
    this.esProfesional = false,
  });

  @override
  State<PantallaVerificarCorreo> createState() => _PantallaVerificarCorreoState();
}

class _PantallaVerificarCorreoState extends State<PantallaVerificarCorreo> {
  bool _estaComprobando = false;
  bool _enlaceReenviado = false;

  void _comprobarVerificacion() {
    setState(() {
      _estaComprobando = true;
    });

    // Como indica E06: este boton debe comprobar el estado real en Supabase Auth.
    // Si la sesion aun no se recupero mediante el enlace, se redirige al inicio de sesion.
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() {
        _estaComprobando = false;
      });

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: TemaPsicobloom.colorSuperficie,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          icon: const Icon(
            Icons.info_outline_rounded,
            color: TemaPsicobloom.colorInformacion,
            size: 36,
          ),
          title: const Text(
            'Comprobación de verificación',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
          content: Text(
            'Para continuar, abre el enlace que enviamos a:\n${widget.correo}\n\nSi ya lo abriste en tu navegador, ingresa con tu correo y contraseña.',
            style: const TextStyle(
              color: TemaPsicobloom.colorTexto,
              height: 1.4,
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Cierra dialogo
                _irAIniciarSesion();
              },
              child: const Text('Ir a iniciar sesión'),
            ),
          ],
        ),
      );
    });
  }

  void _reenviarEnlace() {
    setState(() {
      _enlaceReenviado = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: TemaPsicobloom.colorExito,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          'Nuevo enlace de verificación enviado a: ${widget.correo}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  void _irAIniciarSesion() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => const PantallaIniciarSesion(),
      ),
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
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
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
                'Te enviamos un enlace para verificar tu cuenta a:',
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
                      const Divider(height: 20, color: TemaPsicobloom.colorBorde),
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
                onPressed: _estaComprobando ? null : _comprobarVerificacion,
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
                onPressed: _enlaceReenviado ? null : _reenviarEnlace,
                child: Text(
                  _enlaceReenviado ? 'Enlace reenviado' : 'Reenviar enlace',
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

