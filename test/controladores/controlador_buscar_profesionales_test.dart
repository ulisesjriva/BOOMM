import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:boom/datos/profesionales_simulados.dart';
import 'package:boom/modelos/filtro_profesional.dart';
import 'package:boom/modelos/profesional.dart';
import 'package:boom/modulos/paciente/controladores/controlador_buscar_profesionales.dart';
import 'package:boom/modulos/paciente/servicios/servicio_rutas_consultorio.dart';
import 'package:boom/modulos/profesional/servicios/servicio_ubicacion_consultorio.dart';
import 'package:boom/repositorios/repositorio_profesionales_simulado.dart';

class _ServicioUbicacionFija extends ServicioUbicacionConsultorio {
  final ResultadoUbicacionDispositivo resultado;

  const _ServicioUbicacionFija(this.resultado);

  @override
  Future<ResultadoUbicacionDispositivo> obtenerUbicacionActual() async =>
      resultado;
}

class RepositorioConDemora extends RepositorioProfesionalesSimulado {
  final solicitudes = <Completer<List<Profesional>>>[];

  @override
  Future<List<Profesional>> buscarProfesionales(FiltroProfesional filtro) {
    final solicitud = Completer<List<Profesional>>();
    solicitudes.add(solicitud);
    return solicitud.future;
  }
}

class RepositorioConFallo extends RepositorioProfesionalesSimulado {
  bool debeFallar = true;

  @override
  Future<List<Profesional>> buscarProfesionales(FiltroProfesional filtro) {
    if (debeFallar) return Future.error(StateError('Fallo simulado'));
    return super.buscarProfesionales(filtro);
  }
}

