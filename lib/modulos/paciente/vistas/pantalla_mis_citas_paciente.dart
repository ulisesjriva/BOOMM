import 'dart:async';

import 'package:flutter/material.dart';

import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_sesion.dart';
import 'package:boom/modulos/paciente/componentes/barra_navegacion_paciente.dart';
import 'package:boom/modulos/paciente/controladores/controlador_citas_paciente.dart';
import 'package:boom/modulos/paciente/modelos/cita_paciente.dart';
import 'package:boom/modulos/paciente/servicios/servicio_citas_paciente.dart';
import 'package:boom/nucleo/componentes/fondo_decorativo_bloom.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/repositorios/repositorio_profesionales.dart';

import 'pantalla_buscar_profesionales.dart';
import 'pantalla_inicio_paciente.dart';
import 'pantalla_mapa_profesionales.dart';
import 'pantalla_perfil_paciente.dart';

class PantallaMisCitasPaciente extends StatefulWidget {
  const PantallaMisCitasPaciente({
    super.key,
    this.servicioCitas,
    this.perfilInicial,
    this.servicioSesion = const ServicioSesion(),
    this.repositorio,
    this.seccionInicial,
  });

  final ServicioCitasPaciente? servicioCitas;
  final PerfilUsuario? perfilInicial;
  final ServicioSesion servicioSesion;
  final RepositorioProfesionales? repositorio;
  final SeccionMisCitas? seccionInicial;

  @override
  State<PantallaMisCitasPaciente> createState() =>
      _PantallaMisCitasPacienteState();
}

