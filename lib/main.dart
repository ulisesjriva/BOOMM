import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'configuracion/configuracion_supabase.dart';
import 'modulos/autenticacion/modelos/enlace_autenticacion.dart';
import 'modulos/autenticacion/controladores/controlador_enlaces_autenticacion.dart';
import 'modulos/autenticacion/servicios/servicio_sesion.dart';
import 'modulos/autenticacion/vistas/navegador_roles.dart';
import 'modulos/autenticacion/vistas/pantalla_estado_cuenta.dart';
import 'nucleo/tema/tema_psicobloom.dart';
import 'modulos/autenticacion/vistas/pantalla_carga.dart';
import 'modulos/autenticacion/vistas/pantalla_iniciar_sesion.dart';
import 'modulos/autenticacion/vistas/pantalla_nueva_clave.dart';
import 'modulos/autenticacion/vistas/pantalla_opciones_acceso.dart';
import 'modulos/autenticacion/vistas/pantalla_verificar_correo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Instancia temprana; el enlace inicial tambien se recupera una sola vez.
  AppLinks();
  if (ConfiguracionSupabase.estaConfigurado) {
    await Supabase.initialize(
      url: ConfiguracionSupabase.url,
      publishableKey: ConfiguracionSupabase.claveAnon,
      authOptions: FlutterAuthClientOptions(
        detectSessionInUriPredicate: (uri) {
          // El SDK procesa el callback OAuth web; token_hash sigue a cargo
          // de nuestras pantallas de confirmacion y recuperacion.
          if (kIsWeb) {
            try {
              final valores = {
                ...uri.queryParameters,
                ...Uri.splitQueryString(uri.fragment),
              };
              if (valores.containsKey('token_hash')) return false;
              return [
                'code',
                'access_token',
                'error',
                'error_code',
                'error_description',
              ].any(valores.containsKey);
            } on FormatException {
              return false;
            }
          }
          if (EnlaceAutenticacion.esUrlWebPropia(uri)) return false;
          // Conserva los callbacks del esquema propio para el SDK.
          if (uri.scheme != 'psicobloom' || uri.host != 'acceso') return false;
          try {
            final valores = {
              ...uri.queryParameters,
              ...Uri.splitQueryString(uri.fragment),
            };
            if (valores.containsKey('token_hash')) return false;
            return [
              'code',
              'access_token',
              'error',
              'error_code',
              'error_description',
            ].any(valores.containsKey);
          } on FormatException {
            return false;
          }
        },
      ),
    );
  } else {
    debugPrint('[PsicoBloom] Falta SUPABASE_URL o SUPABASE_ANON_KEY.');
  }
  runApp(const AplicacionPsicoBloom());
}

class AplicacionPsicoBloom extends StatefulWidget {
  const AplicacionPsicoBloom({
    super.key,
    this.flujoEnlaces,
    this.obtenerEnlaceInicial,
    this.servicioSesion = const ServicioSesion(),
  });

  /// Permite probar la navegacion sin abrir canales nativos de Android.
  /// Si no se proporciona, la aplicacion usa app_links como antes.
  final Stream<Uri>? flujoEnlaces;
  final Future<Uri?> Function()? obtenerEnlaceInicial;
  final ServicioSesion servicioSesion;

  @override
  State<AplicacionPsicoBloom> createState() => _AplicacionPsicoBloomState();
}

class _AplicacionPsicoBloomState extends State<AplicacionPsicoBloom> {
  final _navegador = GlobalKey<NavigatorState>();
  final _mensajero = GlobalKey<ScaffoldMessengerState>();
  final _controladorEnlaces = ControladorEnlacesAutenticacion();
  Future<ResultadoResolucionSesion>? _resolucionSesion;
  bool _resolviendoArranque = false;

  @override
  void initState() {
    super.initState();
    _controladorEnlaces.addListener(_atenderCambiosDeEnlaces);
    _resolucionSesion = widget.servicioSesion.resolverSesionActual();
    if (widget.flujoEnlaces != null ||
        widget.obtenerEnlaceInicial != null ||
        !kIsWeb) {
      unawaited(_escucharEnlaces());
    }
  }

  Future<void> _escucharEnlaces() async {
    try {
      final usaFuenteSimulada =
          widget.flujoEnlaces != null || widget.obtenerEnlaceInicial != null;
      final enlaces = usaFuenteSimulada ? null : AppLinks();
      final flujo =
          widget.flujoEnlaces ??
          enlaces?.uriLinkStream ??
          const Stream<Uri>.empty();
      await _controladorEnlaces.escuchar(
        flujo: flujo,
        obtenerInicial: widget.obtenerEnlaceInicial ?? enlaces?.getInitialLink,
      );
    } catch (_) {
      _controladorEnlaces.avisarErrorEscucha();
    }
  }

