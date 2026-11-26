import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  bool simularErrorSubidaFoto;
  bool simularErrorEliminacionFoto;
  Completer<void>? esperaSubidaFoto;
  int llamadasGuardar = 0;
  int llamadasSubirFoto = 0;
  int llamadasEliminarFoto = 0;
  ImageSource? ultimoOrigenSeleccionado;
  final String urlFotoSubida =
      'https://res.cloudinary.com/demo/image/upload/psicobloom/pacientes/pac-10_nueva.png';

  _ServicioPerfilPacienteFalso({
    required this.perfilAlmacenado,
    this.simularErrorGuardado = false,
    this.simularErrorSubidaFoto = false,
    this.simularErrorEliminacionFoto = false,
    this.esperaSubidaFoto,
    super.proveedorSeleccionFoto,
  });

  @override
  Future<ArchivoFotoPacienteSeleccionada?> seleccionarFotografia({
    ImageSource origen = ImageSource.gallery,
  }) async {
    ultimoOrigenSeleccionado = origen;
    return super.seleccionarFotografia(origen: origen);
  }

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

  @override
  Future<PerfilUsuario> subirYGuardarFotografia(
    ArchivoFotoPacienteSeleccionada imagen,
  ) async {
    llamadasSubirFoto++;
    if (esperaSubidaFoto != null) {
      await esperaSubidaFoto!.future;
    }
    if (simularErrorSubidaFoto) {
      throw const ErrorPerfilPaciente('No se pudo actualizar la foto');
    }
    perfilAlmacenado = perfilAlmacenado.copiarCon(
      fotoUrl: urlFotoSubida,
      tieneFotoPersonalizada: true,
    );
    return perfilAlmacenado;
  }

  @override
  Future<PerfilUsuario> eliminarFotografia() async {
    llamadasEliminarFoto++;
    if (simularErrorEliminacionFoto) {
      throw const ErrorPerfilPaciente('No se pudo eliminar la foto');
    }
    perfilAlmacenado = perfilAlmacenado.copiarCon(limpiarFotoUrl: true);
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
    ServicioSesion.limpiarPerfilPacienteSincronizado();
  }
}