class _PantallaMisCitasPacienteState extends State<PantallaMisCitasPaciente>
    with WidgetsBindingObserver {
  late final ControladorCitasPaciente _controlador;
  Timer? _temporizadorCambioEstado;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controlador = ControladorCitasPaciente(
      servicio: widget.servicioCitas,
      seccionInicial: widget.seccionInicial,
    )..addListener(_alCambiarControlador);
    unawaited(_controlador.cargarCitasPropias());
  }

  void _alCambiarControlador() {
    _programarProximoCambioTemporal();
    if (mounted) {
      setState(() {});
    }
  }

  /// Programa un unico temporizador exacto hasta el siguiente cambio real de
  /// estado (inicio/fin de cita o vencimiento de solicitud) sin polling continuo.
  void _programarProximoCambioTemporal() {
    _temporizadorCambioEstado?.cancel();
    _temporizadorCambioEstado = null;

    if (!mounted || _controlador.estaCargandoCitasPropias) {
      return;
    }

    final espera = _controlador.calcularTiempoHastaProximoCambioEstado();
    if (espera == null) {
      return;
    }

    _temporizadorCambioEstado = Timer(espera, () {
      if (!mounted) {
        return;
      }
      final huboCambio = _controlador.recalcularClasificacionTemporal();
      if (!huboCambio) {
        _programarProximoCambioTemporal();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final huboCambio = _controlador.recalcularClasificacionTemporal();
      if (!huboCambio) {
        _programarProximoCambioTemporal();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _temporizadorCambioEstado?.cancel();
    _controlador.removeListener(_alCambiarControlador);
    _controlador.dispose();
    super.dispose();
  }

  void _gestionarCambioPestana(int nuevoIndice) {
    if (nuevoIndice == 3) return;

    switch (nuevoIndice) {
      case 0:
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => PantallaInicioPaciente(
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
            builder: (_) =>
                PantallaBuscarProfesionales(repositorio: widget.repositorio),
          ),
        );
        break;
      case 2:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => PantallaMapaProfesionales(
              repositorio: widget.repositorio,
              perfilInicial: widget.perfilInicial,
              servicioSesion: widget.servicioSesion,
            ),
          ),
        );
        break;
      case 4:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => PantallaPerfilPaciente(
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
    final puedeVolver = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: TemaPsicobloom.colorFondo,
      bottomNavigationBar: BarraNavegacionPaciente(
        indiceSeleccionado: 3,
        alCambiarPestana: _gestionarCambioPestana,
      ),
      body: FondoDecorativoBloom(
        mostrarHojas: false,
        mostrarCorazones: false,
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                children: [
                  _construirEncabezado(puedeVolver: puedeVolver),
                  const SizedBox(height: 16),
                  _construirSelectorSecciones(),
                  const SizedBox(height: 16),
                  _construirContenidoPrincipal(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _construirEncabezado({required bool puedeVolver}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (puedeVolver) ...[
          Padding(
            padding: const EdgeInsets.only(right: 6, top: 2),
            child: IconButton(
              tooltip: 'Volver',
              visualDensity: VisualDensity.compact,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: TemaPsicobloom.colorTexto,
              ),
            ),
          ),
        ],
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mis citas',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: TemaPsicobloom.colorTexto,
                  letterSpacing: -0.3,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Consulta y organiza tus solicitudes.',
                style: TextStyle(
                  fontSize: 13.5,
                  color: TemaPsicobloom.colorTextoSecundario,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          key: const Key('botonActualizarMisCitas'),
          tooltip: 'Actualizar solicitudes',
          onPressed: _controlador.estaCargandoCitasPropias
              ? null
              : () => unawaited(_controlador.cargarCitasPropias()),
          icon: const Icon(
            Icons.refresh_rounded,
            color: TemaPsicobloom.colorPrincipal,
          ),
        ),
      ],
    );
  }

  Widget _construirSelectorSecciones() {
    final totalProximas = _controlador.citasProximas.length;
    final totalPendientes = _controlador.citasPendientes.length;
    final totalHistorial = _controlador.citasHistorial.length;

    return Container(
      key: const Key('selectorSeccionesMisCitas'),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorLavanda.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Row(
        children: [
          _construirOpcionSeccion(
            key: const Key('pestanaCitasProximas'),
            seccion: SeccionMisCitas.proximas,
            etiqueta: 'Próximas',
            cantidad: totalProximas,
          ),
          _construirOpcionSeccion(
            key: const Key('pestanaCitasPendientes'),
            seccion: SeccionMisCitas.pendientes,
            etiqueta: 'Pendientes',
            cantidad: totalPendientes,
          ),
          _construirOpcionSeccion(
            key: const Key('pestanaCitasHistorial'),
            seccion: SeccionMisCitas.historial,
            etiqueta: 'Historial',
            cantidad: totalHistorial,
          ),
        ],
      ),
    );
  }

  Widget _construirOpcionSeccion({
    required Key key,
    required SeccionMisCitas seccion,
    required String etiqueta,
    required int cantidad,
  }) {
    final seleccionada = _controlador.seccionSeleccionada == seccion;

    return Expanded(
      child: Semantics(
        button: true,
        selected: seleccionada,
        label: '$etiqueta ($cantidad)',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(12),
            onTap: () => _controlador.seleccionarSeccion(seccion),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              decoration: BoxDecoration(
                color: seleccionada
                    ? TemaPsicobloom.colorPrincipal
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                boxShadow: seleccionada
                    ? [
                        BoxShadow(
                          color: TemaPsicobloom.colorPrincipal.withValues(
                            alpha: 0.2,
                          ),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      etiqueta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: seleccionada
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: seleccionada
                            ? TemaPsicobloom.colorSobrePrincipal
                            : TemaPsicobloom.colorTextoSecundario,
                      ),
                    ),
                  ),
                  if (cantidad > 0) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: seleccionada
                            ? Colors.white.withValues(alpha: 0.22)
                            : TemaPsicobloom.colorSuperficie,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$cantidad',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: seleccionada
                              ? TemaPsicobloom.colorSobrePrincipal
                              : TemaPsicobloom.colorPrincipalOscuro,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _construirContenidoPrincipal() {
    if (_controlador.estaCargandoCitasPropias) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 42),
        child: Center(
          child: CircularProgressIndicator(
            color: TemaPsicobloom.colorPrincipal,
          ),
        ),
      );
    }

    if (_controlador.mensajeErrorCitasPropias != null) {
      return Container(
        key: const Key('estadoErrorMisCitasPaciente'),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: TemaPsicobloom.colorFondoError,
          borderRadius: BorderRadius.circular(18),
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
            const SizedBox(height: 10),
            Text(
              _controlador.mensajeErrorCitasPropias!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: TemaPsicobloom.colorError,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('botonReintentarMisCitasPaciente'),
              onPressed: () => unawaited(_controlador.cargarCitasPropias()),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    final citasVisibles = _controlador.citasVisiblesSeccionActual;
    if (citasVisibles.isEmpty) {
      return _construirEstadoVacio(_controlador.seccionSeleccionada);
    }

    final referenciaUtc = _controlador.obtenerAhoraUtc();

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...citasVisibles.map(
            (cita) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _construirTarjetaCita(cita, referenciaUtc: referenciaUtc),
            ),
          ),
          if (_controlador.tieneMasCitasEnSeccionActual) ...[
            const SizedBox(height: 4),
            Center(
              child: OutlinedButton.icon(
                key: const Key('botonVerMasCitas'),
                onPressed: _controlador.mostrarMasCitas,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  side: const BorderSide(
                    color: TemaPsicobloom.colorBorde,
                    width: 1.2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.expand_more_rounded, size: 18),
                label: Text(
                  _controlador.textoBotonVerMas,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _construirEstadoVacio(SeccionMisCitas seccion) {
    final IconData icono;
    final String mensaje;
    final Key claveEstado;

    switch (seccion) {
      case SeccionMisCitas.proximas:
        icono = Icons.event_available_outlined;
        mensaje = 'No tienes citas próximas';
        claveEstado = const Key('estadoVacioCitas_proximas');
        break;
      case SeccionMisCitas.pendientes:
        icono = Icons.hourglass_empty_rounded;
        mensaje = 'No tienes solicitudes pendientes';
        claveEstado = const Key('estadoVacioCitas_pendientes');
        break;
      case SeccionMisCitas.historial:
        icono = Icons.history_rounded;
        mensaje = 'Todavía no tienes historial de citas';
        claveEstado = const Key('estadoVacioCitas_historial');
        break;
    }

    return Container(
      key: claveEstado,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: const BoxDecoration(
              color: TemaPsicobloom.colorLavanda,
              shape: BoxShape.circle,
            ),
            child: Icon(icono, size: 26, color: TemaPsicobloom.colorPrincipal),
          ),
          const SizedBox(height: 12),
          Text(
            mensaje,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirTarjetaCita(
    CitaPaciente cita, {
    required DateTime referenciaUtc,
  }) {
    final esVencida = cita.esSolicitudPendienteVencida(
      referenciaUtc: referenciaUtc,
    );
    final estaEnCurso = cita.estaEnCursoEnEcuador(referenciaUtc: referenciaUtc);
    final etiquetaEstado = cita.etiquetaEstadoEnEcuador(
      referenciaUtc: referenciaUtc,
    );

    final Color colorFondoEstado;
    final Color colorTextoEstado;
    if (esVencida) {
      colorFondoEstado = const Color(0xFFF1EEF7);
      colorTextoEstado = TemaPsicobloom.colorTextoSecundario;
    } else if (cita.esPendiente) {
      colorFondoEstado = TemaPsicobloom.colorFondoAdvertencia;
      colorTextoEstado = TemaPsicobloom.colorAdvertencia;
    } else if (cita.esConfirmada) {
      colorFondoEstado = TemaPsicobloom.colorFondoExito;
      colorTextoEstado = TemaPsicobloom.colorExito;
    } else {
      colorFondoEstado = TemaPsicobloom.colorFondoError;
      colorTextoEstado = TemaPsicobloom.colorError;
    }

    final IconData iconoModalidad;
    if (cita.esModalidadVirtual) {
      iconoModalidad = Icons.videocam_outlined;
    } else if (cita.esModalidadHibrida) {
      iconoModalidad = Icons.devices_other_outlined;
    } else {
      iconoModalidad = Icons.person_pin_circle_outlined;
    }

    return Container(
      key: Key('tarjetaCitaPaciente_${cita.idCita}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: estaEnCurso
              ? TemaPsicobloom.colorSecundario.withValues(alpha: 0.45)
              : TemaPsicobloom.colorBorde,
          width: estaEnCurso ? 1.3 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: TemaPsicobloom.colorPrincipal.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cita.nombreProfesional,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                        color: TemaPsicobloom.colorTexto,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cita.especialidadProfesional,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: TemaPsicobloom.colorPrincipal,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    key: Key('chipEstadoCita_${cita.idCita}'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: colorFondoEstado,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      etiquetaEstado,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: colorTextoEstado,
                      ),
                    ),
                  ),
                  if (estaEnCurso) ...[
                    const SizedBox(height: 5),
                    Container(
                      key: Key('insigniaCitaEnCurso_${cita.idCita}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: TemaPsicobloom.colorMenta,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.circle,
                            size: 7,
                            color: TemaPsicobloom.colorSecundario,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'En curso',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: TemaPsicobloom.colorSecundario,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: TemaPsicobloom.colorFondo,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: TemaPsicobloom.colorBorde.withValues(alpha: 0.7),
              ),
            ),
            child: Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                _construirDatoCompacto(
                  icono: Icons.event_outlined,
                  texto: cita.fechaLegible,
                  resaltado: true,
                ),
                _construirDatoCompacto(
                  icono: Icons.schedule_rounded,
                  texto: cita.duracionMinutos > 0
                      ? '${cita.rangoHorarioTexto} · ${cita.duracionMinutos} min'
                      : cita.rangoHorarioTexto,
                  resaltado: true,
                ),
                _construirDatoCompacto(
                  icono: iconoModalidad,
                  texto: cita.modalidadProfesional,
                ),
              ],
            ),
          ),
          if (cita.debeMostrarDireccionConsultorio) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: TemaPsicobloom.colorTextoSecundario,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    cita.esModalidadHibrida
                        ? 'Consultorio (si es presencial): ${cita.direccionConsultorio}'
                        : cita.direccionConsultorio,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: TemaPsicobloom.colorTextoSecundario,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (esVencida) ...[
            const SizedBox(height: 8),
            const Text(
              'El horario venció sin confirmación.',
              style: TextStyle(
                fontSize: 12,
                color: TemaPsicobloom.colorTextoSecundario,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _construirDatoCompacto({
    required IconData icono,
    required String texto,
    bool resaltado = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icono,
          size: 16,
          color: resaltado
              ? TemaPsicobloom.colorPrincipal
              : TemaPsicobloom.colorTextoSecundario,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 13,
              fontWeight: resaltado ? FontWeight.w600 : FontWeight.w500,
              color: resaltado
                  ? TemaPsicobloom.colorTexto
                  : TemaPsicobloom.colorTextoSecundario,
            ),
          ),
        ),
      ],
    );
  }
}
