import 'dart:convert';
import 'dart:typed_data';

import 'package:boom/modelos/especialidad.dart';
import 'package:boom/modulos/profesional/servicios/servicio_perfil_profesional.dart';
import 'package:boom/repositorios/repositorio_especialidades.dart';
import 'package:flutter_test/flutter_test.dart';

class _RepositorioEspecialidadesStub implements RepositorioEspecialidades {
  @override
  Future<List<Especialidad>> obtenerCatalogoEspecialidades() async => const [];

  @override
  Future<void> guardarEspecialidadesProfesional(
    List<String> especialidadesIds,
  ) async {}
}

Map<String, dynamic> _filaPerfilProfesional({String? fotoUrl}) {
  return {
    'id': 'prof-100',
    'nombre': 'Carlos',
    'apellido': 'Pérez',
    'correo': 'carlos@ejemplo.com',
    'aprobacion': 'aprobado',
    'cuenta_activa': true,
    'numero_registro': 'REG-1234',
    'descripcion': 'Psicólogo clínico.',
    'anios_experiencia': 5,
    'telefono_contacto': '0999999999',
    'modalidad': 'ambas',
    'foto_url': fotoUrl,
    'direccion_consultorio': 'Av. Principal 100',
    'latitud': -1.67,
    'longitud': -78.64,
    'especialidades_ids': ['esp-1'],
    'especialidades_nombres': ['Psicología Clínica'],
    'servicios': 'Terapia individual',
  };
}

Uint8List _bytesJpgValidos() =>
    Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2]);

Uint8List _bytesPngValidos() =>
    Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2]);

