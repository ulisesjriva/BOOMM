import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/modelos/especialidad.dart';
import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/profesional/controladores/controlador_perfil_profesional.dart';
import 'package:boom/modulos/profesional/modelos/perfil_profesional.dart';
import 'package:boom/modulos/profesional/servicios/servicio_perfil_profesional.dart';
import 'package:boom/modulos/profesional/servicios/servicio_ubicacion_consultorio.dart';
import 'package:boom/modulos/profesional/vistas/pantalla_inicio_profesional.dart';
import 'package:boom/modulos/profesional/vistas/pantalla_perfil_profesional.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/repositorios/repositorio_especialidades.dart';

class _ServicioPerfilProfesionalFalso extends ServicioPerfilProfesional {
  PerfilProfesional perfilActual;
  ArchivoImagenSeleccionada? archivoSimulado;
  String? errorSubidaSimulado;
  String urlFotoSimulada =
      'https://proyecto.supabase.co/storage/v1/object/public/fotos-profesionales/prof-100/perfil.jpg';
  int llamadasGuardar = 0;
  int llamadasSubirFoto = 0;

  _ServicioPerfilProfesionalFalso({
    required this.perfilActual,
    this.archivoSimulado,
  });

  @override
  Future<PerfilProfesional> obtenerPerfilPropio() async {
    return perfilActual;
  }

  @override
  Future<ArchivoImagenSeleccionada?> seleccionarFotografia({
    ImageSource origen = ImageSource.gallery,
  }) async {
    return archivoSimulado;
  }

  @override
  Future<String> subirYGuardarFotografia(
    ArchivoImagenSeleccionada imagen,
  ) async {
    llamadasSubirFoto++;
    if (errorSubidaSimulado != null) {
      throw ErrorPerfilProfesional(errorSubidaSimulado!);
    }
    perfilActual = perfilActual.copiarCon(fotoUrl: urlFotoSimulada);
    return urlFotoSimulada;
  }

  @override
  Future<PerfilProfesional> guardarPerfilCompleto({
    required String nombre,
    required String apellido,
    required List<String> especialidadesIds,
    required List<String> especialidadesNombres,
    String? numeroRegistro,
    String? descripcion,
    int? aniosExperiencia,
    String? telefonoContacto,
    required String modalidad,
    String? servicios,
    String? direccionConsultorio,
    double? latitud,
    double? longitud,
  }) async {
    llamadasGuardar++;
    perfilActual = perfilActual.copiarCon(
      nombre: nombre,
      apellido: apellido,
      especialidadesIds: especialidadesIds,
      especialidadesNombres: especialidadesNombres,
      especialidadTexto: especialidadesNombres.join(', '),
      numeroRegistro: numeroRegistro,
      descripcion: descripcion,
      aniosExperiencia: aniosExperiencia,
      telefonoContacto: telefonoContacto,
      modalidad: modalidad,
      servicios: servicios,
      direccionConsultorio: direccionConsultorio,
      latitud: latitud,
      longitud: longitud,
      limpiarUbicacion: latitud == null && longitud == null,
    );
    return perfilActual;
  }
}

class _RepositorioEspecialidadesFalso implements RepositorioEspecialidades {
  List<Especialidad> catalogo;
  List<String> idsGuardados = const [];

  _RepositorioEspecialidadesFalso({required this.catalogo});

  @override
  Future<List<Especialidad>> obtenerCatalogoEspecialidades() async {
    return List<Especialidad>.unmodifiable(catalogo);
  }

  @override
  Future<void> guardarEspecialidadesProfesional(
    List<String> especialidadesIds,
  ) async {
    idsGuardados = List<String>.unmodifiable(especialidadesIds);
  }
}

class _ServicioUbicacionFalso extends ServicioUbicacionConsultorio {
  ResultadoUbicacionDispositivo resultadoUbicacion;

  _ServicioUbicacionFalso({required this.resultadoUbicacion});

  @override
  Future<ResultadoUbicacionDispositivo> obtenerUbicacionActual() async {
    return resultadoUbicacion;
  }
}

