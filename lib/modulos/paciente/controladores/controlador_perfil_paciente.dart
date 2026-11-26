import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_sesion.dart';
import 'package:boom/modulos/paciente/servicios/servicio_perfil_paciente.dart';

/// Resultado tipado de una operacion sobre la fotografia de perfil del paciente.
enum EstadoOperacionFotoPaciente {
  actualizada,
  eliminada,
  cancelada,
  errorSeleccion,
  errorServidor,
}

class ResultadoOperacionFotoPaciente {
  final EstadoOperacionFotoPaciente estado;
  final String? mensaje;

  const ResultadoOperacionFotoPaciente({required this.estado, this.mensaje});

  bool get fueExitosa =>
      estado == EstadoOperacionFotoPaciente.actualizada ||
      estado == EstadoOperacionFotoPaciente.eliminada;

  bool get esError =>
      estado == EstadoOperacionFotoPaciente.errorSeleccion ||
      estado == EstadoOperacionFotoPaciente.errorServidor;
}

/// Coordina la carga, edicion de datos basicos, gestion automatica de fotografia
/// (Cloudinary + Supabase mediante Edge Function segura) y cierre de sesion.
class ControladorPerfilPaciente extends ChangeNotifier {
  ControladorPerfilPaciente({
    this.servicio = const ServicioPerfilPaciente(),
    this.servicioSesion = const ServicioSesion(),
    PerfilUsuario? perfilInicial,
  }) : _perfil = perfilInicial;

  final ServicioPerfilPaciente servicio;
  final ServicioSesion servicioSesion;

  PerfilUsuario? _perfil;
  ArchivoFotoPacienteSeleccionada? _fotoTemporal;
  bool _estaCargando = false;
  bool _estaGuardando = false;
  bool _estaSeleccionandoFoto = false;
  bool _estaProcesandoFoto = false;
  bool _estaCerrandoSesion = false;
  bool _cerrado = false;
  String? _mensajeError;
  String? _mensajeExito;

  PerfilUsuario? get perfil => _perfil;
  ArchivoFotoPacienteSeleccionada? get fotoTemporal => _fotoTemporal;
  bool get tieneFotoPersonalizada =>
      _perfil?.tieneFotoPersonalizada == true &&
      (_perfil?.fotoUrl?.trim().isNotEmpty ?? false);
  bool get estaCargando => _estaCargando;
  bool get estaGuardando => _estaGuardando;
  bool get estaSeleccionandoFoto => _estaSeleccionandoFoto;
  bool get estaProcesandoFoto => _estaProcesandoFoto;
  bool get estaCerrandoSesion => _estaCerrandoSesion;
  bool get ocupado =>
      _estaCargando ||
      _estaGuardando ||
      _estaSeleccionandoFoto ||
      _estaProcesandoFoto ||
      _estaCerrandoSesion;
  String? get mensajeError => _mensajeError;
  String? get mensajeExito => _mensajeExito;

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
      ServicioSesion.notificarPerfilPacienteActualizado(perfilServidor);
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
      ServicioSesion.notificarPerfilPacienteActualizado(perfilActualizado);
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

