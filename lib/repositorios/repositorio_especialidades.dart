import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modelos/especialidad.dart';
import 'package:boom/nucleo/utilidades/traductor_errores_supabase.dart';

class ErrorEspecialidades implements Exception {
  final String mensaje;
  const ErrorEspecialidades(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Contrato para consultar y persistir el catalogo real de especialidades.
abstract class RepositorioEspecialidades {
  /// Devuelve las especialidades activas (y las vinculadas historicamente al profesional).
  Future<List<Especialidad>> obtenerCatalogoEspecialidades();

  /// Guarda las especialidades seleccionadas por el profesional autenticado.
  Future<void> guardarEspecialidadesProfesional(List<String> especialidadesIds);
}

/// Implementacion conectada con Supabase PostgreSQL para el catalogo real
/// public."Especialidades" y la tabla puente public."ProfesionalEspecialidad".
class RepositorioEspecialidadesSupabase implements RepositorioEspecialidades {
  const RepositorioEspecialidadesSupabase();

  SupabaseClient get _cliente {
    if (!ConfiguracionSupabase.estaConfigurado) {
      throw const ErrorEspecialidades(
        'Falta la configuración de Supabase. Ejecuta la aplicación con la URL y la clave pública.',
      );
    }
    return Supabase.instance.client;
  }

  @override
  Future<List<Especialidad>> obtenerCatalogoEspecialidades() async {
    try {
      dynamic respuesta;
      try {
        respuesta = await _cliente
            .from('Especialidades')
            .select('id_especialidad, nombre, descripcion, activa')
            .order('nombre', ascending: true);
      } on PostgrestException catch (error) {
        // Si la columna aditiva `activa` del Script 05 aun no se ha ejecutado,
        // consulta las columnas base existentes en public."Especialidades".
        if (error.code == '42703') {
          respuesta = await _cliente
              .from('Especialidades')
              .select('id_especialidad, nombre, descripcion')
              .order('nombre', ascending: true);
        } else {
          rethrow;
        }
      }

      return (respuesta as List)
          .whereType<Map>()
          .map(
            (fila) => Especialidad.desdeMapa(Map<String, dynamic>.from(fila)),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw ErrorEspecialidades(
        TraductorErroresSupabase.traducirErrorBaseDatos(
          error,
          accionPorDefecto: 'No se pudo cargar el catálogo de especialidades en este momento. Inténtalo nuevamente.',
        ),
      );
    } catch (error) {
      if (error is ErrorEspecialidades) rethrow;
      throw ErrorEspecialidades(
        TraductorErroresSupabase.traducirErrorBaseDatos(
          error,
          accionPorDefecto: 'No se pudo consultar el catálogo de especialidades. Comprueba tu conexión.',
        ),
      );
    }
  }

  @override
  Future<void> guardarEspecialidadesProfesional(
    List<String> especialidadesIds,
  ) async {
    final idsUnicos = especialidadesIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    try {
      await _cliente.rpc(
        'guardar_especialidades_profesional',
        params: {'p_especialidades_ids': idsUnicos},
      );
    } on PostgrestException catch (error) {
      if (error.code == '42501') {
        throw const ErrorEspecialidades(
          'No tienes permiso para modificar las especialidades de este perfil.',
        );
      }
      if (error.code == '22023') {
        throw const ErrorEspecialidades(
          'Una o más especialidades seleccionadas no están activas o disponibles.',
        );
      }
      throw ErrorEspecialidades(
        TraductorErroresSupabase.traducirErrorBaseDatos(
          error,
          accionPorDefecto: 'No se pudieron guardar las especialidades en este momento. Inténtalo nuevamente.',
        ),
      );
    } catch (error) {
      if (error is ErrorEspecialidades) rethrow;
      throw ErrorEspecialidades(
        TraductorErroresSupabase.traducirErrorBaseDatos(
          error,
          accionPorDefecto: 'No se pudieron guardar las especialidades. Comprueba tu conexión.',
        ),
      );
    }
  }
}
