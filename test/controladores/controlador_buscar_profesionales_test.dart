import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:boom/datos/profesionales_simulados.dart';
import 'package:boom/modelos/filtro_profesional.dart';
import 'package:boom/modelos/profesional.dart';
import 'package:boom/modulos/paciente/controladores/controlador_buscar_profesionales.dart';
import 'package:boom/repositorios/repositorio_profesionales_simulado.dart';

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
}
