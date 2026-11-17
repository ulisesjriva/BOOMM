import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/administrador/controladores/controlador_administracion.dart';
import 'package:boom/modulos/administrador/servicios/servicio_administracion.dart';
import 'package:boom/modulos/administrador/vistas/pantalla_inicio_administrador.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

void main() {
  const adminAutorizado = PerfilUsuario(
    id: 'adm-1',
    nombre: 'Sara',
    apellido: 'Altamirano',
    correo: 'admin@psicobloom.ec',
    rol: 'administrador',
    aprobacion: 'aprobado',
    cuentaActiva: true,
  );

  group('Modulo Administrador completo (servicios, controlador y UI)', () {
    test('ServicioAdministracion traduce errores de ultimo admin, duplicados y rol no autorizado sin detalles tecnicos', () async {
      final servicioUltimoAdmin = ServicioAdministracion(
        ejecutorRpc: (nombreFuncion, {parametros}) async {
          if (nombreFuncion == 'cambiar_estado_cuenta') {
            throw const PostgrestException(
              message: 'No se puede desactivar al último administrador activo del sistema.',
              code: '42501',
            );
          }
          if (nombreFuncion == 'guardar_especialidad_administracion') {
            throw const PostgrestException(
              message: 'duplicate key value violates unique constraint',
              code: '23505',
            );
          }
          if (nombreFuncion == 'resumen_administracion') {
            throw const PostgrestException(
              message: 'permission denied for schema psicobloom_interno',
              code: '42501',
            );
          }
          throw const PostgrestException(
            message: 'internal postgres failure 42P01',
            code: '42P01',
          );
        },
      );

      final ctrl = ControladorAdministracion(servicio: servicioUltimoAdmin);
      addTearDown(ctrl.dispose);

      final desactivado = await ctrl.cambiarEstadoCuenta(
        usuarioId: 'adm-2',
        activo: false,
        motivo: 'Prueba de protección',
      );
      expect(desactivado, isFalse);
      expect(ctrl.mensajeError, contains('último administrador activo'));

      final espDuplicada = await ctrl.guardarEspecialidad(
        nombre: 'Psicología Clínica',
      );
      expect(espDuplicada, isFalse);
      expect(
        ctrl.mensajeError,
        equals('Ya existe un registro con ese nombre.'),
      );

      await ctrl.cargarCitas();
      expect(ctrl.mensajeError, isNot(contains('42P01')));
      expect(ctrl.mensajeError, isNot(contains('postgres')));
    });

    test('ControladorAdministracion gestiona paginacion, especialidades sin duplicados, activacion separada y CSV', () async {
      final especialidadesDb = <Map<String, dynamic>>[
        {
          'id': 'esp-1',
          'nombre': 'Psicología Clínica',
          'descripcion': 'Terapia clínica',
          'activa': true,
        },
      ];
      var profesionalCuentaActiva = false;
      var profesionalAprobacion = 'pendiente';

      final servicio = ServicioAdministracion(
        ejecutorRpc: (nombreFuncion, {parametros}) async {
          switch (nombreFuncion) {
            case 'listar_usuarios_administracion':
              final pagina = parametros?['p_pagina'] as int? ?? 0;
              if (pagina == 0) {
                return [
                  {
                    'id': 'usr-1',
                    'nombre': 'Ana',
                    'apellido': 'Pérez',
                    'correo': 'ana@correo.com',
                    'rol': 'paciente',
                    'cuenta_activa': true,
                    'total_registros': 2,
                  },
                ];
              }
              return [
                {
                  'id': 'usr-2',
                  'nombre': 'Luis',
                  'apellido': 'Mena',
                  'correo': 'luis@correo.com',
                  'rol': 'profesional',
                  'cuenta_activa': profesionalCuentaActiva,
                  'aprobacion': profesionalAprobacion,
                  'total_registros': 2,
                },
              ];
            case 'listar_profesionales_administracion':
              return [
                {
                  'id_usuario': 'usr-2',
                  'id_profesional': 'prof-2',
                  'nombre': 'Luis',
                  'apellido': 'Mena',
                  'correo': 'luis@correo.com',
                  'aprobacion': profesionalAprobacion,
                  'cuenta_activa': profesionalCuentaActiva,
                  'especialidad': 'Psicología Clínica',
                },
              ];
            case 'cambiar_estado_cuenta':
              profesionalCuentaActiva = parametros?['p_activo'] as bool;
              return null;
            case 'listar_especialidades_administracion':
              return especialidadesDb;
            case 'guardar_especialidad_administracion':
              final nombre = (parametros?['p_nombre'] as String).trim();
              final existe = especialidadesDb.any(
                (e) =>
                    (e['nombre'] as String).toLowerCase() ==
                    nombre.toLowerCase(),
              );
              if (existe) {
                throw const PostgrestException(
                  message:
                      'Ya existe una especialidad registrada con ese nombre.',
                  code: '23505',
                );
              }
              especialidadesDb.add({
                'id': 'esp-2',
                'nombre': nombre,
                'descripcion': parametros?['p_descripcion'],
                'activa': true,
              });
              return 'esp-2';
            case 'cambiar_estado_especialidad_administracion':
              final id = parametros?['p_id_especialidad'] as String;
              for (final item in especialidadesDb) {
                if (item['id'] == id) item['activa'] = parametros?['p_activa'];
              }
              return null;
            case 'listar_citas_administracion':
              return [
                {
                  'id_cita': 'cita-1',
                  'paciente_nombre': 'Ana "Anita" Pérez',
                  'profesional_nombre': 'Luis Mena',
                  'fecha': '2026-11-20',
                  'hora_inicio': '10:00',
                  'hora_fin': '11:00',
                  'estado': 'confirmada',
                  'total_registros': 1,
                },
              ];
            default:
              return null;
          }
        },
      );

      final ctrl = ControladorAdministracion(servicio: servicio);
      addTearDown(ctrl.dispose);

      // 1. Paginacion de usuarios
      await ctrl.cargarUsuarios(reiniciar: true);
      expect(ctrl.usuarios.length, equals(1));
      expect(ctrl.hayMasUsuarios, isTrue);
      await ctrl.cargarUsuarios(reiniciar: false);
      expect(ctrl.usuarios.length, equals(2));
      expect(ctrl.hayMasUsuarios, isFalse);

      // 2. Reactivar profesional deshabilitado NO aprueba automaticamente su perfil
      await ctrl.cargarProfesionales(estado: 'deshabilitado');
      expect(ctrl.profesionales.single.cuentaActiva, isFalse);
      expect(ctrl.profesionales.single.aprobacion, equals('pendiente'));

      final reactivado = await ctrl.cambiarEstadoCuenta(
        usuarioId: 'usr-2',
        activo: true,
        motivo: 'Verificación de identidad completada.',
      );
      expect(reactivado, isTrue);
      expect(ctrl.profesionales.single.cuentaActiva, isTrue);
      expect(ctrl.profesionales.single.aprobacion, equals('pendiente'));

      // 3. Especialidades: evita duplicados y desactiva sin borrar
      await ctrl.cargarEspecialidades();
      final dup = await ctrl.guardarEspecialidad(
        nombre: '  psicología   clínica ',
      );
      expect(dup, isFalse);
      final creada = await ctrl.guardarEspecialidad(nombre: 'Terapia Familiar');
      expect(creada, isTrue);
      expect(ctrl.especialidades.length, equals(2));
      await ctrl.cambiarEstadoEspecialidad(
        idEspecialidad: 'esp-1',
        activa: false,
      );
      expect(ctrl.especialidades.first.activa, isFalse);

      // 4. Supervision y exportacion CSV de citas
      await ctrl.cargarCitas(estado: 'confirmada');
      final csv = ctrl.generarCsvCitas();
      expect(
        csv,
        contains('Paciente,Profesional,Fecha,Hora inicio,Hora fin,Estado'),
      );
      expect(csv, contains('"Ana ""Anita"" Pérez","Luis Mena","2026-11-20"'));
    });

    testWidgets(
      'Navegacion de 5 pestanas, Panel general, Usuarios, Profesionales, Especialidades, Citas y Mantenimiento',
      (WidgetTester probador) async {
        probador.view.physicalSize = const Size(1080, 2400);
        probador.view.devicePixelRatio = 2.0;
        addTearDown(probador.view.resetPhysicalSize);
        addTearDown(probador.view.resetDevicePixelRatio);

        final servicio = ServicioAdministracion(
          ejecutorRpc: (nombreFuncion, {parametros}) async {
            switch (nombreFuncion) {
              case 'listar_profesionales_pendientes':
                return const [];
              case 'resumen_administracion':
                return {
                  'usuarios_registrados': 12,
                  'profesionales_activos_aprobados': 4,
                  'profesionales_pendientes': 1,
                  'citas_pendientes': 2,
                  'citas_confirmadas': 5,
                  'citas_canceladas': 1,
                  'citas_rechazadas': 0,
                  'citas_finalizadas': 3,
                  'total_citas': 11,
                  'actividad_reciente': [
                    {
                      'tipo': 'nuevo_profesional',
                      'titulo': 'Nuevo profesional registrado',
                      'detalle': 'Camila Ruiz se registró como profesional',
                      'fecha': '2026-11-16T12:00:00Z',
                    },
                  ],
                };
              case 'listar_usuarios_administracion':
                return [
                  {
                    'id': 'u-1',
                    'nombre': 'Camila',
                    'apellido': 'Ruiz',
                    'correo': 'camila@ejemplo.com',
                    'rol': 'profesional',
                    'cuenta_activa': true,
                    'aprobacion': 'aprobado',
                    'total_registros': 1,
                  },
                ];
              case 'listar_profesionales_administracion':
                return [
                  {
                    'id_usuario': 'u-1',
                    'id_profesional': 'p-1',
                    'nombre': 'Camila',
                    'apellido': 'Ruiz',
                    'correo': 'camila@ejemplo.com',
                    'aprobacion': 'aprobado',
                    'cuenta_activa': true,
                    'especialidad': 'Psicología Clínica',
                  },
                ];
              case 'listar_especialidades_administracion':
                return [
                  {
                    'id': 'e-1',
                    'nombre': 'Psicología Clínica',
                    'descripcion': 'Atención clínica',
                    'activa': true,
                  },
                ];
              case 'listar_citas_administracion':
                return [
                  {
                    'id_cita': 'c-1',
                    'paciente_nombre': 'Juan Pérez',
                    'profesional_nombre': 'Camila Ruiz',
                    'fecha': '2026-11-20',
                    'hora_inicio': '10:00',
                    'hora_fin': '11:00',
                    'estado': 'confirmada',
                    'total_registros': 1,
                  },
                ];
              default:
                return null;
            }
          },
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

        // Inicio: Panel general y donut
        expect(find.text('Panel de administración'), findsOneWidget);
        final donut = find.byKey(const Key('tarjetaDonutCitasAdmin'));
        await probador.scrollUntilVisible(
          donut,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await probador.pumpAndSettle();
        expect(donut, findsOneWidget);
        expect(find.text('11'), findsOneWidget);
        final actividad = find.text('Nuevo profesional registrado');
        await probador.scrollUntilVisible(
          actividad,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await probador.pumpAndSettle();
        expect(actividad, findsOneWidget);

        // Tab Usuarios
        await probador.tap(find.byKey(const Key('navAdmin_usuarios')));
        await probador.pumpAndSettle();
        expect(find.text('Gestión de usuarios'), findsOneWidget);
        expect(find.text('Camila Ruiz'), findsOneWidget);

        // Tab Profesionales
        await probador.tap(find.byKey(const Key('navAdmin_profesionales')));
        await probador.pumpAndSettle();
        expect(find.text('Desactivar cuenta'), findsOneWidget);

        // Tab Especialidades
        await probador.tap(find.byKey(const Key('navAdmin_especialidades')));
        await probador.pumpAndSettle();
        expect(find.text('Psicología Clínica'), findsOneWidget);

        // Tab Citas + Exportar CSV
        await probador.tap(find.byKey(const Key('navAdmin_citas')));
        await probador.pumpAndSettle();
        expect(find.text('Juan Pérez → Camila Ruiz'), findsOneWidget);
        await probador.tap(find.byKey(const Key('botonExportarCitasCsv')));
        await probador.pumpAndSettle();
        expect(find.text('Exportación CSV lista'), findsOneWidget);
        await probador.tap(find.text('Cerrar'));
        await probador.pumpAndSettle();

        // Pantalla Mantenimiento + Registros de prueba honesto
        await probador.tap(find.byKey(const Key('botonMantenimientoAdmin')));
        await probador.pumpAndSettle();
        expect(find.text('Mantenimiento de información'), findsOneWidget);
        await probador.tap(
          find.byKey(const Key('mantenimiento_registrosPrueba')),
        );
        await probador.pumpAndSettle();
        expect(
          find.textContaining('no incluye una marca explícita'),
          findsOneWidget,
        );
      },
    );
  });
}
