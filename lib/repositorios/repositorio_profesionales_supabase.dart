import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modelos/filtro_profesional.dart';
import 'package:boom/modelos/profesional.dart';
import 'package:boom/nucleo/utilidades/traductor_errores_supabase.dart';
import 'package:boom/repositorios/repositorio_especialidades.dart';
import 'package:boom/repositorios/repositorio_profesionales.dart';

class ErrorDirectorioProfesionales implements Exception {
  final String mensaje;
  const ErrorDirectorioProfesionales(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Implementacion real del repositorio de profesionales conectada con Supabase.
/// Consulta el directorio autorizado mediante `directorio_profesionales_completo`
/// (con respaldo a `directorio_profesionales`) y el catalogo real `public."Especialidades"`.
/// No cae silenciosamente a datos simulados.
class RepositorioProfesionalesSupabase implements RepositorioProfesionales {
  final RepositorioEspecialidades repositorioEspecialidades;
  final Future<List<Map<String, dynamic>>> Function()? proveedorFilasDirectorio;
  List<Profesional>? _cacheProfesionales;

  RepositorioProfesionalesSupabase({
    this.repositorioEspecialidades = const RepositorioEspecialidadesSupabase(),
    this.proveedorFilasDirectorio,
  });

  /// Limpia la cache en memoria para forzar una nueva consulta al servidor.
  void limpiarCache() {
    _cacheProfesionales = null;
  }

  SupabaseClient get _cliente {
    if (!ConfiguracionSupabase.estaConfigurado) {
      throw const ErrorDirectorioProfesionales(
        'Falta la configuración de Supabase para consultar el directorio real.',
      );
    }
    return Supabase.instance.client;
  }

  @override
  Future<List<Profesional>> obtenerProfesionales() async {
    try {
      dynamic respuesta;
      if (proveedorFilasDirectorio != null) {
        respuesta = await proveedorFilasDirectorio!();
      } else {
        try {
          respuesta = await _cliente.rpc('directorio_profesionales_completo');
        } on PostgrestException catch (error) {
          // Si la RPC extendida del Script 05 aun no fue ejecutada, usa la
          // funcion base `directorio_profesionales` existente en el proyecto remoto.
          if (error.code == 'PGRST202' || error.code == '42883') {
            respuesta = await _cliente.rpc('directorio_profesionales');
          } else {
            rethrow;
          }
        }
      }
      if (respuesta is! List) {
        _cacheProfesionales = const [];
        return const [];
      }
      final lista = respuesta
          .whereType<Map>()
          .map((fila) => Profesional.desdeMapa(Map<String, dynamic>.from(fila)))
          .toList();
      _cacheProfesionales = List.unmodifiable(lista);
      return _cacheProfesionales!;
    } on PostgrestException catch (error) {
      if (error.code == '42501') {
        throw const ErrorDirectorioProfesionales(
          'Tu cuenta debe estar activa para consultar el directorio de profesionales.',
        );
      }
      throw ErrorDirectorioProfesionales(
        TraductorErroresSupabase.traducirErrorBaseDatos(
          error,
          accionPorDefecto: 'No pudimos cargar el directorio de profesionales en este momento. Inténtalo nuevamente.',
        ),
      );
    } catch (error) {
      if (error is ErrorDirectorioProfesionales) rethrow;
      throw ErrorDirectorioProfesionales(
        TraductorErroresSupabase.traducirErrorBaseDatos(
          error,
          accionPorDefecto: 'No se pudo conectar con el servidor para cargar los profesionales. Revisa tu conexión e inténtalo nuevamente.',
        ),
      );
    }
  }

  @override
  Future<List<Profesional>> buscarProfesionales(
    FiltroProfesional filtro,
  ) async {
    // Reutiliza el directorio cargado en memoria para evitar solicitudes de red
    // innecesarias en cada pulsacion del buscador o cambio de filtro.
    final listado = _cacheProfesionales ?? await obtenerProfesionales();
    final textoLimpio = _normalizarTexto(filtro.textoBusqueda.trim());
    final especialidadLimpia = _normalizarTexto(filtro.especialidad.trim());
    final modalidadLimpia = _normalizarTexto(filtro.modalidad.trim());
    final disponibilidadLimpia = _normalizarTexto(filtro.disponibilidad.trim());

    final resultados = listado.where((profesional) {
      // 1. Filtro por nombre, especialidad o servicio
      if (textoLimpio.isNotEmpty) {
        final nombreLimpio = _normalizarTexto(profesional.nombre);
        final espLimpia = _normalizarTexto(profesional.especialidad);
        final serviciosLimpios = _normalizarTexto(profesional.servicios);
        final coincide =
            nombreLimpio.contains(textoLimpio) ||
            espLimpia.contains(textoLimpio) ||
            serviciosLimpios.contains(textoLimpio) ||
            profesional.especialidades.any(
              (item) => _normalizarTexto(item).contains(textoLimpio),
            );
        if (!coincide) return false;
      }

      // 2. Filtro por especialidad del catalogo
      if (especialidadLimpia.isNotEmpty && especialidadLimpia != 'todas') {
        final coincideEspecialidad =
            _normalizarTexto(profesional.especialidad) == especialidadLimpia ||
            _normalizarTexto(profesional.especialidad)
                .contains(especialidadLimpia) ||
            profesional.especialidades.any(
              (item) => _normalizarTexto(item) == especialidadLimpia,
            );
        if (!coincideEspecialidad) return false;
      }

      // 3. Filtro por modalidad
      if (modalidadLimpia.isNotEmpty && modalidadLimpia != 'todas') {
        final modalidadProfLimpia = _normalizarTexto(profesional.modalidad);
        if (modalidadProfLimpia != modalidadLimpia) return false;
      }

      // 4. Filtro por disponibilidad cuando aplique
      if (disponibilidadLimpia.isNotEmpty &&
          disponibilidadLimpia != 'todas' &&
          disponibilidadLimpia != 'cualquiera') {
        final dispProf = _normalizarTexto(profesional.disponibilidadTexto);
        if (!dispProf.contains(disponibilidadLimpia)) {
          return false;
        }
      }

      return true;
    }).toList();

    switch (filtro.ordenamiento) {
      case CriterioOrdenamiento.nombreAscendente:
        resultados.sort((a, b) => a.nombre.compareTo(b.nombre));
        break;
      case CriterioOrdenamiento.calificacionDescendente:
        resultados.sort((a, b) => b.calificacion.compareTo(a.calificacion));
        break;
      case CriterioOrdenamiento.especialidadAscendente:
        resultados.sort((a, b) => a.especialidad.compareTo(b.especialidad));
        break;
    }

    return resultados;
  }

  @override
  Future<Profesional?> obtenerProfesionalPorId(String id) async {
    final profesionales = _cacheProfesionales ?? await obtenerProfesionales();
    for (final p in profesionales) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<List<String>> obtenerEspecialidades() async {
    final opciones = <String>{'Todas'};
    try {
      final catalogo = await repositorioEspecialidades
          .obtenerCatalogoEspecialidades();
      for (final item in catalogo) {
        if (item.activa && item.nombre.trim().isNotEmpty) {
          opciones.add(item.nombre.trim());
        }
      }
    } catch (_) {
      // Si el catalogo no pudo consultarse, usa las especialidades de los perfiles aprobados.
    }
    if (opciones.length == 1) {
      final profesionales = _cacheProfesionales ?? await obtenerProfesionales();
      for (final p in profesionales) {
        for (final esp in p.especialidades) {
          if (esp.trim().isNotEmpty) {
            opciones.add(esp.trim());
          }
        }
      }
    }
    return opciones.toList();
  }

  @override
  Future<List<String>> obtenerModalidades() async {
    return const ['Todas', 'Presencial', 'Virtual', 'Híbrida'];
  }

  @override
  Future<List<String>> obtenerDisponibilidades() async {
    return const ['Todas', 'Consulta de perfil disponible'];
  }

  String _normalizarTexto(String entrada) {
    var resultado = entrada.toLowerCase();
    resultado = resultado.replaceAll(RegExp(r'[áàäâ]'), 'a');
    resultado = resultado.replaceAll(RegExp(r'[éèëê]'), 'e');
    resultado = resultado.replaceAll(RegExp(r'[íìïî]'), 'i');
    resultado = resultado.replaceAll(RegExp(r'[óòöô]'), 'o');
    resultado = resultado.replaceAll(RegExp(r'[úùüû]'), 'u');
    return resultado;
  }
}
