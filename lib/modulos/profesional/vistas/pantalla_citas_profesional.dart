import 'dart:async';

import 'package:flutter/material.dart';

import 'package:boom/nucleo/componentes/fondo_decorativo_bloom.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

import '../controladores/controlador_citas_profesional.dart';
import '../modelos/cita_profesional.dart';
import '../servicios/servicio_citas_profesional.dart';

class PantallaCitasProfesional extends StatefulWidget {
  const PantallaCitasProfesional({
    super.key,
    this.controlador,
    this.servicio,
    this.esVistaIntegrada = false,
  });

  final ControladorCitasProfesional? controlador;
  final ServicioCitasProfesional? servicio;
  final bool esVistaIntegrada;

  @override
  State<PantallaCitasProfesional> createState() =>
      _PantallaCitasProfesionalState();
}

class _PantallaCitasProfesionalState extends State<PantallaCitasProfesional> {
  late final ControladorCitasProfesional _controlador;
  late final bool _esControladorPropio;

  @override
  void initState() {
    super.initState();
    if (widget.controlador != null) {
      _controlador = widget.controlador!;
      _esControladorPropio = false;
    } else {
      _controlador = ControladorCitasProfesional(servicio: widget.servicio);
      _esControladorPropio = true;
    }
    _controlador.addListener(_actualizarVista);
    if (_esControladorPropio ||
        (_controlador.citas.isEmpty && !_controlador.estaCargando)) {
      unawaited(_controlador.cargarCitasPropias());
    }
  }

