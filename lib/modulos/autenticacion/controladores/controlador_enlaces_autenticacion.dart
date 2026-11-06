import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:boom/modulos/autenticacion/modelos/enlace_autenticacion.dart';

/// Coordina enlaces en memoria; la aplicacion decide como navegar.
class ControladorEnlacesAutenticacion extends ChangeNotifier {
  ControladorEnlacesAutenticacion({DateTime Function()? obtenerHora})
    : _obtenerHora = obtenerHora ?? DateTime.now;

  final DateTime Function() _obtenerHora;
  StreamSubscription<Uri>? _suscripcion;
  EnlaceAutenticacion? _pendiente;
  String? _identidadActiva;
  String? _ultimaIdentidad;
  DateTime? _horaUltimoEnlace;
  String? _aviso;
  bool _arranqueListo = false;
  bool _escuchaIniciada = false;
  bool _cerrado = false;
  Future<void>? _cierre;

  Future<void> escuchar({
    required Stream<Uri> flujo,
    Future<Uri?> Function()? obtenerInicial,
  }) async {
    if (_cerrado || _escuchaIniciada) {
      return;
    }
    _escuchaIniciada = true;
    try {
      _suscripcion = flujo.listen(
        recibirEnlace,
        onError: (Object error, StackTrace pila) => avisarErrorEscucha(),
      );
      final inicial = await obtenerInicial?.call();
      if (!_cerrado && inicial != null) {
        recibirEnlace(inicial);
      }
    } catch (_) {
      avisarErrorEscucha();
    }
  }

  void avisarErrorEscucha() {
    if (_cerrado) {
      return;
    }
    _aviso = 'No se pudo abrir el enlace. Intentalo de nuevo desde tu correo.';
    notifyListeners();
  }

  void recibirEnlace(Uri uri) {
    if (_cerrado) {
      return;
    }
    final enlace = EnlaceAutenticacion.desdeUri(uri);
    if (enlace == null) {
      return;
    }
    final ahora = _obtenerHora();
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
    // Conserva el ultimo enlace pendiente, como hacia main.dart.
    _pendiente = enlace;
    if (_identidadActiva != null) {
      _aviso = 'Recibiste otro enlace. Termina o cierra el proceso actual para continuar.';
    }
    notifyListeners();
  }

  /// Devuelve si hay un enlace que deba abrirse en lugar de las opciones.
  bool finalizarArranque() {
    if (_cerrado) {
      return false;
    }
    _arranqueListo = true;
    return _pendiente != null;
  }

  /// Reserva un unico proceso cuando el navegador ya esta disponible.
  EnlaceAutenticacion? tomarEnlacePendiente() {
    if (_cerrado || !_arranqueListo || _identidadActiva != null) {
      return null;
    }
    final enlace = _pendiente;
    if (enlace == null) {
      return null;
    }
    _pendiente = null;
    _identidadActiva = enlace.identidadEnMemoria;
    return enlace;
  }

  String? tomarAviso() {
    if (_cerrado) {
      return null;
    }
    final aviso = _aviso;
    _aviso = null;
    return aviso;
  }

  void finalizarProcesoActual() {
    if (!_cerrado) {
      _identidadActiva = null;
    }
  }

  Future<void> cerrar() {
    if (_cerrado) {
      return _cierre ?? Future<void>.value();
    }
    _cerrado = true;
    _pendiente = null;
    _identidadActiva = null;
    _ultimaIdentidad = null;
    _horaUltimoEnlace = null;
    _aviso = null;
    return _cierre = _suscripcion?.cancel() ?? Future<void>.value();
  }

  @override
  void dispose() {
    unawaited(cerrar());
    super.dispose();
  }
}
