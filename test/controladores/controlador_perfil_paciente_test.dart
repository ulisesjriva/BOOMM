import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_sesion.dart';
import 'package:boom/modulos/paciente/componentes/avatar_paciente.dart';
import 'package:boom/modulos/paciente/controladores/controlador_perfil_paciente.dart';
import 'package:boom/modulos/paciente/servicios/servicio_perfil_paciente.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_perfil_paciente.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

Uint8List _crearPngValido({int rojo = 109, int verde = 75, int azul = 195}) {
  Uint8List bloque(String tipo, Uint8List datos) {
    final tipoBytes = Uint8List.fromList(tipo.codeUnits);
    final salida = BytesBuilder();
    final cabecera = ByteData(4)..setUint32(0, datos.length, Endian.big);
    salida.add(cabecera.buffer.asUint8List());
    salida.add(tipoBytes);
    salida.add(datos);
    final paraCrc = BytesBuilder()
      ..add(tipoBytes)
      ..add(datos);
    var crc = 0xFFFFFFFF;
    for (final byte in paraCrc.toBytes()) {
      crc ^= byte;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >>> 1) ^ 0xEDB88320 : crc >>> 1;
      }
    }
    final crcBytes = ByteData(4)..setUint32(0, crc ^ 0xFFFFFFFF, Endian.big);
    salida.add(crcBytes.buffer.asUint8List());
    return salida.toBytes();
  }

  final ihdr = ByteData(13)
    ..setUint32(0, 2, Endian.big)
    ..setUint32(4, 2, Endian.big)
    ..setUint8(8, 8)
    ..setUint8(9, 6);

  final crudo = BytesBuilder();
  for (var y = 0; y < 2; y++) {
    crudo.addByte(0);
    for (var x = 0; x < 2; x++) {
      crudo.add(<int>[rojo, verde, azul, 255]);
    }
  }
  final comprimido = Uint8List.fromList(zlib.encode(crudo.toBytes()));
  return (BytesBuilder()
        ..add(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ..add(bloque('IHDR', ihdr.buffer.asUint8List()))
        ..add(bloque('IDAT', comprimido))
        ..add(bloque('IEND', Uint8List(0))))
      .toBytes();
}

class _ServicioPerfilPacienteFalso extends ServicioPerfilPaciente {
  PerfilUsuario perfilAlmacenado;
  bool simularErrorGuardado;
  int llamadasGuardar = 0;

  _ServicioPerfilPacienteFalso({
    required this.perfilAlmacenado,
    this.simularErrorGuardado = false,
    super.proveedorSeleccionFoto,
  });

  @override
  Future<PerfilUsuario> obtenerPerfilPropio() async {
    return perfilAlmacenado;
  }

  @override
  Future<PerfilUsuario> actualizarDatosBasicos({
    required String nombre,
    required String apellido,
  }) async {
    llamadasGuardar++;
    if (simularErrorGuardado) {
      throw const ErrorPerfilPaciente('No se pudieron guardar los cambios.');
    }
    perfilAlmacenado = perfilAlmacenado.copiarCon(
      nombre: nombre,
      apellido: apellido,
    );
    return perfilAlmacenado;
  }
}

class _ServicioSesionFalso extends ServicioSesion {
  int llamadasCerrar = 0;
  final String? fotoGoogle;

  _ServicioSesionFalso({this.fotoGoogle});

  @override
  String? obtenerFotoUsuarioActual() => fotoGoogle;

  @override
  Future<void> cerrarSesion() async {
    llamadasCerrar++;
  }
}