void main() {
  const perfilBase = PerfilProfesional(
    id: 'prof-100',
    nombre: 'Carlos',
    apellido: 'Pérez',
    correo: 'carlos@ejemplo.com',
    aprobacion: 'aprobado',
    cuentaActiva: true,
    especialidadTexto: 'Psicología Clínica',
    especialidadesIds: ['esp-1', 'esp-hist'],
    especialidadesNombres: [
      'Psicología Clínica',
      'Especialidad Histórica Inactiva',
    ],
    numeroRegistro: '0601234567',
    aniosExperiencia: 6,
    telefonoContacto: '0991234567',
    descripcion: 'Atención psicológica integral en Riobamba.',
    modalidad: 'Presencial',
    servicios: 'Psicoterapia individual, Evaluación clínica',
    direccionConsultorio: 'Av. Daniel León Borja, Riobamba',
    latitud: -1.67098,
    longitud: -78.64712,
  );

  const espClinica = Especialidad(
    id: 'esp-1',
    nombre: 'Psicología Clínica',
    descripcion: 'Evaluación y psicoterapia.',
    activa: true,
  );
  const espFamiliar = Especialidad(
    id: 'esp-2',
    nombre: 'Psicología Familiar',
    descripcion: 'Terapia de pareja y familia.',
    activa: true,
  );
  const espInactivaNoAsociada = Especialidad(
    id: 'esp-inactiva-2',
    nombre: 'Especialidad Inactiva No Asociada',
    descripcion: 'No debe ofrecerse.',
    activa: false,
  );
  const espInactivaHistorica = Especialidad(
    id: 'esp-hist',
    nombre: 'Especialidad Histórica Inactiva',
    descripcion: 'Desactivada en el catálogo.',
    activa: false,
  );

  group('ControladorPerfilProfesional - Perfil, foto, especialidades y mapa', () {
    test('Carga perfil profesional, oculta inactivas no asociadas y conserva historica vinculada', () async {
      final servicioPerfil = _ServicioPerfilProfesionalFalso(
        perfilActual: perfilBase,
      );
      final repoEspecialidades = _RepositorioEspecialidadesFalso(
        catalogo: const [
          espClinica,
          espFamiliar,
          espInactivaNoAsociada,
          espInactivaHistorica,
        ],
      );
      final servicioUbicacion = _ServicioUbicacionFalso(
        resultadoUbicacion: const ResultadoUbicacionDispositivo.obtenida(
          latitud: -1.67098,
          longitud: -78.64712,
        ),
      );

      final controlador = ControladorPerfilProfesional(
        servicio: servicioPerfil,
        repositorioEspecialidades: repoEspecialidades,
        servicioUbicacion: servicioUbicacion,
      );

      await controlador.inicializar();

      expect(controlador.estaCargando, isFalse);
      expect(controlador.perfil?.nombreCompleto, equals('Carlos Pérez'));
      // Muestra las 2 activas + 1 historica vinculada, pero oculta la inactiva no asociada
      expect(controlador.especialidadesVisibles.length, equals(3));
      expect(
        controlador.especialidadesVisibles.any((e) => e.id == 'esp-inactiva-2'),
        isFalse,
      );

      // No permite seleccionar una especialidad desactivada para nuevas relaciones
      controlador.alternarEspecialidad(espInactivaNoAsociada);
      expect(
        controlador.especialidadesSeleccionadasIds.contains('esp-inactiva-2'),
        isFalse,
      );
      expect(controlador.mensajeError, isNotNull);
    });

    test(
      'Asocia especialidades del catalogo y guarda perfil profesional completo',
      () async {
        final servicioPerfil = _ServicioPerfilProfesionalFalso(
          perfilActual: perfilBase.copiarCon(
            especialidadesIds: const ['esp-1'],
            especialidadesNombres: const ['Psicología Clínica'],
          ),
        );
        final repoEspecialidades = _RepositorioEspecialidadesFalso(
          catalogo: const [espClinica, espFamiliar],
        );
        final controlador = ControladorPerfilProfesional(
          servicio: servicioPerfil,
          repositorioEspecialidades: repoEspecialidades,
          servicioUbicacion: _ServicioUbicacionFalso(
            resultadoUbicacion: const ResultadoUbicacionDispositivo.obtenida(
              latitud: -1.67098,
              longitud: -78.64712,
            ),
          ),
        );

        await controlador.inicializar();
        controlador.alternarEspecialidad(espFamiliar);
        controlador.cambiarModalidad('Híbrida');

        expect(controlador.especialidadesSeleccionadasIds.length, equals(2));

        final exito = await controlador.guardarPerfil(
          nombre: 'Carlos Alberto',
          apellido: 'Pérez Andrade',
          numeroRegistro: '0609998887',
          textoAniosExperiencia: '8',
          telefonoContacto: '0998887776',
          descripcion: 'Psicoterapia cognitiva y familiar.',
          servicios: 'Terapia individual, Terapia familiar',
          direccionConsultorio: 'Parque Sucre, Riobamba',
          textoLatitud: '-1.67150',
          textoLongitud: '-78.64830',
        );

        expect(exito, isTrue);
        expect(servicioPerfil.llamadasGuardar, equals(1));
        expect(controlador.perfil?.modalidad, equals('Híbrida'));
        expect(controlador.perfil?.especialidadesNombres.length, equals(2));
        expect(controlador.perfil?.latitud, closeTo(-1.67150, 0.00001));
      },
    );

    test(
      'Flujo de fotografia maneja seleccion exitosa, cancelacion y error',
      () async {
        final servicioPerfil = _ServicioPerfilProfesionalFalso(
          perfilActual: perfilBase,
          archivoSimulado: null,
        );
        final controlador = ControladorPerfilProfesional(
          servicio: servicioPerfil,
          repositorioEspecialidades: _RepositorioEspecialidadesFalso(
            catalogo: const [espClinica],
          ),
          servicioUbicacion: _ServicioUbicacionFalso(
            resultadoUbicacion: const ResultadoUbicacionDispositivo.obtenida(
              latitud: -1.67,
              longitud: -78.64,
            ),
          ),
          perfilInicial: perfilBase,
        );

        // 1. Cancelacion no rompe el estado ni registra error
        final cancelado = await controlador.seleccionarYSubirFotografia();
        expect(cancelado, isFalse);
        expect(controlador.mensajeError, isNull);

        // 2. Subida exitosa actualiza fotoUrl
        servicioPerfil.archivoSimulado = ArchivoImagenSeleccionada(
          bytes: Uint8List.fromList([1, 2, 3, 4]),
          extensionArchivo: 'jpg',
          tipoMime: 'image/jpeg',
        );
        final subido = await controlador.seleccionarYSubirFotografia();
        expect(subido, isTrue);
        expect(
          controlador.perfil?.fotoUrl,
          contains('fotos-profesionales/prof-100/perfil.jpg'),
        );

        // 3. Error de almacenamiento informa mensaje claro y conserva la foto anterior
        servicioPerfil.errorSubidaSimulado =
            'La fotografía supera el límite de 5 MB.';
        final fallido = await controlador.seleccionarYSubirFotografia();
        expect(fallido, isFalse);
        expect(
          controlador.mensajeError,
          equals('La fotografía supera el límite de 5 MB.'),
        );
        expect(
          controlador.perfil?.fotoUrl,
          contains('fotos-profesionales/prof-100/perfil.jpg'),
        );
      },
    );

    test('Valida coordenadas geograficas y maneja estados de permisos de ubicacion', () async {
      final servicioUbicacion = _ServicioUbicacionFalso(
        resultadoUbicacion: const ResultadoUbicacionDispositivo.fallo(
          EstadoUbicacionDispositivo.permisoRechazado,
          'Permiso de ubicación rechazado.',
        ),
      );
      final controlador = ControladorPerfilProfesional(
        servicio: _ServicioPerfilProfesionalFalso(perfilActual: perfilBase),
        repositorioEspecialidades: _RepositorioEspecialidadesFalso(
          catalogo: const [espClinica],
        ),
        servicioUbicacion: servicioUbicacion,
        perfilInicial: perfilBase,
      );

      // Validaciones de coordenadas
      expect(
        ServicioUbicacionConsultorio.validarCoordenadas(
          textoLatitud: '',
          textoLongitud: '',
        ),
        isNull,
      );
      expect(
        ServicioUbicacionConsultorio.validarCoordenadas(
          textoLatitud: '-1.67',
          textoLongitud: '',
        ),
        isNotNull,
      );
      expect(
        ServicioUbicacionConsultorio.validarCoordenadas(
          textoLatitud: '99.5',
          textoLongitud: '-78.64',
        ),
        isNotNull,
      );
      expect(
        ServicioUbicacionConsultorio.validarCoordenadas(
          textoLatitud: '-1.67098',
          textoLongitud: '-78.64712',
        ),
        isNull,
      );

      // Estado 1: Permiso rechazado
      final resDenegado = await controlador.usarUbicacionActualDispositivo();
      expect(resDenegado, isFalse);
      expect(controlador.avisoUbicacion, contains('rechazado'));

      // Estado 2: Permiso rechazado permanentemente
      servicioUbicacion.resultadoUbicacion =
          const ResultadoUbicacionDispositivo.fallo(
            EstadoUbicacionDispositivo.permisoRechazadoPermanente,
            'El permiso de ubicación fue rechazado permanentemente.',
          );
      final resPermanente = await controlador.usarUbicacionActualDispositivo();
      expect(resPermanente, isFalse);
      expect(controlador.avisoUbicacion, contains('permanentemente'));

      // Estado 3: Servicio GPS desactivado
      servicioUbicacion.resultadoUbicacion =
          const ResultadoUbicacionDispositivo.fallo(
            EstadoUbicacionDispositivo.servicioDesactivado,
            'El servicio de ubicación (GPS) está desactivado.',
          );
      final resDesactivado = await controlador.usarUbicacionActualDispositivo();
      expect(resDesactivado, isFalse);
      expect(controlador.avisoUbicacion, contains('GPS'));

      // Estado 4: Permiso concedido con lectura exitosa
      servicioUbicacion.resultadoUbicacion =
          const ResultadoUbicacionDispositivo.obtenida(
            latitud: -1.66850,
            longitud: -78.65120,
          );
      final resExito = await controlador.usarUbicacionActualDispositivo();
      expect(resExito, isTrue);
      expect(controlador.latitudSeleccionada, closeTo(-1.66850, 0.00001));
      expect(controlador.longitudSeleccionada, closeTo(-78.65120, 0.00001));
    });

    testWidgets(
      'Desplazarse hasta el final de PantallaPerfilProfesional muestra mapa seguro y permite guardar sin errores',
      (tester) async {
        final servicioPerfil = _ServicioPerfilProfesionalFalso(
          perfilActual: perfilBase,
        );
        final repoEspecialidades = _RepositorioEspecialidadesFalso(
          catalogo: const [espClinica, espFamiliar],
        );
        final servicioUbicacion = _ServicioUbicacionFalso(
          resultadoUbicacion: const ResultadoUbicacionDispositivo.obtenida(
            latitud: -1.66850,
            longitud: -78.65120,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: PantallaPerfilProfesional(
              perfilInicial: perfilBase,
              servicio: servicioPerfil,
              repositorioEspecialidades: repoEspecialidades,
              servicioUbicacion: servicioUbicacion,
              mostrarMapaInteractivo: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('seccionPerfil_fotografia')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('seccionPerfil_datosProfesionales')),
          findsOneWidget,
        );

        final botonGuardar = find.byKey(
          const Key('botonGuardarPerfilProfesional'),
        );
        await tester.scrollUntilVisible(
          botonGuardar,
          250.0,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('seccionPerfil_modalidadConsultorio')),
          findsOneWidget,
        );
        final lienzoMapa = find.byKey(const Key('mapaGeoapify'));
        expect(lienzoMapa, findsOneWidget);

        await tester.tap(lienzoMapa);
        await tester.pumpAndSettle();

        await tester.tap(botonGuardar);
        await tester.pumpAndSettle();

        expect(servicioPerfil.llamadasGuardar, equals(1));
        expect(tester.takeException(), isNull);
      },
    );

    test('No oculta fallos parciales de servicios o fotografia ni ejecuta guardados parciales si falta una RPC', () async {
      expect(
        ServicioPerfilProfesional.duracionServicioMinutosAcordada,
        equals(60),
      );

      // 1. Si falta la RPC actualizar_perfil_profesional_propio, comunica incompatibilidad sin caminos parciales
      final llamadasRpcFaltante = <String>[];
      final servicioSinRpc = ServicioPerfilProfesional(
        lectorUsuarioActualId: () => 'prof-100',
        ejecutorRpc: (nombreFuncion, {parametros}) async {
          llamadasRpcFaltante.add(nombreFuncion);
          if (nombreFuncion == 'actualizar_perfil_profesional_propio') {
            throw const PostgrestException(
              message: 'Could not find function',
              code: 'PGRST202',
            );
          }
          return const [];
        },
      );

      await expectLater(
        () => servicioSinRpc.guardarPerfilCompleto(
          nombre: 'Carlos',
          apellido: 'Pérez',
          especialidadesIds: const ['esp-1'],
          especialidadesNombres: const ['Psicología Clínica'],
          modalidad: 'Presencial',
          servicios: 'Psicoterapia individual',
        ),
        throwsA(
          isA<ErrorPerfilProfesional>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('No se aplicaron cambios parciales'),
          ),
        ),
      );
      // Verifica que no llamo a actualizar_nombre_apellido ni guardados alternativos parciales
      expect(
        llamadasRpcFaltante,
        equals(['actualizar_perfil_profesional_propio']),
      );

      // 2. Si el servidor guarda datos basicos pero omite guardar los servicios solicitados, falla y no reporta guardado completo
      final servicioServiciosIncompletos = ServicioPerfilProfesional(
        lectorUsuarioActualId: () => 'prof-100',
        ejecutorRpc: (nombreFuncion, {parametros}) async {
          if (nombreFuncion == 'actualizar_perfil_profesional_propio') {
            return null;
          }
          if (nombreFuncion == 'obtener_perfil_profesional_propio') {
            return <Map<String, dynamic>>[
              {
                'id': 'prof-100',
                'nombre': 'Carlos',
                'apellido': 'Pérez',
                'correo': 'carlos@ejemplo.com',
                'aprobacion': 'aprobado',
                'cuenta_activa': true,
                'especialidades_ids': <String>['esp-1'],
                'especialidades_nombres': <String>['Psicología Clínica'],
                'modalidad': 'Presencial',
                'servicios':
                    'Psicoterapia individual', // Falta 'Evaluación clínica'
              },
            ];
          }
          return null;
        },
      );

      final controladorServiciosIncompletos = ControladorPerfilProfesional(
        servicio: servicioServiciosIncompletos,
        repositorioEspecialidades: _RepositorioEspecialidadesFalso(
          catalogo: const [espClinica],
        ),
        servicioUbicacion: _ServicioUbicacionFalso(
          resultadoUbicacion: const ResultadoUbicacionDispositivo.obtenida(
            latitud: -1.67,
            longitud: -78.64,
          ),
        ),
        perfilInicial: perfilBase.copiarCon(
          especialidadesIds: const ['esp-1'],
          especialidadesNombres: const ['Psicología Clínica'],
        ),
      );
      addTearDown(controladorServiciosIncompletos.dispose);

      final guardadoParcial = await controladorServiciosIncompletos
          .guardarPerfil(
            nombre: 'Carlos',
            apellido: 'Pérez',
            servicios: 'Psicoterapia individual, Evaluación clínica',
          );
      expect(guardadoParcial, isFalse);
      expect(controladorServiciosIncompletos.mensajeExito, isNull);
      expect(
        controladorServiciosIncompletos.mensajeError,
        contains('No se pudieron guardar los servicios'),
      );

      // 3. Si la fotografia se sube pero la URL no queda asociada al perfil en base de datos, no informa exito
      final servicioFotoSinAsociar = ServicioPerfilProfesional(
        lectorUsuarioActualId: () => 'prof-100',
        invocadorSubidaFoto: (nombreFuncion, {required cuerpo}) async =>
            const RespuestaSubidaFotoEdge(
              estado: 200,
              datos: {
                'fotoUrl': 'https://res.cloudinary.com/demo/image/upload/v1/psicobloom/profesionales/prof-100.jpg',
              },
            ),
        ejecutorRpc: (nombreFuncion, {parametros}) async {
          if (nombreFuncion == 'obtener_perfil_profesional_propio') {
            return <Map<String, dynamic>>[
              {
                'id': 'prof-100',
                'nombre': 'Carlos',
                'apellido': 'Pérez',
                'correo': 'carlos@ejemplo.com',
                'aprobacion': 'aprobado',
                'cuenta_activa': true,
                'foto_url': null, // La URL no quedo asociada al perfil
                'modalidad': 'Presencial',
              },
            ];
          }
          return null;
        },
      );

      await expectLater(
        () => servicioFotoSinAsociar.subirYGuardarFotografia(
          ArchivoImagenSeleccionada(
            bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3]),
            extensionArchivo: 'jpg',
            tipoMime: 'image/jpeg',
          ),
        ),
        throwsA(
          isA<ErrorPerfilProfesional>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('No se pudo confirmar la actualización de tu fotografía'),
          ),
        ),
      );
    });

    test('No oculta fallos parciales de servicios o fotografia ni ejecuta guardados parciales si falta una RPC', () async {
      expect(
        ServicioPerfilProfesional.duracionServicioMinutosAcordada,
        equals(60),
      );

      // 1. Si falta la RPC actualizar_perfil_profesional_propio, comunica incompatibilidad sin caminos parciales
      final llamadasRpcFaltante = <String>[];
      final servicioSinRpc = ServicioPerfilProfesional(
        lectorUsuarioActualId: () => 'prof-100',
        ejecutorRpc: (nombreFuncion, {parametros}) async {
          llamadasRpcFaltante.add(nombreFuncion);
          if (nombreFuncion == 'actualizar_perfil_profesional_propio') {
            throw const PostgrestException(
              message: 'Could not find function',
              code: 'PGRST202',
            );
          }
          return const [];
        },
      );

      await expectLater(
        () => servicioSinRpc.guardarPerfilCompleto(
          nombre: 'Carlos',
          apellido: 'Pérez',
          especialidadesIds: const ['esp-1'],
          especialidadesNombres: const ['Psicología Clínica'],
          modalidad: 'Presencial',
          servicios: 'Psicoterapia individual',
        ),
        throwsA(
          isA<ErrorPerfilProfesional>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('No se aplicaron cambios parciales'),
          ),
        ),
      );
      // Verifica que no llamo a actualizar_nombre_apellido ni guardados alternativos parciales
      expect(
        llamadasRpcFaltante,
        equals(['actualizar_perfil_profesional_propio']),
      );

      // 2. Si el servidor guarda datos basicos pero omite guardar los servicios solicitados, falla y no reporta guardado completo
      final servicioServiciosIncompletos = ServicioPerfilProfesional(
        lectorUsuarioActualId: () => 'prof-100',
        ejecutorRpc: (nombreFuncion, {parametros}) async {
          if (nombreFuncion == 'actualizar_perfil_profesional_propio') {
            return null;
          }
          if (nombreFuncion == 'obtener_perfil_profesional_propio') {
            return <Map<String, dynamic>>[
              {
                'id': 'prof-100',
                'nombre': 'Carlos',
                'apellido': 'Pérez',
                'correo': 'carlos@ejemplo.com',
                'aprobacion': 'aprobado',
                'cuenta_activa': true,
                'especialidades_ids': <String>['esp-1'],
                'especialidades_nombres': <String>['Psicología Clínica'],
                'modalidad': 'Presencial',
                'servicios':
                    'Psicoterapia individual', // Falta 'Evaluación clínica'
              },
            ];
          }
          return null;
        },
      );

      final controladorServiciosIncompletos = ControladorPerfilProfesional(
        servicio: servicioServiciosIncompletos,
        repositorioEspecialidades: _RepositorioEspecialidadesFalso(
          catalogo: const [espClinica],
        ),
        servicioUbicacion: _ServicioUbicacionFalso(
          resultadoUbicacion: const ResultadoUbicacionDispositivo.obtenida(
            latitud: -1.67,
            longitud: -78.64,
          ),
        ),
        perfilInicial: perfilBase.copiarCon(
          especialidadesIds: const ['esp-1'],
          especialidadesNombres: const ['Psicología Clínica'],
        ),
      );
      addTearDown(controladorServiciosIncompletos.dispose);

      final guardadoParcial = await controladorServiciosIncompletos
          .guardarPerfil(
            nombre: 'Carlos',
            apellido: 'Pérez',
            servicios: 'Psicoterapia individual, Evaluación clínica',
          );
      expect(guardadoParcial, isFalse);
      expect(controladorServiciosIncompletos.mensajeExito, isNull);
      expect(
        controladorServiciosIncompletos.mensajeError,
        contains('No se pudieron guardar los servicios'),
      );

      // 3. Si la fotografia se sube pero la URL no queda asociada al perfil en base de datos, no informa exito
      final servicioFotoSinAsociar = ServicioPerfilProfesional(
        lectorUsuarioActualId: () => 'prof-100',
        invocadorSubidaFoto: (nombreFuncion, {required cuerpo}) async =>
            const RespuestaSubidaFotoEdge(
              estado: 200,
              datos: {
                'fotoUrl': 'https://res.cloudinary.com/demo/image/upload/v1/psicobloom/profesionales/prof-100.jpg',
              },
            ),
        ejecutorRpc: (nombreFuncion, {parametros}) async {
          if (nombreFuncion == 'obtener_perfil_profesional_propio') {
            return <Map<String, dynamic>>[
              {
                'id': 'prof-100',
                'nombre': 'Carlos',
                'apellido': 'Pérez',
                'correo': 'carlos@ejemplo.com',
                'aprobacion': 'aprobado',
                'cuenta_activa': true,
                'foto_url': null, // La URL no quedo asociada al perfil
                'modalidad': 'Presencial',
              },
            ];
          }
          return null;
        },
      );

      await expectLater(
        () => servicioFotoSinAsociar.subirYGuardarFotografia(
          ArchivoImagenSeleccionada(
            bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3]),
            extensionArchivo: 'jpg',
            tipoMime: 'image/jpeg',
          ),
        ),
        throwsA(
          isA<ErrorPerfilProfesional>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('No se pudo confirmar la actualización de tu fotografía'),
          ),
        ),
      );
    });

    testWidgets(
      'Inicio profesional muestra iniciales si no hay foto y refleja la fotografia actualizada al volver desde Perfil sin cerrar sesion',
      (tester) async {
        final servicioPerfil = _ServicioPerfilProfesionalFalso(
          perfilActual: perfilBase,
          archivoSimulado: ArchivoImagenSeleccionada(
            bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
            extensionArchivo: 'png',
            tipoMime: 'image/png',
          ),
        );
        final repoEspecialidades = _RepositorioEspecialidadesFalso(
          catalogo: const [espClinica, espFamiliar],
        );
        final servicioUbicacion = _ServicioUbicacionFalso(
          resultadoUbicacion: const ResultadoUbicacionDispositivo.obtenida(
            latitud: -1.67098,
            longitud: -78.64712,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: TemaPsicobloom.obtenerTema(),
            home: PantallaInicioProfesional(
              perfilInicial: const PerfilUsuario(
                id: 'prof-100',
                nombre: 'Carlos',
                apellido: 'Pérez',
                correo: 'carlos@ejemplo.com',
                rol: 'profesional',
                aprobacion: 'aprobado',
                cuentaActiva: true,
              ),
              servicioPerfilProfesional: servicioPerfil,
              repositorioEspecialidades: repoEspecialidades,
              servicioUbicacion: servicioUbicacion,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Sin fotografia inicial: muestra avatar circular con iniciales reales CP y sin icono de corazon
        expect(find.text('Hola, Carlos 👋'), findsOneWidget);
        expect(
          find.byKey(const Key('avatarBienvenidaProfesional')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('inicialesBienvenidaProfesional')),
          findsOneWidget,
        );
        expect(find.text('CP'), findsOneWidget);
        expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);

        // 2. Ir a Perfil, subir fotografia y regresar a Inicio sin cerrar sesion
        await tester.tap(find.byKey(const Key('pestanaProfesional_perfil')));
        await tester.pumpAndSettle();

        final botonSubirGaleria = find.byKey(
          const Key('botonSubirFotoGaleria'),
        );
        await tester.ensureVisible(botonSubirGaleria);
        await tester.pumpAndSettle();
        await tester.tap(botonSubirGaleria);
        await tester.pumpAndSettle();
        expect(servicioPerfil.llamadasSubirFoto, equals(1));

        await tester.tap(find.byKey(const Key('pestanaProfesional_inicio')));
        await tester.pumpAndSettle();

        // 3. En Inicio se refleja la fotografia actualizada con BoxFit.cover y fallback a iniciales si falla la red
        final claveFoto = ValueKey(
          'fotoBienvenidaProfesional_${servicioPerfil.urlFotoSimulada}',
        );
        expect(find.byKey(claveFoto), findsOneWidget);
        final widgetImagen = tester.widget<Image>(find.byKey(claveFoto));
        expect(widgetImagen.fit, equals(BoxFit.cover));
      },
    );
  });
}
