import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_sesion.dart';
import 'package:boom/modulos/paciente/controladores/gestor_resultado_orientacion.dart';
import 'package:boom/modulos/paciente/modelos/cuestionario_orientacion.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_inicio_paciente.dart';

class _ServicioSesionConFotoGoogle extends ServicioSesion {
  final String? fotoGoogle;

  const _ServicioSesionConFotoGoogle(this.fotoGoogle);

  @override
  String? obtenerFotoUsuarioActual() => fotoGoogle;
}

void main() {
  setUp(() {
    GestorResultadoOrientacion.instancia.limpiar();
  });

  tearDown(() {
    GestorResultadoOrientacion.instancia.limpiar();
  });

  Widget crearPantallaDePrueba({String nombrePaciente = 'María'}) {
    return MaterialApp(
      theme: TemaPsicobloom.obtenerTema(),
      home: PantallaInicioPaciente(nombrePaciente: nombrePaciente),
    );
  }

  testWidgets(
    'Verificacion de elementos visuales principales de la Pantalla de Inicio',
    (WidgetTester probador) async {
      await probador.pumpWidget(crearPantallaDePrueba());
      await probador.pump();

      // 1. Cabecera e identidad
      expect(find.text('PsicoBloom'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);

      // 2. Saludo al paciente y avatar circular (sin icono meditando)
      expect(find.text('Hola, María 👋'), findsOneWidget);
      expect(find.text('¿En qué podemos ayudarte?'), findsOneWidget);
      expect(find.byIcon(Icons.self_improvement_rounded), findsNothing);
      expect(find.byKey(const Key('avatarPacienteInicio')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('avatarPacienteInicio')),
          matching: find.text('M'),
        ),
        findsOneWidget,
      );

      // 3. Tarjetas de accion rapida
      expect(find.text('Buscar profesional'), findsOneWidget);
      expect(find.text('Orientarme'), findsOneWidget);

      // 4. Seccion de profesionales recomendados
      expect(find.text('Profesionales cerca de ti'), findsOneWidget);
      expect(find.text('Ver todos'), findsOneWidget);
      expect(
        find.text('Demostración con datos referenciales para Riobamba.'),
        findsOneWidget,
      );

      // 5. Profesionales simulados renderizados
      expect(find.text('Dra. María López'), findsOneWidget);
      expect(find.text('Psicología Clínica'), findsOneWidget);
      expect(find.text('Dr. Carlos Pérez'), findsOneWidget);

      // 6. Barra de navegacion inferior con las cinco opciones
      expect(find.text('Inicio'), findsOneWidget);
      expect(find.text('Buscar'), findsOneWidget);
      expect(find.text('Mapa'), findsOneWidget);
      expect(find.text('Citas'), findsOneWidget);
      expect(find.text('Perfil'), findsOneWidget);
    },
  );

  testWidgets(
    'Interaccion con tarjetas de accion rapida muestra mensajes y navega a buscar',
    (WidgetTester probador) async {
      await probador.pumpWidget(crearPantallaDePrueba());
      await probador.pump();

      // Pulsa en Orientarme y navega al cuestionario de orientacion
      await probador.tap(find.text('Orientarme'));
      await probador.pumpAndSettle();

      expect(find.text('Introducción y Consentimiento'), findsOneWidget);
      expect(find.text('Aviso importante y descargo ético'), findsOneWidget);

      // Regresa a la pantalla de inicio
      await probador.tap(find.byTooltip('Atrás'));
      await probador.pumpAndSettle();

      // Pulsa en Buscar profesional y navega a la pantalla 6
      await probador.tap(find.text('Buscar profesional'));
      await probador.pumpAndSettle();

      expect(find.text('Encuentra el apoyo que necesitas'), findsOneWidget);
      expect(find.text('Nombre, especialidad o palabra clave'), findsOneWidget);
    },
  );

  testWidgets(
    'Al pulsar Orientarme con resultado previo navega a PantallaCuestionarioCompletado',
    (WidgetTester probador) async {
      // Guardar un resultado previo en memoria de sesion
      GestorResultadoOrientacion.instancia.guardarResultado(
        const ResultadoOrientacion(
          especialidadRecomendada: 'Psicología Clínica',
          descripcion: 'Orientación para manejo del ánimo y ansiedad.',
          categoriasDetectadas: ['Estado de Ánimo y Afectividad'],
          centrosRecomendadosRiobamba: ['Hospital General Docente de Riobamba'],
          requiereAtencionPrioritaria: false,
        ),
      );

      await probador.pumpWidget(crearPantallaDePrueba());
      await probador.pump();

      // Pulsa en Orientarme
      await probador.tap(find.text('Orientarme'));
      await probador.pumpAndSettle();

      // Debe abrir la pantalla de cuestionario completado
      expect(find.text('Cuestionario completado'), findsOneWidget);
      expect(find.text('Ver recomendaciones detalladas'), findsOneWidget);
      expect(find.text('Volver a realizar el cuestionario'), findsOneWidget);
    },
  );

  testWidgets(
    'Interaccion con favoritos y botones de la tarjeta del profesional',
    (WidgetTester probador) async {
      probador.view.physicalSize = const Size(1080, 2400);
      probador.view.devicePixelRatio = 2.0;
      addTearDown(probador.view.resetPhysicalSize);
      addTearDown(probador.view.resetDevicePixelRatio);

      await probador.pumpWidget(crearPantallaDePrueba());
      await probador.pump();

      // Pulsa el primer boton de favorito
      final primerBotonFavorito = find.byTooltip('Agregar a favoritos').first;
      await probador.ensureVisible(primerBotonFavorito);
      await probador.pump();

      await probador.tap(primerBotonFavorito);
      await probador.pump();
      await probador.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Guardado en tus profesionales favoritos'),
        findsOneWidget,
      );

      // Pulsa en Ver perfil
      final primerBotonVerPerfil = find.text('Ver perfil').first;
      await probador.ensureVisible(primerBotonVerPerfil);
      await probador.pump();

      await probador.tap(primerBotonVerPerfil);
      await probador.pump();
      await probador.pump(const Duration(milliseconds: 100));

      expect(
        find.text(
          'La visualización de perfil detallado se implementará en etapas posteriores.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('Interaccion con las opciones de la barra de navegacion', (
    WidgetTester probador,
  ) async {
    await probador.pumpWidget(crearPantallaDePrueba());
    await probador.pump();

    // Pulsa en la pestana Mapa y navega a la pantalla preliminar del mapa
    await probador.tap(find.text('Mapa'));
    await probador.pumpAndSettle();

    expect(find.text('Profesionales en Riobamba'), findsOneWidget);
    expect(find.byKey(const Key('areaPreliminarMapa')), findsOneWidget);

    // Regresa a Inicio y pulsa en la pestana Buscar para navegar a la pantalla 6
    await probador.tap(find.text('Inicio'));
    await probador.pumpAndSettle();
    await probador.tap(find.text('Buscar'));
    await probador.pumpAndSettle();

    expect(find.text('Encuentra el apoyo que necesitas'), findsOneWidget);
  });

  testWidgets(
    'Avatar de inicio muestra iniciales completas sin foto y usa foto de perfil o Google cuando existe',
    (WidgetTester probador) async {
      await probador.pumpWidget(
        MaterialApp(
          theme: TemaPsicobloom.obtenerTema(),
          home: const PantallaInicioPaciente(
            perfilInicial: PerfilUsuario(
              id: 'pac-1',
              nombre: 'Ana',
              apellido: 'Gómez',
              rol: 'paciente',
              aprobacion: 'no_aplica',
              cuentaActiva: true,
            ),
          ),
        ),
      );
      await probador.pump();

      expect(
        find.descendant(
          of: find.byKey(const Key('avatarPacienteInicio')),
          matching: find.text('AG'),
        ),
        findsOneWidget,
      );

      // Cuando la sesion de Google provee foto, renderiza Image.network en el avatar circular.
      await probador.pumpWidget(
        MaterialApp(
          theme: TemaPsicobloom.obtenerTema(),
          home: const PantallaInicioPaciente(
            perfilInicial: PerfilUsuario(
              id: 'pac-2',
              nombre: 'Ana',
              apellido: 'Gómez',
              rol: 'paciente',
              aprobacion: 'no_aplica',
              cuentaActiva: true,
            ),
            servicioSesion: _ServicioSesionConFotoGoogle(
              'https://lh3.googleusercontent.com/demo-avatar.jpg',
            ),
          ),
        ),
      );
      await probador.pump();

      expect(
        find.descendant(
          of: find.byKey(const Key('avatarPacienteInicio')),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );

      // Si Perfil actualiza la foto personalizada, Inicio se sincroniza automaticamente.
      const urlPersonalizada =
          'https://res.cloudinary.com/demo/image/upload/psicobloom/pacientes/pac-2_nueva.jpg';
      ServicioSesion.notificarPerfilPacienteActualizado(
        const PerfilUsuario(
          id: 'pac-2',
          nombre: 'Ana',
          apellido: 'Gómez',
          rol: 'paciente',
          aprobacion: 'no_aplica',
          cuentaActiva: true,
          fotoUrl: urlPersonalizada,
          tieneFotoPersonalizada: true,
        ),
      );
      await probador.pump();

      final avatarInicio = probador.widget<Image>(
        find.descendant(
          of: find.byKey(const Key('avatarPacienteInicio')),
          matching: find.byType(Image),
        ),
      );
      expect(
        (avatarInicio.image as NetworkImage).url,
        equals(urlPersonalizada),
      );

      ServicioSesion.limpiarPerfilPacienteSincronizado();
    },
  );
}
