import 'dart:async';

import 'package:flutter/material.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modelos/profesional.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_sesion.dart';
import 'package:boom/modulos/paciente/componentes/barra_navegacion_paciente.dart';
import 'package:boom/modulos/paciente/componentes/mapa_consultorio_ruta.dart';
import 'package:boom/modulos/paciente/componentes/tarjeta_profesional.dart';
import 'package:boom/modulos/paciente/controladores/controlador_ruta_consultorio.dart';
import 'package:boom/modulos/paciente/controladores/gestor_favoritos.dart';
import 'package:boom/modulos/paciente/servicios/servicio_rutas_consultorio.dart';
import 'package:boom/modulos/profesional/servicios/servicio_ubicacion_consultorio.dart';
import 'package:boom/nucleo/componentes/fondo_decorativo_bloom.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/repositorios/repositorio_profesionales.dart';
import 'package:boom/repositorios/repositorio_profesionales_supabase.dart';

import 'pantalla_buscar_profesionales.dart';
import 'pantalla_inicio_paciente.dart';
import 'pantalla_mis_citas_paciente.dart';
import 'pantalla_perfil_paciente.dart';
import 'pantalla_perfil_publico_profesional.dart';

/// Pantalla 7 (preliminar): Mapa de profesionales para el rol paciente.
/// Presenta el encabezado institucional, el espacio reservado para la futura
/// integracion del mapa interactivo y el listado de profesionales aprobados
/// consultados desde Supabase con acceso a su perfil publico.
class PantallaMapaProfesionales extends StatefulWidget {
  final RepositorioProfesionales? repositorio;
  final PerfilUsuario? perfilInicial;
  final ServicioSesion servicioSesion;
  final ServicioUbicacionConsultorio servicioUbicacion;
  final ServicioRutasConsultorio servicioRutas;

  const PantallaMapaProfesionales({
    super.key,
    this.repositorio,
    this.perfilInicial,
    this.servicioSesion = const ServicioSesion(),
    this.servicioUbicacion = const ServicioUbicacionConsultorio(),
    this.servicioRutas = const ServicioRutasConsultorio(),
  });

  @override
  State<PantallaMapaProfesionales> createState() =>
      _PantallaMapaProfesionalesState();
}

class _PantallaMapaProfesionalesState extends State<PantallaMapaProfesionales> {
  List<Profesional> _profesionales = const <Profesional>[];
  String? _idProfesionalSeleccionadoMapa;
  bool _estaCargando = true;
  bool _mapaAmpliado = false;
  String? _mensajeError;
  late final ControladorRutaConsultorio _controladorRuta;

  List<Profesional> get _profesionalesConUbicacion => _profesionales
      .where((profesional) => profesional.tieneCoordenadasValidas)
      .toList();

  Profesional? get _profesionalSeleccionadoEnMapa {
    final conUbicacion = _profesionalesConUbicacion;
    if (conUbicacion.isEmpty) return null;
    for (final p in conUbicacion) {
      if (p.id == _idProfesionalSeleccionadoMapa) return p;
    }
    return conUbicacion.first;
  }

  @override
  void initState() {
    super.initState();
    _controladorRuta = ControladorRutaConsultorio(
      servicioUbicacion: widget.servicioUbicacion,
      servicioRutas: widget.servicioRutas,
    )..addListener(_actualizarVistaRuta);
    unawaited(_cargarProfesionalesDisponibles());
  }

