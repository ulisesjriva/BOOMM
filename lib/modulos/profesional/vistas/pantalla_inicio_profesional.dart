import 'dart:async';

import 'package:flutter/material.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_sesion.dart';
import 'package:boom/modulos/autenticacion/vistas/navegador_roles.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_opciones_acceso.dart';
import 'package:boom/modulos/profesional/componentes/barra_navegacion_profesional.dart';
import 'package:boom/modulos/profesional/controladores/controlador_citas_profesional.dart';
import 'package:boom/modulos/profesional/controladores/controlador_disponibilidad_profesional.dart';
import 'package:boom/modulos/profesional/modelos/cita_profesional.dart';
import 'package:boom/modulos/profesional/modelos/horario_disponibilidad.dart';
import 'package:boom/modulos/profesional/modelos/perfil_profesional.dart';
import 'package:boom/modulos/profesional/servicios/servicio_citas_profesional.dart';
import 'package:boom/modulos/profesional/servicios/servicio_disponibilidad_profesional.dart';
import 'package:boom/modulos/profesional/servicios/servicio_perfil_profesional.dart';
import 'package:boom/modulos/profesional/servicios/servicio_ubicacion_consultorio.dart';
import 'package:boom/modulos/profesional/vistas/pantalla_citas_profesional.dart';
import 'package:boom/modulos/profesional/vistas/pantalla_disponibilidad_profesional.dart';
import 'package:boom/modulos/profesional/vistas/pantalla_perfil_profesional.dart';
import 'package:boom/nucleo/componentes/fondo_decorativo_bloom.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/repositorios/repositorio_especialidades.dart';

/// Contenedor principal del modulo Profesional con barra inferior persistente
/// de cuatro secciones: Inicio | Solicitudes | Agenda | Perfil.
class PantallaInicioProfesional extends StatefulWidget {
  final PerfilUsuario perfilInicial;
  final ServicioSesion servicioSesion;
  final ServicioPerfilProfesional? servicioPerfilProfesional;
  final ServicioDisponibilidadProfesional? servicioDisponibilidad;
  final ServicioCitasProfesional? servicioCitas;
  final RepositorioEspecialidades? repositorioEspecialidades;
  final ServicioUbicacionConsultorio? servicioUbicacion;
  final Widget? seccionPerfilExtendida;
  final int pestanaInicial;

  const PantallaInicioProfesional({
    super.key,
    required this.perfilInicial,
    this.servicioSesion = const ServicioSesion(),
    this.servicioPerfilProfesional,
    this.servicioDisponibilidad,
    this.servicioCitas,
    this.repositorioEspecialidades,
    this.servicioUbicacion,
    this.seccionPerfilExtendida,
    this.pestanaInicial = 0,
  });

  @override
  State<PantallaInicioProfesional> createState() =>
      _PantallaInicioProfesionalState();
}

