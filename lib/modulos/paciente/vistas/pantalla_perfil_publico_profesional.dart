import 'dart:async';

import 'package:flutter/material.dart';

import 'package:boom/modelos/profesional.dart';
import 'package:boom/modulos/paciente/componentes/mapa_consultorio_ruta.dart';
import 'package:boom/modulos/paciente/componentes/tarjeta_info_economica_profesional.dart';
import 'package:boom/modulos/paciente/controladores/controlador_info_economica_profesional.dart';
import 'package:boom/modulos/paciente/controladores/controlador_ruta_consultorio.dart';
import 'package:boom/modulos/paciente/servicios/servicio_citas_paciente.dart';
import 'package:boom/modulos/paciente/servicios/servicio_info_economica_profesional.dart';
import 'package:boom/modulos/paciente/servicios/servicio_rutas_consultorio.dart';
import 'package:boom/modulos/profesional/servicios/servicio_ubicacion_consultorio.dart';
import 'package:boom/nucleo/componentes/fondo_decorativo_bloom.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

import 'pantalla_horarios_profesional_paciente.dart';

/// Pantalla de perfil publico de un profesional con datos autorizados.
/// Expone nombre, fotografia, especialidades, modalidad, servicios, descripcion,
/// ubicacion en mapa y calculo de ruta, distancia y tiempo estimado cuando las
/// coordenadas del consultorio estan disponibles.
class PantallaPerfilPublicoProfesional extends StatefulWidget {
  final Profesional profesional;
  final bool mostrarMapaInteractivo;
  final ServicioUbicacionConsultorio servicioUbicacion;
  final ServicioRutasConsultorio servicioRutas;
  final ServicioCitasPaciente? servicioCitas;
  final ServicioInfoEconomicaProfesional? servicioInfoEconomica;

  const PantallaPerfilPublicoProfesional({
    super.key,
    required this.profesional,
    this.mostrarMapaInteractivo = true,
    this.servicioUbicacion = const ServicioUbicacionConsultorio(),
    this.servicioRutas = const ServicioRutasConsultorio(),
    this.servicioCitas,
    this.servicioInfoEconomica,
  });

  @override
  State<PantallaPerfilPublicoProfesional> createState() =>
      _PantallaPerfilPublicoProfesionalState();
}

