import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modelos/especialidad.dart';
import 'package:boom/modelos/profesional.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_perfil_publico_profesional.dart';
import 'package:boom/modulos/profesional/controladores/controlador_perfil_profesional.dart';
import 'package:boom/modulos/profesional/modelos/perfil_profesional.dart';
import 'package:boom/modulos/profesional/servicios/servicio_perfil_profesional.dart';
import 'package:boom/modulos/profesional/servicios/servicio_ubicacion_consultorio.dart';
import 'package:boom/nucleo/componentes/fondo_decorativo_bloom.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/repositorios/repositorio_especialidades.dart';

/// Pantalla para editar el perfil del profesional, organizada en cuatro secciones:
/// 1. Fotografia
/// 2. Datos profesionales
/// 3. Especialidades y servicios
/// 4. Modalidad y consultorio
class PantallaPerfilProfesional extends StatefulWidget {
  final PerfilProfesional? perfilInicial;
  final String? aprobacionInicial;
  final ServicioPerfilProfesional servicio;
  final RepositorioEspecialidades repositorioEspecialidades;
  final ServicioUbicacionConsultorio servicioUbicacion;
  final bool mostrarMapaInteractivo;
  final bool esVistaIntegrada;
  final ValueChanged<PerfilProfesional>? alActualizarPerfil;
  final VoidCallback? alCerrarSesion;
  final bool estaCerrandoSesion;

  const PantallaPerfilProfesional({
    super.key,
    this.perfilInicial,
    this.aprobacionInicial,
    this.servicio = const ServicioPerfilProfesional(),
    this.repositorioEspecialidades = const RepositorioEspecialidadesSupabase(),
    this.servicioUbicacion = const ServicioUbicacionConsultorio(),
    this.mostrarMapaInteractivo = true,
    this.esVistaIntegrada = false,
    this.alActualizarPerfil,
    this.alCerrarSesion,
    this.estaCerrandoSesion = false,
  });

  @override
  State<PantallaPerfilProfesional> createState() =>
      _PantallaPerfilProfesionalState();
}

class _PantallaPerfilProfesionalState extends State<PantallaPerfilProfesional> {
  final _claveFormulario = GlobalKey<FormState>();
  late final TextEditingController _controladorNombre;
  late final TextEditingController _controladorApellido;
  late final TextEditingController _controladorRegistro;
  late final TextEditingController _controladorAniosExperiencia;
  late final TextEditingController _controladorTelefono;
  late final TextEditingController _controladorDescripcion;
  late final TextEditingController _controladorServicios;
  late final TextEditingController _controladorDireccion;
  late final TextEditingController _controladorLatitud;
  late final TextEditingController _controladorLongitud;

  late final ControladorPerfilProfesional _controlador;
  GoogleMapController? _controladorMapa;
  double? _ultimaLatitudSincronizada;
  double? _ultimaLongitudSincronizada;

  @override
  void initState() {
    super.initState();
    final inicial = widget.perfilInicial;
    _ultimaLatitudSincronizada = inicial?.latitud;
    _ultimaLongitudSincronizada = inicial?.longitud;
    _controladorNombre = TextEditingController(text: inicial?.nombre ?? '');
    _controladorApellido = TextEditingController(text: inicial?.apellido ?? '');
    _controladorRegistro = TextEditingController(
      text: inicial?.numeroRegistro ?? '',
    );
    _controladorAniosExperiencia = TextEditingController(
      text: inicial?.aniosExperiencia?.toString() ?? '',
    );
    _controladorTelefono = TextEditingController(
      text: inicial?.telefonoContacto ?? '',
    );
    _controladorDescripcion = TextEditingController(
      text: inicial?.descripcion ?? '',
    );
    _controladorServicios = TextEditingController(
      text: inicial?.servicios ?? '',
    );
    _controladorDireccion = TextEditingController(
      text: inicial?.direccionConsultorio ?? '',
    );
    _controladorLatitud = TextEditingController(
      text: inicial?.latitud?.toStringAsFixed(6) ?? '',
    );
    _controladorLongitud = TextEditingController(
      text: inicial?.longitud?.toStringAsFixed(6) ?? '',
    );

    _controlador = ControladorPerfilProfesional(
      servicio: widget.servicio,
      repositorioEspecialidades: widget.repositorioEspecialidades,
      servicioUbicacion: widget.servicioUbicacion,
      perfilInicial: inicial,
    );
    _controlador.addListener(_sincronizarVista);
    unawaited(_inicializarDatos());
  }

