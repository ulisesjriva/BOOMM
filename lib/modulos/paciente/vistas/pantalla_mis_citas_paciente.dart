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
  });

  final ServicioCitasPaciente? servicioCitas;
  final PerfilUsuario? perfilInicial;
  final ServicioSesion servicioSesion;
  final RepositorioProfesionales? repositorio;

  @override
  State<PantallaMisCitasPaciente> createState() =>
      _PantallaMisCitasPacienteState();
}

class _PantallaMisCitasPacienteState extends State<PantallaMisCitasPaciente> {
  late final ControladorCitasPaciente _controlador;

  @override
  void initState() {
    super.initState();
    _controlador = ControladorCitasPaciente(servicio: widget.servicioCitas)
      ..addListener(_actualizarVista);
    unawaited(_controlador.cargarCitasPropias());
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
    return Scaffold(
      backgroundColor: TemaPsicobloom.colorFondo,
      appBar: AppBar(
        title: const Text('Mis citas'),
        actions: [
          IconButton(
            tooltip: 'Actualizar solicitudes',
            onPressed: _controlador.estaCargandoCitasPropias
                ? null
                : () => unawaited(_controlador.cargarCitasPropias()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      bottomNavigationBar: BarraNavegacionPaciente(
        indiceSeleccionado: 3,
        alCambiarPestana: _gestionarCambioPestana,
      ),
      body: FondoDecorativoBloom(
        mostrarHojas: false,
        mostrarCorazones: false,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _construirEncabezadoInformativo(),
              const SizedBox(height: 16),
              _construirContenidoPrincipal(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _construirEncabezadoInformativo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.calendar_month_outlined,
            color: TemaPsicobloom.colorPrincipal,
            size: 22,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Solicitudes y citas registradas',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Aquí se muestran únicamente tus propias solicitudes de cita en horario de Ecuador continental (America/Guayaquil). Las nuevas solicitudes permanecen en estado pendiente hasta su revisión.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: TemaPsicobloom.colorTextoSecundario,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
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

    final citas = _controlador.citasPropias;
    if (citas.isEmpty) {
      return Container(
        key: const Key('estadoSinCitasPaciente'),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: TemaPsicobloom.colorSuperficie,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: TemaPsicobloom.colorBorde),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.event_note_outlined,
              size: 38,
              color: TemaPsicobloom.colorPrincipal,
            ),
            const SizedBox(height: 10),
            const Text(
              'Aún no tienes solicitudes de cita registradas',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: TemaPsicobloom.colorTexto,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Explora el directorio de profesionales aprobados, entra a su perfil y pulsa "Consultar horarios" para enviar una solicitud.',
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
      children: citas
          .map(
            (cita) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _construirTarjetaCita(cita),
            ),
          )
          .toList(),
    );
  }

  Widget _construirTarjetaCita(CitaPaciente cita) {
    final Color colorFondoEstado;
    final Color colorTextoEstado;
    if (cita.esPendiente) {
      colorFondoEstado = const Color(0xFFFFF4E5);
      colorTextoEstado = const Color(0xFF9A5B13);
    } else if (cita.esConfirmada) {
      colorFondoEstado = TemaPsicobloom.colorMenta;
      colorTextoEstado = TemaPsicobloom.colorSecundario;
    } else {
      colorFondoEstado = TemaPsicobloom.colorFondoError;
      colorTextoEstado = TemaPsicobloom.colorError;
    }

    return Container(
      key: Key('tarjetaCitaPaciente_${cita.idCita}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TemaPsicobloom.colorBorde),
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
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: TemaPsicobloom.colorTexto,
                      ),
                    ),
                    const SizedBox(height: 3),
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
              Container(
                key: Key('chipEstadoCita_${cita.idCita}'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: colorFondoEstado,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  cita.etiquetaEstado,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorTextoEstado,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.event_outlined,
                    size: 17,
                    color: TemaPsicobloom.colorPrincipal,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    cita.fechaLegible,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: TemaPsicobloom.colorTexto,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 17,
                    color: TemaPsicobloom.colorPrincipal,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${cita.rangoHorarioTexto} (${cita.duracionMinutos} min)',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: TemaPsicobloom.colorTexto,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.people_outline_rounded,
                    size: 17,
                    color: TemaPsicobloom.colorTextoSecundario,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Modalidad: ${cita.modalidadProfesional}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: TemaPsicobloom.colorTextoSecundario,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (cita.direccionConsultorio.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: TemaPsicobloom.colorTextoSecundario,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    cita.direccionConsultorio,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: TemaPsicobloom.colorTextoSecundario,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (cita.descripcionEstado.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: TemaPsicobloom.colorFondo,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: TemaPsicobloom.colorBorde),
              ),
              child: Text(
                cita.descripcionEstado,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: TemaPsicobloom.colorTextoSecundario,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