void main() {
  const perfilInicial = PerfilUsuario(
    id: 'pac-10',
    nombre: 'Lucía',
    apellido: 'Mendoza',
    correo: 'lucia@ejemplo.com',
    rol: 'paciente',
    aprobacion: 'no_aplica',
    cuentaActiva: true,
  );

  group('ControladorPerfilPaciente - Carga, validacion y persistencia', () {
    test('Carga el perfil actual del paciente desde el servicio', () async {
      final servicio = _ServicioPerfilPacienteFalso(
        perfilAlmacenado: perfilInicial,
      );
      final controlador = ControladorPerfilPaciente(servicio: servicio);

      await controlador.cargarPerfil();

      expect(controlador.estaCargando, isFalse);
      expect(controlador.perfil?.nombre, equals('Lucía'));
      expect(controlador.perfil?.apellido, equals('Mendoza'));
      expect(controlador.mensajeError, isNull);
    });

    test('Valida campos obligatorios y longitud minima', () async {
      final servicio = _ServicioPerfilPacienteFalso(
        perfilAlmacenado: perfilInicial,
      );
      final controlador = ControladorPerfilPaciente(
        servicio: servicio,
        perfilInicial: perfilInicial,
      );

      expect(
        ControladorPerfilPaciente.validarNombreOApellido('', 'nombre'),
        isNotNull,
      );
      expect(
        ControladorPerfilPaciente.validarNombreOApellido('A', 'nombre'),
        isNotNull,
      );
      expect(
        ControladorPerfilPaciente.validarNombreOApellido('Lucía', 'nombre'),
        isNull,
      );

      expect(
        ControladorPerfilPaciente.validarNombreOApellido('', 'apellido'),
        isNotNull,
      );
      expect(
        ControladorPerfilPaciente.validarNombreOApellido('B', 'apellido'),
        isNotNull,
      );
      expect(
        ControladorPerfilPaciente.validarNombreOApellido('Mendoza', 'apellido'),
        isNull,
      );

      final exitoInvalido = await controlador.guardarPerfil(
        nombre: 'A',
        apellido: '',
      );
      expect(exitoInvalido, isFalse);
      expect(servicio.llamadasGuardar, equals(0));
    });

    test(
      'Guarda cambios validos y conserva los datos tras recargar el perfil',
      () async {
        final servicio = _ServicioPerfilPacienteFalso(
          perfilAlmacenado: perfilInicial,
        );
        final controlador = ControladorPerfilPaciente(
          servicio: servicio,
          perfilInicial: perfilInicial,
        );

        final exito = await controlador.guardarPerfil(
          nombre: 'Lucía Fernanda',
          apellido: 'Mendoza Ortiz',
        );

        expect(exito, isTrue);
        expect(servicio.llamadasGuardar, equals(1));
        expect(controlador.perfil?.nombre, equals('Lucía Fernanda'));
        expect(controlador.perfil?.apellido, equals('Mendoza Ortiz'));
        expect(
          controlador.mensajeExito,
          equals('Tu perfil se actualizó correctamente en PsicoBloom.'),
        );

        // Simula nuevo inicio de sesion cargando desde el servicio
        final nuevoControlador = ControladorPerfilPaciente(servicio: servicio);
        await nuevoControlador.cargarPerfil();
        expect(nuevoControlador.perfil?.nombre, equals('Lucía Fernanda'));
        expect(nuevoControlador.perfil?.apellido, equals('Mendoza Ortiz'));
      },
    );

    test('Informa error cuando falla la persistencia en el backend', () async {
      final servicio = _ServicioPerfilPacienteFalso(
        perfilAlmacenado: perfilInicial,
        simularErrorGuardado: true,
      );
      final controlador = ControladorPerfilPaciente(
        servicio: servicio,
        perfilInicial: perfilInicial,
      );

      final exito = await controlador.guardarPerfil(
        nombre: 'Lucía',
        apellido: 'Actualizada',
      );

      expect(exito, isFalse);
      expect(
        controlador.mensajeError,
        equals('No se pudieron guardar los cambios.'),
      );
    });
  });

  group('PantallaPerfilPaciente - Interfaz y flujo de edicion', () {
    testWidgets('Permite editar y guardar cambios en el perfil', (
      WidgetTester probador,
    ) async {
      probador.view.physicalSize = const Size(1080, 2400);
      probador.view.devicePixelRatio = 2.0;
      addTearDown(probador.view.resetPhysicalSize);
      addTearDown(probador.view.resetDevicePixelRatio);

      final servicioPerfil = _ServicioPerfilPacienteFalso(
        perfilAlmacenado: perfilInicial,
      );
      final servicioSesion = _ServicioSesionFalso();
      PerfilUsuario? perfilNotificado;

      await probador.pumpWidget(
        MaterialApp(
          theme: TemaPsicobloom.obtenerTema(),
          home: PantallaPerfilPaciente(
            perfilInicial: perfilInicial,
            servicio: servicioPerfil,
            servicioSesion: servicioSesion,
            alActualizarPerfil: (nuevo) => perfilNotificado = nuevo,
          ),
        ),
      );
      await probador.pumpAndSettle();

      expect(find.text('Lucía Mendoza'), findsOneWidget);
      expect(find.text('lucia@ejemplo.com'), findsAtLeastNWidgets(1));

      await probador.enterText(
        find.byKey(const Key('campoNombrePaciente')),
        'Valeria',
      );
      await probador.enterText(
        find.byKey(const Key('campoApellidoPaciente')),
        'Salazar',
      );

      final botonGuardar = find.byKey(const Key('botonGuardarPerfilPaciente'));
      await probador.ensureVisible(botonGuardar);
      await probador.tap(botonGuardar);
      await probador.pumpAndSettle();

      expect(servicioPerfil.llamadasGuardar, equals(1));
      expect(perfilNotificado?.nombre, equals('Valeria'));
      expect(perfilNotificado?.apellido, equals('Salazar'));
      expect(
        find.text('Tu perfil se actualizó correctamente en PsicoBloom.'),
        findsAtLeastNWidgets(1),
      );
    });

    test(
      'ServicioPerfilPaciente valida formato real JPG/PNG y limite de 5 MB',
      () {
        final jpgValido = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 1]);
        final pngValido = _crearPngValido();
        final gifInvalido = Uint8List.fromList(<int>[
          0x47,
          0x49,
          0x46,
          0x38,
          0x39,
          0x61,
        ]);
        final demasiadoGrande =
            Uint8List(ServicioPerfilPaciente.limiteBytesFotografia + 1)
              ..[0] = 0xFF
              ..[1] = 0xD8
              ..[2] = 0xFF;

        expect(
          ServicioPerfilPaciente.validarFotografiaLocal(
            jpgValido,
            nombreArchivo: 'foto.jpg',
          ).extensionArchivo,
          equals('jpg'),
        );
        expect(
          ServicioPerfilPaciente.validarFotografiaLocal(
            pngValido,
            nombreArchivo: 'foto.png',
          ).extensionArchivo,
          equals('png'),
        );
        expect(
          () => ServicioPerfilPaciente.validarFotografiaLocal(Uint8List(0)),
          throwsA(isA<ErrorPerfilPaciente>()),
        );
        expect(
          () => ServicioPerfilPaciente.validarFotografiaLocal(gifInvalido),
          throwsA(isA<ErrorPerfilPaciente>()),
        );
        expect(
          () => ServicioPerfilPaciente.validarFotografiaLocal(demasiadoGrande),
          throwsA(isA<ErrorPerfilPaciente>()),
        );
      },
    );

    testWidgets(
      'Permite vista previa local desde galeria, cambiar, cancelar y mantiene deshabilitados guardar y eliminar',
      (WidgetTester probador) async {
        probador.view.physicalSize = const Size(1080, 2400);
        probador.view.devicePixelRatio = 2.0;
        addTearDown(probador.view.resetPhysicalSize);
        addTearDown(probador.view.resetDevicePixelRatio);

        final primeraFoto = _crearPngValido(rojo: 109, verde: 75, azul: 195);
        final segundaFoto = _crearPngValido(rojo: 47, verde: 125, azul: 98);
        var seleccion = 0;

        final servicioPerfil = _ServicioPerfilPacienteFalso(
          perfilAlmacenado: perfilInicial,
          proveedorSeleccionFoto: (_) async {
            seleccion++;
            if (seleccion == 1) {
              return ImagenCrudaPaciente(
                bytes: primeraFoto,
                nombreArchivo: 'perfil_uno.png',
              );
            }
            if (seleccion == 2) {
              return ImagenCrudaPaciente(
                bytes: segundaFoto,
                nombreArchivo: 'perfil_dos.png',
              );
            }
            return ImagenCrudaPaciente(
              bytes: Uint8List.fromList(<int>[0x47, 0x49, 0x46, 0x38, 0x39]),
              nombreArchivo: 'invalido.gif',
            );
          },
        );
        final servicioSesion = _ServicioSesionFalso(
          fotoGoogle: 'https://lh3.googleusercontent.com/avatar-demo.jpg',
        );

        await probador.pumpWidget(
          MaterialApp(
            theme: TemaPsicobloom.obtenerTema(),
            home: PantallaPerfilPaciente(
              perfilInicial: perfilInicial,
              servicio: servicioPerfil,
              servicioSesion: servicioSesion,
            ),
          ),
        );
        await probador.pumpAndSettle();

        // Muestra AvatarPaciente reutilizable con foto de Google OAuth inicialmente.
        expect(find.byType(AvatarPaciente), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('avatarPacientePerfil')),
            matching: find.byType(Image),
          ),
          findsOneWidget,
        );

        // Botones futuros de almacenamiento visibles pero deshabilitados.
        final botonGuardarFoto = probador.widget<ElevatedButton>(
          find.byKey(const Key('botonGuardarFotoPaciente')),
        );
        final botonEliminarFoto = probador.widget<OutlinedButton>(
          find.byKey(const Key('botonEliminarFotoPaciente')),
        );
        expect(botonGuardarFoto.onPressed, isNull);
        expect(botonEliminarFoto.onPressed, isNull);
        expect(
          find.byKey(const Key('avisoAlmacenamientoFotoPendiente')),
          findsOneWidget,
        );

        // Selecciona primera fotografia desde la galeria -> vista previa local.
        await probador.tap(
          find.byKey(const Key('botonSeleccionarFotoPaciente')),
        );
        await probador.pumpAndSettle();

        expect(
          find.byKey(const Key('insigniaVistaPreviaFoto')),
          findsOneWidget,
        );
        expect(find.text('Elegir otra foto'), findsOneWidget);
        expect(find.text('Cancelar selección'), findsOneWidget);
        expect(find.textContaining('perfil_uno.png'), findsOneWidget);

        // Selecciona otra fotografia -> reemplaza vista previa local.
        await probador.tap(
          find.byKey(const Key('botonSeleccionarFotoPaciente')),
        );
        await probador.pumpAndSettle();
        expect(find.textContaining('perfil_dos.png'), findsOneWidget);

        // Selecciona archivo con formato invalido -> informa error y conserva vista previa.
        await probador.tap(
          find.byKey(const Key('botonSeleccionarFotoPaciente')),
        );
        await probador.pumpAndSettle();
        expect(
          find.byKey(const Key('errorFotografiaPaciente')),
          findsOneWidget,
        );
        expect(find.textContaining('perfil_dos.png'), findsOneWidget);

        // Cancela la seleccion -> quita la vista previa local y vuelve a foto actual.
        await probador.tap(find.byKey(const Key('botonCancelarFotoPaciente')));
        await probador.pumpAndSettle();
        expect(find.byKey(const Key('insigniaVistaPreviaFoto')), findsNothing);
        expect(find.text('Seleccionar de la galería'), findsOneWidget);
      },
    );
  });
}