  void _actualizarVistaRuta() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controladorRuta.removeListener(_actualizarVistaRuta);
    _controladorRuta.dispose();
    super.dispose();
  }

  void _seleccionarProfesionalEnMapa(String idProfesional) {
    if (_idProfesionalSeleccionadoMapa == idProfesional) return;
    setState(() {
      _idProfesionalSeleccionadoMapa = idProfesional;
    });
    _controladorRuta.limpiarRuta();
  }

  Future<void> _calcularRutaSeleccionada() async {
    final seleccionado = _profesionalSeleccionadoEnMapa;
    await _controladorRuta.calcularRutaHaciaConsultorio(
      destinoLatitud: seleccionado?.latitud,
      destinoLongitud: seleccionado?.longitud,
    );
  }

  Future<void> _cargarProfesionalesDisponibles() async {
    if (!mounted) return;
    setState(() {
      _estaCargando = true;
      _mensajeError = null;
    });

    if (widget.repositorio == null && !ConfiguracionSupabase.estaConfigurado) {
      if (!mounted) return;
      setState(() {
        _profesionales = const <Profesional>[];
        _estaCargando = false;
      });
      return;
    }

    try {
      final repositorio =
          widget.repositorio ?? RepositorioProfesionalesSupabase();
      final resultados = await repositorio.obtenerProfesionales();
      if (!mounted) return;
      final primeroConUbicacion = resultados
          .where((p) => p.tieneCoordenadasValidas)
          .firstOrNull;
      setState(() {
        _profesionales = resultados;
        _idProfesionalSeleccionadoMapa ??= primeroConUbicacion?.id;
        _estaCargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _estaCargando = false;
        _mensajeError =
            'No pudimos cargar los profesionales disponibles en este momento. '
            'Por favor, verifica tu conexión e inténtalo nuevamente.';
      });
    }
  }

  void _alternarFavorito(String idProfesional) {
    final esFavorito = GestorFavoritos.instancia.alternarFavorito(
      idProfesional,
    );
    _mostrarMensajeInformativo(
      esFavorito
          ? 'Guardado en tus profesionales favoritos'
          : 'Eliminado de tus profesionales favoritos',
    );
  }

  void _mostrarMensajeInformativo(String mensaje) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: TemaPsicobloom.colorLavanda,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                mensaje,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: TemaPsicobloom.colorPrincipalOscuro,
        behavior: SnackBarBehavior.floating,
        elevation: 3,
        margin: const EdgeInsets.only(bottom: 12, left: 20, right: 20),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: TemaPsicobloom.colorLavanda.withValues(alpha: 0.35),
            width: 1.0,
          ),
        ),
        duration: const Duration(milliseconds: 2200),
      ),
    );
  }

  void _gestionarCambioPestana(int nuevoIndice) {
    if (nuevoIndice == 2) return; // Ya estamos en Mapa

    switch (nuevoIndice) {
      case 0:
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (context) => PantallaInicioPaciente(
                perfilInicial: widget.perfilInicial,
                servicioSesion: widget.servicioSesion,
                repositorio: widget.repositorio,
              ),
            ),
          );
        }
        break;
      case 1:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (context) =>
                PantallaBuscarProfesionales(repositorio: widget.repositorio),
          ),
        );
        break;
      case 3:
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (context) => PantallaMisCitasPaciente(
              repositorio: widget.repositorio,
              perfilInicial: widget.perfilInicial,
              servicioSesion: widget.servicioSesion,
            ),
          ),
        );
        break;
      case 4:
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (context) => PantallaPerfilPaciente(
              perfilInicial: widget.perfilInicial,
              servicioSesion: widget.servicioSesion,
            ),
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaPsicobloom.colorFondo,
      bottomNavigationBar: BarraNavegacionPaciente(
        indiceSeleccionado: 2,
        alCambiarPestana: _gestionarCambioPestana,
      ),
      body: FondoDecorativoBloom(
        mostrarHojas: false,
        mostrarCorazones: false,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 20.0,
              vertical: 16.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _construirCabeceraSuperior(),
                const SizedBox(height: 18),
                _construirEncabezadoPantalla(),
                const SizedBox(height: 18),
                _construirAreaPreliminarMapa(),
                const SizedBox(height: 22),
                _construirEncabezadoSeccionProfesionales(),
                const SizedBox(height: 12),
                _construirContenidoProfesionales(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Barra superior institucional con logo de PsicoBloom y campana de notificaciones.
  Widget _construirCabeceraSuperior() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: TemaPsicobloom.colorSuperficie,
                shape: BoxShape.circle,
                border: Border.all(
                  color: TemaPsicobloom.colorBorde,
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: TemaPsicobloom.colorPrincipal.withValues(
                      alpha: 0.08,
                    ),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/imagenes/icono_psicobloom.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.local_florist_rounded,
                    color: TemaPsicobloom.colorPrincipal,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'PsicoBloom',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: TemaPsicobloom.colorPrincipalOscuro,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        Stack(
          children: [
            IconButton(
              icon: const Icon(
                Icons.notifications_none_rounded,
                color: TemaPsicobloom.colorTexto,
                size: 24,
              ),
              tooltip: 'Notificaciones',
              onPressed: () {
                _mostrarMensajeInformativo('No tienes nuevas notificaciones.');
              },
            ),
            Positioned(
              top: 10,
              right: 12,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: TemaPsicobloom.colorPrincipal,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// A. Encabezado con titulo y subtitulo requeridos para el modulo de mapa en Riobamba.
  Widget _construirEncabezadoPantalla() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: TemaPsicobloom.colorBorde.withValues(alpha: 0.7),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: TemaPsicobloom.colorPrincipal.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profesionales en Riobamba',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorTexto,
                    letterSpacing: -0.4,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Encuentra atención cerca de ti.',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: TemaPsicobloom.colorTextoSecundario,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            Icons.location_on_outlined,
            key: const Key('iconoEncabezadoMapa'),
            color: TemaPsicobloom.colorPrincipal.withValues(alpha: 0.72),
            size: 28,
          ),
        ],
      ),
    );
  }

  void _abrirPerfilPublico(Profesional profesional) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PantallaPerfilPublicoProfesional(
          profesional: profesional,
          servicioUbicacion: widget.servicioUbicacion,
          servicioRutas: widget.servicioRutas,
        ),
      ),
    );
  }

  List<MarcadorConsultorioMapa> _construirMarcadoresMapa() {
    final seleccionado = _profesionalSeleccionadoEnMapa;
    return _profesionalesConUbicacion
        .map(
          (prof) => MarcadorConsultorioMapa(
            id: prof.id,
            titulo: prof.nombre,
            subtitulo: prof.direccionConsultorio.trim().isNotEmpty
                ? prof.direccionConsultorio.trim()
                : prof.especialidad,
            latitud: prof.latitud,
            longitud: prof.longitud,
            fotoUrl: prof.fotoUrl,
            seleccionado: prof.id == seleccionado?.id,
          ),
        )
        .toList();
  }

  Future<void> _abrirMapaAmpliado() async {
    if (_mapaAmpliado) return;
    setState(() {
      _mapaAmpliado = true;
    });

    try {
      await showDialog<void>(
        context: context,
        useSafeArea: true,
        barrierDismissible: true,
        builder: (dialogContext) => Dialog.fullscreen(
          key: const Key('vistaMapaAmpliado'),
          child: StatefulBuilder(
            builder: (context, setStateDialog) {
              final seleccionado = _profesionalSeleccionadoEnMapa;
              return Scaffold(
                backgroundColor: TemaPsicobloom.colorFondo,
                body: SafeArea(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: const BoxDecoration(
                          color: TemaPsicobloom.colorSuperficie,
                          border: Border(
                            bottom: BorderSide(
                              color: TemaPsicobloom.colorBorde,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.map_outlined,
                              color: TemaPsicobloom.colorPrincipal,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Mapa de consultorios',
                                    style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.bold,
                                      color: TemaPsicobloom.colorTexto,
                                    ),
                                  ),
                                  if (seleccionado != null)
                                    Text(
                                      seleccionado.nombre,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color:
                                            TemaPsicobloom.colorTextoSecundario,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              key: const Key('botonCerrarMapaAmpliado'),
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: const Text('Cerrar'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: LayoutBuilder(
                            builder: (_, restricciones) => MapaConsultorioRuta(
                              altura: restricciones.maxHeight,
                              marcadores: _construirMarcadoresMapa(),
                              ubicacionPaciente:
                                  _controladorRuta.ubicacionPaciente,
                              rutaActiva: _controladorRuta.ruta,
                              alSeleccionarMarcador: (id) {
                                _seleccionarProfesionalEnMapa(id);
                                setStateDialog(() {});
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _mapaAmpliado = false;
        });
      }
    }
  }

  /// B. Mapa de consultorios de profesionales en Riobamba con calculo de ruta vial.
  Widget _construirAreaPreliminarMapa() {
    final conUbicacion = _profesionalesConUbicacion;
    final seleccionado = _profesionalSeleccionadoEnMapa;
    final marcadores = _construirMarcadoresMapa();
    final alturaMapa = (MediaQuery.sizeOf(context).height * 0.36).clamp(
      250.0,
      360.0,
    );

    return Container(
      key: const Key('areaPreliminarMapa'),
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 14.0),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: TemaPsicobloom.colorBorde, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: TemaPsicobloom.colorPrincipal.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: TemaPsicobloom.colorMenta,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Riobamba, Ecuador',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: TemaPsicobloom.colorSecundario,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  conUbicacion.isEmpty
                      ? 'Sin consultorios georreferenciados aún'
                      : '${conUbicacion.length} ${conUbicacion.length == 1 ? "consultorio en el mapa" : "consultorios en el mapa"}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: TemaPsicobloom.colorTextoSecundario,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_mapaAmpliado)
            SizedBox(height: alturaMapa)
          else
            MapaConsultorioRuta(
              altura: alturaMapa,
              marcadores: marcadores,
              ubicacionPaciente: _controladorRuta.ubicacionPaciente,
              rutaActiva: _controladorRuta.ruta,
              alSeleccionarMarcador: _seleccionarProfesionalEnMapa,
              alAmpliar: () => unawaited(_abrirMapaAmpliado()),
            ),
          if (conUbicacion.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Selecciona un profesional',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: TemaPsicobloom.colorTextoSecundario,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: conUbicacion.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, indice) {
                  final prof = conUbicacion[indice];
                  final activo = prof.id == seleccionado?.id;
                  return InkWell(
                    key: Key('tarjetaSelectorMapa_${prof.id}'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _seleccionarProfesionalEnMapa(prof.id),
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 148,
                        maxWidth: 196,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: activo
                            ? TemaPsicobloom.colorLavanda.withValues(
                                alpha: 0.55,
                              )
                            : TemaPsicobloom.colorFondo,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: activo
                              ? TemaPsicobloom.colorPrincipal
                              : TemaPsicobloom.colorBorde,
                          width: activo ? 1.8 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          AvatarFotoProfesional(
                            nombre: prof.nombre,
                            fotoUrl: prof.fotoUrl,
                            diametro: 38,
                            colorBorde: activo
                                ? TemaPsicobloom.colorPrincipal
                                : TemaPsicobloom.colorBorde,
                            anchoBorde: activo ? 2.0 : 1.2,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              prof.nombre,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: activo
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: TemaPsicobloom.colorTexto,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (seleccionado != null) ...[
            const SizedBox(height: 12),
            Container(
              key: const Key('tarjetaProfesionalSeleccionadoMapa'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: TemaPsicobloom.colorFondo,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: TemaPsicobloom.colorBorde),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AvatarFotoProfesional(
                        nombre: seleccionado.nombre,
                        fotoUrl: seleccionado.fotoUrl,
                        diametro: 52,
                        colorBorde: TemaPsicobloom.colorPrincipal,
                        anchoBorde: 2.0,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              seleccionado.nombre,
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold,
                                color: TemaPsicobloom.colorTexto,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              seleccionado.especialidades.isNotEmpty
                                  ? seleccionado.especialidades.join(', ')
                                  : seleccionado.especialidad,
                              style: const TextStyle(
                                fontSize: 13,
                                color: TemaPsicobloom.colorTextoSecundario,
                              ),
                            ),
                            if (seleccionado.direccionConsultorio
                                .trim()
                                .isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Icon(
                                      Icons.location_on_outlined,
                                      size: 14,
                                      color: TemaPsicobloom.colorPrincipal,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      seleccionado.direccionConsultorio.trim(),
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color:
                                            TemaPsicobloom.colorTextoSecundario,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  PanelResultadoRutaConsultorio(
                    claveBotonCalcular: const Key('botonCalcularRutaMapa'),
                    controlador: _controladorRuta,
                    alSolicitarRuta: () =>
                        unawaited(_calcularRutaSeleccionada()),
                    alVerPerfil: () => _abrirPerfilPublico(seleccionado),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            const Text(
              'Cuando los profesionales aprobados registren las coordenadas de su consultorio, podrás seleccionarlos en el mapa y calcular cómo llegar.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: TemaPsicobloom.colorTextoSecundario,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// C. Encabezado de la seccion de profesionales disponibles.
  Widget _construirEncabezadoSeccionProfesionales() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Expanded(
          child: Text(
            'Profesionales disponibles',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (!_estaCargando && _mensajeError == null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: TemaPsicobloom.colorLavanda,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_profesionales.length}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: TemaPsicobloom.colorPrincipalOscuro,
              ),
            ),
          ),
      ],
    );
  }

  /// Contenido dinamico segun el estado de la consulta a Supabase.
  Widget _construirContenidoProfesionales() {
    if (_estaCargando) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 18),
        decoration: BoxDecoration(
          color: TemaPsicobloom.colorSuperficie,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: TemaPsicobloom.colorBorde),
        ),
        child: const Column(
          children: [
            CircularProgressIndicator(color: TemaPsicobloom.colorPrincipal),
            SizedBox(height: 14),
            Text(
              'Cargando profesionales disponibles en Riobamba...',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: TemaPsicobloom.colorTextoSecundario,
              ),
            ),
          ],
        ),
      );
    }

    if (_mensajeError != null) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: TemaPsicobloom.colorFondoError,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: TemaPsicobloom.colorError.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: TemaPsicobloom.colorError,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              _mensajeError!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: TemaPsicobloom.colorError,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _cargarProfesionalesDisponibles,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_profesionales.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: TemaPsicobloom.colorSuperficie,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: TemaPsicobloom.colorBorde),
        ),
        child: const Column(
          children: [
            Icon(
              Icons.person_search_outlined,
              color: TemaPsicobloom.colorPrincipal,
              size: 34,
            ),
            SizedBox(height: 10),
            Text(
              'No hay profesionales aprobados disponibles',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: TemaPsicobloom.colorTexto,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'En cuanto se habiliten perfiles profesionales y sus consultorios en Riobamba, aparecerán listados en esta sección.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: TemaPsicobloom.colorTextoSecundario,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    return ValueListenableBuilder<Set<String>>(
      valueListenable: GestorFavoritos.instancia.favoritos,
      builder: (context, conjuntoFavoritos, child) {
        return Column(
          children: _profesionales.map((profesional) {
            final esFavorito = conjuntoFavoritos.contains(profesional.id);

            return Padding(
              padding: const EdgeInsets.only(bottom: 14.0),
              child: TarjetaProfesional(
                profesional: profesional,
                esFavorito: esFavorito,
                mostrarDireccionConsultorio: true,
                alAlternarFavorito: () => _alternarFavorito(profesional.id),
                alVerPerfil: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PantallaPerfilPublicoProfesional(
                        profesional: profesional,
                      ),
                    ),
                  );
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
