import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/administrador/controladores/controlador_administracion.dart';
import 'package:boom/modulos/administrador/servicios/servicio_administracion.dart';
import 'package:boom/modulos/administrador/vistas/pantalla_inicio_administrador.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

class _ServicioAdministracionFalso extends ServicioAdministracion {
  List<ProfesionalPendienteRevision> listaPendientes;
  bool fallarCarga = false;
  bool fallarRevision = false;
  final List<Map<String, dynamic>> decisionesRegistradas = [];

  _ServicioAdministracionFalso({required this.listaPendientes});

  @override
  Future<List<ProfesionalPendienteRevision>>
  listarProfesionalesPendientes() async {
    if (fallarCarga) {
      throw const ErrorAdministracion(
        'No se pudieron consultar las solicitudes pendientes.',
      );
    }
    return List<ProfesionalPendienteRevision>.unmodifiable(listaPendientes);
  }

  @override
  Future<void> revisarProfesional({
    required String profesionalId,
    required bool aprobar,
    String? motivo,
  }) async {
    if (!aprobar && (motivo == null || motivo.trim().length < 5)) {
      throw const ErrorAdministracion(
        'Indica un motivo de rechazo de al menos 5 caracteres.',
      );
    }
    if (fallarRevision) {
      throw const ErrorAdministracion(
        'No se pudo registrar la decisión administrativa.',
      );
    }
    decisionesRegistradas.add(<String, dynamic>{
      'profesionalId': profesionalId,
      'aprobar': aprobar,
      'motivo': motivo?.trim(),
    });
    listaPendientes = listaPendientes
        .where(
          (item) =>
              item.idUsuario != profesionalId &&
              item.idProfesional != profesionalId,
        )
        .toList();
  }
}

