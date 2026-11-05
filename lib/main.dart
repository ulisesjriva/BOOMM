import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'configuracion/configuracion_supabase.dart';
import 'modelos/enlace_autenticacion.dart';
import 'nucleo/tema/tema_psicobloom.dart';
import 'pantallas/acceso/pantalla_carga.dart';
import 'pantallas/acceso/pantalla_iniciar_sesion.dart';
import 'pantallas/acceso/pantalla_nueva_clave.dart';
import 'pantallas/acceso/pantalla_opciones_acceso.dart';
import 'pantallas/registro/pantalla_verificar_correo.dart';

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
  StreamSubscription<Uri>? _suscripcion;
  EnlaceAutenticacion? _pendiente;
  String? _identidadActiva;
  String? _ultimaIdentidad;
  DateTime? _horaUltimoEnlace;
  bool _arranqueListo = false;

  @override
  void initState() {
    super.initState();
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
      _suscripcion = flujo.listen(
        _recibirEnlace,
        onError: (Object error, StackTrace pila) => _avisarErrorEnlace(),
      );
      final obtenerInicial = widget.obtenerEnlaceInicial;
      final Uri? inicial;
      if (obtenerInicial != null) {
        inicial = await obtenerInicial();
      } else {
        inicial = await enlaces?.getInitialLink();
      }
      if (mounted && inicial != null) _recibirEnlace(inicial);
    } catch (_) {
      if (mounted) _avisarErrorEnlace();
    }
  }

  void _avisarErrorEnlace() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mensajero.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo abrir el enlace. Intentalo de nuevo desde tu correo.',
          ),
        ),
      );
    });
  }

  void _recibirEnlace(Uri uri) {
    if (!mounted) return;
    final enlace = EnlaceAutenticacion.desdeUri(uri);
    if (enlace == null) return;
    final ahora = DateTime.now();
    final identidad = enlace.identidadEnMemoria;
    if (identidad == _identidadActiva ||
        (identidad == _ultimaIdentidad &&
            _horaUltimoEnlace != null &&
            ahora.difference(_horaUltimoEnlace!) <
                const Duration(seconds: 2))) {
      return;
    }
    _ultimaIdentidad = identidad;
    _horaUltimoEnlace = ahora;
    _pendiente = enlace;
    if (_identidadActiva != null) {
      _mensajero.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
            'Recibiste otro enlace. Termina o cierra el proceso actual para continuar.',
          ),
        ),
      );
    }
    _abrirPendiente();
  }

  void _finalizarArranque() {
    if (!mounted) return;
    _arranqueListo = true;
    if (_pendiente != null) {
      _abrirPendiente();
    } else {
      _navegador.currentState?.pushReplacement<void, void>(
        MaterialPageRoute<void>(builder: (_) => const PantallaOpcionesAcceso()),
      );
    }
  }

  void _abrirPendiente() {
    final navegador = _navegador.currentState;
    final enlace = _pendiente;
    if (!_arranqueListo ||
        _identidadActiva != null ||
        navegador == null ||
        enlace == null)
      return;
    _pendiente = null;
    _identidadActiva = enlace.identidadEnMemoria;
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
        _identidadActiva = null;
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _abrirPendiente();
        });
      }),
    );
  }

  @override
  void dispose() {
    unawaited(_suscripcion?.cancel());
    _pendiente = null;
    _identidadActiva = null;
    _ultimaIdentidad = null;
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