void main() {
  test('Carga catalogos, aplica filtros y permite restablecerlos', () async {
    final controlador = ControladorBuscarProfesionales(
      repositorio: RepositorioProfesionalesSimulado(),
    );
    addTearDown(controlador.dispose);
    await controlador.inicializar();
    expect(controlador.estaCargando, isFalse);
    expect(controlador.mensajeError, isNull);
    expect(controlador.especialidades, contains('Todas'));
    expect(controlador.profesionales, isNotEmpty);
    await controlador.cambiarModalidad('Virtual');
    expect(controlador.profesionales, isNotEmpty);
    expect(
      controlador.profesionales.every(
        (profesional) => profesional.modalidad == 'Virtual',
      ),
      isTrue,
    );
    await controlador.actualizarTexto('TerminoInexistenteXYZ');
    expect(controlador.profesionales, isEmpty);
    await controlador.limpiarFiltros();
    expect(controlador.filtro.tieneFiltrosActivos, isFalse);
    expect(controlador.profesionales.length, profesionalesSimulados.length);
  });

  test('Una respuesta antigua no reemplaza la busqueda mas reciente', () async {
    final repositorio = RepositorioConDemora();
    final controlador = ControladorBuscarProfesionales(
      repositorio: repositorio,
    );
    addTearDown(controlador.dispose);
    final primera = controlador.actualizarTexto('primera');
    final segunda = controlador.actualizarTexto('segunda');
    final actuales = [profesionalesSimulados.last];
    repositorio.solicitudes[1].complete(actuales);
    await segunda;
    repositorio.solicitudes[0].complete([profesionalesSimulados.first]);
    await primera;
    expect(controlador.profesionales, actuales);
    expect(controlador.filtro.textoBusqueda, 'segunda');
    expect(controlador.estaCargando, isFalse);
  });

  test('Informa un fallo y permite reintentar la consulta', () async {
    final repositorio = RepositorioConFallo();
    final controlador = ControladorBuscarProfesionales(
      repositorio: repositorio,
    );
    addTearDown(controlador.dispose);
    await controlador.inicializar();
    expect(controlador.mensajeError, isNotNull);
    expect(controlador.estaCargando, isFalse);
    repositorio.debeFallar = false;
    await controlador.inicializar();
    expect(controlador.mensajeError, isNull);
    expect(controlador.profesionales, isNotEmpty);
  });

  test('Una consulta pendiente no notifica despues de cerrar', () async {
    final repositorio = RepositorioConDemora();
    final controlador = ControladorBuscarProfesionales(
      repositorio: repositorio,
    );
    var notificaciones = 0;
    controlador.addListener(() => notificaciones++);
    final consulta = controlador.buscar();
    final cantidadAntesDeCerrar = notificaciones;
    controlador.dispose();
    repositorio.solicitudes.single.complete(profesionalesSimulados);
    await consulta;
    expect(notificaciones, cantidadAntesDeCerrar);
  });

  test('Filtro de cercania ordena por distancia y tiempo de ruta, y conserva resultados si no hay permiso GPS', () async {
    const profLejano = Profesional(
      id: 'prof-lejano',
      nombre: 'Dr. Lejano',
      especialidad: 'Psicología Clínica',
      modalidad: 'Presencial',
      disponibilidadTexto: 'Hoy',
      distanciaTexto: '3.0 km',
      direccionConsultorio: 'Norte',
      latitud: -1.6500,
      longitud: -78.6600,
    );
    const profCercano = Profesional(
      id: 'prof-cercano',
      nombre: 'Dra. Cercana',
      especialidad: 'Psicología Clínica',
      modalidad: 'Presencial',
      disponibilidadTexto: 'Hoy',
      distanciaTexto: '0.5 km',
      direccionConsultorio: 'Centro',
      latitud: -1.6710,
      longitud: -78.6470,
    );

    final controladorConGps = ControladorBuscarProfesionales(
      repositorio: RepositorioProfesionalesSimulado(
        fuenteDatos: const [profLejano, profCercano],
      ),
      servicioUbicacion: const _ServicioUbicacionFija(
        ResultadoUbicacionDispositivo.obtenida(
          latitud: -1.6709,
          longitud: -78.6471,
        ),
      ),
      servicioRutas: ServicioRutasConsultorio(
        invocadorPorTransporte:
            ({
              required origenLatitud,
              required origenLongitud,
              required destinoLatitud,
              required destinoLongitud,
              required medioTransporte,
            }) async {
              final esCercano =
                  (destinoLatitud - profCercano.latitud).abs() < 0.001;
              return <String, dynamic>{
                'puntosRuta': <Map<String, double>>[
                  {'latitud': origenLatitud, 'longitud': origenLongitud},
                  {'latitud': destinoLatitud, 'longitud': destinoLongitud},
                ],
                // Simula que la ruta al lejano toma menos tiempo (180 s vs 420 s)
                'distanciaMetros': esCercano ? 900.0 : 2500.0,
                'duracionEstimadaSegundos': esCercano ? 420 : 180,
                'medioTransporte': medioTransporte,
                'proveedor': 'openrouteservice',
              };
            },
      ),
    );
    addTearDown(controladorConGps.dispose);

    await controladorConGps.inicializar();
    await controladorConGps.cambiarCercania(
      FiltroProfesional.opcionCercaniaMasCercanos,
    );
    expect(controladorConGps.mensajeCercania, isNull);
    expect(controladorConGps.profesionales.first.id, 'prof-cercano');
    expect(controladorConGps.obtenerResumenCercania('prof-cercano'), isNotNull);

    await controladorConGps.cambiarCercania(
      FiltroProfesional.opcionCercaniaMenorTiempoRuta,
    );
    expect(controladorConGps.mensajeCercania, isNull);
    expect(controladorConGps.profesionales.first.id, 'prof-lejano');

    // Sin permiso GPS: no rompe la busqueda y muestra mensaje claro
    final controladorSinGps = ControladorBuscarProfesionales(
      repositorio: RepositorioProfesionalesSimulado(
        fuenteDatos: const [profLejano, profCercano],
      ),
      servicioUbicacion: const _ServicioUbicacionFija(
        ResultadoUbicacionDispositivo.fallo(
          EstadoUbicacionDispositivo.permisoRechazado,
          'Permiso denegado',
        ),
      ),
    );
    addTearDown(controladorSinGps.dispose);

    await controladorSinGps.inicializar();
    await controladorSinGps.cambiarCercania(
      FiltroProfesional.opcionCercaniaMasCercanos,
    );
    expect(controladorSinGps.profesionales.length, 2);
    expect(controladorSinGps.mensajeCercania, isNotNull);
    expect(controladorSinGps.mensajeCercania, contains('demás filtros'));
  });

  test(
    'Filtro de cercania ordena por distancia y tiempo de ruta, y conserva resultados si no hay permiso GPS',
    () async {
      const profLejano = Profesional(
        id: 'prof-lejano',
        nombre: 'Dr. Lejano',
        especialidad: 'Psicología Clínica',
        modalidad: 'Presencial',
        disponibilidadTexto: 'Hoy',
        distanciaTexto: '3.0 km',
        direccionConsultorio: 'Norte',
        latitud: -1.6500,
        longitud: -78.6600,
      );
      const profCercano = Profesional(
        id: 'prof-cercano',
        nombre: 'Dra. Cercana',
        especialidad: 'Psicología Clínica',
        modalidad: 'Presencial',
        disponibilidadTexto: 'Hoy',
        distanciaTexto: '0.5 km',
        direccionConsultorio: 'Centro',
        latitud: -1.6710,
        longitud: -78.6470,
      );

      final controladorConGps = ControladorBuscarProfesionales(
        repositorio: RepositorioProfesionalesSimulado(
          fuenteDatos: const [profLejano, profCercano],
        ),
        servicioUbicacion: const _ServicioUbicacionFija(
          ResultadoUbicacionDispositivo.obtenida(
            latitud: -1.6709,
            longitud: -78.6471,
          ),
        ),
        servicioRutas: ServicioRutasConsultorio(
          invocadorPorTransporte:
              ({
                required origenLatitud,
                required origenLongitud,
                required destinoLatitud,
                required destinoLongitud,
                required medioTransporte,
              }) async {
                final esCercano = (destinoLatitud - profCercano.latitud).abs() < 0.001;
                return <String, dynamic>{
                  'puntosRuta': <Map<String, double>>[
                    {'latitud': origenLatitud, 'longitud': origenLongitud},
                    {'latitud': destinoLatitud, 'longitud': destinoLongitud},
                  ],
                  // Simula que la ruta al lejano toma menos tiempo (180 s vs 420 s)
                  'distanciaMetros': esCercano ? 900.0 : 2500.0,
                  'duracionEstimadaSegundos': esCercano ? 420 : 180,
                  'medioTransporte': medioTransporte,
                  'proveedor': 'openrouteservice',
                };
              },
        ),
      );
      addTearDown(controladorConGps.dispose);

      await controladorConGps.inicializar();
      await controladorConGps.cambiarCercania(
        FiltroProfesional.opcionCercaniaMasCercanos,
      );
      expect(controladorConGps.mensajeCercania, isNull);
      expect(controladorConGps.profesionales.first.id, 'prof-cercano');
      expect(
        controladorConGps.obtenerResumenCercania('prof-cercano'),
        isNotNull,
      );

      await controladorConGps.cambiarCercania(
        FiltroProfesional.opcionCercaniaMenorTiempoRuta,
      );
      expect(controladorConGps.mensajeCercania, isNull);
      expect(controladorConGps.profesionales.first.id, 'prof-lejano');

      // Sin permiso GPS: no rompe la busqueda y muestra mensaje claro
      final controladorSinGps = ControladorBuscarProfesionales(
        repositorio: RepositorioProfesionalesSimulado(
          fuenteDatos: const [profLejano, profCercano],
        ),
        servicioUbicacion: const _ServicioUbicacionFija(
          ResultadoUbicacionDispositivo.fallo(
            EstadoUbicacionDispositivo.permisoRechazado,
            'Permiso denegado',
          ),
        ),
      );
      addTearDown(controladorSinGps.dispose);

      await controladorSinGps.inicializar();
      await controladorSinGps.cambiarCercania(
        FiltroProfesional.opcionCercaniaMasCercanos,
      );
      expect(controladorSinGps.profesionales.length, 2);
      expect(controladorSinGps.mensajeCercania, isNotNull);
      expect(
        controladorSinGps.mensajeCercania,
        contains('demás filtros'),
      );
    },
  );
}
