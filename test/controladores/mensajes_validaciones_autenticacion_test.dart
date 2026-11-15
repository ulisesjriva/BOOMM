import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/modulos/administrador/servicios/servicio_administracion.dart';
import 'package:boom/modulos/autenticacion/controladores/controlador_inicio_sesion.dart';
import 'package:boom/modulos/autenticacion/controladores/controlador_nueva_clave.dart';
import 'package:boom/modulos/autenticacion/controladores/controlador_recuperar_clave.dart';
import 'package:boom/modulos/autenticacion/controladores/controlador_registro.dart';
import 'package:boom/modulos/autenticacion/modelos/enlace_autenticacion.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_enlace_autenticacion.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_inicio_sesion.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_recuperacion_clave.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_registro.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_iniciar_sesion.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_registro_paso_dos.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_registro_paso_uno.dart';
import 'package:boom/modulos/paciente/servicios/servicio_perfil_paciente.dart';
import 'package:boom/modulos/profesional/servicios/servicio_perfil_profesional.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/nucleo/utilidades/traductor_errores_supabase.dart';
import 'package:boom/modelos/perfil_usuario.dart';

class _ServicioRegistroSimulado extends ServicioRegistro {
  Object? errorAlRegistrar;
  int intentos = 0;

  @override
  Future<void> registrar({
    required String nombre,
    required String apellido,
    required String correo,
    required String clave,
    required bool esProfesional,
  }) async {
    intentos++;
    if (errorAlRegistrar != null) {
      throw errorAlRegistrar!;
    }
  }
}

class _ServicioInicioSesionSimulado extends ServicioInicioSesion {
  Object? errorAlIniciar;
  PerfilUsuario? perfilRespuesta;

  @override
  Future<PerfilUsuario> iniciarSesionPaciente({
    required String correo,
    required String clave,
  }) async {
    if (errorAlIniciar != null) {
      throw errorAlIniciar!;
    }
    return perfilRespuesta!;
  }
}

class _ServicioRecuperacionSimulado extends ServicioRecuperacionClave {
  Object? errorAlSolicitar;

  @override
  Future<void> solicitarEnlace(String correo) async {
    if (errorAlSolicitar != null) {
      throw errorAlSolicitar!;
    }
  }
}

class _ServicioEnlaceSimulado extends ServicioEnlaceAutenticacion {
  Object? errorAlValidar;
  Object? errorAlGuardar;

  @override
  Future<void> validarRecuperacion(EnlaceAutenticacion enlace) async {
    if (errorAlValidar != null) {
      throw errorAlValidar!;
    }
  }

  @override
  Future<void> guardarClave(String clave) async {
    if (errorAlGuardar != null) {
      throw errorAlGuardar!;
    }
  }

  @override
  Future<void> cerrar() async {}
}

void _verificarSinJergaTecnica(String mensaje) {
  final textoMinuscula = mensaje.toLowerCase();
  const terminosProhibidos = <String>[
    'authexception',
    'postgrestexception',
    'socketexception',
    'storageexception',
    'supabase',
    'jwt',
    'sql',
    'status code',
    'unhandled exception',
    'perfil_del_usuario_actual',
    'invalid login credentials',
    'email not confirmed',
    'password should contain',
  ];
  for (final termino in terminosProhibidos) {
    expect(
      textoMinuscula.contains(termino),
      isFalse,
      reason: 'El mensaje "$mensaje" expone el término técnico "$termino".',
    );
  }
}

