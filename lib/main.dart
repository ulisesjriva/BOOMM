import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'configuracion/configuracion_supabase.dart';
import 'modulos/autenticacion/modelos/enlace_autenticacion.dart';
import 'modulos/autenticacion/controladores/controlador_enlaces_autenticacion.dart';
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
    debugPrint('URL SUPABASE: ${ConfiguracionSupabase.url}');
debugPrint(
  'CLAVE CONFIGURADA: ${ConfiguracionSupabase.claveAnon.isNotEmpty}',
);
    await Supabase.initialize(
      url: ConfiguracionSupabase.url,
      publishableKey: ConfiguracionSupabase.claveAnon,
      authOptions: FlutterAuthClientOptions(
        detectSessionInUriPredicate: (uri) {
          // Los token_hash HTTPS los procesan nuestras pantallas con verifyOTP.
          // Conserva los antiguos callbacks del esquema propio para el SDK.
          if (EnlaceAutenticacion.esUrlWebPropia(uri)) return false;
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
  });

  /// Permite probar la navegacion sin abrir canales nativos de Android.
  /// Si no se proporciona, la aplicacion usa app_links como antes.
  final Stream<Uri>? flujoEnlaces;
  final Future<Uri?> Function()? obtenerEnlaceInicial;

  @override
  State<AplicacionPsicoBloom> createState() => _AplicacionPsicoBloomState();
}

class _AplicacionPsicoBloomState extends State<AplicacionPsicoBloom> {
  final _navegador = GlobalKey<NavigatorState>();
  final _mensajero = GlobalKey<ScaffoldMessengerState>();
  final _controladorEnlaces = ControladorEnlacesAutenticacion();

  @override
  void initState() {
    super.initState();
    _controladorEnlaces.addListener(_atenderCambiosDeEnlaces);
    if (widget.flujoEnlaces != null ||
        widget.obtenerEnlaceInicial != null ||
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)) {
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

  void _finalizarArranque() {
    if (!mounted) {
      return;
    }
    if (_controladorEnlaces.finalizarArranque()) {
      _abrirPendiente();
    } else {
      _navegador.currentState?.pushReplacement<void, void>(
        MaterialPageRoute<void>(builder: (_) => const PantallaOpcionesAcceso()),
      );
    }
  }

  void _abrirPendiente() {
    final navegador = _navegador.currentState;
    if (navegador == null) {
      return;
    }
    final enlace = _controladorEnlaces.tomarEnlacePendiente();
    if (enlace == null) {
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
