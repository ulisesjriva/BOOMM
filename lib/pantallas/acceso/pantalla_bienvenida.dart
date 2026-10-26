import 'package:flutter/material.dart';
import '../../tema/tema_psicobloom.dart';
import 'pantalla_iniciar_sesion.dart';
import '../registro/pantalla_registro_paso_uno.dart';

/// Pantalla inicial de bienvenida que presenta la identidad y proposito de PsicoBloom.
class PantallaBienvenida extends StatelessWidget {
  const PantallaBienvenida({super.key});

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: TemaPsicobloom.colorFondo,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: tamano.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom - 40,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),

                // Seccion de identidad de marca (logo, nombre y lema)
                Column(
                  children: [
                    // Contenedor decorativo suave para la mascota/icono
                    Container(
                      width: 130,
                      height: 130,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: TemaPsicobloom.colorLavanda,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: TemaPsicobloom.colorPrincipal.withOpacity(0.08),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/imagenes/icono_psicobloom.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.local_florist_rounded,
                              size: 64,
                              color: TemaPsicobloom.colorPrincipal,
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'PsicoBloom',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: TemaPsicobloom.colorTexto,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Tu camino hacia el bienestar\ncomienza con una conexión',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: TemaPsicobloom.colorTextoSecundario,
                        height: 1.35,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Tarjeta informativa con la descripcion aprobada
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: TemaPsicobloom.colorSuperficie,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: TemaPsicobloom.colorBorde, width: 1),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: TemaPsicobloom.colorPrincipal,
                        size: 24,
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Encuentra profesionales de atención psicológica en Riobamba, consulta su disponibilidad y solicita una cita.',
                          style: TextStyle(
                            fontSize: 14,
                            color: TemaPsicobloom.colorTexto,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 36),

                // Botones de accion para acceder a la aplicacion
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const PantallaIniciarSesion(),
                          ),
                        );
                      },
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Iniciar sesión'),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, size: 20),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const PantallaRegistroPasoUno(),
                          ),
                        );
                      },
                      child: const Text('Crear cuenta'),
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