void main() {
  group('Validaciones locales de formularios de autenticación', () {
    test('1. Valida correo electrónico vacío o con formato inválido', () {
      final errorVacio = TraductorErroresSupabase.validarCorreo('');
      final errorEspacios = TraductorErroresSupabase.validarCorreo('   ');
      final errorSinArroba = TraductorErroresSupabase.validarCorreo(
        'usuariodominio.com',
      );
      final errorSinDominio = TraductorErroresSupabase.validarCorreo(
        'usuario@dominio',
      );
      final correoValido = TraductorErroresSupabase.validarCorreo(
        'paciente@psicobloom.ec',
      );

      expect(errorVacio, 'Ingresa tu correo electrónico para continuar.');
      expect(errorEspacios, 'Ingresa tu correo electrónico para continuar.');
      expect(
        errorSinArroba,
        'Revisa tu correo electrónico. Parece que tiene un formato incorrecto.',
      );
      expect(
        errorSinDominio,
        'Revisa tu correo electrónico. Parece que tiene un formato incorrecto.',
      );
      expect(correoValido, isNull);
    });

    test(
      '2 y 3. Valida contraseña vacía, corta o sin complejidad requerida',
      () {
        expect(
          TraductorErroresSupabase.validarClaveRegistro(''),
          'Ingresa una contraseña para continuar.',
        );
        expect(
          TraductorErroresSupabase.validarClaveRegistro('Corta1!'),
          'La contraseña debe contener al menos 11 caracteres',
        );
        // 11+ caracteres pero sin mayúscula, número o símbolo
        expect(
          TraductorErroresSupabase.validarClaveRegistro('solominusculas'),
          'Tu contraseña aún no cumple los requisitos: incluye mayúscula, minúscula, número y símbolo.',
        );
        expect(
          TraductorErroresSupabase.validarClaveRegistro('SinSimbolo1234'),
          'Tu contraseña aún no cumple los requisitos: incluye mayúscula, minúscula, número y símbolo.',
        );
        // Contraseña que cumple todos los requisitos
        expect(
          TraductorErroresSupabase.validarClaveRegistro('PsicoBloom2026!'),
          isNull,
        );
      },
    );

    test('4. Valida confirmación de contraseña vacía o que no coincide', () {
      expect(
        TraductorErroresSupabase.validarConfirmacionClave(
          '',
          'PsicoBloom2026!',
        ),
        'Confirma tu contraseña para continuar.',
      );
      expect(
        TraductorErroresSupabase.validarConfirmacionClave(
          'OtraClave2026!',
          'PsicoBloom2026!',
        ),
        'Las contraseñas no coinciden. Revísalas e inténtalo nuevamente.',
      );
      expect(
        TraductorErroresSupabase.validarConfirmacionClave(
          'PsicoBloom2026!',
          'PsicoBloom2026!',
        ),
        isNull,
      );
    });
  });

  group('Traducción de errores de Supabase y red sin detalles técnicos', () {
    test(
      '3. Traduce error de contraseña débil en inglés procedente de Auth',
      () async {
        final servicio = _ServicioRegistroSimulado()
          ..errorAlRegistrar = AuthWeakPasswordException(
            message: 'Password should contain at least one character of each: abcdefghijklmnopqrstuvwxyz, ABCDEFGHIJKLMNOPQRSTUVWXYZ, 0123456789, !@#\$%^&*()_+-=[]{};\':"|<>?,./`~.',
            statusCode: '422',
            reasons: ['characters'],
          );
        final controlador = ControladorRegistro(servicio: servicio);
        addTearDown(controlador.dispose);

        final exito = await controlador.registrar(
          nombre: 'Ana',
          apellido: 'Torres',
          correo: 'ana@ejemplo.com',
          clave: 'PsicoBloom2026!',
          esProfesional: false,
          aceptaTerminos: true,
        );

        expect(exito, isFalse);
        expect(
          controlador.mensajeError,
          'Tu contraseña aún no cumple los requisitos. Usa al menos 11 caracteres e incluye mayúsculas, minúsculas, números y un símbolo.',
        );
        _verificarSinJergaTecnica(controlador.mensajeError!);
      },
    );

    test('5. Traduce credenciales incorrectas en inicio de sesión', () async {
      final servicio = _ServicioInicioSesionSimulado()
        ..errorAlIniciar = const AuthException(
          'Invalid login credentials',
          statusCode: '400',
          code: 'invalid_credentials',
        );
      final controlador = ControladorInicioSesion(servicio: servicio);
      addTearDown(controlador.dispose);

      final perfil = await controlador.iniciarSesion(
        correo: 'ana@ejemplo.com',
        clave: 'ClaveIncorrecta123!',
      );

      expect(perfil, isNull);
      expect(
        controlador.mensajeError,
        'El correo o la contraseña son incorrectos. Revísalos e inténtalo nuevamente.',
      );
      _verificarSinJergaTecnica(controlador.mensajeError!);
    });

    test('6. Traduce cuenta con correo pendiente de confirmación', () async {
      final servicio = _ServicioInicioSesionSimulado()
        ..errorAlIniciar = const AuthException(
          'Email not confirmed',
          statusCode: '400',
          code: 'email_not_confirmed',
        );
      final controlador = ControladorInicioSesion(servicio: servicio);
      addTearDown(controlador.dispose);

      final perfil = await controlador.iniciarSesion(
        correo: 'ana@ejemplo.com',
        clave: 'PsicoBloom2026!',
      );

      expect(perfil, isNull);
      expect(
        controlador.mensajeError,
        'Confirma tu correo electrónico mediante el enlace enviado antes de iniciar sesión.',
      );
      _verificarSinJergaTecnica(controlador.mensajeError!);
    });

    test(
      '7. Traduce errores de conexión a Internet (SocketException y Timeout)',
      () async {
        final servicio = _ServicioRecuperacionSimulado()
          ..errorAlSolicitar = const SocketException(
            'Failed host lookup: xyz.supabase.co',
          );
        final controlador = ControladorRecuperarClave(servicio: servicio);
        addTearDown(controlador.dispose);

        final enviado = await controlador.solicitarEnlace('ana@ejemplo.com');

        expect(enviado, isFalse);
        expect(
          controlador.mensajeError,
          'No pudimos conectarnos. Revisa tu conexión a Internet e inténtalo nuevamente.',
        );
        _verificarSinJergaTecnica(controlador.mensajeError!);

        final mensajeTimeout = ServicioInicioSesion.explicarError(
          TimeoutException('Connection timed out'),
        );
        expect(
          mensajeTimeout,
          'No pudimos conectarnos. Revisa tu conexión a Internet e inténtalo nuevamente.',
        );
        _verificarSinJergaTecnica(mensajeTimeout);
      },
    );

    test('8. Traduce límite de intentos (código 429) en todos los flujos', () {
      const errorLimite = AuthException(
        'Email rate limit exceeded',
        statusCode: '429',
        code: 'over_email_send_rate_limit',
      );

      final msjLogin = ServicioInicioSesion.explicarError(errorLimite);
      final msjRegistro = ServicioRegistro.explicarError(errorLimite);
      final msjRecuperacion = ServicioRecuperacionClave.explicarError(
        errorLimite,
      );
      final msjEnlace = ServicioEnlaceAutenticacion.explicarError(errorLimite);

      const esperado =
          'Has realizado varios intentos. Espera un momento antes de volver a intentarlo.';
      expect(msjLogin, esperado);
      expect(msjRegistro, esperado);
      expect(msjRecuperacion, esperado);
      expect(msjEnlace, esperado);
      _verificarSinJergaTecnica(msjLogin);
    });

    test('9. Traduce enlace de recuperación vencido o inválido', () async {
      final servicio = _ServicioEnlaceSimulado()
        ..errorAlValidar = const AuthException(
          'Token has expired or is invalid',
          statusCode: '403',
          code: 'otp_expired',
        );
      final controlador = ControladorNuevaClave(servicio: servicio);
      addTearDown(controlador.dispose);

      final enlace = EnlaceAutenticacion.desdeUri(
        Uri.parse(
          'https://psicobloom-7201a.web.app/autenticacion.html#tipo=recovery&token_hash=hash_expirado',
        ),
      );
      final validado = await controlador.validarEnlace(enlace);

      expect(validado, isFalse);
      expect(
        controlador.mensajeEnlace,
        'Este enlace ya no es válido o ha expirado. Solicita uno nuevo para continuar.',
      );
      _verificarSinJergaTecnica(controlador.mensajeEnlace!);
    });

    test('10. Oculta detalles técnicos ante errores inesperados de base de datos o almacenamiento', () {
      const errorSql = PostgrestException(
        message: 'function public.perfil_del_usuario_actual() does not exist at character 15',
        code: '42883',
      );
      const errorStorage = StorageException(
        'new row violates row-level security policy for table objects',
        statusCode: '403',
      );

      final msjLogin = ServicioInicioSesion.explicarError(errorSql);
      final msjRegistro = ServicioRegistro.explicarError(errorSql);
      final msjPaciente = ServicioPerfilPaciente.explicarError(errorSql);
      final msjProfesional = ServicioPerfilProfesional.explicarError(errorSql);
      final msjAdmin = ServicioAdministracion.explicarError(errorSql);
      final msjFoto = TraductorErroresSupabase.traducirErrorAlmacenamiento(
        errorStorage,
      );

      for (final mensaje in [
        msjLogin,
        msjRegistro,
        msjPaciente,
        msjProfesional,
        msjAdmin,
        msjFoto,
      ]) {
        _verificarSinJergaTecnica(mensaje);
      }
    });
  });

  group('Validación en vistas de formularios y estados exitosos', () {
    testWidgets(
      'PantallaRegistroPasoUno muestra mensajes claros ante campos vacíos o correo inválido',
      (probador) async {
        probador.view.physicalSize = const Size(1080, 2400);
        probador.view.devicePixelRatio = 2.0;
        addTearDown(probador.view.resetPhysicalSize);
        addTearDown(probador.view.resetDevicePixelRatio);

        await probador.pumpWidget(
          MaterialApp(
            theme: TemaPsicobloom.obtenerTema(),
            home: const PantallaRegistroPasoUno(),
          ),
        );
        await probador.pumpAndSettle();

        await probador.tap(find.text('Continuar'));
        await probador.pumpAndSettle();

        expect(find.text('Ingresa tu nombre para continuar.'), findsOneWidget);
        expect(
          find.text('Ingresa tu apellido para continuar.'),
          findsOneWidget,
        );
        expect(
          find.text('Ingresa tu correo electrónico para continuar.'),
          findsOneWidget,
        );

        final campos = find.byType(TextFormField);
        await probador.enterText(campos.at(0), 'Valeria');
        await probador.enterText(campos.at(1), 'Salazar');
        await probador.enterText(campos.at(2), 'correo-invalido');
        await probador.tap(find.text('Continuar'));
        await probador.pumpAndSettle();

        expect(
          find.text(
            'Revisa tu correo electrónico. Parece que tiene un formato incorrecto.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'PantallaRegistroPasoDos valida requisitos de contraseña y coincidencia antes de enviar',
      (probador) async {
        probador.view.physicalSize = const Size(1080, 2400);
        probador.view.devicePixelRatio = 2.0;
        addTearDown(probador.view.resetPhysicalSize);
        addTearDown(probador.view.resetDevicePixelRatio);

        final servicio = _ServicioRegistroSimulado();
        await probador.pumpWidget(
          MaterialApp(
            theme: TemaPsicobloom.obtenerTema(),
            home: PantallaRegistroPasoDos(
              nombre: 'Valeria',
              apellido: 'Salazar',
              correo: 'valeria@ejemplo.com',
              servicio: servicio,
            ),
          ),
        );
        await probador.pumpAndSettle();

        final campos = find.byType(TextFormField);
        // 11 caracteres pero sin símbolo ni mayúscula
        await probador.enterText(campos.at(0), 'clavesinsimbolo1');
        await probador.enterText(campos.at(1), 'clavediferente1');
        final botonCrear = find.widgetWithText(ElevatedButton, 'Crear cuenta');
        await probador.ensureVisible(botonCrear);
        await probador.tap(botonCrear);
        await probador.pumpAndSettle();

        expect(servicio.intentos, 0);
        expect(
          find.text(
            'Tu contraseña aún no cumple los requisitos: incluye mayúscula, minúscula, número y símbolo.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Las contraseñas no coinciden. Revísalas e inténtalo nuevamente.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'PantallaIniciarSesion muestra mensajes claros cuando correo o contraseña están vacíos',
      (probador) async {
        probador.view.physicalSize = const Size(1080, 2400);
        probador.view.devicePixelRatio = 2.0;
        addTearDown(probador.view.resetPhysicalSize);
        addTearDown(probador.view.resetDevicePixelRatio);

        await probador.pumpWidget(
          MaterialApp(
            theme: TemaPsicobloom.obtenerTema(),
            home: const PantallaIniciarSesion(),
          ),
        );
        await probador.pumpAndSettle();

        final boton = find.widgetWithText(ElevatedButton, 'Iniciar sesión');
        await probador.ensureVisible(boton);
        await probador.tap(boton);
        await probador.pumpAndSettle();

        expect(
          find.text('Ingresa tu correo electrónico para continuar.'),
          findsOneWidget,
        );
        expect(
          find.text('Ingresa tu contraseña para continuar.'),
          findsOneWidget,
        );
      },
    );
  });
}