void main() {
  group('ServicioPerfilProfesional - subida de fotografía vía Edge Function', () {
    test('rechaza sesión ausente sin invocar la Edge Function', () async {
      var invocaciones = 0;
      final servicio = ServicioPerfilProfesional(
        repositorioEspecialidades: _RepositorioEspecialidadesStub(),
        lectorUsuarioActualId: () => null,
        invocadorSubidaFoto: (nombreFuncion, {required cuerpo}) async {
          invocaciones++;
          return const RespuestaSubidaFotoEdge(estado: 200, datos: {});
        },
      );

      await expectLater(
        () => servicio.subirYGuardarFotografia(
          ArchivoImagenSeleccionada(
            bytes: _bytesJpgValidos(),
            extensionArchivo: 'jpg',
            tipoMime: 'image/jpeg',
          ),
        ),
        throwsA(
          isA<ErrorPerfilProfesional>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('Sesión no válida'),
          ),
        ),
      );
      expect(invocaciones, equals(0));
    });

    test('rechaza archivos que no sean JPG o PNG ni superen 5 MB antes de llamar al servidor', () async {
      var invocaciones = 0;
      final servicio = ServicioPerfilProfesional(
        repositorioEspecialidades: _RepositorioEspecialidadesStub(),
        lectorUsuarioActualId: () => 'usr-100',
        invocadorSubidaFoto: (nombreFuncion, {required cuerpo}) async {
          invocaciones++;
          return const RespuestaSubidaFotoEdge(estado: 200, datos: {});
        },
      );

      // WebP / bytes inválidos
      final bytesWebp = Uint8List.fromList(utf8.encode('RIFF1234WEBP'));
      await expectLater(
        () => servicio.subirYGuardarFotografia(
          ArchivoImagenSeleccionada(
            bytes: bytesWebp,
            extensionArchivo: 'webp',
            tipoMime: 'image/webp',
          ),
        ),
        throwsA(
          isA<ErrorPerfilProfesional>().having(
            (e) => e.mensaje,
            'mensaje',
            equals('Solo se permiten fotografías en formato JPG o PNG.'),
          ),
        ),
      );

      // Archivo vacío
      await expectLater(
        () => servicio.subirYGuardarFotografia(
          ArchivoImagenSeleccionada(
            bytes: Uint8List(0),
            extensionArchivo: 'jpg',
            tipoMime: 'image/jpeg',
          ),
        ),
        throwsA(isA<ErrorPerfilProfesional>()),
      );

      // Archivo mayor a 5 MB (con cabecera JPG válida)
      final bytesGrandes = Uint8List(
        ServicioPerfilProfesional.limiteBytesFotografia + 1,
      );
      bytesGrandes[0] = 0xFF;
      bytesGrandes[1] = 0xD8;
      bytesGrandes[2] = 0xFF;
      await expectLater(
        () => servicio.subirYGuardarFotografia(
          ArchivoImagenSeleccionada(
            bytes: bytesGrandes,
            extensionArchivo: 'jpg',
            tipoMime: 'image/jpeg',
          ),
        ),
        throwsA(
          isA<ErrorPerfilProfesional>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('5 MB'),
          ),
        ),
      );

      expect(invocaciones, equals(0));
    });

    test('propaga rechazo 401 (sesión inválida) y 403 (rol no autorizado) desde la Edge Function', () async {
      final servicio401 = ServicioPerfilProfesional(
        repositorioEspecialidades: _RepositorioEspecialidadesStub(),
        lectorUsuarioActualId: () => 'usr-100',
        invocadorSubidaFoto: (nombreFuncion, {required cuerpo}) async {
          return const RespuestaSubidaFotoEdge(
            estado: 401,
            datos: {
              'codigo': 'SESION_INVALIDA',
              'mensaje':
                  'Tu sesión expiró o no es válida. Vuelve a iniciar sesión.',
            },
          );
        },
      );

      await expectLater(
        () => servicio401.subirYGuardarFotografia(
          ArchivoImagenSeleccionada(
            bytes: _bytesJpgValidos(),
            extensionArchivo: 'jpg',
            tipoMime: 'image/jpeg',
          ),
        ),
        throwsA(
          isA<ErrorPerfilProfesional>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('sesión expiró'),
          ),
        ),
      );

      final servicio403 = ServicioPerfilProfesional(
        repositorioEspecialidades: _RepositorioEspecialidadesStub(),
        lectorUsuarioActualId: () => 'usr-100',
        invocadorSubidaFoto: (nombreFuncion, {required cuerpo}) async {
          return const RespuestaSubidaFotoEdge(
            estado: 403,
            datos: {
              'codigo': 'ROL_NO_AUTORIZADO',
              'mensaje': 'Solo las cuentas de profesionales pueden subir esta fotografía.',
            },
          );
        },
      );

      await expectLater(
        () => servicio403.subirYGuardarFotografia(
          ArchivoImagenSeleccionada(
            bytes: _bytesPngValidos(),
            extensionArchivo: 'png',
            tipoMime: 'image/png',
          ),
        ),
        throwsA(
          isA<ErrorPerfilProfesional>().having(
            (e) => e.mensaje,
            'mensaje',
            equals(
              'Solo las cuentas de profesionales pueden subir esta fotografía.',
            ),
          ),
        ),
      );
    });

    test('sube PNG a subir-foto-profesional y verifica la URL de Cloudinary persistida en el perfil', () async {
      const urlCloudinary =
          'https://res.cloudinary.com/demo/image/upload/v1700000000/psicobloom/profesionales/usr-100_abc.png';
      String? funcionInvocada;
      String? base64Enviado;
      var llamadasRpc = <String>[];

      final servicio = ServicioPerfilProfesional(
        repositorioEspecialidades: _RepositorioEspecialidadesStub(),
        lectorUsuarioActualId: () => 'usr-100',
        invocadorSubidaFoto: (nombreFuncion, {required cuerpo}) async {
          funcionInvocada = nombreFuncion;
          base64Enviado = cuerpo['archivoBase64'] as String?;
          return const RespuestaSubidaFotoEdge(
            estado: 200,
            datos: {'fotoUrl': urlCloudinary},
          );
        },
        ejecutorRpc: (nombreFuncion, {parametros}) async {
          llamadasRpc.add(nombreFuncion);
          if (nombreFuncion == 'obtener_perfil_profesional_propio') {
            return [_filaPerfilProfesional(fotoUrl: urlCloudinary)];
          }
          return null;
        },
      );

      final bytesPng = _bytesPngValidos();
      final resultado = await servicio.subirYGuardarFotografia(
        ArchivoImagenSeleccionada(
          bytes: bytesPng,
          extensionArchivo: 'png',
          tipoMime: 'image/png',
        ),
      );

      expect(funcionInvocada, equals('subir-foto-profesional'));
      expect(base64Enviado, equals(base64Encode(bytesPng)));
      expect(llamadasRpc, equals(['obtener_perfil_profesional_propio']));
      expect(resultado, equals(urlCloudinary));
    });

    test('fallo de Cloudinary (502) o persistencia (500) no simula éxito y conserva la foto previa', () async {
      const urlStorageAnterior =
          'https://ejemplo.supabase.co/storage/v1/object/public/fotos-profesionales/usr-100/perfil.jpg?t=123';

      final servicioFalloCloudinary = ServicioPerfilProfesional(
        repositorioEspecialidades: _RepositorioEspecialidadesStub(),
        lectorUsuarioActualId: () => 'usr-100',
        invocadorSubidaFoto: (nombreFuncion, {required cuerpo}) async {
          return const RespuestaSubidaFotoEdge(
            estado: 502,
            datos: {
              'codigo': 'ERROR_PROVEEDOR_IMAGEN',
              'mensaje': 'No se pudo subir la fotografía en este momento. Inténtalo nuevamente.',
            },
          );
        },
        ejecutorRpc: (nombreFuncion, {parametros}) async {
          return [_filaPerfilProfesional(fotoUrl: urlStorageAnterior)];
        },
      );

      await expectLater(
        () => servicioFalloCloudinary.subirYGuardarFotografia(
          ArchivoImagenSeleccionada(
            bytes: _bytesJpgValidos(),
            extensionArchivo: 'jpg',
            tipoMime: 'image/jpeg',
          ),
        ),
        throwsA(
          isA<ErrorPerfilProfesional>().having(
            (e) => e.mensaje,
            'mensaje',
            equals(
              'No se pudo subir la fotografía en este momento. Inténtalo nuevamente.',
            ),
          ),
        ),
      );

      // Si el perfil sigue manteniendo la URL anterior tras la respuesta, se rechaza confirmar el cambio
      final servicioPersistenciaInconsistente = ServicioPerfilProfesional(
        repositorioEspecialidades: _RepositorioEspecialidadesStub(),
        lectorUsuarioActualId: () => 'usr-100',
        invocadorSubidaFoto: (nombreFuncion, {required cuerpo}) async {
          return const RespuestaSubidaFotoEdge(
            estado: 200,
            datos: {
              'fotoUrl': 'https://res.cloudinary.com/demo/image/upload/v1700000001/psicobloom/profesionales/nueva.jpg',
            },
          );
        },
        ejecutorRpc: (nombreFuncion, {parametros}) async {
          return [_filaPerfilProfesional(fotoUrl: urlStorageAnterior)];
        },
      );

      await expectLater(
        () => servicioPersistenciaInconsistente.subirYGuardarFotografia(
          ArchivoImagenSeleccionada(
            bytes: _bytesJpgValidos(),
            extensionArchivo: 'jpg',
            tipoMime: 'image/jpeg',
          ),
        ),
        throwsA(
          isA<ErrorPerfilProfesional>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('Se conservó tu foto anterior'),
          ),
        ),
      );

      // Compatibilidad: obtenerPerfilPropio sigue leyendo URLs antiguas de Supabase Storage
      final perfilLeido = await servicioPersistenciaInconsistente
          .obtenerPerfilPropio();
      expect(perfilLeido.fotoUrl, equals(urlStorageAnterior));
    });
  });
}
