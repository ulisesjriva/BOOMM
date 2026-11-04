import 'package:flutter/material.dart';
import '../../nucleo/tema/tema_psicobloom.dart';
import '../../nucleo/componentes/fondo_decorativo_bloom.dart';
import '../../nucleo/componentes/icono_google.dart';
import 'pantalla_iniciar_sesion.dart';
import '../registro/pantalla_registro_paso_uno.dart';
import '../registro/pantalla_completar_perfil.dart';

/// Pantalla donde el usuario elige su metodo de acceso:
/// Iniciar sesion, Crear una cuenta o Continuar con Google.
class PantallaOpcionesAcceso extends StatelessWidget {
  const PantallaOpcionesAcceso({super.key});

  void _continuarConGoogle(BuildContext context) {
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
          'PsicoBloom conectará de forma segura con Google mediante OAuth en Supabase sin pedir contraseñas externas dentro de la app.\n\n¿Deseas previsualizar la pantalla de completar perfil para nuevos usuarios?',
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
                    correoGoogle: 'usuario.nuevo@gmail.com',
                    nombreSugerido: 'Sara',
                  ),
                ),
              );
            },
            child: const Text('Ver completar perfil'),
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
    final tamano = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: TemaPsicobloom.colorFondo,
      body: FondoDecorativoBloom(
        mostrarHojas: true,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: tamano.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom - 32,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),

                  // Cabecera con la identidad y mascota
                  Column(
                    children: [
                      Container(
                        width: 125,
                        height: 125,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: TemaPsicobloom.colorPrincipal.withOpacity(0.10),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/imagenes/icono_psicobloom.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => const Icon(
                            Icons.local_florist_rounded,
                            size: 70,
                            color: TemaPsicobloom.colorPrincipal,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'PsicoBloom',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF38236B),
                          letterSpacing: -0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tu camino hacia el bienestar comienza con una conexión',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: TemaPsicobloom.colorTextoSecundario,
                          height: 1.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),

                  // Tarjeta con las opciones de acceso principales
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 24),
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: TemaPsicobloom.colorSuperficie,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: TemaPsicobloom.colorBorde, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: TemaPsicobloom.colorPrincipal.withOpacity(0.06),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Bienvenido a PsicoBloom',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: TemaPsicobloom.colorTexto,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Selecciona cómo deseas acceder a la plataforma',
                          style: TextStyle(
                            fontSize: 13,
                            color: TemaPsicobloom.colorTextoSecundario,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),

                        // Opcion 1: Iniciar sesion
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
                              Icon(Icons.login_rounded, size: 20),
                              SizedBox(width: 8),
                              Text('Iniciar sesión'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Opcion 2: Crear una cuenta
                        OutlinedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const PantallaRegistroPasoUno(),
                              ),
                            );
                          },
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person_add_outlined, size: 20),
                              SizedBox(width: 8),
                              Text('Crear una cuenta'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Separador "o"
                        Row(
                          children: [
                            const Expanded(
                              child: Divider(color: TemaPsicobloom.colorBorde, thickness: 1),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              child: Text(
                                'o',
                                style: TextStyle(
                                  color: TemaPsicobloom.colorTextoSecundario,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const Expanded(
                              child: Divider(color: TemaPsicobloom.colorBorde, thickness: 1),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // Opcion 3: Continuar con Google
                        OutlinedButton(
                          onPressed: () => _continuarConGoogle(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: TemaPsicobloom.colorTexto,
                            side: const BorderSide(color: TemaPsicobloom.colorBorde, width: 1.2),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconoGoogle(tamano: 20),
                              SizedBox(width: 10),
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
                      ],
                    ),
                  ),

                  // Mensaje informativo inferior
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      'Atención psicológica accesible y profesional en Riobamba.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: TemaPsicobloom.colorTextoSecundario,
                      ),
                      textAlign: TextAlign.center,
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