  Future<void> _inicializarDatos() async {
    await _controlador.inicializar();
    if (!mounted) return;
    final p = _controlador.perfil;
    if (p != null) {
      _ultimaLatitudSincronizada = p.latitud;
      _ultimaLongitudSincronizada = p.longitud;
      _controladorNombre.text = p.nombre;
      _controladorApellido.text = p.apellido;
      _controladorRegistro.text = p.numeroRegistro ?? '';
      _controladorAniosExperiencia.text = p.aniosExperiencia?.toString() ?? '';
      _controladorTelefono.text = p.telefonoContacto ?? '';
      _controladorDescripcion.text = p.descripcion ?? '';
      _controladorServicios.text = p.servicios ?? '';
      _controladorDireccion.text = p.direccionConsultorio ?? '';
      _controladorLatitud.text = p.latitud?.toStringAsFixed(6) ?? '';
      _controladorLongitud.text = p.longitud?.toStringAsFixed(6) ?? '';
      widget.alActualizarPerfil?.call(p);
    }
  }

  void _sincronizarVista() {
    if (!mounted) return;
    final lat = _controlador.latitudSeleccionada;
    final lng = _controlador.longitudSeleccionada;
    final cambiaronCoordenadas =
        lat != _ultimaLatitudSincronizada || lng != _ultimaLongitudSincronizada;
    if (cambiaronCoordenadas) {
      _ultimaLatitudSincronizada = lat;
      _ultimaLongitudSincronizada = lng;
      if (lat != null && lng != null) {
        final latTxt = lat.toStringAsFixed(6);
        final lngTxt = lng.toStringAsFixed(6);
        if (_controladorLatitud.text != latTxt) {
          _controladorLatitud.text = latTxt;
        }
        if (_controladorLongitud.text != lngTxt) {
          _controladorLongitud.text = lngTxt;
        }
      }
    }
    setState(() {});
  }

  void _actualizarCoordenadasDesdeTexto() {
    final lat = double.tryParse(
      _controladorLatitud.text.trim().replaceAll(',', '.'),
    );
    final lng = double.tryParse(
      _controladorLongitud.text.trim().replaceAll(',', '.'),
    );
    if (lat != null &&
        lng != null &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180) {
      _ultimaLatitudSincronizada = lat;
      _ultimaLongitudSincronizada = lng;
      _controlador.seleccionarCoordenadasManuales(lat, lng);
    }
  }

  @override
  void dispose() {
    _controlador.removeListener(_sincronizarVista);
    _controlador.dispose();
    _controladorMapa?.dispose();
    _controladorNombre.dispose();
    _controladorApellido.dispose();
    _controladorRegistro.dispose();
    _controladorAniosExperiencia.dispose();
    _controladorTelefono.dispose();
    _controladorDescripcion.dispose();
    _controladorServicios.dispose();
    _controladorDireccion.dispose();
    _controladorLatitud.dispose();
    _controladorLongitud.dispose();
    super.dispose();
  }

  Future<void> _elegirFoto(ImageSource origen) async {
    final subida = await _controlador.seleccionarYSubirFotografia(
      origen: origen,
    );
    if (!mounted) return;
    if (subida && _controlador.perfil != null) {
      widget.alActualizarPerfil?.call(_controlador.perfil!);
    }
    if (subida && _controlador.mensajeExito != null) {
      _mostrarSnackBar(_controlador.mensajeExito!, esError: false);
    } else if (_controlador.mensajeError != null) {
      _mostrarSnackBar(_controlador.mensajeError!, esError: true);
    }
  }

