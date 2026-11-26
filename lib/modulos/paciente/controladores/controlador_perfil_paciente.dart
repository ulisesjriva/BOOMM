import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_sesion.dart';
import 'package:boom/modulos/paciente/servicios/servicio_perfil_paciente.dart';

/// Coordina la carga, edicion, vista previa local de fotografia, guardado en Supabase
/// y cierre de sesion del perfil del paciente.
class ControladorPerfilPaciente extends ChangeNotifier {
  ControladorPerfilPaciente({
    this.servicio = const ServicioPerfilPaciente(),
    this.servicioSesion = const ServicioSesion(),
    PerfilUsuario? perfilInicial,
  }) : _perfil = perfilInicial;

  final ServicioPerfilPaciente servicio;
  final ServicioSesion servicioSesion;

  PerfilUsuario? _perfil;
  ArchivoFotoPacienteSeleccionada? _fotoVistaPrevia;
  bool _estaCargando = false;
  bool _estaGuardando = false;
  bool _estaSeleccionandoFoto = false;
  bool _estaCerrandoSesion = false;
  bool _cerrado = false;
  String? _mensajeError;
  String? _mensajeExito;
  String? _mensajeErrorFoto;

  PerfilUsuario? get perfil => _perfil;
  ArchivoFotoPacienteSeleccionada? get fotoVistaPrevia => _fotoVistaPrevia;
  bool get tieneFotoVistaPrevia => _fotoVistaPrevia != null;
  bool get estaCargando => _estaCargando;
  bool get estaGuardando => _estaGuardando;
  bool get estaSeleccionandoFoto => _estaSeleccionandoFoto;
  bool get estaCerrandoSesion => _estaCerrandoSesion;
  bool get ocupado =>
      _estaCargando ||
      _estaGuardando ||
      _estaSeleccionandoFoto ||
      _estaCerrandoSesion;
  String? get mensajeError => _mensajeError;
  String? get mensajeExito => _mensajeExito;
  String? get mensajeErrorFoto => _mensajeErrorFoto;

  static String? validarNombreOApellido(String? valor, String campo) {
    final limpio = valor?.trim() ?? '';
    if (limpio.isEmpty) {
      return 'Ingresa tu $campo.';
    }
    if (limpio.length < 2) {
      return 'El $campo debe tener al menos 2 caracteres.';
    }
    return null;
  }

  Future<PerfilUsuario?> cargarPerfil() async {
    if (_cerrado || _estaCargando) return _perfil;
    _estaCargando = true;
    _mensajeError = null;
    _mensajeExito = null;
    notifyListeners();

    try {
      final perfilServidor = await servicio.obtenerPerfilPropio();
      if (_cerrado) return null;
      _perfil = perfilServidor;
      return perfilServidor;
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioPerfilPaciente.explicarError(error);
      }
      return null;
    } finally {
      if (!_cerrado) {
        _estaCargando = false;
        notifyListeners();
      }
    }
  }

  Future<bool> guardarPerfil({
    required String nombre,
    required String apellido,
  }) async {
    if (_cerrado || ocupado) return false;

    final errorNombre = validarNombreOApellido(nombre, 'nombre');
    if (errorNombre != null) {
      _mensajeError = errorNombre;
      _mensajeExito = null;
      notifyListeners();
      return false;
    }

    final errorApellido = validarNombreOApellido(apellido, 'apellido');
    if (errorApellido != null) {
      _mensajeError = errorApellido;
      _mensajeExito = null;
      notifyListeners();
      return false;
    }

    _estaGuardando = true;
    _mensajeError = null;
    _mensajeExito = null;
    notifyListeners();

    try {
      final perfilActualizado = await servicio.actualizarDatosBasicos(
        nombre: nombre.trim(),
        apellido: apellido.trim(),
      );
      if (_cerrado) return false;
      _perfil = perfilActualizado;
      _mensajeExito = 'Tu perfil se actualizó correctamente en PsicoBloom.';
      return true;
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioPerfilPaciente.explicarError(error);
      }
      return false;
    } finally {
      if (!_cerrado) {
        _estaGuardando = false;
        notifyListeners();
      }
    }
  }

  Future<bool> solicitarCambioCorreo(String nuevoCorreo) async {
    if (_cerrado || ocupado) return false;
    final correoLimpio = nuevoCorreo.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(correoLimpio)) {
      _mensajeError = 'Ingresa un correo electrónico válido.';
      _mensajeExito = null;
      notifyListeners();
      return false;
    }

    _estaGuardando = true;
    _mensajeError = null;
    _mensajeExito = null;
    notifyListeners();

    try {
      await servicio.solicitarCambioCorreo(correoLimpio);
      if (_cerrado) return false;
      _mensajeExito = 'Se envió la solicitud de confirmación al nuevo correo. Confírmalo desde tu bandeja para completar el cambio.';
      return true;
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioPerfilPaciente.explicarError(error);
      }
      return false;
    } finally {
      if (!_cerrado) {
        _estaGuardando = false;
        notifyListeners();
      }
    }
  }

  /// Selecciona una fotografia desde la galeria para mostrarla unicamente como
  /// vista previa local en memoria, sin modificar la foto actual ni subirla aun.
  Future<bool> seleccionarFotografiaVistaPrevia({
    ImageSource origen = ImageSource.gallery,
  }) async {
    if (_cerrado || ocupado) return false;
    _estaSeleccionandoFoto = true;
    _mensajeErrorFoto = null;
    notifyListeners();

    try {
      final seleccionada = await servicio.seleccionarFotografiaGaleria(
        origen: origen,
      );
      if (_cerrado) return false;
      if (seleccionada == null) {
        return false;
      }
      _fotoVistaPrevia = seleccionada;
      return true;
    } catch (error) {
      if (!_cerrado) {
        _mensajeErrorFoto = ServicioPerfilPaciente.explicarError(error);
      }
      return false;
    } finally {
      if (!_cerrado) {
        _estaSeleccionandoFoto = false;
        notifyListeners();
      }
    }
  }

  /// Descarta la fotografia seleccionada localmente y restaura la vista actual.
  void cancelarSeleccionFotografia() {
    if (_cerrado || ocupado) return;
    _fotoVistaPrevia = null;
    _mensajeErrorFoto = null;
    notifyListeners();
  }

  Future<void> cerrarSesion() async {
    if (_cerrado || _estaCerrandoSesion) return;
    _estaCerrandoSesion = true;
    _mensajeError = null;
    _mensajeExito = null;
    _mensajeErrorFoto = null;
    notifyListeners();

    try {
      await servicioSesion.cerrarSesion();
      if (!_cerrado) {
        _perfil = null;
        _fotoVistaPrevia = null;
      }
    } finally {
      if (!_cerrado) {
        _estaCerrandoSesion = false;
        notifyListeners();
      }
    }
  }

  void limpiarMensajes() {
    if (_cerrado) return;
    _mensajeError = null;
    _mensajeExito = null;
    _mensajeErrorFoto = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _cerrado = true;
    super.dispose();
  }
}
