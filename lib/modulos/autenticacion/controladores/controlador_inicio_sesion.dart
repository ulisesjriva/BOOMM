import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_inicio_sesion.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_sesion.dart';

/// Coordina el acceso sin almacenar credenciales ni depender de la navegacion.
class ControladorInicioSesion extends ChangeNotifier {
  ControladorInicioSesion({this.servicio = const ServicioInicioSesion()});

  final ServicioInicioSesion servicio;
  bool _estaCargando = false;
  bool _cerrado = false;
  String? _mensajeError;
  StreamSubscription<AuthState>? _escuchaGoogle;
  PerfilUsuario? _perfilGoogle;
  bool _esperaGoogle = false;

  bool get estaCargando => _estaCargando;
  String? get mensajeError => _mensajeError;
  PerfilUsuario? get perfilGoogle => _perfilGoogle;

  Future<PerfilUsuario?> iniciarSesion({
    required String correo,
    required String clave,
  }) async {
    if (_cerrado || _estaCargando) return null;
    _estaCargando = true;
    _mensajeError = null;
    notifyListeners();
    try {
      final perfil = await servicio.iniciarSesionPaciente(
        correo: correo.trim(),
        clave: clave,
      );
      if (_cerrado) return null;
      return perfil;
    } catch (error) {
      debugPrint('[PsicoBloom] Error en iniciarSesion: $error');
      if (!_cerrado) {
        _mensajeError = ServicioInicioSesion.explicarError(error);
      }
      return null;
    } finally {
      if (!_cerrado) {
        _estaCargando = false;
        notifyListeners();
      }
    }
  }

  /// Abre el flujo OAuth; el SDK de Supabase procesa el enlace de retorno.
  Future<bool> iniciarConGoogle() async {
    if (_cerrado || _estaCargando) return false;
    _estaCargando = true;
    _mensajeError = null;
    _perfilGoogle = null;
    _esperaGoogle = true;
    notifyListeners();
    try {
      if (!ConfiguracionSupabase.estaConfigurado) {
        throw const ErrorInicioSesion(
          'El servicio de acceso no está disponible en este momento. Inténtalo más tarde.',
        );
      }
      final cliente = Supabase.instance.client;
      _escuchaGoogle ??= cliente.auth.onAuthStateChange.listen((estado) {
        if (estado.event == AuthChangeEvent.signedIn && _esperaGoogle) {
          if (estado.session?.user.appMetadata['provider'] == 'google') {
            unawaited(_resolverPerfilGoogle());
          } else {
            _esperaGoogle = false;
          }
        }
      });
      await servicio.iniciarConGoogle();
      return true;
    } catch (error) {
      _esperaGoogle = false;
      if (!_cerrado) {
        _mensajeError = ServicioInicioSesion.explicarError(error);
      }
      return false;
    } finally {
      if (!_cerrado) {
        _estaCargando = false;
        notifyListeners();
      }
    }
  }

  Future<void> _resolverPerfilGoogle() async {
    final resultado = await const ServicioSesion().resolverSesionActual();
    if (_cerrado || !_esperaGoogle) return;
    if (resultado.perfil != null) {
      _perfilGoogle = resultado.perfil;
    } else {
      _mensajeError =
          resultado.mensaje ??
          'No se pudo cargar el perfil de tu cuenta. Inténtalo nuevamente.';
    }
    _esperaGoogle = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _cerrado = true;
    unawaited(_escuchaGoogle?.cancel());
    super.dispose();
  }
}