  Future<void> _obtenerUbicacionDispositivo() async {
    final obtenida = await _controlador.usarUbicacionActualDispositivo();
    if (!mounted) return;
    final lat = _controlador.latitudSeleccionada;
    final lng = _controlador.longitudSeleccionada;
    if (obtenida && lat != null && lng != null) {
      await _controladorMapa?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16),
      );
    }
    if (_controlador.avisoUbicacion != null) {
      _mostrarSnackBar(_controlador.avisoUbicacion!, esError: !obtenida);
    }
  }

  Future<void> _guardarFormulario() async {
    if (_controlador.ocupado ||
        !(_claveFormulario.currentState?.validate() ?? false)) {
      return;
    }
    FocusScope.of(context).unfocus();

    final guardado = await _controlador.guardarPerfil(
      nombre: _controladorNombre.text,
      apellido: _controladorApellido.text,
      numeroRegistro: _controladorRegistro.text,
      descripcion: _controladorDescripcion.text,
      textoAniosExperiencia: _controladorAniosExperiencia.text,
      telefonoContacto: _controladorTelefono.text,
      servicios: _controladorServicios.text,
      direccionConsultorio: _controladorDireccion.text,
      textoLatitud: _controladorLatitud.text,
      textoLongitud: _controladorLongitud.text,
    );
    if (!mounted) return;
    if (guardado && _controlador.perfil != null) {
      widget.alActualizarPerfil?.call(_controlador.perfil!);
    }
    if (guardado && _controlador.mensajeExito != null) {
      _mostrarSnackBar(_controlador.mensajeExito!, esError: false);
    } else if (_controlador.mensajeError != null) {
      _mostrarSnackBar(_controlador.mensajeError!, esError: true);
    }
  }

  void _previsualizarPerfilPublico() {
    final nombresEsp = _controlador.catalogoEspecialidades
        .where(
          (e) => _controlador.especialidadesSeleccionadasIds.contains(e.id),
        )
        .map((e) => e.nombre)
        .toList();
    final lat = double.tryParse(
      _controladorLatitud.text.trim().replaceAll(',', '.'),
    );
    final lng = double.tryParse(
      _controladorLongitud.text.trim().replaceAll(',', '.'),
    );
    final tieneCoords = lat != null && lng != null;

    final vistaPrevia = Profesional(
      id: _controlador.perfil?.id ?? 'vista-previa',
      nombre:
          '${_controladorNombre.text.trim()} ${_controladorApellido.text.trim()}'
              .trim(),
      especialidad: nombresEsp.isNotEmpty
          ? nombresEsp.join(', ')
          : 'Psicología General',
      especialidades: nombresEsp,
      modalidad: _controlador.modalidadSeleccionada,
      descripcion: _controladorDescripcion.text.trim(),
      servicios: _controladorServicios.text.trim(),
      aniosExperiencia: int.tryParse(_controladorAniosExperiencia.text.trim()),
      fotoUrl: _controlador.perfil?.fotoUrl,
      disponibilidadTexto: 'Vista previa de tu perfil',
      distanciaTexto: _controladorDireccion.text.trim().isNotEmpty
          ? _controladorDireccion.text.trim()
          : 'Ubicación por confirmar',
      direccionConsultorio: _controladorDireccion.text.trim(),
      latitud: lat ?? 0.0,
      longitud: lng ?? 0.0,
      tieneUbicacion: tieneCoords,
    );

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PantallaPerfilPublicoProfesional(
          profesional: vistaPrevia,
          mostrarMapaInteractivo: widget.mostrarMapaInteractivo,
        ),
      ),
    );
  }

  void _mostrarSnackBar(String mensaje, {required bool esError}) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: esError
            ? TemaPsicobloom.colorError
            : TemaPsicobloom.colorExito,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          mensaje,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contenido = _controlador.estaCargando
        ? const Center(
            child: CircularProgressIndicator(
              color: TemaPsicobloom.colorPrincipal,
            ),
          )
        : Form(
            key: _claveFormulario,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                if (widget.esVistaIntegrada) ...[
                  _construirBarraSuperiorIntegrada(),
                  const SizedBox(height: 12),
                ],
                _construirInsigniaEstadoAprobacionPerfil(),
                const SizedBox(height: 16),
                if (_controlador.motivoRechazo != null &&
                    _controlador.motivoRechazo!.isNotEmpty) ...[
                  _construirAvisoRechazo(_controlador.motivoRechazo!),
                  const SizedBox(height: 16),
                ],
                _construirSeccionFotografia(),
                const SizedBox(height: 16),
                _construirSeccionDatosProfesionales(),
                const SizedBox(height: 16),
                _construirSeccionEspecialidadesYServicios(),
                const SizedBox(height: 16),
                _construirSeccionModalidadYConsultorio(),
                const SizedBox(height: 18),
                if (_controlador.mensajeError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: TemaPsicobloom.colorFondoError,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _controlador.mensajeError!,
                      style: const TextStyle(
                        color: TemaPsicobloom.colorError,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                ElevatedButton.icon(
                  key: const Key('botonGuardarPerfilProfesional'),
                  onPressed: _controlador.ocupado ? null : _guardarFormulario,
                  icon: _controlador.estaGuardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _controlador.estaGuardando
                        ? 'Guardando perfil...'
                        : 'Guardar perfil profesional',
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('botonPrevisualizarPerfilPublico'),
                  onPressed: _previsualizarPerfilPublico,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Previsualizar perfil público'),
                ),
                if (widget.alCerrarSesion != null) ...[
                  const SizedBox(height: 18),
                  _construirSeccionCierreSesion(),
                ],
                const SizedBox(height: 24),
              ],
            ),
          );

    if (widget.esVistaIntegrada) {
      return contenido;
    }

    return Scaffold(
      backgroundColor: TemaPsicobloom.colorFondo,
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Volver',
                onPressed: () => Navigator.of(context).pop(_controlador.perfil),
              )
            : null,
        title: const Text('Editar perfil profesional'),
        actions: [
          IconButton(
            icon: const Icon(Icons.visibility_outlined),
            tooltip: 'Ver cómo luce tu perfil público',
            onPressed: _previsualizarPerfilPublico,
          ),
        ],
      ),
      body: FondoDecorativoBloom(
        mostrarHojas: false,
        child: SafeArea(child: contenido),
      ),
    );
  }

  Widget _construirBarraSuperiorIntegrada() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Mi perfil profesional',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
        ),
        TextButton.icon(
          key: const Key('botonGuardarRapidoPerfilProfesional'),
          onPressed: _controlador.ocupado ? null : _guardarFormulario,
          icon: const Icon(Icons.save_outlined, size: 18),
          label: const Text('Guardar'),
        ),
      ],
    );
  }

  Widget _construirEtiquetaCampo(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: TemaPsicobloom.colorTexto,
        ),
      ),
    );
  }

  Widget _construirInsigniaEstadoAprobacionPerfil() {
    final estadoAprobacion =
        (_controlador.perfil?.aprobacion.trim().isNotEmpty == true
                ? _controlador.perfil!.aprobacion
                : (widget.aprobacionInicial ?? 'pendiente'))
            .trim()
            .toLowerCase();
    final bool esAprobado = estadoAprobacion == 'aprobado';
    final bool esRechazado = estadoAprobacion == 'rechazado';

    final Color colorFondo = esAprobado
        ? TemaPsicobloom.colorFondoExito
        : esRechazado
        ? TemaPsicobloom.colorFondoError
        : TemaPsicobloom.colorFondoAdvertencia;
    final Color colorTexto = esAprobado
        ? TemaPsicobloom.colorExito
        : esRechazado
        ? TemaPsicobloom.colorError
        : TemaPsicobloom.colorAdvertencia;
    final IconData icono = esAprobado
        ? Icons.verified_rounded
        : esRechazado
        ? Icons.cancel_outlined
        : Icons.hourglass_top_rounded;
    final String titulo = esAprobado
        ? 'Perfil profesional aprobado'
        : esRechazado
        ? 'Solicitud profesional observada'
        : 'Perfil en revisión administrativa';
    final String resumen = esAprobado
        ? 'Tu perfil está activo y visible en el directorio de pacientes.'
        : esRechazado
        ? 'Revisa las observaciones y actualiza tus datos para solicitar una nueva revisión.'
        : 'Un administrador verificará tus datos antes de publicar tu perfil.';

    return Container(
      key: const Key('insigniaEstadoAprobacionPerfilProfesional'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: colorFondo,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorTexto.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: colorTexto, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: colorTexto,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  resumen,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirAvisoRechazo(String motivo) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorFondoError,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TemaPsicobloom.colorError),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.report_problem_outlined,
            color: TemaPsicobloom.colorError,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Motivo de observación administrativa: $motivo',
              style: const TextStyle(
                color: TemaPsicobloom.colorError,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirSeccionFotografia() {
    final fotoUrl = _controlador.perfil?.fotoUrl;
    final tieneFoto = fotoUrl != null && fotoUrl.trim().isNotEmpty;

    return Container(
      key: const Key('seccionPerfil_fotografia'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(
                Icons.camera_enhance_outlined,
                size: 20,
                color: TemaPsicobloom.colorPrincipal,
              ),
              SizedBox(width: 8),
              Text(
                'Fotografía',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: TemaPsicobloom.colorTexto,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: TemaPsicobloom.colorLavanda,
              shape: BoxShape.circle,
              border: Border.all(color: TemaPsicobloom.colorPrincipal),
            ),
            child: ClipOval(
              child: tieneFoto
                  ? Image.network(
                      fotoUrl.trim(),
                      width: 92,
                      height: 92,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.person_rounded,
                        size: 46,
                        color: TemaPsicobloom.colorPrincipal,
                      ),
                    )
                  : const Icon(
                      Icons.person_rounded,
                      size: 46,
                      color: TemaPsicobloom.colorPrincipal,
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const Key('botonSubirFotoGaleria'),
                onPressed: _controlador.ocupado
                    ? null
                    : () => _elegirFoto(ImageSource.gallery),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(148, 42),
                ),
                icon: _controlador.estaSubiendoFoto
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_library_outlined, size: 18),
                label: Text(
                  _controlador.estaSubiendoFoto
                      ? 'Subiendo...'
                      : 'Elegir de galería',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _controlador.ocupado
                    ? null
                    : () => _elegirFoto(ImageSource.camera),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(138, 42),
                ),
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: const Text('Tomar foto'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _construirSeccionDatosProfesionales() {
    final correoCuenta = _controlador.perfil?.correo ?? '';

    return Container(
      key: const Key('seccionPerfil_datosProfesionales'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(
                Icons.badge_outlined,
                size: 20,
                color: TemaPsicobloom.colorPrincipal,
              ),
              SizedBox(width: 8),
              Text(
                'Datos profesionales',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: TemaPsicobloom.colorTexto,
                ),
              ),
            ],
          ),
          if (correoCuenta.isNotEmpty) ...[
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
              child: Row(
                children: [
                  const Icon(
                    Icons.mail_outline_rounded,
                    size: 18,
                    color: TemaPsicobloom.colorTextoSecundario,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Correo electrónico de la cuenta (solo lectura)',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: TemaPsicobloom.colorTextoSecundario,
                          ),
                        ),
                        Text(
                          correoCuenta,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: TemaPsicobloom.colorTexto,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          _construirEtiquetaCampo('Nombre'),
          TextFormField(
            key: const Key('campoNombreProfesional'),
            controller: _controladorNombre,
            decoration: const InputDecoration(
              hintText: 'Ej. Carlos Alberto',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            validator: (v) => (v == null || v.trim().length < 2)
                ? 'Ingresa al menos 2 caracteres.'
                : null,
          ),
          const SizedBox(height: 14),
          _construirEtiquetaCampo('Apellido'),
          TextFormField(
            key: const Key('campoApellidoProfesional'),
            controller: _controladorApellido,
            decoration: const InputDecoration(
              hintText: 'Ej. Pérez Andrade',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            validator: (v) => (v == null || v.trim().length < 2)
                ? 'Ingresa al menos 2 caracteres.'
                : null,
          ),
          const SizedBox(height: 14),
          _construirEtiquetaCampo(
            'Número de registro profesional (SENESCYT / MSP)',
          ),
          TextFormField(
            key: const Key('campoRegistroProfesional'),
            controller: _controladorRegistro,
            decoration: const InputDecoration(
              hintText: 'Ej. 0601234567',
              prefixIcon: Icon(Icons.verified_outlined),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _construirEtiquetaCampo('Años de experiencia'),
                    TextFormField(
                      key: const Key('campoAniosExperiencia'),
                      controller: _controladorAniosExperiencia,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: 'Ej. 5',
                        prefixIcon: Icon(Icons.work_history_outlined),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _construirEtiquetaCampo('Teléfono de contacto'),
                    TextFormField(
                      key: const Key('campoTelefonoProfesional'),
                      controller: _controladorTelefono,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        hintText: '0991234567',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _construirEtiquetaCampo('Descripción y enfoque terapéutico'),
          TextFormField(
            key: const Key('campoDescripcionProfesional'),
            controller: _controladorDescripcion,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Describe brevemente tu formación y enfoque de atención psicológica.',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirSeccionEspecialidadesYServicios() {
    final opciones = _controlador.especialidadesVisibles;

    return Container(
      key: const Key('seccionPerfil_especialidadesServicios'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(
                Icons.psychology_outlined,
                size: 20,
                color: TemaPsicobloom.colorPrincipal,
              ),
              SizedBox(width: 8),
              Text(
                'Especialidades y servicios',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: TemaPsicobloom.colorTexto,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _construirEtiquetaCampo('Catálogo de especialidades'),
          if (opciones.isEmpty)
            const Text(
              'El catálogo de especialidades está vacío en el servidor.',
              style: TextStyle(
                fontSize: 13.5,
                color: TemaPsicobloom.colorTextoSecundario,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: opciones.map((Especialidad esp) {
                final seleccionada = _controlador.especialidadesSeleccionadasIds
                    .contains(esp.id);
                return FilterChip(
                  label: Text(
                    esp.activa ? esp.nombre : '${esp.nombre} (histórica)',
                  ),
                  selected: seleccionada,
                  selectedColor: TemaPsicobloom.colorLavanda,
                  checkmarkColor: TemaPsicobloom.colorPrincipalOscuro,
                  onSelected: (_) => _controlador.alternarEspecialidad(esp),
                );
              }).toList(),
            ),
          const SizedBox(height: 16),
          _construirEtiquetaCampo(
            'Servicios ofrecidos (separados por coma o línea)',
          ),
          TextFormField(
            key: const Key('campoServiciosProfesional'),
            controller: _controladorServicios,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Ej. Evaluación psicológica, Terapia individual, Orientación familiar',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirSeccionModalidadYConsultorio() {
    const modalidades = ['Presencial', 'Virtual', 'Híbrida'];
    final lat = _controlador.latitudSeleccionada;
    final lng = _controlador.longitudSeleccionada;
    final tienePunto = lat != null && lng != null;
    final puntoCamara = tienePunto
        ? LatLng(lat, lng)
        : const LatLng(
            ServicioUbicacionConsultorio.latitudReferenciaRiobamba,
            ServicioUbicacionConsultorio.longitudReferenciaRiobamba,
          );

    return Container(
      key: const Key('seccionPerfil_modalidadConsultorio'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 20,
                color: TemaPsicobloom.colorPrincipal,
              ),
              SizedBox(width: 8),
              Text(
                'Modalidad y consultorio',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: TemaPsicobloom.colorTexto,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _construirEtiquetaCampo('Modalidad de atención'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: modalidades.map((mod) {
              final activa = _controlador.modalidadSeleccionada == mod;
              return ChoiceChip(
                label: Text(mod),
                selected: activa,
                selectedColor: TemaPsicobloom.colorLavanda,
                onSelected: (_) => _controlador.cambiarModalidad(mod),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          _construirEtiquetaCampo('Dirección referencial del consultorio'),
          TextFormField(
            key: const Key('campoDireccionConsultorio'),
            controller: _controladorDireccion,
            decoration: const InputDecoration(
              hintText: 'Ej. Av. Daniel León Borja y Lavalle, Riobamba',
              prefixIcon: Icon(Icons.location_city_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _construirEtiquetaCampo('Latitud'),
                    TextFormField(
                      key: const Key('campoLatitudConsultorio'),
                      controller: _controladorLatitud,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      decoration: const InputDecoration(hintText: '-1.670980'),
                      onChanged: (_) => _actualizarCoordenadasDesdeTexto(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _construirEtiquetaCampo('Longitud'),
                    TextFormField(
                      key: const Key('campoLongitudConsultorio'),
                      controller: _controladorLongitud,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      decoration: const InputDecoration(hintText: '-78.647120'),
                      onChanged: (_) => _actualizarCoordenadasDesdeTexto(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('botonUsarUbicacionActual'),
            onPressed: _controlador.ocupado
                ? null
                : _obtenerUbicacionDispositivo,
            icon: _controlador.estaObteniendoUbicacion
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded),
            label: Text(
              _controlador.estaObteniendoUbicacion
                  ? 'Obteniendo ubicación...'
                  : 'Usar mi ubicación actual',
            ),
          ),
          if (_controlador.avisoUbicacion != null) ...[
            const SizedBox(height: 10),
            Text(
              _controlador.avisoUbicacion!,
              style: const TextStyle(
                fontSize: 12.5,
                color: TemaPsicobloom.colorTextoSecundario,
              ),
            ),
          ],
          if (widget.mostrarMapaInteractivo) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 220,
                child: ConfiguracionSupabase.tieneClaveGoogleMaps
                    ? GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: puntoCamara,
                          zoom: 14.5,
                        ),
                        markers: tienePunto
                            ? {
                                Marker(
                                  markerId: const MarkerId(
                                    'marcador_consultorio',
                                  ),
                                  position: LatLng(lat, lng),
                                  infoWindow: const InfoWindow(
                                    title: 'Ubicación seleccionada',
                                  ),
                                ),
                              }
                            : const {},
                        myLocationButtonEnabled: false,
                        onMapCreated: (controlador) {
                          _controladorMapa = controlador;
                        },
                        onTap: (coordenada) {
                          _controlador.seleccionarCoordenadasManuales(
                            coordenada.latitude,
                            coordenada.longitude,
                          );
                        },
                      )
                    : _LienzoMapaInteractivoRiobamba(
                        latitud: lat,
                        longitud: lng,
                        alSeleccionarCoordenadas: (nuevaLat, nuevaLng) {
                          _controlador.seleccionarCoordenadasManuales(
                            nuevaLat,
                            nuevaLng,
                          );
                        },
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _construirSeccionCierreSesion() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Sesión de la cuenta',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('botonCerrarSesionDesdePerfilProfesional'),
            onPressed: widget.estaCerrandoSesion ? null : widget.alCerrarSesion,
            style: OutlinedButton.styleFrom(
              foregroundColor: TemaPsicobloom.colorError,
              side: const BorderSide(
                color: TemaPsicobloom.colorError,
                width: 1.2,
              ),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: Text(
              widget.estaCerrandoSesion
                  ? 'Cerrando sesión...'
                  : 'Cerrar sesión',
            ),
          ),
        ],
      ),
    );
  }
}

/// Selector interactivo de coordenadas para Riobamba basado en Flutter puro.
/// Se utiliza cuando no se ha inyectado una clave nativa de Google Maps SDK
/// en Android, evitando el cierre inesperado (IllegalStateException: API key not found).
class _LienzoMapaInteractivoRiobamba extends StatelessWidget {
  final double? latitud;
  final double? longitud;
  final void Function(double latitud, double longitud) alSeleccionarCoordenadas;

  static const double _latCentro =
      ServicioUbicacionConsultorio.latitudReferenciaRiobamba;
  static const double _lngCentro =
      ServicioUbicacionConsultorio.longitudReferenciaRiobamba;
  static const double _rangoGrados = 0.030;

  const _LienzoMapaInteractivoRiobamba({
    required this.latitud,
    required this.longitud,
    required this.alSeleccionarCoordenadas,
  });

  void _manejarToque(TapUpDetails detalles, Size tamano) {
    if (tamano.width <= 0 || tamano.height <= 0) return;
    final proporcionX = (detalles.localPosition.dx / tamano.width).clamp(
      0.0,
      1.0,
    );
    final proporcionY = (detalles.localPosition.dy / tamano.height).clamp(
      0.0,
      1.0,
    );
    final nuevaLng = _lngCentro + (proporcionX - 0.5) * 2 * _rangoGrados;
    final nuevaLat = _latCentro - (proporcionY - 0.5) * 2 * _rangoGrados;
    alSeleccionarCoordenadas(nuevaLat, nuevaLng);
  }

  @override
  Widget build(BuildContext context) {
    final tienePunto = latitud != null && longitud != null;

    return LayoutBuilder(
      builder: (context, restricciones) {
        final ancho = restricciones.maxWidth;
        final alto = restricciones.maxHeight;
        final tamano = Size(ancho, alto);

        double? posX;
        double? posY;
        if (tienePunto && ancho > 0 && alto > 0) {
          final normX = ((longitud! - _lngCentro) / (2 * _rangoGrados) + 0.5)
              .clamp(0.08, 0.92);
          final normY = ((_latCentro - latitud!) / (2 * _rangoGrados) + 0.5)
              .clamp(0.12, 0.88);
          posX = normX * ancho;
          posY = normY * alto;
        }

        return GestureDetector(
          key: const Key('lienzoMapaInteractivoRiobamba'),
          behavior: HitTestBehavior.opaque,
          onTapUp: (detalles) => _manejarToque(detalles, tamano),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: _PintorCuadriculaMapaRiobamba()),
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: TemaPsicobloom.colorBorde),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.touch_app_outlined,
                        size: 16,
                        color: TemaPsicobloom.colorPrincipal,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          tienePunto
                              ? 'Marcador: ${latitud!.toStringAsFixed(5)}, ${longitud!.toStringAsFixed(5)}'
                              : 'Toca el mapa de Riobamba para situar el consultorio',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: TemaPsicobloom.colorTexto,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (posX != null && posY != null)
                Positioned(
                  left: posX - 18,
                  top: posY - 34,
                  child: const Icon(
                    Icons.location_on_rounded,
                    size: 36,
                    color: TemaPsicobloom.colorPrincipal,
                  ),
                ),
              Positioned(
                bottom: 8,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Riobamba, Ecuador',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: TemaPsicobloom.colorTextoSecundario,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PintorCuadriculaMapaRiobamba extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fondo = Paint()..color = const Color(0xFFEEF3F1);
    canvas.drawRect(Offset.zero & size, fondo);

    final areaVerde = Paint()..color = const Color(0xFFDCEBE2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.12,
          size.height * 0.22,
          size.width * 0.22,
          size.height * 0.25,
        ),
        const Radius.circular(10),
      ),
      areaVerde,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.64,
          size.height * 0.55,
          size.width * 0.24,
          size.height * 0.26,
        ),
        const Radius.circular(10),
      ),
      areaVerde,
    );

    final calleSecundaria = Paint()
      ..color = const Color(0xFFD5DFDC)
      ..strokeWidth = 1.4;
    for (var i = 1; i <= 5; i++) {
      final x = size.width * (i / 6);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), calleSecundaria);
    }
    for (var j = 1; j <= 4; j++) {
      final y = size.height * (j / 5);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), calleSecundaria);
    }

    final avenidaPrincipal = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.5;
    canvas.drawLine(
      Offset(0, size.height * 0.48),
      Offset(size.width, size.height * 0.48),
      avenidaPrincipal,
    );
    canvas.drawLine(
      Offset(size.width * 0.52, 0),
      Offset(size.width * 0.52, size.height),
      avenidaPrincipal,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