  void _atenderCambiosDeEnlaces() {
    if (!mounted) {
      return;
    }
    final aviso = _controladorEnlaces.tomarAviso();
    if (aviso != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _mensajero.currentState?.showSnackBar(SnackBar(content: Text(aviso)));
      });
    }
    _abrirPendiente();
  }

  Future<void> _finalizarArranque() async {
    if (!mounted || _resolviendoArranque) {
      return;
    }
    _resolviendoArranque = true;
    try {
      // Los enlaces de confirmacion y recuperacion conservan la prioridad
      // para que una sesion persistente nunca interrumpa un cambio de clave.
      if (_controladorEnlaces.finalizarArranque()) {
        _abrirPendiente();
        return;
      }

      final resultado =
          await (_resolucionSesion ??
              widget.servicioSesion.resolverSesionActual());
      if (!mounted) {
        return;
      }
      // Si llego un enlace mientras se resolvia la sesion, tiene prioridad.
      final enlaceTardio = _controladorEnlaces.tomarEnlacePendiente();
      if (enlaceTardio != null) {
        _abrirEnlace(enlaceTardio);
        return;
      }

      _navegarSegunResultadoSesion(resultado);
    } finally {
      _resolviendoArranque = false;
    }
  }

  void _navegarSegunResultadoSesion(ResultadoResolucionSesion resultado) {
    final navegador = _navegador.currentState;
    if (navegador == null) return;

    if (resultado.mensaje != null &&
        resultado.estado == EstadoResolucionSesion.sinSesion) {
      _mensajero.currentState?.showSnackBar(
        SnackBar(content: Text(resultado.mensaje!)),
      );
    }

    final Widget destino = switch (resultado.estado) {
      EstadoResolucionSesion.autenticado when resultado.perfil != null =>
        NavegadorRoles.construirDestinoPorPerfil(
          resultado.perfil!,
          servicioSesion: widget.servicioSesion,
        ),
      EstadoResolucionSesion.cuentaInactiva => PantallaEstadoCuenta(
        perfil: resultado.perfil,
        mensaje:
            resultado.mensaje ??
            'Tu cuenta está inactiva. Contacta al administrador.',
        servicioSesion: widget.servicioSesion,
      ),
      EstadoResolucionSesion.errorConexion => PantallaEstadoCuenta(
        titulo: 'Error de conexión',
        mensaje:
            resultado.mensaje ??
            'No se pudo comprobar tu sesión por un problema de red.',
        servicioSesion: widget.servicioSesion,
        alReintentar: () {
          _resolucionSesion = widget.servicioSesion.resolverSesionActual();
          unawaited(_reintentarSesion());
        },
      ),
      _ => const PantallaOpcionesAcceso(),
    };

    navegador.pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(builder: (_) => destino),
      (_) => false,
    );
  }

  Future<void> _reintentarSesion() async {
    final resultado = await widget.servicioSesion.resolverSesionActual();
    if (!mounted) return;
    _navegarSegunResultadoSesion(resultado);
  }

  void _abrirPendiente() {
    final enlace = _controladorEnlaces.tomarEnlacePendiente();
    if (enlace == null) {
      return;
    }
    _abrirEnlace(enlace);
  }

  void _abrirEnlace(EnlaceAutenticacion enlace) {
    final navegador = _navegador.currentState;
    if (navegador == null) {
      return;
    }
    final Widget pantalla = switch (enlace.tipo) {
      TipoEnlaceAutenticacion.recuperacion => PantallaNuevaClave(
        enlace: enlace,
      ),
      TipoEnlaceAutenticacion.abrirAcceso => const PantallaIniciarSesion(),
      _ => PantallaVerificarCorreo.desdeEnlace(enlace: enlace),
    };
    final cierre = navegador.pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(builder: (_) => pantalla),
      (_) => false,
    );
    unawaited(
      cierre.whenComplete(() {
        _controladorEnlaces.finalizarProcesoActual();
        if (!mounted) {
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _abrirPendiente();
        });
      }),
    );
  }

  @override
  void dispose() {
    _controladorEnlaces.removeListener(_atenderCambiosDeEnlaces);
    _controladorEnlaces.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PsicoBloom',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navegador,
      scaffoldMessengerKey: _mensajero,
      theme: TemaPsicobloom.obtenerTema(),
      home: PantallaCarga(alFinalizarCarga: _finalizarArranque),
    );
  }
}
