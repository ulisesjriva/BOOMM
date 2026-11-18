import 'package:flutter/material.dart';
import 'package:boom/modulos/autenticacion/controladores/controlador_inicio_sesion.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_inicio_sesion.dart';
import 'package:boom/modulos/autenticacion/vistas/navegador_roles.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/nucleo/componentes/fondo_decorativo_bloom.dart';
import 'package:boom/nucleo/componentes/icono_google.dart';
import 'package:boom/nucleo/utilidades/traductor_errores_supabase.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_recuperar_clave.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_registro_paso_uno.dart';

/// Inicio de sesion real con correo y clave, conservando la identidad visual.
/// La opcion Google usa OAuth de Supabase igual que el acceso con correo.
class PantallaIniciarSesion extends StatefulWidget {
  const PantallaIniciarSesion({
    super.key,
    this.servicio = const ServicioInicioSesion(),
  });

  final ServicioInicioSesion servicio;

  @override
  State<PantallaIniciarSesion> createState() => _PantallaIniciarSesionState();
}

class _PantallaIniciarSesionState extends State<PantallaIniciarSesion> {
  final _claveFormulario = GlobalKey<FormState>();
  final _controladorCorreo = TextEditingController();
  final _controladorClave = TextEditingController();

  late final ControladorInicioSesion _controladorInicioSesion;

  bool _mostrarClave = false;
  bool _navegandoGoogle = false;
  bool get _estaCargando => _controladorInicioSesion.estaCargando;

  @override
  void initState() {
    super.initState();
    _controladorInicioSesion = ControladorInicioSesion(
      servicio: widget.servicio,
    );
    _controladorInicioSesion.addListener(_actualizarVista);
  }

  void _actualizarVista() {
    if (mounted) {
      setState(() {});
      final perfilGoogle = _controladorInicioSesion.perfilGoogle;
      if (perfilGoogle != null && !_navegandoGoogle) {
        _navegandoGoogle = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil<void>(
            MaterialPageRoute<void>(
              builder: (context) =>
                  NavegadorRoles.construirDestinoPorPerfil(perfilGoogle),
            ),
            (ruta) => false,
          );
        });
      }
    }
  }

  @override
  void dispose() {
    _controladorInicioSesion.removeListener(_actualizarVista);
    _controladorInicioSesion.dispose();
    _controladorCorreo.dispose();
    _controladorClave.dispose();
    super.dispose();
  }

  Future<void> _ejecutarInicioSesion() async {
    if (_estaCargando ||
        !(_claveFormulario.currentState?.validate() ?? false)) {
      return;
    }
    FocusScope.of(context).unfocus();
    final perfil = await _controladorInicioSesion.iniciarSesion(
      correo: _controladorCorreo.text,
      clave: _controladorClave.text,
    );
    if (!mounted) return;

    if (perfil == null) {
      final mensaje = _controladorInicioSesion.mensajeError;
      if (mensaje == null) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: TemaPsicobloom.colorPrincipalOscuro,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Text(
            mensaje,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

    _controladorClave.clear();
    Navigator.of(context).pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(
        builder: (context) => NavegadorRoles.construirDestinoPorPerfil(perfil),
      ),
      (ruta) => false,
    );
  }

  Future<void> _continuarConGoogle() async {
    if (_estaCargando) return;
    FocusScope.of(context).unfocus();
    final inicioCorrecto = await _controladorInicioSesion.iniciarConGoogle();
    if (!mounted || inicioCorrecto) return;
    final mensaje = _controladorInicioSesion.mensajeError;
    if (mensaje == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_estaCargando,
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
                      onPressed: _estaCargando
                          ? null
                          : () => Navigator.pop(context),
                      tooltip: 'Regresar',
                    ),
                  ),
                ),

                // Contenido con desplazamiento
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 4.0,
                    ),
                    child: Form(
                      key: _claveFormulario,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Mascota oficial de PsicoBloom
                          Center(
                            child: Container(
                              width: 105,
                              height: 105,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: TemaPsicobloom.colorPrincipal
                                        .withValues(alpha: 0.12),
                                    blurRadius: 18,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/imagenes/icono_psicobloom.png',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(
                                      Icons.local_florist_rounded,
                                      size: 64,
                                      color: TemaPsicobloom.colorPrincipal,
                                    ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Nombre de marca y subtitulo aprobados
                          const Text(
                            'PsicoBloom',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF38236B),
                              letterSpacing: -0.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Encuentra atención psicológica\ncerca de ti.',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: TemaPsicobloom.colorTextoSecundario,
                              height: 1.25,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),

                          // Titulo Iniciar sesion y saludo
                          const Text(
                            'Iniciar sesión',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: TemaPsicobloom.colorTexto,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Qué gusto verte de nuevo',
                            style: TextStyle(
                              fontSize: 14,
                              color: TemaPsicobloom.colorTextoSecundario,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),

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
                            enabled: !_estaCargando,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              hintText: 'tu@correo.com',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                            validator: TraductorErroresSupabase.validarCorreo,
                          ),
                          const SizedBox(height: 16),

                          // Campo Contrasena
                          const Text(
                            'Contraseña',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: TemaPsicobloom.colorTexto,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _controladorClave,
                            enabled: !_estaCargando,
                            obscureText: !_mostrarClave,
                            decoration: InputDecoration(
                              hintText: '••••••••',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
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
                                return 'Ingresa tu contraseña para continuar.';
                              }
                              if (valor.length < 6) {
                                return 'La contraseña debe tener al menos 6 caracteres.';
                              }
                              return null;
                            },
                          ),

                          // Enlace a recuperar contrasena
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _estaCargando
                                  ? null
                                  : () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const PantallaRecuperarClave(),
                                        ),
                                      );
                                    },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                              ),
                              child: const Text('¿Olvidaste tu contraseña?'),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Boton principal Iniciar sesion con flecha
                          ElevatedButton(
                            onPressed: _estaCargando
                                ? null
                                : _ejecutarInicioSesion,
                            child: _estaCargando
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
                                      Text('Iniciar sesión'),
                                      SizedBox(width: 8),
                                      Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 20,
                                      ),
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
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 14),
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

                          // Boton Continuar con Google
                          OutlinedButton(
                            onPressed: _estaCargando
                                ? null
                                : _continuarConGoogle,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: TemaPsicobloom.colorTexto,
                              side: const BorderSide(
                                color: TemaPsicobloom.colorBorde,
                                width: 1.2,
                              ),
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
                          const SizedBox(height: 20),

                          // Enlace a registro
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                '¿No tienes una cuenta? ',
                                style: TextStyle(
                                  color: TemaPsicobloom.colorTextoSecundario,
                                  fontSize: 13.5,
                                ),
                              ),
                              GestureDetector(
                                onTap: _estaCargando
                                    ? null
                                    : () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                const PantallaRegistroPasoUno(),
                                          ),
                                        );
                                      },
                                child: const Text(
                                  'Regístrate',
                                  style: TextStyle(
                                    color: TemaPsicobloom.colorPrincipal,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