class _PantallaPerfilPublicoProfesionalState
    extends State<PantallaPerfilPublicoProfesional> {
  late final ControladorRutaConsultorio _controladorRuta;
  late final ControladorInfoEconomicaProfesional _controladorInfoEconomica;

  @override
  void initState() {
    super.initState();
    _controladorRuta = ControladorRutaConsultorio(
      servicioUbicacion: widget.servicioUbicacion,
      servicioRutas: widget.servicioRutas,
    )..addListener(_actualizarVista);
    _controladorInfoEconomica = ControladorInfoEconomicaProfesional(
      servicio: widget.servicioInfoEconomica,
    )..addListener(_actualizarVista);
    unawaited(
      _controladorInfoEconomica.cargar(
        widget.profesional.idProfesionalEfectivo,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant PantallaPerfilPublicoProfesional oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profesional.idProfesionalEfectivo !=
        widget.profesional.idProfesionalEfectivo) {
      unawaited(
        _controladorInfoEconomica.cargar(
          widget.profesional.idProfesionalEfectivo,
        ),
      );
    }
  }

  void _actualizarVista() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controladorRuta.removeListener(_actualizarVista);
    _controladorRuta.dispose();
    _controladorInfoEconomica.removeListener(_actualizarVista);
    _controladorInfoEconomica.dispose();
    super.dispose();
  }

  Future<void> _calcularRutaConsultorio() async {
    final prof = widget.profesional;
    await _controladorRuta.calcularRutaHaciaConsultorio(
      destinoLatitud: prof.tieneCoordenadasValidas ? prof.latitud : null,
      destinoLongitud: prof.tieneCoordenadasValidas ? prof.longitud : null,
    );
  }

  void _abrirHorariosProfesional(Profesional prof) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PantallaHorariosProfesionalPaciente(
          profesional: prof,
          servicioCitas: widget.servicioCitas,
          servicioInfoEconomica: widget.servicioInfoEconomica,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prof = widget.profesional;
    final especialidades = prof.especialidades.isNotEmpty
        ? prof.especialidades
        : (prof.especialidad.trim().isNotEmpty
              ? [prof.especialidad.trim()]
              : const <String>[]);

    return Scaffold(
      backgroundColor: TemaPsicobloom.colorFondo,
      appBar: AppBar(title: const Text('Perfil del profesional')),
      body: FondoDecorativoBloom(
        mostrarHojas: false,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20.0),
            children: [
              _construirCabeceraPerfil(prof),
              const SizedBox(height: 16),
              TarjetaInfoEconomicaProfesional(
                controlador: _controladorInfoEconomica,
                alReintentar: () =>
                    unawaited(_controladorInfoEconomica.reintentar()),
              ),
              const SizedBox(height: 18),
              _construirSeccionEspecialidadesYModalidad(prof, especialidades),
              const SizedBox(height: 16),
              _construirSeccionAcercaDe(prof),
              const SizedBox(height: 16),
              _construirSeccionServicios(prof),
              const SizedBox(height: 16),
              _construirSeccionUbicacion(prof),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _construirCabeceraPerfil(Profesional prof) {
    final tieneFoto = prof.fotoUrl != null && prof.fotoUrl!.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: TemaPsicobloom.colorLavanda,
              shape: BoxShape.circle,
              border: Border.all(
                color: TemaPsicobloom.colorPrincipal.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: ClipOval(
              child: tieneFoto
                  ? Image.network(
                      prof.fotoUrl!.trim(),
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _construirAvatarIniciales(prof.nombre),
                    )
                  : _construirAvatarIniciales(prof.nombre),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            prof.nombre.trim().isNotEmpty
                ? prof.nombre.trim()
                : 'Profesional de PsicoBloom',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            prof.especialidad.trim().isNotEmpty
                ? prof.especialidad.trim()
                : 'Especialidad en actualización',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: TemaPsicobloom.colorPrincipal,
            ),
          ),
          if (prof.aniosExperiencia != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: TemaPsicobloom.colorMenta,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${prof.aniosExperiencia} ${prof.aniosExperiencia == 1 ? "año" : "años"} de experiencia profesional',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: TemaPsicobloom.colorSecundario,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const Key('botonConsultarHorariosProfesional'),
              onPressed: () => _abrirHorariosProfesional(prof),
              icon: const Icon(Icons.event_available_outlined, size: 19),
              label: const Text('Consultar horarios'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirAvatarIniciales(String nombre) {
    final partes = nombre
        .replaceAll('Dra. ', '')
        .replaceAll('Dr. ', '')
        .replaceAll('Lic. ', '')
        .trim()
        .split(RegExp(r'\s+'));
    String iniciales = 'PB';
    if (partes.length >= 2 && partes[0].isNotEmpty && partes[1].isNotEmpty) {
      iniciales = '${partes[0][0]}${partes[1][0]}'.toUpperCase();
    } else if (partes.isNotEmpty && partes[0].isNotEmpty) {
      iniciales = partes[0][0].toUpperCase();
    }
    return Center(
      child: Text(
        iniciales,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: TemaPsicobloom.colorPrincipalOscuro,
        ),
      ),
    );
  }

  Widget _construirSeccionEspecialidadesYModalidad(
    Profesional prof,
    List<String> especialidades,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              const Icon(
                Icons.people_outline_rounded,
                size: 20,
                color: TemaPsicobloom.colorPrincipal,
              ),
              const Text(
                'Modalidad de atención:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: TemaPsicobloom.colorTexto,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: TemaPsicobloom.colorLavanda,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  prof.modalidad.trim().isNotEmpty
                      ? prof.modalidad.trim()
                      : 'Presencial',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorPrincipalOscuro,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Especialidades acreditadas',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
          const SizedBox(height: 8),
          if (especialidades.isEmpty)
            const Text(
              'El profesional aún no ha detallado especialidades específicas.',
              style: TextStyle(
                fontSize: 13.5,
                color: TemaPsicobloom.colorTextoSecundario,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: especialidades.map((esp) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: TemaPsicobloom.colorFondo,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: TemaPsicobloom.colorBorde),
                  ),
                  child: Text(
                    esp,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: TemaPsicobloom.colorTexto,
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _construirSeccionAcercaDe(Profesional prof) {
    final descripcion = prof.descripcion.trim();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Presentación profesional',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            descripcion.isNotEmpty ? descripcion : 'El profesional aún no ha registrado una descripción detallada de su enfoque terapéutico.',
            style: TextStyle(
              fontSize: 14,
              color: descripcion.isNotEmpty
                  ? TemaPsicobloom.colorTexto
                  : TemaPsicobloom.colorTextoSecundario,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirSeccionServicios(Profesional prof) {
    final listaServicios = prof.servicios
        .split(RegExp(r'[\n,;]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Servicios psicológicos ofrecidos',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
          const SizedBox(height: 8),
          if (listaServicios.isEmpty)
            const Text(
              'Los servicios específicos de consulta aún no han sido detallados por el profesional.',
              style: TextStyle(
                fontSize: 13.5,
                color: TemaPsicobloom.colorTextoSecundario,
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: listaServicios.map((servicio) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 18,
                        color: TemaPsicobloom.colorSecundario,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          servicio,
                          style: const TextStyle(
                            fontSize: 14,
                            color: TemaPsicobloom.colorTexto,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _construirSeccionUbicacion(Profesional prof) {
    final direccion = prof.direccionConsultorio.trim();
    final tieneCoords = prof.tieneCoordenadasValidas;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                color: TemaPsicobloom.colorPrincipal,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Ubicación del consultorio',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: TemaPsicobloom.colorTexto,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            direccion.isNotEmpty
                ? direccion
                : (prof.modalidad == 'Virtual'
                      ? 'Atención en modalidad virtual (sin consultorio físico registrado).'
                      : 'Dirección exacta aún no especificada por el profesional.'),
            style: const TextStyle(
              fontSize: 13.5,
              color: TemaPsicobloom.colorTextoSecundario,
              height: 1.35,
            ),
          ),
          if (tieneCoords) ...[
            const SizedBox(height: 8),
            Text(
              'Coordenadas: ${prof.latitud.toStringAsFixed(5)}, ${prof.longitud.toStringAsFixed(5)}',
              style: const TextStyle(
                fontSize: 12,
                color: TemaPsicobloom.colorTextoSecundario,
              ),
            ),
            if (widget.mostrarMapaInteractivo) ...[
              const SizedBox(height: 12),
              MapaConsultorioRuta(
                altura: 200,
                marcadores: [
                  MarcadorConsultorioMapa(
                    id: prof.id,
                    titulo: prof.nombre,
                    subtitulo: direccion.isNotEmpty
                        ? direccion
                        : 'Consultorio en Riobamba',
                    latitud: prof.latitud,
                    longitud: prof.longitud,
                    seleccionado: true,
                  ),
                ],
                ubicacionPaciente: _controladorRuta.ubicacionPaciente,
                rutaActiva: _controladorRuta.ruta,
              ),
            ],
            const SizedBox(height: 12),
            PanelResultadoRutaConsultorio(
              controlador: _controladorRuta,
              alSolicitarRuta: () => unawaited(_calcularRutaConsultorio()),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TemaPsicobloom.colorFondo,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: TemaPsicobloom.colorBorde),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.map_outlined,
                    size: 18,
                    color: TemaPsicobloom.colorTextoSecundario,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'El profesional aún no ha registrado coordenadas en el mapa.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: TemaPsicobloom.colorTextoSecundario,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