  void _actualizarVista() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controlador.removeListener(_actualizarVista);
    if (_esControladorPropio) {
      _controlador.dispose();
    }
    super.dispose();
  }

  Future<void> _confirmarDecision(
    CitaProfesional cita, {
    required bool esAceptacion,
  }) async {
    if (_controlador.estaProcesandoRespuesta) {
      return;
    }

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contextoDialogo) {
        return AlertDialog(
          backgroundColor: TemaPsicobloom.colorSuperficie,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            esAceptacion
                ? 'Confirmar aceptación de cita'
                : 'Confirmar rechazo de solicitud',
          ),
          content: Text(
            esAceptacion
                ? '¿Deseas aceptar la solicitud de ${cita.nombrePaciente} para el ${cita.fechaLegible} de ${cita.horaInicioNormalizada} a ${cita.horaFinNormalizada}?\n\nLa cita pasará a estado confirmada y el horario se mantendrá reservado.'
                : '¿Deseas rechazar la solicitud de ${cita.nombrePaciente} para el ${cita.fechaLegible} de ${cita.horaInicioNormalizada} a ${cita.horaFinNormalizada}?\n\nLa solicitud se conservará como rechazada en el historial y el horario volverá a estar disponible.',
            style: const TextStyle(height: 1.35),
          ),
          actions: [
            TextButton(
              key: const Key('botonCancelarDialogoDecisionCita'),
              onPressed: () => Navigator.of(contextoDialogo).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              key: Key(
                esAceptacion
                    ? 'botonConfirmarAceptacionCita'
                    : 'botonConfirmarRechazoCita',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: esAceptacion
                    ? TemaPsicobloom.colorSecundario
                    : TemaPsicobloom.colorError,
                minimumSize: const Size(140, 42),
              ),
              onPressed: () => Navigator.of(contextoDialogo).pop(true),
              child: Text(
                esAceptacion ? 'Confirmar aceptación' : 'Confirmar rechazo',
              ),
            ),
          ],
        );
      },
    );

    if (confirmado != true || !mounted) {
      return;
    }

    if (esAceptacion) {
      await _controlador.aceptarSolicitud(cita.idCita);
    } else {
      await _controlador.rechazarSolicitud(cita.idCita);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cuerpo = RefreshIndicator(
      color: TemaPsicobloom.colorPrincipal,
      onRefresh: () => _controlador.cargarCitasPropias(),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          _construirCabeceraCompacta(),
          const SizedBox(height: 12),
          _construirBarraFiltros(context),
          const SizedBox(height: 14),
          if (_controlador.mensajeExito != null) ...[
            _construirBannerExito(_controlador.mensajeExito!),
            const SizedBox(height: 12),
          ],
          if (_controlador.mensajeErrorOperacion != null) ...[
            _construirBannerErrorOperacion(_controlador.mensajeErrorOperacion!),
            const SizedBox(height: 12),
          ],
          _construirContenidoLista(),
          const SizedBox(height: 24),
        ],
      ),
    );

    if (widget.esVistaIntegrada) {
      return cuerpo;
    }

    return Scaffold(
      backgroundColor: TemaPsicobloom.colorFondo,
      appBar: AppBar(
        title: const Text('Solicitudes'),
        actions: [
          IconButton(
            tooltip: 'Actualizar solicitudes',
            onPressed:
                (_controlador.estaCargando ||
                    _controlador.estaProcesandoRespuesta)
                ? null
                : () => unawaited(_controlador.cargarCitasPropias()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FondoDecorativoBloom(
        mostrarHojas: false,
        mostrarCorazones: false,
        child: SafeArea(child: cuerpo),
      ),
    );
  }

  Widget _construirCabeceraCompacta() {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Solicitudes de citas',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: TemaPsicobloom.colorTexto,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Horario de Ecuador (America/Guayaquil)',
                style: TextStyle(
                  fontSize: 12.5,
                  color: TemaPsicobloom.colorTextoSecundario,
                ),
              ),
            ],
          ),
        ),
        if (widget.esVistaIntegrada)
          IconButton(
            key: const Key('botonActualizarSolicitudesProfesional'),
            tooltip: 'Actualizar solicitudes',
            onPressed:
                (_controlador.estaCargando ||
                    _controlador.estaProcesandoRespuesta)
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

  Widget _construirBarraFiltros(BuildContext context) {
    final escalaTexto = MediaQuery.textScalerOf(context).scale(1.0);

    return LayoutBuilder(
      builder: (context, restricciones) {
        final usarFilaUnica =
            restricciones.maxWidth >= 340 && escalaTexto <= 1.25;

        if (usarFilaUnica) {
          return Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: TemaPsicobloom.colorSuperficie,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: TemaPsicobloom.colorBorde),
            ),
            child: Row(
              children: FiltroEstadoCitaProfesional.values.map((filtro) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _construirBotonFiltroSegmentado(filtro),
                  ),
                );
              }).toList(),
            ),
          );
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: FiltroEstadoCitaProfesional.values
              .map(_construirChipFiltroAdaptable)
              .toList(),
        );
      },
    );
  }

  int _cantidadParaFiltro(FiltroEstadoCitaProfesional filtro) {
    switch (filtro) {
      case FiltroEstadoCitaProfesional.pendientes:
        return _controlador.totalPendientes;
      case FiltroEstadoCitaProfesional.confirmadas:
        return _controlador.totalConfirmadas;
      case FiltroEstadoCitaProfesional.rechazadas:
        return _controlador.totalRechazadas;
    }
  }

  Widget _construirBotonFiltroSegmentado(FiltroEstadoCitaProfesional filtro) {
    final seleccionado = _controlador.filtroSeleccionado == filtro;
    final cantidad = _cantidadParaFiltro(filtro);

    return InkWell(
      key: Key('filtroCitasProfesional_${filtro.valorEstado}'),
      borderRadius: BorderRadius.circular(10),
      onTap: _controlador.estaProcesandoRespuesta
          ? null
          : () => _controlador.cambiarFiltro(filtro),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        decoration: BoxDecoration(
          color: seleccionado
              ? TemaPsicobloom.colorLavanda
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: seleccionado
                ? TemaPsicobloom.colorPrincipal.withValues(alpha: 0.45)
                : Colors.transparent,
          ),
        ),
        child: Text(
          '${filtro.etiqueta} ($cantidad)',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            color: seleccionado
                ? TemaPsicobloom.colorPrincipalOscuro
                : TemaPsicobloom.colorTextoSecundario,
          ),
        ),
      ),
    );
  }

  Widget _construirChipFiltroAdaptable(FiltroEstadoCitaProfesional filtro) {
    final seleccionado = _controlador.filtroSeleccionado == filtro;
    final cantidad = _cantidadParaFiltro(filtro);

    return ChoiceChip(
      key: Key('filtroCitasProfesional_${filtro.valorEstado}'),
      label: Text('${filtro.etiqueta} ($cantidad)'),
      selected: seleccionado,
      onSelected: _controlador.estaProcesandoRespuesta
          ? null
          : (_) => _controlador.cambiarFiltro(filtro),
      selectedColor: TemaPsicobloom.colorLavanda,
      backgroundColor: TemaPsicobloom.colorSuperficie,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: seleccionado
            ? TemaPsicobloom.colorPrincipalOscuro
            : TemaPsicobloom.colorTextoSecundario,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: seleccionado
              ? TemaPsicobloom.colorPrincipal
              : TemaPsicobloom.colorBorde,
        ),
      ),
    );
  }

  Widget _construirBannerExito(String mensaje) {
    return Container(
      key: const Key('bannerExitoCitasProfesional'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorFondoExito,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: TemaPsicobloom.colorExito.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            color: TemaPsicobloom.colorExito,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: const TextStyle(
                color: TemaPsicobloom.colorExito,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirBannerErrorOperacion(String mensaje) {
    return Container(
      key: const Key('bannerErrorOperacionCitasProfesional'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorFondoError,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: TemaPsicobloom.colorError.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: TemaPsicobloom.colorError,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: const TextStyle(
                color: TemaPsicobloom.colorError,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirContenidoLista() {
    if (_controlador.estaCargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 42),
        child: Center(
          child: CircularProgressIndicator(
            color: TemaPsicobloom.colorPrincipal,
          ),
        ),
      );
    }

    if (_controlador.mensajeErrorCarga != null) {
      return Container(
        key: const Key('estadoErrorCitasProfesional'),
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
              _controlador.mensajeErrorCarga!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: TemaPsicobloom.colorError,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('botonReintentarCitasProfesional'),
              onPressed: () => unawaited(_controlador.cargarCitasPropias()),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    final citasFiltradas = _controlador.citasFiltradas;
    if (citasFiltradas.isEmpty) {
      final etiquetaFiltro = _controlador.filtroSeleccionado.etiqueta
          .toLowerCase();
      return Container(
        key: const Key('estadoSinCitasProfesional'),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: TemaPsicobloom.colorSuperficie,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: TemaPsicobloom.colorBorde),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.inbox_outlined,
              size: 34,
              color: TemaPsicobloom.colorPrincipal,
            ),
            const SizedBox(height: 10),
            Text(
              'No tienes solicitudes $etiquetaFiltro en este momento',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: TemaPsicobloom.colorTexto,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Cambia de filtro o actualiza para consultar nuevas solicitudes.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: TemaPsicobloom.colorTextoSecundario,
                height: 1.3,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: citasFiltradas
          .map(
            (cita) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _construirTarjetaCitaProfesional(cita),
            ),
          )
          .toList(),
    );
  }

  Widget _construirTarjetaCitaProfesional(CitaProfesional cita) {
    final ahoraUtc = _controlador.obtenerAhoraUtc();
    final puedeResponder = cita.puedeResponder(referenciaUtc: ahoraUtc);
    final estaEnProceso =
        _controlador.estaProcesandoRespuesta &&
        _controlador.idCitaEnProceso == cita.idCita;

    final Color colorFondoEstado;
    final Color colorTextoEstado;
    final IconData iconoEstado;
    if (cita.esPendiente) {
      colorFondoEstado = TemaPsicobloom.colorFondoAdvertencia;
      colorTextoEstado = TemaPsicobloom.colorAdvertencia;
      iconoEstado = Icons.hourglass_top_rounded;
    } else if (cita.esConfirmada) {
      colorFondoEstado = TemaPsicobloom.colorMenta;
      colorTextoEstado = TemaPsicobloom.colorSecundario;
      iconoEstado = Icons.check_circle_outline_rounded;
    } else {
      colorFondoEstado = TemaPsicobloom.colorFondoError;
      colorTextoEstado = TemaPsicobloom.colorError;
      iconoEstado = Icons.cancel_outlined;
    }

    return Container(
      key: Key('tarjetaCitaProfesional_${cita.idCita}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TemaPsicobloom.colorBorde),
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _construirAvatarInicialesPaciente(cita.nombrePaciente),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cita.nombrePaciente,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                        color: TemaPsicobloom.colorTexto,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.medical_information_outlined,
                          size: 14,
                          color: TemaPsicobloom.colorTextoSecundario,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            cita.modalidadProfesional,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: TemaPsicobloom.colorTextoSecundario,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                key: Key('chipEstadoCitaProfesional_${cita.idCita}'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: colorFondoEstado,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(iconoEstado, size: 14, color: colorTextoEstado),
                    const SizedBox(width: 4),
                    Text(
                      cita.etiquetaEstado,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorTextoEstado,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: TemaPsicobloom.colorFondo,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: TemaPsicobloom.colorBorde.withValues(alpha: 0.7),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.event_outlined,
                      size: 16,
                      color: TemaPsicobloom.colorPrincipal,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cita.fechaLegible,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: TemaPsicobloom.colorTexto,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.schedule_outlined,
                      size: 16,
                      color: TemaPsicobloom.colorPrincipal,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${cita.horaInicioNormalizada} - ${cita.horaFinNormalizada} (${cita.duracionMinutos} min)',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: TemaPsicobloom.colorPrincipalOscuro,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (cita.esPendiente && !puedeResponder) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: TemaPsicobloom.colorFondoAdvertencia,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.history_toggle_off_rounded,
                    size: 16,
                    color: TemaPsicobloom.colorAdvertencia,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'El horario de esta solicitud ya comenzó o pertenece al pasado (hora de Ecuador), por lo que no admite respuesta.',
                      style: TextStyle(
                        fontSize: 12,
                        color: TemaPsicobloom.colorAdvertencia,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (puedeResponder) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('botonRechazarCita_${cita.idCita}'),
                    onPressed: _controlador.estaProcesandoRespuesta
                        ? null
                        : () => unawaited(
                            _confirmarDecision(cita, esAceptacion: false),
                          ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: TemaPsicobloom.colorError,
                      side: const BorderSide(color: TemaPsicobloom.colorError),
                      minimumSize: const Size(0, 42),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Rechazar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    key: Key('botonAceptarCita_${cita.idCita}'),
                    onPressed: _controlador.estaProcesandoRespuesta
                        ? null
                        : () => unawaited(
                            _confirmarDecision(cita, esAceptacion: true),
                          ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TemaPsicobloom.colorSecundario,
                      minimumSize: const Size(0, 42),
                    ),
                    icon: estaEnProceso
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Aceptar'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _construirAvatarInicialesPaciente(String nombreCompleto) {
    final iniciales = _obtenerIniciales(nombreCompleto);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorLavanda,
        shape: BoxShape.circle,
        border: Border.all(
          color: TemaPsicobloom.colorPrincipal.withValues(alpha: 0.3),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        iniciales,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: TemaPsicobloom.colorPrincipalOscuro,
        ),
      ),
    );
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
