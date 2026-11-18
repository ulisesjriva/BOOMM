import 'package:flutter/material.dart';
import 'package:boom/modulos/autenticacion/controladores/controlador_inicio_sesion.dart';
import 'package:boom/modulos/autenticacion/vistas/navegador_roles.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/nucleo/componentes/fondo_decorativo_bloom.dart';
import 'package:boom/nucleo/componentes/icono_google.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_iniciar_sesion.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_registro_paso_uno.dart';

/// Pantalla donde el usuario elige su metodo de acceso:
/// Iniciar sesion, Crear una cuenta o Continuar con Google.
class PantallaOpcionesAcceso extends StatefulWidget {
  const PantallaOpcionesAcceso({super.key});

  @override
  State<PantallaOpcionesAcceso> createState() => _PantallaOpcionesAccesoState();
}

class _PantallaOpcionesAccesoState extends State<PantallaOpcionesAcceso> {
  late final ControladorInicioSesion _controlador;
  bool _navegandoGoogle = false;

  @override
  void initState() {
    super.initState();
    _controlador = ControladorInicioSesion()..addListener(_actualizarVista);
  }

  void _actualizarVista() {
    if (!mounted) return;
    setState(() {});
    final perfil = _controlador.perfilGoogle;
    if (perfil != null && !_navegandoGoogle) {
      _navegandoGoogle = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil<void>(
          MaterialPageRoute<void>(
            builder: (_) => NavegadorRoles.construirDestinoPorPerfil(perfil),
          ),
          (ruta) => false,
        );
      });
    }
  }

  @override
  void dispose() {
    _controlador.removeListener(_actualizarVista);
    _controlador.dispose();
    super.dispose();
  }

  Future<void> _continuarConGoogle() async {
    if (_controlador.estaCargando) return;
    final inicioCorrecto = await _controlador.iniciarConGoogle();
    if (!mounted || inicioCorrecto) return;
    final mensaje = _controlador.mensajeError;
    if (mensaje != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensaje)));
    }
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
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 16.0,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    tamano.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom -
                    32,
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
                              color: TemaPsicobloom.colorPrincipal.withValues(
                                alpha: 0.10,
                              ),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/imagenes/icono_psicobloom.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
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
                      border: Border.all(
                        color: TemaPsicobloom.colorBorde,
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: TemaPsicobloom.colorPrincipal.withValues(
                            alpha: 0.06,
                          ),
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
                                builder: (context) =>
                                    const PantallaIniciarSesion(),
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
                                builder: (context) =>
                                    const PantallaRegistroPasoUno(),
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
                              child: Divider(
                                color: TemaPsicobloom.colorBorde,
                                thickness: 1,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              child: Text(
                                'o',
                                style: TextStyle(
                                  color: TemaPsicobloom.colorTextoSecundario,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const Expanded(
                              child: Divider(
                                color: TemaPsicobloom.colorBorde,
                                thickness: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // Opcion 3: Continuar con Google
                        OutlinedButton(
                          onPressed: _controlador.estaCargando
                              ? null
                              : _continuarConGoogle,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: TemaPsicobloom.colorTexto,
                            side: const BorderSide(
                              color: TemaPsicobloom.colorBorde,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const IconoGoogle(tamano: 20),
                              const SizedBox(width: 10),
                              Text(
                                _controlador.estaCargando
                                    ? 'Conectando con Google…'
                                    : 'Continuar con Google',
                                style: const TextStyle(
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