class _PantallaInicioProfesionalState extends State<PantallaInicioProfesional>
    with WidgetsBindingObserver {
  late PerfilUsuario _perfil;
  PerfilProfesional? _perfilProfesionalDetallado;
  late int _indicePestana;
  bool _estaCerrandoSesion = false;

  late final ControladorCitasProfesional _controladorCitas;
  late final ControladorDisponibilidadProfesional _controladorDisponibilidad;

  late DateTime _ultimoHoyEcuadorConocido;
  late DateTime _fechaSeleccionadaInicio;
  late DateTime _lunesSemanaInicio;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _perfil = widget.perfilInicial;
    _indicePestana = widget.pestanaInicial.clamp(0, 3);
    _controladorCitas = ControladorCitasProfesional(
      servicio: widget.servicioCitas,
    )..addListener(_actualizarVista);
    _controladorDisponibilidad = ControladorDisponibilidadProfesional(
      servicio: widget.servicioDisponibilidad,
    );

    final hoyEcuador = _obtenerHoyEnEcuador();
    _ultimoHoyEcuadorConocido = hoyEcuador;
    _fechaSeleccionadaInicio = hoyEcuador;
    _lunesSemanaInicio = HorarioDisponibilidad.obtenerLunesDeSemana(hoyEcuador);

    _cargarDatosInicialesResumen();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _revisarActualizacionDeFechaActual(recargarCitas: true);
    }
  }

  DateTime _obtenerHoyEnEcuador() {
    return HorarioDisponibilidad.normalizarFechaSoloDia(
      _controladorCitas.obtenerAhoraEnEcuador(),
    );
  }

  void _revisarActualizacionDeFechaActual({bool recargarCitas = false}) {
    final hoyActual = _obtenerHoyEnEcuador();
    final cambioElDia = !_esMismoDia(hoyActual, _ultimoHoyEcuadorConocido);
    if (cambioElDia) {
      final estabaEnHoyAnterior = _esMismoDia(
        _fechaSeleccionadaInicio,
        _ultimoHoyEcuadorConocido,
      );
      _ultimoHoyEcuadorConocido = hoyActual;
      if (estabaEnHoyAnterior) {
        _fechaSeleccionadaInicio = hoyActual;
        _lunesSemanaInicio = HorarioDisponibilidad.obtenerLunesDeSemana(
          hoyActual,
        );
      }
      if (mounted) {
        setState(() {});
      }
    }
    if (recargarCitas &&
        _tieneServicioCitasDisponible &&
        !_controladorCitas.estaCargando) {
      unawaited(_controladorCitas.cargarCitasPropias());
    }
  }

  void _actualizarVista() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controladorCitas.removeListener(_actualizarVista);
    _controladorCitas.dispose();
    _controladorDisponibilidad.dispose();
    super.dispose();
  }

  bool get _tieneServicioCitasDisponible =>
      widget.servicioCitas != null || ConfiguracionSupabase.estaConfigurado;

  bool get _puedeConsultarPerfilDetallado =>
      widget.servicioPerfilProfesional != null ||
      ConfiguracionSupabase.estaConfigurado;

  Future<void> _cargarDatosInicialesResumen() async {
    _revisarActualizacionDeFechaActual();
    unawaited(_cargarPerfilProfesionalDetalladoSiCorresponde());
    if (_tieneServicioCitasDisponible &&
        (_perfil.aprobacion == 'aprobado' || widget.servicioCitas != null)) {
      await _controladorCitas.cargarCitasPropias();
    }
  }

  Future<void> _cargarPerfilProfesionalDetalladoSiCorresponde() async {
    if (!_puedeConsultarPerfilDetallado) return;
    final servicio =
        widget.servicioPerfilProfesional ?? const ServicioPerfilProfesional();
    try {
      final detalle = await servicio.obtenerPerfilPropio();
      if (!mounted) return;
      final aprobacionAnterior = _perfil.aprobacion;
      final fotoPrevia = _perfilProfesionalDetallado?.fotoUrl?.trim();
      final fotoServidor = detalle.fotoUrl?.trim();
      final detalleSincronizado =
          (fotoServidor == null || fotoServidor.isEmpty) &&
              fotoPrevia != null &&
              fotoPrevia.isNotEmpty
          ? detalle.copiarCon(fotoUrl: fotoPrevia)
          : detalle;
      setState(() {
        _perfilProfesionalDetallado = detalleSincronizado;
        _perfil = PerfilUsuario(
          id: _perfil.id,
          nombre: detalleSincronizado.nombre,
          apellido: detalleSincronizado.apellido,
          correo: detalleSincronizado.correo.isNotEmpty
              ? detalleSincronizado.correo
              : _perfil.correo,
          rol: _perfil.rol,
          aprobacion: detalleSincronizado.aprobacion.isNotEmpty
              ? detalleSincronizado.aprobacion
              : _perfil.aprobacion,
          cuentaActiva: detalleSincronizado.cuentaActiva,
        );
      });
      if (aprobacionAnterior != 'aprobado' &&
          _perfil.aprobacion == 'aprobado' &&
          _tieneServicioCitasDisponible &&
          !_controladorCitas.estaCargando) {
        unawaited(_controladorCitas.cargarCitasPropias());
      }
    } catch (_) {
      // Si no hay sesion remota en pruebas unitarias sin doble inyectado, se conserva _perfil.
    }
  }

  void _cambiarPestana(int nuevoIndice) {
    final indiceNormalizado = nuevoIndice.clamp(0, 3);
    if (_indicePestana == indiceNormalizado) return;
    final pestanaAnterior = _indicePestana;
    setState(() {
      _indicePestana = indiceNormalizado;
    });
    if (indiceNormalizado == 0) {
      _revisarActualizacionDeFechaActual();
      if (pestanaAnterior == 3) {
        unawaited(_cargarPerfilProfesionalDetalladoSiCorresponde());
      }
    }
    if ((indiceNormalizado == 0 || indiceNormalizado == 1) &&
        _tieneServicioCitasDisponible &&
        (_perfil.aprobacion == 'aprobado' || widget.servicioCitas != null) &&
        !_controladorCitas.estaCargando) {
      unawaited(_controladorCitas.cargarCitasPropias());
    }
  }

  void _irASolicitudes({FiltroEstadoCitaProfesional? filtro}) {
    if (filtro != null) {
      _controladorCitas.cambiarFiltro(filtro);
    }
    if (_indicePestana != 1) {
      setState(() {
        _indicePestana = 1;
      });
    }
    if (_tieneServicioCitasDisponible &&
        (_perfil.aprobacion == 'aprobado' || widget.servicioCitas != null) &&
        !_controladorCitas.estaCargando) {
      unawaited(_controladorCitas.cargarCitasPropias());
    }
  }

  void _sincronizarPerfilActualizado(PerfilProfesional perfilActualizado) {
    if (!mounted) return;
    setState(() {
      _perfilProfesionalDetallado = perfilActualizado;
      _perfil = PerfilUsuario(
        id: _perfil.id,
        nombre: perfilActualizado.nombre,
        apellido: perfilActualizado.apellido,
        correo: _perfil.correo,
        rol: _perfil.rol,
        aprobacion: perfilActualizado.aprobacion.isNotEmpty
            ? perfilActualizado.aprobacion
            : _perfil.aprobacion,
        cuentaActiva: perfilActualizado.cuentaActiva,
      );
    });
  }

  void _mostrarAvisoNotificaciones() {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('avisoNotificacionesProximamenteProfesional'),
        content: const Row(
          children: [
            Icon(
              Icons.notifications_none_rounded,
              color: TemaPsicobloom.colorLavanda,
              size: 18,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Las notificaciones estarán disponibles próximamente',
                style: TextStyle(
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
        duration: const Duration(milliseconds: 2400),
      ),
    );
  }

  bool _esMismoDia(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<CitaProfesional> _obtenerCitasConfirmadasPorFecha(DateTime fecha) {
    final fechaIso = HorarioDisponibilidad.formatearFechaIso(fecha);
    final confirmadas = _controladorCitas.citas
        .where((cita) => cita.esConfirmada && cita.fechaIso == fechaIso)
        .toList();
    confirmadas.sort((a, b) => a.minutosInicio.compareTo(b.minutosInicio));
    return confirmadas;
  }

  CitaProfesional? _obtenerProximaCitaConfirmadaFutura() {
    final ahoraUtc = _controladorCitas.obtenerAhoraUtc();
    final futurasConfirmadas = _controladorCitas.citas
        .where(
          (cita) =>
              cita.esConfirmada &&
              cita.esFuturoEnEcuador(referenciaUtc: ahoraUtc),
        )
        .toList();
    if (futurasConfirmadas.isEmpty) {
      return null;
    }
    futurasConfirmadas.sort((a, b) {
      final cmpFecha = a.fechaIso.compareTo(b.fechaIso);
      if (cmpFecha != 0) return cmpFecha;
      return a.minutosInicio.compareTo(b.minutosInicio);
    });
    return futurasConfirmadas.first;
  }

  void _cambiarSemanaInicio(int desplazamientoSemanas) {
    final nuevoLunes = DateTime(
      _lunesSemanaInicio.year,
      _lunesSemanaInicio.month,
      _lunesSemanaInicio.day + (desplazamientoSemanas * 7),
    );
    final diasNuevaSemana = HorarioDisponibilidad.obtenerDiasDeSemana(
      nuevoLunes,
    );
    final hoyEcuador = _obtenerHoyEnEcuador();

    DateTime nuevoDiaSeleccionado;
    if (diasNuevaSemana.any((d) => _esMismoDia(d, hoyEcuador))) {
      nuevoDiaSeleccionado = hoyEcuador;
    } else {
      final primerDiaConCitas = diasNuevaSemana
          .where((d) => _obtenerCitasConfirmadasPorFecha(d).isNotEmpty)
          .firstOrNull;
      nuevoDiaSeleccionado = primerDiaConCitas ?? nuevoLunes;
    }

    setState(() {
      _lunesSemanaInicio = nuevoLunes;
      _fechaSeleccionadaInicio = nuevoDiaSeleccionado;
    });
  }

  void _irAHoyInicio() {
    final hoyEcuador = _obtenerHoyEnEcuador();
    _ultimoHoyEcuadorConocido = hoyEcuador;
    setState(() {
      _fechaSeleccionadaInicio = hoyEcuador;
      _lunesSemanaInicio = HorarioDisponibilidad.obtenerLunesDeSemana(
        hoyEcuador,
      );
    });
  }

  void _seleccionarDiaInicio(DateTime fechaDia) {
    final normalizada = HorarioDisponibilidad.normalizarFechaSoloDia(fechaDia);
    setState(() {
      _fechaSeleccionadaInicio = normalizada;
      _lunesSemanaInicio = HorarioDisponibilidad.obtenerLunesDeSemana(
        normalizada,
      );
    });
  }

  Future<void> _mostrarDetalleCitaConfirmada(CitaProfesional cita) async {
    await showDialog<void>(
      context: context,
      builder: (contextoDialogo) {
        return AlertDialog(
          key: const Key('dialogoDetalleProximaCitaProfesional'),
          backgroundColor: TemaPsicobloom.colorSuperficie,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.event_available_rounded,
                color: TemaPsicobloom.colorPrincipal,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Detalle de cita confirmada',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _construirFilaDetalleDialogo('Paciente', cita.nombrePaciente),
              const SizedBox(height: 8),
              _construirFilaDetalleDialogo('Fecha', cita.fechaLegible),
              const SizedBox(height: 8),
              _construirFilaDetalleDialogo(
                'Intervalo',
                '${cita.horaInicioNormalizada} - ${cita.horaFinNormalizada} (${cita.duracionMinutos} min)',
              ),
              const SizedBox(height: 8),
              _construirFilaDetalleDialogo(
                'Modalidad',
                cita.modalidadProfesional,
              ),
              const SizedBox(height: 8),
              _construirFilaDetalleDialogo('Estado', cita.etiquetaEstado),
            ],
          ),
          actions: [
            TextButton(
              key: const Key('botonCerrarDetalleProximaCita'),
              onPressed: () => Navigator.of(contextoDialogo).pop(),
              child: const Text('Cerrar'),
            ),
            ElevatedButton(
              key: const Key('botonIrAConfirmadasDesdeDetalle'),
              onPressed: () {
                Navigator.of(contextoDialogo).pop();
                _irASolicitudes(
                  filtro: FiltroEstadoCitaProfesional.confirmadas,
                );
              },
              child: const Text('Ver en Solicitudes'),
            ),
          ],
        );
      },
    );
  }

  Widget _construirFilaDetalleDialogo(String etiqueta, String valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: TemaPsicobloom.colorTextoSecundario,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          valor,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: TemaPsicobloom.colorTexto,
          ),
        ),
      ],
    );
  }

  Future<void> _cerrarSesion() async {
    if (_estaCerrandoSesion) return;
    setState(() => _estaCerrandoSesion = true);
    try {
      await widget.servicioSesion.cerrarSesion();
    } finally {
      if (mounted) {
        setState(() => _estaCerrandoSesion = false);
        Navigator.of(context).pushAndRemoveUntil<void>(
          MaterialPageRoute<void>(
            builder: (_) => const PantallaOpcionesAcceso(),
          ),
          (_) => false,
        );
      }
    }
  }

  String _tituloAppBarPorPestana() {
    switch (_indicePestana) {
      case 1:
        return 'Solicitudes';
      case 2:
        return 'Agenda';
      case 3:
        return 'Perfil';
      default:
        return 'PsicoBloom';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hoyActual = _obtenerHoyEnEcuador();
    if (!_esMismoDia(hoyActual, _ultimoHoyEcuadorConocido)) {
      final estabaEnHoyAnterior = _esMismoDia(
        _fechaSeleccionadaInicio,
        _ultimoHoyEcuadorConocido,
      );
      _ultimoHoyEcuadorConocido = hoyActual;
      if (estabaEnHoyAnterior) {
        _fechaSeleccionadaInicio = hoyActual;
        _lunesSemanaInicio = HorarioDisponibilidad.obtenerLunesDeSemana(
          hoyActual,
        );
      }
    }

    return NavegadorRoles.protegerPorRol(
      perfil: _perfil,
      rolRequerido: 'profesional',
      servicioSesion: widget.servicioSesion,
      constructorContenido: (perfilValido) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _indicePestana != 0) {
              _cambiarPestana(0);
            }
          },
          child: Scaffold(
            backgroundColor: TemaPsicobloom.colorFondo,
            appBar: _indicePestana == 0
                ? null
                : AppBar(
                    automaticallyImplyLeading: false,
                    leading: IconButton(
                      key: const Key('botonVolverInicioProfesional'),
                      tooltip: 'Volver a Inicio',
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => _cambiarPestana(0),
                    ),
                    title: Text(_tituloAppBarPorPestana()),
                    actions: [
                      IconButton(
                        key: const Key('botonNotificacionesProfesional'),
                        icon: const Icon(Icons.notifications_none_rounded),
                        tooltip: 'Notificaciones',
                        onPressed: _mostrarAvisoNotificaciones,
                      ),
                    ],
                  ),
            body: FondoDecorativoBloom(
              mostrarHojas: false,
              mostrarCorazones: false,
              child: SafeArea(child: _construirCuerpoPestana(perfilValido)),
            ),
            bottomNavigationBar: BarraNavegacionProfesional(
              indiceSeleccionado: _indicePestana,
              alCambiarPestana: _cambiarPestana,
              solicitudesPendientes: _controladorCitas.totalPendientes,
            ),
          ),
        );
      },
    );
  }

  Widget _construirCuerpoPestana(PerfilUsuario perfilValido) {
    switch (_indicePestana) {
      case 0:
        return _construirVistaResumenInicio(perfilValido);
      case 1:
        return PantallaCitasProfesional(
          controlador: _controladorCitas,
          esVistaIntegrada: true,
        );
      case 2:
        return PantallaDisponibilidadProfesional(
          controlador: _controladorDisponibilidad,
          estaPendienteAprobacion: perfilValido.aprobacion != 'aprobado',
          esVistaIntegrada: true,
          alIrASolicitudes: () => _irASolicitudes(),
        );
      case 3:
        return PantallaPerfilProfesional(
          perfilInicial: _perfilProfesionalDetallado,
          aprobacionInicial: perfilValido.aprobacion,
          servicio:
              widget.servicioPerfilProfesional ??
              const ServicioPerfilProfesional(),
          repositorioEspecialidades:
              widget.repositorioEspecialidades ??
              const RepositorioEspecialidadesSupabase(),
          servicioUbicacion:
              widget.servicioUbicacion ?? const ServicioUbicacionConsultorio(),
          esVistaIntegrada: true,
          alActualizarPerfil: _sincronizarPerfilActualizado,
          alCerrarSesion: _cerrarSesion,
          estaCerrandoSesion: _estaCerrandoSesion,
        );
      default:
        return _construirVistaResumenInicio(perfilValido);
    }
  }

  Widget _construirVistaResumenInicio(PerfilUsuario perfilValido) {
    return RefreshIndicator(
      color: TemaPsicobloom.colorPrincipal,
      onRefresh: _cargarDatosInicialesResumen,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        children: [
          _construirCabeceraSuperiorMarca(),
          const SizedBox(height: 14),
          _construirTarjetaBienvenida(perfilValido),
          const SizedBox(height: 18),
          _construirSeccionConsultaSemanal(perfilValido),
          const SizedBox(height: 16),
          _construirAccesoCompactoSolicitudesPendientes(),
          if (widget.seccionPerfilExtendida != null) ...[
            const SizedBox(height: 14),
            widget.seccionPerfilExtendida!,
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// 1. CABECERA: Icono original de PsicoBloom, nombre de la marca y campana
  /// de notificaciones (sin boton de cerrar sesion).
  Widget _construirCabeceraSuperiorMarca() {
    return Row(
      key: const Key('cabeceraMarcaInicioProfesional'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
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
                    key: const Key('iconoMarcaCabeceraProfesional'),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.local_florist_rounded,
                      color: TemaPsicobloom.colorPrincipal,
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Flexible(
                child: Text(
                  'PsicoBloom',
                  key: Key('textoMarcaCabeceraProfesional'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorPrincipalOscuro,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          key: const Key('botonNotificacionesProfesional'),
          icon: const Icon(
            Icons.notifications_none_rounded,
            color: TemaPsicobloom.colorPrincipalOscuro,
            size: 26,
          ),
          tooltip: 'Notificaciones',
          onPressed: _mostrarAvisoNotificaciones,
        ),
      ],
    );
  }

  /// 2. BIENVENIDA: Tarjeta acogedora y compacta con el nombre real del profesional.
  Widget _construirTarjetaBienvenida(PerfilUsuario perfil) {
    final nombreSaludo = _obtenerNombreSaludo(perfil);

    return Container(
      key: const Key('tarjetaBienvenidaProfesional'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: TemaPsicobloom.colorBorde.withValues(alpha: 0.75),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: TemaPsicobloom.colorPrincipal.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hola, $nombreSaludo 👋',
                  key: const Key('textoSaludoBienvenidaProfesional'),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorPrincipalOscuro,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Estas son tus citas de hoy',
                  key: Key('subtituloBienvenidaProfesional'),
                  style: TextStyle(
                    fontSize: 13.5,
                    color: TemaPsicobloom.colorTextoSecundario,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _construirAvatarBienvenidaProfesional(perfil),
        ],
      ),
    );
  }

  Widget _construirAvatarBienvenidaProfesional(PerfilUsuario perfil) {
    final fotoUrl = _perfilProfesionalDetallado?.fotoUrl?.trim();
    final tieneFoto = fotoUrl != null && fotoUrl.isNotEmpty;
    final nombreParaIniciales =
        (_perfilProfesionalDetallado != null &&
            _perfilProfesionalDetallado!.nombreCompleto.trim().isNotEmpty)
        ? _perfilProfesionalDetallado!.nombreCompleto
        : perfil.nombreCompleto;
    final iniciales = _obtenerIniciales(nombreParaIniciales);

    return Container(
      key: const Key('avatarBienvenidaProfesional'),
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorLavanda,
        shape: BoxShape.circle,
        border: Border.all(color: TemaPsicobloom.colorBorde, width: 2.0),
      ),
      child: ClipOval(
        child: tieneFoto
            ? Image.network(
                fotoUrl,
                key: ValueKey('fotoBienvenidaProfesional_$fotoUrl'),
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    _construirInicialesBienvenidaProfesional(iniciales),
              )
            : _construirInicialesBienvenidaProfesional(iniciales),
      ),
    );
  }

  Widget _construirInicialesBienvenidaProfesional(String iniciales) {
    return Center(
      child: Text(
        iniciales,
        key: const Key('inicialesBienvenidaProfesional'),
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: TemaPsicobloom.colorPrincipalOscuro,
        ),
      ),
    );
  }

  /// 4, 5 y 6. CONSULTA SEMANAL DE CITAS, TARJETAS CONFIRMADAS Y DIAS SIN CITAS.
  Widget _construirSeccionConsultaSemanal(PerfilUsuario perfil) {
    final diasSemana = HorarioDisponibilidad.obtenerDiasDeSemana(
      _lunesSemanaInicio,
    );
    final hoyEcuador = _obtenerHoyEnEcuador();
    final esDiaSeleccionadoHoy = _esMismoDia(
      _fechaSeleccionadaInicio,
      hoyEcuador,
    );
    final citasConfirmadasDelDia = _obtenerCitasConfirmadasPorFecha(
      _fechaSeleccionadaInicio,
    );
    final totalDelDia = citasConfirmadasDelDia.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Tu semana',
              key: Key('tituloTuSemanaProfesional'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: TemaPsicobloom.colorPrincipalOscuro,
              ),
            ),
            IconButton(
              key: const Key('botonActualizarCitasInicioProfesional'),
              tooltip: 'Actualizar citas',
              visualDensity: VisualDensity.compact,
              onPressed: _controladorCitas.estaCargando
                  ? null
                  : () => _controladorCitas.cargarCitasPropias(),
              icon: const Icon(
                Icons.refresh_rounded,
                size: 20,
                color: TemaPsicobloom.colorPrincipal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _construirBarraRangoSemana(),
        const SizedBox(height: 10),
        _construirFilaSelectorDiasSemana(diasSemana),
        const SizedBox(height: 8),
        const Text(
          'Elige un día para consultar tus citas',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: TemaPsicobloom.colorTextoSecundario,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          key: const Key('encabezadoDiaSeleccionadoInicioProfesional'),
          children: [
            Expanded(
              child: Text(
                _formatearTituloDiaSeleccionado(
                  _fechaSeleccionadaInicio,
                  esHoy: esDiaSeleccionadoHoy,
                ),
                key: const Key('tituloDiaSeleccionadoInicioProfesional'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: TemaPsicobloom.colorPrincipalOscuro,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  key: const Key('insigniaTotalConfirmadasDiaSeleccionado'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: TemaPsicobloom.colorFondoExito,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    totalDelDia == 1
                        ? '1 cita confirmada'
                        : '$totalDelDia citas confirmadas',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: TemaPsicobloom.colorExito,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _construirContenidoCitasDiaSeleccionado(
          perfil: perfil,
          citasConfirmadasDelDia: citasConfirmadasDelDia,
        ),
      ],
    );
  }

  Widget _construirBarraRangoSemana() {
    return Container(
      key: const Key('barraSelectorSemanaInicioProfesional'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Row(
        children: [
          IconButton(
            key: const Key('botonSemanaAnteriorInicioProfesional'),
            tooltip: 'Semana anterior',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            onPressed: () => _cambiarSemanaInicio(-1),
            icon: const Icon(
              Icons.chevron_left_rounded,
              color: TemaPsicobloom.colorPrincipalOscuro,
              size: 22,
            ),
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _formatearRangoSemanaInicio(_lunesSemanaInicio),
                  key: const Key('textoRangoSemanaInicioProfesional'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            key: const Key('botonSemanaSiguienteInicioProfesional'),
            tooltip: 'Semana siguiente',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            onPressed: () => _cambiarSemanaInicio(1),
            icon: const Icon(
              Icons.chevron_right_rounded,
              color: TemaPsicobloom.colorPrincipalOscuro,
              size: 22,
            ),
          ),
          Container(
            width: 1,
            height: 22,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: TemaPsicobloom.colorBorde,
          ),
          Material(
            color: TemaPsicobloom.colorFondoExito,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              key: const Key('botonHoyInicioProfesional'),
              borderRadius: BorderRadius.circular(10),
              onTap: _irAHoyInicio,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  'Hoy',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorExito,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirFilaSelectorDiasSemana(List<DateTime> diasSemana) {
    return Row(
      children: List<Widget>.generate(diasSemana.length, (indice) {
        final fechaDia = diasSemana[indice];
        final fechaIso = HorarioDisponibilidad.formatearFechaIso(fechaDia);
        final seleccionado = _esMismoDia(fechaDia, _fechaSeleccionadaInicio);
        final conteoConfirmadas = _obtenerCitasConfirmadasPorFecha(fechaDia)
            .length;

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: indice < diasSemana.length - 1 ? 5 : 0,
            ),
            child: Semantics(
              button: true,
              selected: seleccionado,
              label:
                  '${_abreviaturaDiaSemana(fechaDia)} ${fechaDia.day}, $conteoConfirmadas citas confirmadas',
              child: Material(
                color: seleccionado
                    ? TemaPsicobloom.colorPrincipal
                    : TemaPsicobloom.colorSuperficie,
                borderRadius: BorderRadius.circular(13),
                child: InkWell(
                  key: Key('selectorDiaInicioProfesional_$fechaIso'),
                  borderRadius: BorderRadius.circular(13),
                  onTap: () => _seleccionarDiaInicio(fechaDia),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: seleccionado
                            ? TemaPsicobloom.colorPrincipal
                            : TemaPsicobloom.colorBorde,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _abreviaturaDiaSemana(fechaDia),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: seleccionado
                                  ? Colors.white
                                  : TemaPsicobloom.colorTextoSecundario,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${fechaDia.day}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: seleccionado
                                  ? Colors.white
                                  : TemaPsicobloom.colorTexto,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Container(
                            key: Key('conteoConfirmadasDia_$fechaIso'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: seleccionado
                                  ? Colors.white
                                  : TemaPsicobloom.colorFondoExito,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$conteoConfirmadas',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: seleccionado
                                    ? TemaPsicobloom.colorPrincipalOscuro
                                    : TemaPsicobloom.colorExito,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _construirContenidoCitasDiaSeleccionado({
    required PerfilUsuario perfil,
    required List<CitaProfesional> citasConfirmadasDelDia,
  }) {
    if (_controladorCitas.estaCargando && _controladorCitas.citas.isEmpty) {
      return Container(
        key: const Key('estadoCargandoCitasInicioProfesional'),
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          color: TemaPsicobloom.colorSuperficie,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: TemaPsicobloom.colorBorde),
        ),
        child: const Column(
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: TemaPsicobloom.colorPrincipal,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Consultando tus citas confirmadas...',
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

    if (_controladorCitas.mensajeErrorCarga != null ||
        perfil.aprobacion != 'aprobado') {
      final mensajeMostrado =
          _controladorCitas.mensajeErrorCarga ??
          'Tu perfil profesional debe estar aprobado y activo para consultar y gestionar tus citas.';

      return Container(
        key: const Key('estadoErrorCitasInicioProfesional'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: TemaPsicobloom.colorSuperficie,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: TemaPsicobloom.colorError.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: TemaPsicobloom.colorError,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              mensajeMostrado,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: TemaPsicobloom.colorTexto,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('botonReintentarCitasInicioProfesional'),
              onPressed: _controladorCitas.estaCargando
                  ? null
                  : () => _controladorCitas.cargarCitasPropias(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    final proximaCitaFutura = _obtenerProximaCitaConfirmadaFutura();

    if (citasConfirmadasDelDia.isEmpty) {
      return Container(
        key: const Key('estadoSinCitasDiaSeleccionado'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: TemaPsicobloom.colorSuperficie,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: TemaPsicobloom.colorBorde),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.event_busy_outlined,
                  color: TemaPsicobloom.colorTextoSecundario,
                  size: 20,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No tienes citas confirmadas para este día',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: TemaPsicobloom.colorTexto,
                    ),
                  ),
                ),
              ],
            ),
            if (proximaCitaFutura != null) ...[
              const SizedBox(height: 12),
              _construirAccesoCompactoProximaCitaFutura(proximaCitaFutura),
            ],
          ],
        ),
      );
    }

    return Column(
      children: List<Widget>.generate(citasConfirmadasDelDia.length, (indice) {
        final cita = citasConfirmadasDelDia[indice];
        final esLaProximaCita =
            proximaCitaFutura != null &&
            proximaCitaFutura.idCita == cita.idCita;

        return Padding(
          padding: EdgeInsets.only(
            bottom: indice < citasConfirmadasDelDia.length - 1 ? 10 : 0,
          ),
          child: _construirTarjetaCitaConfirmadaDia(
            cita: cita,
            esProxima: esLaProximaCita,
          ),
        );
      }),
    );
  }

  Widget _construirAccesoCompactoProximaCitaFutura(
    CitaProfesional proximaCita,
  ) {
    return Container(
      key: const Key('tarjetaProximaCitaConfirmada'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorLavanda.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: TemaPsicobloom.colorPrincipal.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.event_available_rounded,
                size: 16,
                color: TemaPsicobloom.colorPrincipal,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Próxima cita confirmada',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorPrincipalOscuro,
                  ),
                ),
              ),
              Text(
                proximaCita.fechaLegible,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: TemaPsicobloom.colorPrincipalOscuro,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${proximaCita.rangoHorarioCompacto} · ${proximaCita.nombrePaciente}',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
              ),
              TextButton(
                key: const Key('botonIrADiaProximaCita'),
                onPressed: () => _seleccionarDiaInicio(proximaCita.fecha),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Ir al día'),
              ),
              TextButton(
                key: const Key('botonVerProximaCitaConfirmada'),
                onPressed: () => _mostrarDetalleCitaConfirmada(proximaCita),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Ver detalle'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _construirTarjetaCitaConfirmadaDia({
    required CitaProfesional cita,
    required bool esProxima,
  }) {
    final iniciales = _obtenerIniciales(cita.nombrePaciente);
    final iconoModalidad = _obtenerIconoModalidad(cita.modalidadProfesional);

    return Container(
      key: Key('tarjetaCitaConfirmadaInicio_${cita.idCita}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: esProxima
              ? TemaPsicobloom.colorPrincipal.withValues(alpha: 0.45)
              : TemaPsicobloom.colorBorde,
        ),
        boxShadow: [
          BoxShadow(
            color: TemaPsicobloom.colorTexto.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.access_time_rounded,
                size: 18,
                color: TemaPsicobloom.colorPrincipalOscuro,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  cita.rangoHorarioCompacto,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
              ),
              if (esProxima) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    key: Key('insigniaProximaCita_${cita.idCita}'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: TemaPsicobloom.colorLavanda,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Próxima',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: TemaPsicobloom.colorPrincipalOscuro,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: TemaPsicobloom.colorLavanda,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    iniciales,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: TemaPsicobloom.colorPrincipalOscuro,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            cita.nombrePaciente,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: TemaPsicobloom.colorTexto,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        TextButton(
                          key: esProxima
                              ? const Key('botonVerProximaCitaConfirmada')
                              : Key(
                                  'botonVerDetalleCitaConfirmada_${cita.idCita}',
                                ),
                          onPressed: () => _mostrarDetalleCitaConfirmada(cita),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Ver detalle',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: TemaPsicobloom.colorPrincipalOscuro,
                                ),
                              ),
                              SizedBox(width: 2),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 16,
                                color: TemaPsicobloom.colorPrincipalOscuro,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              iconoModalidad,
                              size: 14,
                              color: TemaPsicobloom.colorTextoSecundario,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                cita.modalidadProfesional,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: TemaPsicobloom.colorTextoSecundario,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: TemaPsicobloom.colorFondoExito,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_rounded,
                                size: 13,
                                color: TemaPsicobloom.colorExito,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'Confirmada',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: TemaPsicobloom.colorExito,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 7. SOLICITUDES PENDIENTES: Acceso compacto secundario a las citas del dia.
  Widget _construirAccesoCompactoSolicitudesPendientes() {
    final int pendientes = _controladorCitas.totalPendientes;

    return Material(
      key: const Key('tarjetaSolicitudesCitasProfesional'),
      color: TemaPsicobloom.colorSuperficie,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('botonIrACitasProfesional'),
        borderRadius: BorderRadius.circular(16),
        onTap: () =>
            _irASolicitudes(filtro: FiltroEstadoCitaProfesional.pendientes),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: TemaPsicobloom.colorBorde),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: TemaPsicobloom.colorLavanda.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.assignment_outlined,
                  color: TemaPsicobloom.colorPrincipalOscuro,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Solicitudes pendientes',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
              ),
              Container(
                key: const Key('contadorSolicitudesPendientesInicio'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: TemaPsicobloom.colorFondoExito,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$pendientes',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorExito,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: TemaPsicobloom.colorPrincipalOscuro,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _obtenerNombreSaludo(PerfilUsuario perfil) {
    final limpio = perfil.nombre.trim();
    if (limpio.isNotEmpty) {
      return limpio.split(RegExp(r'\s+')).first;
    }
    final completo = perfil.nombreCompleto.trim();
    if (completo.isNotEmpty) {
      return completo.split(RegExp(r'\s+')).first;
    }
    return 'Profesional';
  }

  String _abreviaturaDiaSemana(DateTime fecha) {
    const abreviaturas = <int, String>{
      DateTime.monday: 'Lun',
      DateTime.tuesday: 'Mar',
      DateTime.wednesday: 'Mié',
      DateTime.thursday: 'Jueves' == '' ? '' : 'Jue',
      DateTime.friday: 'Vie',
      DateTime.saturday: 'Sáb',
      DateTime.sunday: 'Dom',
    };
    return abreviaturas[fecha.weekday] ?? '';
  }

  String _nombreDiaSemana(DateTime fecha) {
    const nombres = <int, String>{
      DateTime.monday: 'Lunes',
      DateTime.tuesday: 'Martes',
      DateTime.wednesday: 'Miércoles',
      DateTime.thursday: 'Jueves',
      DateTime.friday: 'Viernes',
      DateTime.saturday: 'Sábado',
      DateTime.sunday: 'Domingo',
    };
    return nombres[fecha.weekday] ?? '';
  }

  String _nombreMesLargo(int mes) {
    const meses = <int, String>{
      1: 'enero',
      2: 'febrero',
      3: 'marzo',
      4: 'abril',
      5: 'mayo',
      6: 'junio',
      7: 'julio',
      8: 'agosto',
      9: 'septiembre',
      10: 'octubre',
      11: 'noviembre',
      12: 'diciembre',
    };
    return meses[mes] ?? '';
  }

  String _nombreMesCorto(int mes) {
    const meses = <int, String>{
      1: 'ene',
      2: 'feb',
      3: 'mar',
      4: 'abr',
      5: 'may',
      6: 'jun',
      7: 'jul',
      8: 'ago',
      9: 'sep',
      10: 'oct',
      11: 'nov',
      12: 'dic',
    };
    return meses[mes] ?? '';
  }

  String _formatearRangoSemanaInicio(DateTime lunesSemana) {
    final lunes = HorarioDisponibilidad.obtenerLunesDeSemana(lunesSemana);
    final domingo = DateTime(lunes.year, lunes.month, lunes.day + 6);
    if (lunes.year == domingo.year && lunes.month == domingo.month) {
      return '${lunes.day}–${domingo.day} ${_nombreMesLargo(lunes.month)} ${lunes.year}';
    }
    if (lunes.year == domingo.year) {
      return '${lunes.day} ${_nombreMesCorto(lunes.month)} – ${domingo.day} ${_nombreMesCorto(domingo.month)} ${domingo.year}';
    }
    return '${lunes.day} ${_nombreMesCorto(lunes.month)} ${lunes.year} – ${domingo.day} ${_nombreMesCorto(domingo.month)} ${domingo.year}';
  }

  String _formatearTituloDiaSeleccionado(
    DateTime fecha, {
    required bool esHoy,
  }) {
    final diaNombre = _nombreDiaSemana(fecha);
    if (esHoy) {
      return 'Hoy · $diaNombre ${fecha.day}';
    }
    return '$diaNombre, ${fecha.day} de ${_nombreMesLargo(fecha.month)}';
  }

  IconData _obtenerIconoModalidad(String modalidad) {
    final minusculas = modalidad.trim().toLowerCase();
    final mencionaVirtual =
        minusculas.contains('virtual') || minusculas.contains('online');
    final mencionaPresencial = minusculas.contains('presencial');
    final esHibrida =
        minusculas.contains('híbrida') ||
        minusculas.contains('hibrida') ||
        (mencionaVirtual && mencionaPresencial);
    if (esHibrida) {
      return Icons.sync_alt_rounded;
    }
    if (mencionaVirtual) {
      return Icons.videocam_outlined;
    }
    return Icons.location_on_outlined;
  }

  String _obtenerIniciales(String nombreCompleto) {
    final partes = nombreCompleto
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (partes.length >= 2) {
      return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
    }
    if (partes.length == 1 && partes[0].isNotEmpty) {
      return partes[0][0].toUpperCase();
    }
    return 'P';
  }
}