void main() {
  setUp(() {
    ServicioSesion.limpiarPerfilPacienteSincronizado();
  });

  tearDown(() {
    ServicioSesion.limpiarPerfilPacienteSincronizado();
  });

  const perfilInicial = PerfilUsuario(
    id: 'pac-10',
    nombre: 'Lucía',
    apellido: 'Mendoza',
    correo: 'lucia@ejemplo.com',
    rol: 'paciente',
    aprobacion: 'no_aplica',
    cuentaActiva: true,
  );

  const perfilConFotoPersonalizada = PerfilUsuario(
    id: 'pac-10',
    nombre: 'Lucía',
    apellido: 'Mendoza',
    correo: 'lucia@ejemplo.com',
    rol: 'paciente',
    aprobacion: 'no_aplica',
    cuentaActiva: true,
    fotoUrl: 'https://res.cloudinary.com/demo/image/upload/psicobloom/pacientes/pac-10_actual.jpg',
    tieneFotoPersonalizada: true,
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

    test('ServicioPerfilPaciente invoca Edge Function segura para subir y eliminar sin enviar URLs arbitrarias', () async {
      Map<String, dynamic>? ultimoCuerpoEdge;
      String? fotoGuardada;
      var tienePersonalizada = false;

      final servicio = ServicioPerfilPaciente(
        lectorUsuarioActualId: () => 'pac-10',
        invocadorFotoEdge: (nombreFuncion, {required cuerpo}) async {
          expect(
            nombreFuncion,
            equals(ServicioPerfilPaciente.nombreFuncionGestionarFoto),
          );
          ultimoCuerpoEdge = cuerpo;
          if (cuerpo['accion'] == 'subir') {
            expect(cuerpo.containsKey('archivoBase64'), isTrue);
            expect(cuerpo.containsKey('fotoUrl'), isFalse);
            expect(cuerpo.containsKey('publicId'), isFalse);
            fotoGuardada = 'https://res.cloudinary.com/demo/image/upload/psicobloom/pacientes/pac-10_ok.png';
            tienePersonalizada = true;
            return RespuestaFotoPacienteEdge(
              estado: 200,
              datos: <String, dynamic>{
                'fotoUrl': fotoGuardada,
                'tieneFotoPersonalizada': true,
              },
            );
          }
          if (cuerpo['accion'] == 'eliminar') {
            fotoGuardada = null;
            tienePersonalizada = false;
            return const RespuestaFotoPacienteEdge(
              estado: 200,
              datos: <String, dynamic>{
                'eliminada': true,
                'fotoUrl': null,
                'tieneFotoPersonalizada': false,
              },
            );
          }
          return const RespuestaFotoPacienteEdge(estado: 400, datos: null);
        },
        ejecutorRpc: (nombreFuncion, {parametros}) async {
          expect(nombreFuncion, equals('obtener_perfil_paciente_propio'));
          return <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'pac-10',
              'nombre': 'Lucía',
              'apellido': 'Mendoza',
              'correo': 'lucia@ejemplo.com',
              'rol': 'paciente',
              'aprobacion': 'no_aplica',
              'cuenta_activa': true,
              'foto_url': fotoGuardada,
              'tiene_foto_personalizada': tienePersonalizada,
            },
          ];
        },
      );

      final archivo = ServicioPerfilPaciente.validarFotografiaLocal(
        _crearPngValido(),
        nombreArchivo: 'avatar.png',
      );

      final perfilConFoto = await servicio.subirYGuardarFotografia(archivo);
      expect(ultimoCuerpoEdge?['accion'], equals('subir'));
      expect(perfilConFoto.tieneFotoPersonalizada, isTrue);
      expect(perfilConFoto.fotoUrl, equals(fotoGuardada));

      final perfilSinFoto = await servicio.eliminarFotografia();
      expect(ultimoCuerpoEdge?['accion'], equals('eliminar'));
      expect(perfilSinFoto.tieneFotoPersonalizada, isFalse);
      expect(perfilSinFoto.fotoUrl, isNull);
    });

    test('Maneja camara no disponible o permiso denegado sin alterar la foto actual', () async {
      final servicioSinCamara = _ServicioPerfilPacienteFalso(
        perfilAlmacenado: perfilConFotoPersonalizada,
        proveedorSeleccionFoto: (_) async {
          throw PlatformException(code: 'camera_access_denied');
        },
      );
      final controlador = ControladorPerfilPaciente(
        servicio: servicioSinCamara,
        perfilInicial: perfilConFotoPersonalizada,
      );

      final resultado = await controlador.cambiarFotografia(
        origen: ImageSource.camera,
      );

      expect(
        resultado.estado,
        equals(EstadoOperacionFotoPaciente.errorSeleccion),
      );
      expect(resultado.mensaje, contains('cámara'));
      expect(
        controlador.perfil?.fotoUrl,
        equals(perfilConFotoPersonalizada.fotoUrl),
      );
      expect(servicioSinCamara.llamadasSubirFoto, equals(0));
    });

    test('Bloquea operaciones concurrentes de subida o eliminacion mientras hay una foto en proceso', () async {
      final esperaSubida = Completer<void>();
      final servicio = _ServicioPerfilPacienteFalso(
        perfilAlmacenado: perfilConFotoPersonalizada,
        esperaSubidaFoto: esperaSubida,
        proveedorSeleccionFoto: (_) async => ImagenCrudaPaciente(
          bytes: _crearPngValido(),
          nombreArchivo: 'primera.png',
        ),
      );
      final controlador = ControladorPerfilPaciente(
        servicio: servicio,
        perfilInicial: perfilConFotoPersonalizada,
      );

      final futuraPrimeraSubida = controlador.cambiarFotografia(
        origen: ImageSource.gallery,
      );
      await Future<void>.delayed(Duration.zero);

      expect(controlador.estaProcesandoFoto, isTrue);

      // Intentos concurrentes de segunda subida o eliminacion deben quedar bloqueados.
      final segundaSubida = await controlador.cambiarFotografia(
        origen: ImageSource.camera,
      );
      final eliminacionConcurrente = await controlador.eliminarFotografia();

      expect(
        segundaSubida.estado,
        equals(EstadoOperacionFotoPaciente.cancelada),
      );
      expect(
        eliminacionConcurrente.estado,
        equals(EstadoOperacionFotoPaciente.cancelada),
      );
      expect(servicio.llamadasSubirFoto, equals(1));
      expect(servicio.llamadasEliminarFoto, equals(0));

      esperaSubida.complete();
      final resultadoPrimera = await futuraPrimeraSubida;
      expect(
        resultadoPrimera.estado,
        equals(EstadoOperacionFotoPaciente.actualizada),
      );
      expect(controlador.estaProcesandoFoto, isFalse);
    });

    test('ServicioPerfilPaciente hace fallback compatible si obtener_perfil_paciente_propio aun no existe y tolera limpieza pendiente en Cloudinary', () async {
      final rpcsInvocadas = <String>[];
      final servicioFallback = ServicioPerfilPaciente(
        lectorUsuarioActualId: () => 'pac-10',
        ejecutorRpc: (nombreFuncion, {parametros}) async {
          rpcsInvocadas.add(nombreFuncion);
          if (nombreFuncion == 'obtener_perfil_paciente_propio') {
            throw const PostgrestException(
              message: 'Could not find the function',
              code: 'PGRST202',
            );
          }
          return <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'pac-10',
              'nombre': 'Lucía',
              'apellido': 'Mendoza',
              'correo': 'lucia@ejemplo.com',
              'rol': 'paciente',
              'aprobacion': 'no_aplica',
              'cuenta_activa': true,
            },
          ];
        },
        invocadorFotoEdge: (nombreFuncion, {required cuerpo}) async {
          expect(cuerpo['accion'], equals('eliminar'));
          return const RespuestaFotoPacienteEdge(
            estado: 200,
            datos: <String, dynamic>{
              'eliminada': true,
              'fotoUrl': null,
              'tieneFotoPersonalizada': false,
              'limpiezaAlmacenamientoPendiente': true,
            },
          );
        },
      );

      final perfilFallback = await servicioFallback.obtenerPerfilPropio();
      expect(
        rpcsInvocadas,
        equals(<String>[
          'obtener_perfil_paciente_propio',
          'perfil_del_usuario_actual',
        ]),
      );
      expect(perfilFallback.nombre, equals('Lucía'));
      expect(perfilFallback.tieneFotoPersonalizada, isFalse);

      // Si Cloudinary queda pendiente de reintento pero Supabase ya confirmo la eliminacion,
      // el servicio confirma el perfil sin foto personalizada y sin referencias rotas.
      final perfilEliminado = await servicioFallback.eliminarFotografia();
      expect(perfilEliminado.tieneFotoPersonalizada, isFalse);
      expect(perfilEliminado.fotoUrl, isNull);
    });

    test(
      'Bloquea operaciones concurrentes de subida o eliminacion mientras hay una foto en proceso',
      () async {
        final esperaSubida = Completer<void>();
        final servicio = _ServicioPerfilPacienteFalso(
          perfilAlmacenado: perfilConFotoPersonalizada,
          esperaSubidaFoto: esperaSubida,
          proveedorSeleccionFoto: (_) async => ImagenCrudaPaciente(
            bytes: _crearPngValido(),
            nombreArchivo: 'primera.png',
          ),
        );
        final controlador = ControladorPerfilPaciente(
          servicio: servicio,
          perfilInicial: perfilConFotoPersonalizada,
        );

        final futuraPrimeraSubida = controlador.cambiarFotografia(
          origen: ImageSource.gallery,
        );
        await Future<void>.delayed(Duration.zero);

        expect(controlador.estaProcesandoFoto, isTrue);

        // Intentos concurrentes de segunda subida o eliminacion deben quedar bloqueados.
        final segundaSubida = await controlador.cambiarFotografia(
          origen: ImageSource.camera,
        );
        final eliminacionConcurrente = await controlador.eliminarFotografia();

        expect(
          segundaSubida.estado,
          equals(EstadoOperacionFotoPaciente.cancelada),
        );
        expect(
          eliminacionConcurrente.estado,
          equals(EstadoOperacionFotoPaciente.cancelada),
        );
        expect(servicio.llamadasSubirFoto, equals(1));
        expect(servicio.llamadasEliminarFoto, equals(0));

        esperaSubida.complete();
        final resultadoPrimera = await futuraPrimeraSubida;
        expect(
          resultadoPrimera.estado,
          equals(EstadoOperacionFotoPaciente.actualizada),
        );
        expect(controlador.estaProcesandoFoto, isFalse);
      },
    );

    test(
      'ServicioPerfilPaciente hace fallback compatible si obtener_perfil_paciente_propio aun no existe y tolera limpieza pendiente en Cloudinary',
      () async {
        final rpcsInvocadas = <String>[];
        final servicioFallback = ServicioPerfilPaciente(
          lectorUsuarioActualId: () => 'pac-10',
          ejecutorRpc: (nombreFuncion, {parametros}) async {
            rpcsInvocadas.add(nombreFuncion);
            if (nombreFuncion == 'obtener_perfil_paciente_propio') {
              throw const PostgrestException(
                message: 'Could not find the function',
                code: 'PGRST202',
              );
            }
            return <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'pac-10',
                'nombre': 'Lucía',
                'apellido': 'Mendoza',
                'correo': 'lucia@ejemplo.com',
                'rol': 'paciente',
                'aprobacion': 'no_aplica',
                'cuenta_activa': true,
              },
            ];
          },
          invocadorFotoEdge: (nombreFuncion, {required cuerpo}) async {
            expect(cuerpo['accion'], equals('eliminar'));
            return const RespuestaFotoPacienteEdge(
              estado: 200,
              datos: <String, dynamic>{
                'eliminada': true,
                'fotoUrl': null,
                'tieneFotoPersonalizada': false,
                'limpiezaAlmacenamientoPendiente': true,
              },
            );
          },
        );

        final perfilFallback = await servicioFallback.obtenerPerfilPropio();
        expect(
          rpcsInvocadas,
          equals(<String>[
            'obtener_perfil_paciente_propio',
            'perfil_del_usuario_actual',
          ]),
        );
        expect(perfilFallback.nombre, equals('Lucía'));
        expect(perfilFallback.tieneFotoPersonalizada, isFalse);

        // Si Cloudinary queda pendiente de reintento pero Supabase ya confirmo la eliminacion,
        // el servicio confirma el perfil sin foto personalizada y sin referencias rotas.
        final perfilEliminado = await servicioFallback.eliminarFotografia();
        expect(perfilEliminado.tieneFotoPersonalizada, isFalse);
        expect(perfilEliminado.fotoUrl, isNull);
      },
    );
  });

  group('PantallaPerfilPaciente - Rediseño, menu emergente y foto automatica', () {
    testWidgets(
      'Muestra tarjeta superior centrada sin seccion antigua y textos corregidos en Datos personales',
      (WidgetTester probador) async {
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

        // Estructura superior centrada y limpia
        expect(find.byType(AvatarPaciente), findsOneWidget);
        final avatar = probador.widget<AvatarPaciente>(
          find.byKey(const Key('avatarPacientePerfil')),
        );
        expect(avatar.diametro, inInclusiveRange(90, 110));
        expect(
          find.byKey(const Key('botonCambiarFotoPaciente')),
          findsOneWidget,
        );
        expect(find.text('Lucía Mendoza'), findsOneWidget);
        expect(find.text('lucia@ejemplo.com'), findsAtLeastNWidgets(1));
        expect(find.text('Rol: Paciente · Cuenta activa'), findsOneWidget);

        // Elementos eliminados
        expect(find.text('Toca para cambiar tu foto'), findsNothing);
        expect(find.text('Fotografía de perfil'), findsNothing);
        expect(find.text('Seleccionar de la galería'), findsNothing);
        expect(find.text('Guardar fotografía'), findsNothing);
        expect(find.text('Eliminar fotografía'), findsNothing);
        expect(
          find.byKey(const Key('avisoAlmacenamientoFotoPendiente')),
          findsNothing,
        );

        // Textos exactos en Datos personales y secciones inferiores conservadas
        expect(find.text('Datos personales'), findsOneWidget);
        expect(find.text('Actualiza tu nombre y apellido'), findsOneWidget);
        expect(
          find.textContaining(
            'Los cambios se guardan directamente en Supabase',
          ),
          findsNothing,
        );
        expect(find.text('Correo electrónico'), findsOneWidget);
        expect(
          find.text('Correo electrónico (gestionado por Supabase Auth)'),
          findsNothing,
        );
        expect(find.text('Seguridad y sesión'), findsOneWidget);

        // Edicion y guardado de datos personales conserva su funcionamiento
        await probador.enterText(
          find.byKey(const Key('campoNombrePaciente')),
          'Valeria',
        );
        await probador.enterText(
          find.byKey(const Key('campoApellidoPaciente')),
          'Salazar',
        );

        final botonGuardar = find.byKey(
          const Key('botonGuardarPerfilPaciente'),
        );
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
      },
    );

    testWidgets(
      'Menu emergente muestra opciones segun foto personalizada y al cerrarlo no modifica la foto',
      (WidgetTester probador) async {
        probador.view.physicalSize = const Size(1080, 2400);
        probador.view.devicePixelRatio = 2.0;
        addTearDown(probador.view.resetPhysicalSize);
        addTearDown(probador.view.resetDevicePixelRatio);

        final servicioSinPersonalizada = _ServicioPerfilPacienteFalso(
          perfilAlmacenado: perfilInicial,
        );
        final servicioSesionGoogle = _ServicioSesionFalso(
          fotoGoogle: 'https://lh3.googleusercontent.com/avatar-google.jpg',
        );

        await probador.pumpWidget(
          MaterialApp(
            theme: TemaPsicobloom.obtenerTema(),
            home: PantallaPerfilPaciente(
              perfilInicial: perfilInicial,
              servicio: servicioSinPersonalizada,
              servicioSesion: servicioSesionGoogle,
            ),
          ),
        );
        await probador.pumpAndSettle();

        // Con foto de Google (no personalizada en PsicoBloom), NO ofrece Eliminar foto.
        await probador.tap(find.byKey(const Key('botonCambiarFotoPaciente')));
        await probador.pumpAndSettle();

        expect(find.text('Cambiar foto'), findsOneWidget);
        expect(find.text('Elegir de la galería'), findsOneWidget);
        expect(find.text('Tomar foto'), findsOneWidget);
        expect(find.text('Eliminar foto'), findsNothing);

        // Pulsar fuera del menu lo cierra sin tocar la fotografia.
        await probador.tapAt(const Offset(20, 40));
        await probador.pumpAndSettle();
        expect(find.text('Cambiar foto'), findsNothing);
        expect(servicioSinPersonalizada.llamadasSubirFoto, equals(0));
        expect(servicioSinPersonalizada.llamadasEliminarFoto, equals(0));
      },
    );

    testWidgets(
      'Guardado automatico muestra progreso temporal, guarda sin boton extra y actualiza Inicio y Perfil',
      (WidgetTester probador) async {
        probador.view.physicalSize = const Size(1080, 2400);
        probador.view.devicePixelRatio = 2.0;
        addTearDown(probador.view.resetPhysicalSize);
        addTearDown(probador.view.resetDevicePixelRatio);

        final esperaSubida = Completer<void>();
        final nuevaFotoBytes = _crearPngValido(rojo: 47, verde: 125, azul: 98);
        PerfilUsuario? perfilNotificado;

        final servicioPerfil = _ServicioPerfilPacienteFalso(
          perfilAlmacenado: perfilInicial,
          esperaSubidaFoto: esperaSubida,
          proveedorSeleccionFoto: (_) async => ImagenCrudaPaciente(
            bytes: nuevaFotoBytes,
            nombreArchivo: 'nueva.png',
          ),
        );

        await probador.pumpWidget(
          MaterialApp(
            theme: TemaPsicobloom.obtenerTema(),
            home: PantallaPerfilPaciente(
              perfilInicial: perfilInicial,
              servicio: servicioPerfil,
              servicioSesion: _ServicioSesionFalso(),
              alActualizarPerfil: (nuevo) => perfilNotificado = nuevo,
            ),
          ),
        );
        await probador.pumpAndSettle();

        // Abre menu y elige galeria -> inicia subida automatica
        await probador.tap(find.byKey(const Key('botonCambiarFotoPaciente')));
        await probador.pumpAndSettle();
        await probador.tap(find.byKey(const Key('opcionFotoGaleria')));
        await probador.pump();
        await probador.pump(const Duration(milliseconds: 50));

        // Muestra vista previa temporal e indicador de progreso en el avatar
        expect(
          find.byKey(const Key('indicadorProgresoFotoPaciente')),
          findsOneWidget,
        );
        final avatarDuranteSubida = probador.widget<AvatarPaciente>(
          find.byKey(const Key('avatarPacientePerfil')),
        );
        expect(avatarDuranteSubida.bytesVistaPrevia, equals(nuevaFotoBytes));
        expect(avatarDuranteSubida.estaCargando, isTrue);

        // Finaliza la subida simulada
        esperaSubida.complete();
        await probador.pumpAndSettle();

        expect(servicioPerfil.llamadasSubirFoto, equals(1));
        expect(
          servicioPerfil.ultimoOrigenSeleccionado,
          equals(ImageSource.gallery),
        );
        expect(
          find.byKey(const Key('indicadorProgresoFotoPaciente')),
          findsNothing,
        );
        expect(find.text('Foto actualizada'), findsOneWidget);
        expect(perfilNotificado?.tieneFotoPersonalizada, isTrue);
        expect(perfilNotificado?.fotoUrl, equals(servicioPerfil.urlFotoSubida));
        expect(
          ServicioSesion.perfilPacienteSincronizado.value?.fotoUrl,
          equals(servicioPerfil.urlFotoSubida),
        );
      },
    );

    testWidgets(
      'Si falla la subida recupera el avatar anterior y muestra "No se pudo actualizar la foto"',
      (WidgetTester probador) async {
        probador.view.physicalSize = const Size(1080, 2400);
        probador.view.devicePixelRatio = 2.0;
        addTearDown(probador.view.resetPhysicalSize);
        addTearDown(probador.view.resetDevicePixelRatio);

        final esperaSubida = Completer<void>();
        final servicioPerfil = _ServicioPerfilPacienteFalso(
          perfilAlmacenado: perfilConFotoPersonalizada,
          simularErrorSubidaFoto: true,
          esperaSubidaFoto: esperaSubida,
          proveedorSeleccionFoto: (_) async => ImagenCrudaPaciente(
            bytes: _crearPngValido(),
            nombreArchivo: 'fallida.png',
          ),
        );

        await probador.pumpWidget(
          MaterialApp(
            theme: TemaPsicobloom.obtenerTema(),
            home: PantallaPerfilPaciente(
              perfilInicial: perfilConFotoPersonalizada,
              servicio: servicioPerfil,
              servicioSesion: _ServicioSesionFalso(),
            ),
          ),
        );
        await probador.pumpAndSettle();

        await probador.tap(find.byKey(const Key('botonCambiarFotoPaciente')));
        await probador.pumpAndSettle();
        await probador.tap(find.byKey(const Key('opcionFotoCamara')));
        await probador.pump();
        await probador.pump(const Duration(milliseconds: 50));

        expect(
          find.byKey(const Key('indicadorProgresoFotoPaciente')),
          findsOneWidget,
        );

        esperaSubida.complete();
        await probador.pumpAndSettle();

        final avatarFinal = probador.widget<AvatarPaciente>(
          find.byKey(const Key('avatarPacientePerfil')),
        );
        expect(avatarFinal.bytesVistaPrevia, isNull);
        expect(avatarFinal.fotoUrl, equals(perfilConFotoPersonalizada.fotoUrl));
        expect(find.text('No se pudo actualizar la foto'), findsOneWidget);
      },
    );

    testWidgets(
      'Eliminar foto exige confirmacion, respeta cancelar y al confirmar vuelve a foto de Google o iniciales',
      (WidgetTester probador) async {
        probador.view.physicalSize = const Size(1080, 2400);
        probador.view.devicePixelRatio = 2.0;
        addTearDown(probador.view.resetPhysicalSize);
        addTearDown(probador.view.resetDevicePixelRatio);

        const urlGoogle =
            'https://lh3.googleusercontent.com/avatar-google-respaldo.jpg';
        PerfilUsuario? perfilNotificado;

        final servicioPerfil = _ServicioPerfilPacienteFalso(
          perfilAlmacenado: perfilConFotoPersonalizada,
        );
        final servicioSesion = _ServicioSesionFalso(fotoGoogle: urlGoogle);

        await probador.pumpWidget(
          MaterialApp(
            theme: TemaPsicobloom.obtenerTema(),
            home: PantallaPerfilPaciente(
              perfilInicial: perfilConFotoPersonalizada,
              servicio: servicioPerfil,
              servicioSesion: servicioSesion,
              alActualizarPerfil: (nuevo) => perfilNotificado = nuevo,
            ),
          ),
        );
        await probador.pumpAndSettle();

        // 1. Abre menu y pulsa Eliminar foto -> Cancela
        await probador.tap(find.byKey(const Key('botonCambiarFotoPaciente')));
        await probador.pumpAndSettle();
        expect(find.text('Eliminar foto'), findsOneWidget);
        await probador.tap(find.byKey(const Key('opcionFotoEliminar')));
        await probador.pumpAndSettle();

        expect(find.text('¿Eliminar tu foto de perfil?'), findsOneWidget);
        expect(find.text('Cancelar'), findsOneWidget);
        expect(find.text('Eliminar'), findsOneWidget);

        await probador.tap(find.byKey(const Key('botonCancelarEliminarFoto')));
        await probador.pumpAndSettle();
        expect(servicioPerfil.llamadasEliminarFoto, equals(0));

        // 2. Abre menu, pulsa Eliminar foto -> Confirma
        await probador.tap(find.byKey(const Key('botonCambiarFotoPaciente')));
        await probador.pumpAndSettle();
        await probador.tap(find.byKey(const Key('opcionFotoEliminar')));
        await probador.pumpAndSettle();
        await probador.tap(find.byKey(const Key('botonConfirmarEliminarFoto')));
        await probador.pumpAndSettle();

        expect(servicioPerfil.llamadasEliminarFoto, equals(1));
        expect(perfilNotificado?.tieneFotoPersonalizada, isFalse);
        expect(perfilNotificado?.fotoUrl, isNull);
        expect(find.text('Foto eliminada'), findsOneWidget);

        // El avatar ahora muestra la foto de Google OAuth de respaldo
        final avatarDespues = probador.widget<AvatarPaciente>(
          find.byKey(const Key('avatarPacientePerfil')),
        );
        expect(avatarDespues.fotoUrl, equals(urlGoogle));

        // Al abrir el menu nuevamente, Eliminar foto ya no aparece
        await probador.tap(find.byKey(const Key('botonCambiarFotoPaciente')));
        await probador.pumpAndSettle();
        expect(find.text('Eliminar foto'), findsNothing);
      },
    );

    testWidgets(
      'Cancelar selector no altera la foto y un error al eliminar conserva el avatar actual',
      (WidgetTester probador) async {
        probador.view.physicalSize = const Size(1080, 2400);
        probador.view.devicePixelRatio = 2.0;
        addTearDown(probador.view.resetPhysicalSize);
        addTearDown(probador.view.resetDevicePixelRatio);

        final servicioPerfil = _ServicioPerfilPacienteFalso(
          perfilAlmacenado: perfilConFotoPersonalizada,
          simularErrorEliminacionFoto: true,
          proveedorSeleccionFoto: (_) async => null,
        );

        await probador.pumpWidget(
          MaterialApp(
            theme: TemaPsicobloom.obtenerTema(),
            home: PantallaPerfilPaciente(
              perfilInicial: perfilConFotoPersonalizada,
              servicio: servicioPerfil,
              servicioSesion: _ServicioSesionFalso(),
            ),
          ),
        );
        await probador.pumpAndSettle();

        // Cancelar el selector de galeria no dispara subida ni cambia la foto
        await probador.tap(find.byKey(const Key('botonCambiarFotoPaciente')));
        await probador.pumpAndSettle();
        await probador.tap(find.byKey(const Key('opcionFotoGaleria')));
        await probador.pumpAndSettle();
        expect(servicioPerfil.llamadasSubirFoto, equals(0));

        // Error al eliminar conserva la foto anterior y muestra aviso
        await probador.tap(find.byKey(const Key('botonCambiarFotoPaciente')));
        await probador.pumpAndSettle();
        await probador.tap(find.byKey(const Key('opcionFotoEliminar')));
        await probador.pumpAndSettle();
        await probador.tap(find.byKey(const Key('botonConfirmarEliminarFoto')));
        await probador.pumpAndSettle();

        expect(servicioPerfil.llamadasEliminarFoto, equals(1));
        expect(find.text('No se pudo eliminar la foto'), findsOneWidget);
        final avatarActual = probador.widget<AvatarPaciente>(
          find.byKey(const Key('avatarPacientePerfil')),
        );
        expect(
          avatarActual.fotoUrl,
          equals(perfilConFotoPersonalizada.fotoUrl),
        );
      },
    );
  });
}
