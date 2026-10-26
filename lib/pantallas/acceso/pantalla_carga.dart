import 'package:flutter/material.dart';
import '../../tema/tema_psicobloom.dart';
import '../../componentes/fondo_decorativo_bloom.dart';
import 'pantalla_opciones_acceso.dart';

/// Pantalla de bienvenida y carga ultra ligera que precarga texturas y recursos
/// antes de dirigir al usuario a la pantalla de opciones de acceso o a su sesion activa.
class PantallaCarga extends StatefulWidget {
  const PantallaCarga({super.key});

  @override
  State<PantallaCarga> createState() => _PantallaCargaState();
}

class _PantallaCargaState extends State<PantallaCarga> {
  @override
  void initState() {
    super.initState();
    // Inicia la precarga y comprobacion al completar el primer cuadro de dibujo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _iniciarPrecargaYVerificacion();
    });
  }

  Future<void> _iniciarPrecargaYVerificacion() async {
    // 1. Precarga en memoria grafica las imagenes clave para evitar parpadeos
    try {
      await precacheImage(
        const AssetImage('assets/imagenes/icono_psicobloom.png'),
        context,
      );
    } catch (_) {
      // Si la precarga falla o es ignorada, la aplicacion continua sin bloquearse
    }

    // 2. Tiempo optimo para exhibir la marca e inicializar servicios sin saturar la app
    await Future.delayed(const Duration(milliseconds: 1600));

    if (!mounted) return;

    // 3. Transicion suave hacia la seleccion de acceso
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animacion, animacionSecundaria) =>
            const PantallaOpcionesAcceso(),
        transitionsBuilder: (context, animacion, animacionSecundaria, child) {
          return FadeTransition(opacity: animacion, child: child);
        },
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
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Imagen oficial de la mascota de PsicoBloom
                  Container(
                    width: 175,
                    height: 175,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: TemaPsicobloom.colorPrincipal.withOpacity(0.12),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/imagenes/icono_psicobloom.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.local_florist_rounded,
                        size: 90,
                        color: TemaPsicobloom.colorPrincipal,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Nombre de la aplicacion
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

                  // Eslogan oficial en 3 lineas tal como el diseno aprobado
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

                  // Indicador circular de carga en color lavanda/morado suave
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(
                      strokeWidth: 3.2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        TemaPsicobloom.colorPrincipal.withOpacity(0.7),
                      ),
                      backgroundColor: TemaPsicobloom.colorLavanda,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Texto descriptivo de carga
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

