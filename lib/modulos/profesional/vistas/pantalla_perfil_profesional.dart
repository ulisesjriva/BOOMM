import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';

import 'package:boom/nucleo/componentes/mapa_geoapify.dart';
import 'package:boom/nucleo/servicios/servicio_geoapify.dart';
import 'package:boom/modelos/especialidad.dart';
import 'package:boom/modelos/profesional.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_perfil_publico_profesional.dart';
import 'package:boom/modulos/profesional/controladores/controlador_perfil_profesional.dart';
import 'package:boom/modulos/profesional/modelos/perfil_profesional.dart';
import 'package:boom/modulos/profesional/servicios/servicio_avisos_telegram.dart';
import 'package:boom/modulos/profesional/servicios/servicio_cobro_profesional.dart';
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
  final ServicioAvisosTelegram servicioTelegram;
  final ServicioCobroProfesional servicioCobro;
  final ServicioGeoapify servicioGeoapify;
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
    this.servicioTelegram = const ServicioAvisosTelegram(),
    this.servicioCobro = const ServicioCobroProfesional(),
    this.servicioGeoapify = const ServicioGeoapify(),
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
  late final TextEditingController _controladorPrecioConsulta;
  late final TextEditingController _controladorMontoAdelanto;
  late final TextEditingController _controladorBancoBeneficiario;
  late final TextEditingController _controladorTitularBeneficiario;
  late final TextEditingController _controladorTipoCuentaBeneficiario;
  late final TextEditingController _controladorNumeroCuentaReferencia;

  late final ControladorPerfilProfesional _controlador;
  bool _requiereAdelanto = false;
  bool _buscandoDireccion = false;
  List<DireccionGeoapify> _direccionesEncontradas = const [];
  String? _avisoDireccion;
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
    _controladorPrecioConsulta = TextEditingController();
    _controladorMontoAdelanto = TextEditingController();
    _controladorBancoBeneficiario = TextEditingController();
    _controladorTitularBeneficiario = TextEditingController();
    _controladorTipoCuentaBeneficiario = TextEditingController();
    _controladorNumeroCuentaReferencia = TextEditingController();

    _controlador = ControladorPerfilProfesional(
      servicio: widget.servicio,
      repositorioEspecialidades: widget.repositorioEspecialidades,
      servicioUbicacion: widget.servicioUbicacion,
      servicioTelegram: widget.servicioTelegram,
      servicioCobro: widget.servicioCobro,
      perfilInicial: inicial,
    );
    _controlador.addListener(_sincronizarVista);
    unawaited(_inicializarDatos());
  }

  Future<void> _inicializarDatos() async {
    await _controlador.inicializar();
    if (!mounted) {
      return;
    }
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
    _sincronizarCamposCobro();
  }

  void _sincronizarCamposCobro() {
    final cobro = _controlador.configuracionCobro;
    _requiereAdelanto = cobro.requiereAdelanto;
    _controladorPrecioConsulta.text = cobro.precioConsulta != null
        ? cobro.precioConsulta!.toStringAsFixed(2)
        : '';
    _controladorMontoAdelanto.text = cobro.montoAdelanto != null
        ? cobro.montoAdelanto!.toStringAsFixed(2)
        : '';
    _controladorBancoBeneficiario.text = cobro.bancoBeneficiario ?? '';
    _controladorTitularBeneficiario.text = cobro.titularBeneficiario ?? '';
    _controladorTipoCuentaBeneficiario.text =
        cobro.tipoCuentaBeneficiario ?? '';
    _controladorNumeroCuentaReferencia.text =
        cobro.numeroCuentaReferencia ?? '';
  }

  void _sincronizarVista() {
    if (!mounted) {
      return;
    }
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
    _controladorPrecioConsulta.dispose();
    _controladorMontoAdelanto.dispose();
    _controladorBancoBeneficiario.dispose();
    _controladorTitularBeneficiario.dispose();
    _controladorTipoCuentaBeneficiario.dispose();
    _controladorNumeroCuentaReferencia.dispose();
    super.dispose();
  }

  Future<void> _elegirFoto(ImageSource origen) async {
    final subida = await _controlador.seleccionarYSubirFotografia(
      origen: origen,
    );
    if (!mounted) {
      return;
    }
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
    if (!mounted) {
      return;
    }
    if (_controlador.avisoUbicacion != null) {
      _mostrarSnackBar(_controlador.avisoUbicacion!, esError: !obtenida);
    }
  }

  Future<void> _buscarDireccion() async {
    final texto = _controladorDireccion.text.trim();
    setState(() {
      _buscandoDireccion = true;
      _avisoDireccion = null;
      _direccionesEncontradas = const [];
    });
    try {
      final resultados = await widget.servicioGeoapify.buscarDireccion(texto);
      if (!mounted || _controladorDireccion.text.trim() != texto) {
        return;
      }
      setState(() {
        _direccionesEncontradas = resultados;
        _avisoDireccion = resultados.isEmpty
            ? 'No encontramos esa dirección. Prueba con una calle o selecciona el punto en el mapa.'
            : 'Selecciona un resultado y comprueba la ubicación del consultorio.';
      });
    } catch (error) {
      if (mounted && _controladorDireccion.text.trim() == texto) {
        setState(() {
          _avisoDireccion = error is ErrorGeoapify
              ? error.mensaje
              : 'No se pudo buscar la dirección.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _buscandoDireccion = false);
      }
    }
  }

  Future<void> _guardarFormulario() async {
    if (_buscandoDireccion ||
        _controlador.ocupado ||
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
    if (!mounted) {
      return;
    }
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
            child: SingleChildScrollView(
              key: const Key('listaPerfilProfesional'),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  _construirSeccionAvisosTelegram(),
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
                  const SizedBox(height: 18),
                  _construirSeccionCobroYAdelantos(),
                  if (widget.alCerrarSesion != null) ...[
                    const SizedBox(height: 18),
                    _construirSeccionCierreSesion(),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
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

  Future<void> _conectarTelegram() async {
    final iniciado = await _controlador.conectarTelegram();
    if (!mounted) {
      return;
    }
    if (iniciado && _controlador.mensajeExito != null) {
      _mostrarSnackBar(_controlador.mensajeExito!, esError: false);
    } else if (_controlador.mensajeError != null) {
      _mostrarSnackBar(_controlador.mensajeError!, esError: true);
    }
  }

  Future<void> _comprobarConexionTelegram() async {
    final conectado = await _controlador.comprobarConexionTelegram();
    if (!mounted) {
      return;
    }
    if (_controlador.mensajeError != null) {
      _mostrarSnackBar(_controlador.mensajeError!, esError: true);
    } else if (_controlador.mensajeExito != null) {
      _mostrarSnackBar(_controlador.mensajeExito!, esError: !conectado);
    }
  }

  Future<void> _desconectarTelegram() async {
    final desconectado = await _controlador.desconectarTelegram();
    if (!mounted) {
      return;
    }
    if (desconectado && _controlador.mensajeExito != null) {
      _mostrarSnackBar(_controlador.mensajeExito!, esError: false);
    } else if (_controlador.mensajeError != null) {
      _mostrarSnackBar(_controlador.mensajeError!, esError: true);
    }
  }

  Widget _construirSeccionAvisosTelegram() {
    final estado = _controlador.estadoTelegram;
    final estaGestionando = _controlador.estaGestionandoTelegram;

    return Container(
      key: const Key('seccionPerfil_avisosTelegram'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.notifications_active_outlined,
                size: 20,
                color: TemaPsicobloom.colorPrincipal,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Avisos por Telegram',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
              ),
              Container(
                key: const Key('estadoTelegramEtiqueta'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: estado.conectado
                      ? TemaPsicobloom.colorExito.withValues(alpha: 0.14)
                      : TemaPsicobloom.colorFondo,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: estado.conectado
                        ? TemaPsicobloom.colorExito
                        : TemaPsicobloom.colorBorde,
                  ),
                ),
                child: Text(
                  estado.conectado ? 'Conectado' : 'No conectado',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: estado.conectado
                        ? TemaPsicobloom.colorExito
                        : TemaPsicobloom.colorTextoSecundario,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Recibe un aviso cuando tengas una nueva solicitud.',
            style: TextStyle(
              fontSize: 13.5,
              color: TemaPsicobloom.colorTextoSecundario,
            ),
          ),
          if (!estado.conectado && estado.tieneCodigoPendiente) ...[
            const SizedBox(height: 8),
            const Text(
              'Enlace generado. Toca «Iniciar» en Telegram y luego «Comprobar conexión».',
              style: TextStyle(
                fontSize: 12.5,
                color: TemaPsicobloom.colorPrincipal,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (!estado.conectado)
                OutlinedButton.icon(
                  key: const Key('botonConectarTelegram'),
                  onPressed: _controlador.ocupado ? null : _conectarTelegram,
                  icon: estaGestionando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined, size: 18),
                  label: const Text('Conectar Telegram'),
                ),
              OutlinedButton.icon(
                key: const Key('botonComprobarTelegram'),
                onPressed: _controlador.ocupado
                    ? null
                    : _comprobarConexionTelegram,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Comprobar conexión'),
              ),
              if (estado.conectado)
                OutlinedButton.icon(
                  key: const Key('botonDesconectarTelegram'),
                  onPressed: _controlador.ocupado ? null : _desconectarTelegram,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: TemaPsicobloom.colorError,
                  ),
                  icon: const Icon(Icons.link_off_rounded, size: 18),
                  label: const Text('Desconectar'),
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
            onChanged: (_) => setState(() {
              _direccionesEncontradas = const [];
              _avisoDireccion = null;
            }),
            decoration: const InputDecoration(
              hintText: 'Ej. Av. Daniel León Borja y Lavalle, Riobamba',
              prefixIcon: Icon(Icons.location_city_outlined),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('botonBuscarDireccionGeoapify'),
            onPressed: _buscandoDireccion || _controlador.ocupado
                ? null
                : _buscarDireccion,
            icon: _buscandoDireccion
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(
              _buscandoDireccion
                  ? 'Buscando dirección...'
                  : 'Buscar dirección en Riobamba',
            ),
          ),
          if (_avisoDireccion != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                _avisoDireccion!,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          for (final direccion in _direccionesEncontradas)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.place_outlined),
              title: Text(
                direccion.direccion,
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: const Text(
                'Toca para seleccionar; comprueba el punto en el mapa.',
              ),
              onTap: () {
                _controladorDireccion.text = direccion.direccion;
                _controlador.seleccionarCoordenadasManuales(
                  direccion.latitud,
                  direccion.longitud,
                );
                setState(() {
                  _direccionesEncontradas = const [];
                  _avisoDireccion =
                      'Revisa la ubicación y pulsa Guardar para conservarla.';
                });
              },
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
            MapaGeoapify(
              centro: tienePunto
                  ? LatLng(lat, lng)
                  : const LatLng(
                      ServicioUbicacionConsultorio.latitudReferenciaRiobamba,
                      ServicioUbicacionConsultorio.longitudReferenciaRiobamba,
                    ),
              marcadores: [
                if (tienePunto)
                  Marker(
                    point: LatLng(lat, lng),
                    width: 42,
                    height: 42,
                    alignment: Alignment.topCenter,
                    child: const Tooltip(
                      message: 'Ubicación seleccionada',
                      child: Icon(
                        Icons.location_on,
                        size: 40,
                        color: TemaPsicobloom.colorPrincipal,
                      ),
                    ),
                  ),
              ],
              alTocar: (punto) => _controlador.seleccionarCoordenadasManuales(
                punto.latitude,
                punto.longitude,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _elegirQrCobro() async {
    final subido = await _controlador.seleccionarYSubirQrCobro(
      origen: ImageSource.gallery,
    );
    if (!mounted) return;
    if (subido && _controlador.mensajeExito != null) {
      _mostrarSnackBar(_controlador.mensajeExito!, esError: false);
    } else if (_controlador.mensajeError != null) {
      _mostrarSnackBar(_controlador.mensajeError!, esError: true);
    }
  }

  Future<void> _guardarConfiguracionCobro() async {
    if (_controlador.ocupado) return;
    FocusScope.of(context).unfocus();

    final guardado = await _controlador.guardarConfiguracionCobro(
      requiereAdelanto: _requiereAdelanto,
      textoPrecioConsulta: _controladorPrecioConsulta.text,
      textoMontoAdelanto: _controladorMontoAdelanto.text,
      bancoBeneficiario: _controladorBancoBeneficiario.text,
      titularBeneficiario: _controladorTitularBeneficiario.text,
      tipoCuentaBeneficiario: _controladorTipoCuentaBeneficiario.text,
      numeroCuentaReferencia: _controladorNumeroCuentaReferencia.text,
    );
    if (!mounted) return;
    if (guardado) {
      _sincronizarCamposCobro();
      if (_controlador.mensajeExito != null) {
        _mostrarSnackBar(_controlador.mensajeExito!, esError: false);
      }
    } else if (_controlador.mensajeError != null) {
      _mostrarSnackBar(_controlador.mensajeError!, esError: true);
    }
  }

  Widget _construirSeccionCobroYAdelantos() {
    final tieneQr =
        _controlador.rutaQrEfectiva != null &&
        _controlador.rutaQrEfectiva!.trim().isNotEmpty;
    final bytesQr = _controlador.bytesQrLocal;
    final urlQr = _controlador.urlTemporalVistaQr;
    final gestionando = _controlador.estaGestionandoCobro;

    return Container(
      key: const Key('seccionPerfil_cobroAdelanto'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.qr_code_2_rounded,
                size: 20,
                color: TemaPsicobloom.colorPrincipal,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Cobro y adelanto (USD)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
              ),
              Container(
                key: const Key('estadoAdelantoEtiqueta'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _requiereAdelanto
                      ? TemaPsicobloom.colorExito.withValues(alpha: 0.14)
                      : TemaPsicobloom.colorFondo,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _requiereAdelanto
                        ? TemaPsicobloom.colorExito
                        : TemaPsicobloom.colorBorde,
                  ),
                ),
                child: Text(
                  _requiereAdelanto ? 'Activo' : 'Opcional',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _requiereAdelanto
                        ? TemaPsicobloom.colorExito
                        : TemaPsicobloom.colorTextoSecundario,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Configura tu tarifa en USD, el adelanto opcional y tu código QR bancario privado.',
            style: TextStyle(
              fontSize: 13.5,
              color: TemaPsicobloom.colorTextoSecundario,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Solicitar adelanto al confirmar citas',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: TemaPsicobloom.colorTexto,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Requiere precio, monto de adelanto, QR privado y datos mínimos del beneficiario.',
                      style: TextStyle(
                        fontSize: 12,
                        color: TemaPsicobloom.colorTextoSecundario,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch.adaptive(
                key: const Key('interruptorRequiereAdelanto'),
                value: _requiereAdelanto,
                activeTrackColor: TemaPsicobloom.colorPrincipal,
                onChanged: _controlador.ocupado
                    ? null
                    : (valor) => setState(() => _requiereAdelanto = valor),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _construirEtiquetaCampo('Precio total (USD)'),
                    TextField(
                      key: const Key('campoPrecioConsultaUsd'),
                      controller: _controladorPrecioConsulta,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Ej: 35.00',
                        prefixText: '\$ ',
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
                    _construirEtiquetaCampo('Adelanto (USD)'),
                    TextField(
                      key: const Key('campoMontoAdelantoUsd'),
                      controller: _controladorMontoAdelanto,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Ej: 15.00',
                        prefixText: '\$ ',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _construirEtiquetaCampo('Banco o entidad financiera'),
          TextField(
            key: const Key('campoBancoBeneficiario'),
            controller: _controladorBancoBeneficiario,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Ej: Banco Pichincha'),
          ),
          const SizedBox(height: 12),
          _construirEtiquetaCampo('Titular de la cuenta'),
          TextField(
            key: const Key('campoTitularBeneficiario'),
            controller: _controladorTitularBeneficiario,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Ej: Dra. Sofía Paredes',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _construirEtiquetaCampo('Tipo de cuenta (opcional)'),
                    TextField(
                      key: const Key('campoTipoCuentaBeneficiario'),
                      controller: _controladorTipoCuentaBeneficiario,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Ahorros / Corriente',
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
                    _construirEtiquetaCampo('N.º de cuenta (opcional)'),
                    TextField(
                      key: const Key('campoNumeroCuentaReferencia'),
                      controller: _controladorNumeroCuentaReferencia,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: 'Ej: 2204567890',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TemaPsicobloom.colorFondo,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: TemaPsicobloom.colorBorde),
            ),
            child: Column(
              children: [
                if (bytesQr != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      bytesQr,
                      height: 180,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.qr_code_2_rounded,
                        size: 64,
                        color: TemaPsicobloom.colorPrincipal,
                      ),
                    ),
                  )
                else if (urlQr != null && urlQr.trim().isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      urlQr,
                      height: 180,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.qr_code_2_rounded,
                        size: 64,
                        color: TemaPsicobloom.colorPrincipal,
                      ),
                    ),
                  )
                else
                  Icon(
                    tieneQr
                        ? Icons.verified_user_outlined
                        : Icons.qr_code_2_rounded,
                    size: 56,
                    color: tieneQr
                        ? TemaPsicobloom.colorExito
                        : TemaPsicobloom.colorTextoSecundario,
                  ),
                const SizedBox(height: 8),
                Text(
                  tieneQr
                      ? 'QR bancario almacenado en carpeta privada (sin recorte ni compresión).'
                      : 'Aún no has cargado un código QR bancario.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: TemaPsicobloom.colorTextoSecundario,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('botonCargarQrCobro'),
                  onPressed: _controlador.ocupado ? null : _elegirQrCobro,
                  icon: gestionando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_outlined, size: 18),
                  label: Text(
                    tieneQr ? 'Reemplazar QR bancario' : 'Cargar QR bancario',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            key: const Key('botonGuardarConfiguracionCobro'),
            onPressed: _controlador.ocupado ? null : _guardarConfiguracionCobro,
            icon: gestionando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.savings_outlined),
            label: Text(
              gestionando
                  ? 'Guardando cobro...'
                  : 'Guardar configuración de cobro',
            ),
          ),
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
