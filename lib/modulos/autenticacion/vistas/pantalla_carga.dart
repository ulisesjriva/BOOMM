import 'package:flutter/material.dart';

import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/nucleo/componentes/fondo_decorativo_bloom.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_opciones_acceso.dart';

/// Conserva la bienvenida; permite entregar la navegacion al coordinador de enlaces.
class PantallaCarga extends StatefulWidget {
  final VoidCallback? alFinalizarCarga;
  const PantallaCarga({super.key, this.alFinalizarCarga});

  @override
  State<PantallaCarga> createState() => _PantallaCargaState();
}

class _PantallaCargaState extends State<PantallaCarga> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _iniciarPrecargaYVerificacion();
    });
  }

  Future<void> _iniciarPrecargaYVerificacion() async {
    try {
      await precacheImage(
        const AssetImage('assets/imagenes/icono_psicobloom.png'),
        context,
      ).timeout(const Duration(milliseconds: 100), onTimeout: () {});
    } catch (_) {
      // La bienvenida puede continuar aunque no se precargue la imagen.
    }
    await Future.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    final alFinalizar = widget.alFinalizarCarga;
    if (alFinalizar != null) {
      alFinalizar();
      return;
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, animacion, animacionSecundaria) =>
            const PantallaOpcionesAcceso(),
        transitionsBuilder: (_, animacion, animacionSecundaria, child) =>
            FadeTransition(opacity: animacion, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaPsicobloom.colorFondo,
      body: FondoDecorativoBloom(
        mostrarHojas: true,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 175,
                    height: 175,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: TemaPsicobloom.colorPrincipal.withValues(
                            alpha: 0.12,
                          ),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/imagenes/icono_psicobloom.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, error, pila) => const Icon(
                        Icons.local_florist_rounded,
                        size: 90,
                        color: TemaPsicobloom.colorPrincipal,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'PsicoBloom',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF38236B),
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Tu camino hacia el bienestar\ncomienza con una\nconexión',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF544A63),
                      height: 1.35,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(
                      strokeWidth: 3.2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        TemaPsicobloom.colorPrincipal.withValues(alpha: 0.7),
                      ),
                      backgroundColor: TemaPsicobloom.colorLavanda,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Cargando...',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: TemaPsicobloom.colorTextoSecundario,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