void main() {
  const adminAutorizado = PerfilUsuario(
    id: 'admin-1',
    nombre: 'Sara',
    apellido: 'Altamirano',
    correo: 'admin@gmail.com',
    rol: 'administrador',
    aprobacion: 'no_aplica',
    cuentaActiva: true,
  );

  final solicitudUno = ProfesionalPendienteRevision.desdeMapa(const {
    'id': 'usr-prof-101',
    'id_profesional': 'prof-tabla-901',
    'nombre': 'Elena',
    'apellido': 'Montalvo',
    'correo': 'elena.montalvo@gmail.com',
    'especialidad': 'Psicología Clínica',
    'numero_registro': 'MSP-06-2026',
    'creado_en': '2026-11-10T14:30:00Z',
  });

  final solicitudDos = ProfesionalPendienteRevision.desdeMapa(const {
    'id': 'usr-prof-102',
    'id_profesional': 'prof-tabla-902',
    'nombre': 'Roberto',
    'apellido': 'Salazar',
    'correo': 'roberto.salazar@gmail.com',
    'especialidad': 'Psicología Infantil y Adolescente',
    'numero_registro': 'MSP-06-2027',
    'creado_en': '2026-11-11T09:15:00Z',
  });

  group('I2-06 - ControladorAdministracion y distincion id_usuario / id_profesional', () {
    test('Distingue idUsuario e idProfesional y aprueba o rechaza con motivo valido', () async {
      expect(solicitudUno.idUsuario, equals('usr-prof-101'));
      expect(solicitudUno.idProfesional, equals('prof-tabla-901'));
      expect(solicitudUno.idUsuario, isNot(equals(solicitudUno.idProfesional)));

      final servicio = _ServicioAdministracionFalso(
        listaPendientes: [solicitudUno, solicitudDos],
      );
      final controlador = ControladorAdministracion(servicio: servicio);
      addTearDown(controlador.dispose);

      await controlador.cargarPendientes();
      expect(controlador.pendientes.length, equals(2));
      expect(controlador.mensajeError, isNull);

      // 1. Aprobar primera solicitud usando idUsuario
      final aprobada = await controlador.decidirSolicitud(
        profesionalId: solicitudUno.idUsuario,
        aprobar: true,
      );
      expect(aprobada, isTrue);
      expect(controlador.pendientes.length, equals(1));
      expect(controlador.pendientes.single.idUsuario, equals('usr-prof-102'));
      expect(controlador.mensajeExito, contains('aprobada'));

      // 2. Rechazar con motivo menor a 5 caracteres falla y conserva el pendiente
      final rechazoCorto = await controlador.decidirSolicitud(
        profesionalId: solicitudDos.idUsuario,
        aprobar: false,
        motivo: 'no',
      );
      expect(rechazoCorto, isFalse);
      expect(controlador.pendientes.length, equals(1));
      expect(controlador.mensajeError, contains('5 caracteres'));

      // 3. Rechazar con motivo valido (>= 5 caracteres) registra decision y limpia lista
      final rechazoValido = await controlador.decidirSolicitud(
        profesionalId: solicitudDos.idUsuario,
        aprobar: false,
        motivo: 'Número de registro profesional incompleto.',
      );
      expect(rechazoValido, isTrue);
      expect(controlador.pendientes, isEmpty);
      expect(controlador.mensajeExito, contains('rechazada'));
      expect(servicio.decisionesRegistradas.length, equals(2));
    });

    testWidgets(
      'PantallaInicioAdministrador muestra pendientes, valida motivo de rechazo y aprueba solicitudes',
      (WidgetTester probador) async {
        probador.view.physicalSize = const Size(1080, 2400);
        probador.view.devicePixelRatio = 2.0;
        addTearDown(probador.view.resetPhysicalSize);
        addTearDown(probador.view.resetDevicePixelRatio);

        final servicio = _ServicioAdministracionFalso(
          listaPendientes: [solicitudUno, solicitudDos],
        );

        await probador.pumpWidget(
          MaterialApp(
            theme: TemaPsicobloom.obtenerTema(),
            home: PantallaInicioAdministrador(
              perfilInicial: adminAutorizado,
              servicioAdministracion: servicio,
            ),
          ),
        );
        await probador.pumpAndSettle();

        expect(find.text('Elena Montalvo'), findsOneWidget);
        expect(find.text('elena.montalvo@gmail.com'), findsOneWidget);
        expect(find.text('Registro profesional: MSP-06-2026'), findsOneWidget);
        expect(find.text('Roberto Salazar'), findsOneWidget);

        // Aprobar a Elena Montalvo
        await probador.tap(find.text('Aprobar').first);
        await probador.pumpAndSettle();

        expect(find.text('Elena Montalvo'), findsNothing);
        expect(find.text('Solicitud profesional aprobada.'), findsOneWidget);

        // Intentar rechazar a Roberto Salazar con motivo corto y luego valido
        await probador.tap(find.text('Rechazar').first);
        await probador.pumpAndSettle();

        expect(find.text('Rechazar solicitud'), findsOneWidget);
        await probador.enterText(find.byType(TextField), 'mal');
        await probador.tap(find.text('Confirmar rechazo'));
        await probador.pumpAndSettle();

        // El dialogo permanece abierto mostrando el error de validacion
        expect(
          find.text('Indica un motivo de rechazo de al menos 5 caracteres.'),
          findsOneWidget,
        );

        await probador.enterText(
          find.byType(TextField),
          'Falta acreditar el registro sanitario MSP.',
        );
        await probador.tap(find.text('Confirmar rechazo'));
        await probador.pumpAndSettle();

        expect(find.text('Roberto Salazar'), findsNothing);
        expect(
          find.text(
            'No hay solicitudes profesionales pendientes de revisión en este momento.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'PantallaInicioAdministrador bloquea el acceso si el rol no es administrador',
      (WidgetTester probador) async {
        const pacienteNoAutorizado = PerfilUsuario(
          id: 'pac-1',
          nombre: 'Lucía',
          apellido: 'Vega',
          rol: 'paciente',
          aprobacion: 'no_aplica',
          cuentaActiva: true,
        );

        await probador.pumpWidget(
          MaterialApp(
            theme: TemaPsicobloom.obtenerTema(),
            home: PantallaInicioAdministrador(
              perfilInicial: pacienteNoAutorizado,
              servicioAdministracion: _ServicioAdministracionFalso(
                listaPendientes: [solicitudUno],
              ),
            ),
          ),
        );
        await probador.pumpAndSettle();

        // No expone las solicitudes pendientes a un usuario sin rol administrador
        expect(find.text('Elena Montalvo'), findsNothing);
      },
    );
  });
}
