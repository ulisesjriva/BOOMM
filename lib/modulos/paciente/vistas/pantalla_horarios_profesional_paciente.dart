import 'dart:async';

import 'package:flutter/material.dart';

import 'package:boom/modelos/profesional.dart';
import 'package:boom/modulos/paciente/controladores/controlador_citas_paciente.dart';
import 'package:boom/modulos/paciente/modelos/cita_paciente.dart';
import 'package:boom/modulos/paciente/servicios/servicio_citas_paciente.dart';
import 'package:boom/modulos/profesional/modelos/horario_disponibilidad.dart';
import 'package:boom/nucleo/componentes/fondo_decorativo_bloom.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

import 'pantalla_mis_citas_paciente.dart';

class PantallaHorariosProfesionalPaciente extends StatefulWidget {
  const PantallaHorariosProfesionalPaciente({
    super.key,
    required this.profesional,
    this.servicioCitas,
  });

  final Profesional profesional;
  final ServicioCitasPaciente? servicioCitas;

  @override
  State<PantallaHorariosProfesionalPaciente> createState() =>
      _PantallaHorariosProfesionalPacienteState();
}

class _PantallaHorariosProfesionalPacienteState
    extends State<PantallaHorariosProfesionalPaciente> {
  late final ControladorCitasPaciente _controlador;

  String get _idProfesionalEfectivo => widget.profesional.idProfesionalEfectivo;

  @override
  void initState() {
    super.initState();
    _controlador = ControladorCitasPaciente(servicio: widget.servicioCitas)
      ..addListener(_actualizarVista);
    unawaited(_controlador.cargarHorariosDisponibles(_idProfesionalEfectivo));
  }

  void _actualizarVista() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controlador.removeListener(_actualizarVista);
    _controlador.dispose();
    super.dispose();
  }

  Future<void> _enviarSolicitud() async {
    await _controlador.enviarSolicitudCita(
      idProfesional: _idProfesionalEfectivo,
    );
  }

  void _abrirMisCitas() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            PantallaMisCitasPaciente(servicioCitas: widget.servicioCitas),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prof = widget.profesional;
    final horarioSeleccionado = _controlador.horarioSeleccionado;
    final citaSolicitada = _controlador.ultimaCitaSolicitada;

    return Scaffold(
      backgroundColor: TemaPsicobloom.colorFondo,
      appBar: AppBar(
        title: const Text('Consultar horarios'),
        actions: [
          IconButton(
            tooltip: 'Actualizar horarios',
            onPressed:
                (_controlador.estaCargandoHorarios ||
                    _controlador.estaEnviandoSolicitud)
                ? null
                : () => unawaited(
                    _controlador.cargarHorariosDisponibles(
                      _idProfesionalEfectivo,
                    ),
                  ),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FondoDecorativoBloom(
        mostrarHojas: false,
        mostrarCorazones: false,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _construirTarjetaProfesional(prof),
              const SizedBox(height: 16),
              if (citaSolicitada != null) ...[
                _construirConfirmacionSolicitud(citaSolicitada),
                const SizedBox(height: 16),
              ],
              if (_controlador.mensajeErrorSolicitud != null) ...[
                _construirBannerErrorSolicitud(
                  _controlador.mensajeErrorSolicitud!,
                ),
                const SizedBox(height: 16),
              ],
              if (horarioSeleccionado != null) ...[
                _construirResumenSolicitud(prof, horarioSeleccionado),
                const SizedBox(height: 16),
              ],
              _construirSeccionListaHorarios(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _construirTarjetaProfesional(Profesional prof) {
    final nombre = prof.nombre.trim().isNotEmpty
        ? prof.nombre.trim()
        : 'Profesional de PsicoBloom';
    final especialidad = prof.especialidad.trim().isNotEmpty
        ? prof.especialidad.trim()
        : 'Psicología General';
    final modalidad = prof.modalidad.trim().isNotEmpty
        ? prof.modalidad.trim()
        : 'Presencial';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            nombre,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$especialidad • Modalidad: $modalidad',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: TemaPsicobloom.colorPrincipal,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Selecciona un intervalo completo disponible en hora de Ecuador continental (America/Guayaquil, UTC-05:00) para revisar el resumen y enviar tu solicitud de cita.',
            style: TextStyle(
              fontSize: 12.5,
              color: TemaPsicobloom.colorTextoSecundario,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirBannerErrorSolicitud(String mensaje) {
    return Container(
      key: const Key('bannerErrorSolicitudCita'),
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

  Widget _construirConfirmacionSolicitud(CitaPaciente cita) {
    return Container(
      key: const Key('confirmacionSolicitudEnviada'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: TemaPsicobloom.colorSecundario.withValues(alpha: 0.5),
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: TemaPsicobloom.colorMenta,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_read_outlined,
                  color: TemaPsicobloom.colorSecundario,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Solicitud de cita enviada',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  cita.etiquetaEstado,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF9A5B13),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _controlador.mensajeExitoSolicitud ?? 'Tu solicitud fue registrada en estado pendiente de confirmación por el profesional.',
            style: const TextStyle(
              fontSize: 13,
              color: TemaPsicobloom.colorTextoSecundario,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Profesional: ${cita.nombreProfesional}\nFecha: ${cita.fechaLegible}\nHorario: ${cita.rangoHorarioTexto} (${cita.duracionMinutos} minutos)',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: TemaPsicobloom.colorTexto,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const Key('botonIrAMisCitasDesdeConfirmacion'),
              onPressed: _abrirMisCitas,
              icon: const Icon(Icons.calendar_month_outlined, size: 19),
              label: const Text('Mis citas'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirResumenSolicitud(
    Profesional prof,
    HorarioDisponibilidad horario,
  ) {
    final nombreProfesional = prof.nombre.trim().isNotEmpty
        ? prof.nombre.trim()
        : 'Profesional de PsicoBloom';

    return Container(
      key: const Key('resumenSolicitudCita'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: TemaPsicobloom.colorPrincipal.withValues(alpha: 0.55),
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.fact_check_outlined,
                color: TemaPsicobloom.colorPrincipal,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Resumen de solicitud de cita',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: TemaPsicobloom.colorTexto,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _construirFilaResumen('Profesional', nombreProfesional),
          const SizedBox(height: 6),
          _construirFilaResumen('Fecha', horario.fechaLegible),
          const SizedBox(height: 6),
          _construirFilaResumen(
            'Hora de inicio',
            horario.horaInicioNormalizada,
          ),
          const SizedBox(height: 6),
          _construirFilaResumen('Hora de fin', horario.horaFinNormalizada),
          const SizedBox(height: 6),
          _construirFilaResumen('Duración', '${horario.duracionMinutos} min'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: TemaPsicobloom.colorFondo,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: TemaPsicobloom.colorBorde),
            ),
            child: const Text(
              'Al enviar la solicitud, la cita quedará en estado pendiente y el horario se reservará para revisión del profesional.',
              style: TextStyle(
                fontSize: 12.5,
                color: TemaPsicobloom.colorTextoSecundario,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const Key('botonEnviarSolicitudCita'),
              onPressed: _controlador.estaEnviandoSolicitud
                  ? null
                  : () => unawaited(_enviarSolicitud()),
              icon: _controlador.estaEnviandoSolicitud
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(
                _controlador.estaEnviandoSolicitud
                    ? 'Enviando solicitud...'
                    : 'Enviar solicitud',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirFilaResumen(String etiqueta, String valor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 118,
          child: Text(
            '$etiqueta:',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: TemaPsicobloom.colorTextoSecundario,
            ),
          ),
        ),
        Expanded(
          child: Text(
            valor,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
        ),
      ],
    );
  }

  Widget _construirSeccionListaHorarios() {
    if (_controlador.estaCargandoHorarios) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 38),
        child: Center(
          child: CircularProgressIndicator(
            color: TemaPsicobloom.colorPrincipal,
          ),
        ),
      );
    }

    if (_controlador.mensajeErrorHorarios != null) {
      return Container(
        key: const Key('estadoErrorHorariosPaciente'),
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
              _controlador.mensajeErrorHorarios!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: TemaPsicobloom.colorError,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('botonReintentarHorariosPaciente'),
              onPressed: () => unawaited(
                _controlador.cargarHorariosDisponibles(_idProfesionalEfectivo),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    final horarios = _controlador.horariosDisponibles;
    if (horarios.isEmpty) {
      return Container(
        key: const Key('estadoSinHorariosDisponiblesPaciente'),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: TemaPsicobloom.colorSuperficie,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: TemaPsicobloom.colorBorde),
        ),
        child: const Column(
          children: [
            Icon(
              Icons.event_busy_outlined,
              size: 36,
              color: TemaPsicobloom.colorPrincipal,
            ),
            SizedBox(height: 10),
            Text(
              'No hay horarios disponibles en este momento',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: TemaPsicobloom.colorTexto,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'El profesional aún no tiene intervalos futuros disponibles para reservar. Puedes consultar nuevamente más tarde o revisar otros profesionales del directorio.',
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Horarios disponibles',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: TemaPsicobloom.colorTexto,
          ),
        ),
        const SizedBox(height: 10),
        ...horarios.map((horario) {
          final seleccionado =
              _controlador.horarioSeleccionado?.idDisponibilidad ==
              horario.idDisponibilidad;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _construirTarjetaHorarioDisponible(horario, seleccionado),
          );
        }),
      ],
    );
  }

  Widget _construirTarjetaHorarioDisponible(
    HorarioDisponibilidad horario,
    bool seleccionado,
  ) {
    return Material(
      color: seleccionado
          ? TemaPsicobloom.colorLavanda.withValues(alpha: 0.45)
          : TemaPsicobloom.colorSuperficie,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: Key('opcionHorarioDisponible_${horario.idDisponibilidad}'),
        onTap: _controlador.estaEnviandoSolicitud
            ? null
            : () => _controlador.seleccionarHorario(horario),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: seleccionado
                  ? TemaPsicobloom.colorPrincipal
                  : TemaPsicobloom.colorBorde,
              width: seleccionado ? 1.6 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(
                seleccionado
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: seleccionado
                    ? TemaPsicobloom.colorPrincipal
                    : TemaPsicobloom.colorTextoSecundario,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      horario.fechaLegible,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: TemaPsicobloom.colorTexto,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${horario.rangoHorarioTexto} • ${horario.duracionMinutos} minutos',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: TemaPsicobloom.colorPrincipalOscuro,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: TemaPsicobloom.colorMenta,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  seleccionado ? 'Seleccionado' : 'Disponible',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorSecundario,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