  /// Selecciona o toma una fotografia valida, la muestra temporalmente en el avatar
  /// e inicia automaticamente la subida a Cloudinary y persistencia en Supabase.
  /// Si el usuario cancela el selector no hace nada. Si falla la subida, restaura
  /// la fotografia anterior e informa "No se pudo actualizar la foto".
  Future<ResultadoOperacionFotoPaciente> cambiarFotografia({
    required ImageSource origen,
  }) async {
    if (_cerrado || ocupado) {
      return const ResultadoOperacionFotoPaciente(
        estado: EstadoOperacionFotoPaciente.cancelada,
      );
    }

    _estaSeleccionandoFoto = true;
    notifyListeners();

    ArchivoFotoPacienteSeleccionada? seleccionada;
    try {
      seleccionada = await servicio.seleccionarFotografia(origen: origen);
    } catch (error) {
      if (!_cerrado) {
        _estaSeleccionandoFoto = false;
        notifyListeners();
      }
      return ResultadoOperacionFotoPaciente(
        estado: EstadoOperacionFotoPaciente.errorSeleccion,
        mensaje: ServicioPerfilPaciente.explicarError(error),
      );
    }

    if (_cerrado) {
      return const ResultadoOperacionFotoPaciente(
        estado: EstadoOperacionFotoPaciente.cancelada,
      );
    }

    _estaSeleccionandoFoto = false;
    if (seleccionada == null) {
      notifyListeners();
      return const ResultadoOperacionFotoPaciente(
        estado: EstadoOperacionFotoPaciente.cancelada,
      );
    }

    // Muestra la nueva fotografia temporalmente mientras se persiste en servidor.
    _fotoTemporal = seleccionada;
    _estaProcesandoFoto = true;
    notifyListeners();

    try {
      final perfilActualizado = await servicio.subirYGuardarFotografia(
        seleccionada,
      );
      if (_cerrado) {
        return const ResultadoOperacionFotoPaciente(
          estado: EstadoOperacionFotoPaciente.cancelada,
        );
      }
      _perfil = perfilActualizado;
      _fotoTemporal = null;
      ServicioSesion.notificarPerfilPacienteActualizado(perfilActualizado);
      return const ResultadoOperacionFotoPaciente(
        estado: EstadoOperacionFotoPaciente.actualizada,
        mensaje: 'Foto actualizada',
      );
    } catch (_) {
      if (!_cerrado) {
        // Recupera la fotografia anterior descartando la vista previa temporal.
        _fotoTemporal = null;
      }
      return const ResultadoOperacionFotoPaciente(
        estado: EstadoOperacionFotoPaciente.errorServidor,
        mensaje: 'No se pudo actualizar la foto',
      );
    } finally {
      if (!_cerrado) {
        _estaProcesandoFoto = false;
        notifyListeners();
      }
    }
  }

  /// Elimina la fotografia personalizada guardada en PsicoBloom (Cloudinary + Supabase),
  /// conservando intacta cualquier fotografia externa como Google OAuth.
  Future<ResultadoOperacionFotoPaciente> eliminarFotografia() async {
    if (_cerrado || ocupado || !tieneFotoPersonalizada) {
      return const ResultadoOperacionFotoPaciente(
        estado: EstadoOperacionFotoPaciente.cancelada,
      );
    }

    _estaProcesandoFoto = true;
    notifyListeners();

    try {
      final perfilActualizado = await servicio.eliminarFotografia();
      if (_cerrado) {
        return const ResultadoOperacionFotoPaciente(
          estado: EstadoOperacionFotoPaciente.cancelada,
        );
      }
      _perfil = perfilActualizado.copiarCon(limpiarFotoUrl: true);
      ServicioSesion.notificarPerfilPacienteActualizado(_perfil!);
      return const ResultadoOperacionFotoPaciente(
        estado: EstadoOperacionFotoPaciente.eliminada,
        mensaje: 'Foto eliminada',
      );
    } catch (_) {
      return const ResultadoOperacionFotoPaciente(
        estado: EstadoOperacionFotoPaciente.errorServidor,
        mensaje: 'No se pudo eliminar la foto',
      );
    } finally {
      if (!_cerrado) {
        _estaProcesandoFoto = false;
        notifyListeners();
      }
    }
  }

  Future<void> cerrarSesion() async {
    if (_cerrado || _estaCerrandoSesion) return;
    _estaCerrandoSesion = true;
    _mensajeError = null;
    _mensajeExito = null;
    notifyListeners();

    try {
      await servicioSesion.cerrarSesion();
      if (!_cerrado) {
        _perfil = null;
        _fotoTemporal = null;
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
    notifyListeners();
  }

  @override
  void dispose() {
    _cerrado = true;
    super.dispose();
  }
}
