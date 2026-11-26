import 'dart:async';

import 'package:flutter/material.dart';

import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_sesion.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_opciones_acceso.dart';
import 'package:boom/modulos/paciente/componentes/avatar_paciente.dart';
import 'package:boom/modulos/paciente/componentes/barra_navegacion_paciente.dart';
import 'package:boom/modulos/paciente/controladores/controlador_perfil_paciente.dart';
import 'package:boom/modulos/paciente/servicios/servicio_perfil_paciente.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_buscar_profesionales.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_inicio_paciente.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_mis_citas_paciente.dart';
import 'package:boom/nucleo/componentes/fondo_decorativo_bloom.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

/// Pantalla de consulta y edicion del perfil basico del paciente autenticado.
class PantallaPerfilPaciente extends StatefulWidget {
  final PerfilUsuario? perfilInicial;
  final ServicioPerfilPaciente servicio;
  final ServicioSesion servicioSesion;
  final ValueChanged<PerfilUsuario>? alActualizarPerfil;

  const PantallaPerfilPaciente({
    super.key,
    this.perfilInicial,
    this.servicio = const ServicioPerfilPaciente(),
    this.servicioSesion = const ServicioSesion(),
    this.alActualizarPerfil,
  });

  @override
  State<PantallaPerfilPaciente> createState() => _PantallaPerfilPacienteState();
}

class _PantallaPerfilPacienteState extends State<PantallaPerfilPaciente> {
  final _claveFormulario = GlobalKey<FormState>();
  late final TextEditingController _controladorNombre;
  late final TextEditingController _controladorApellido;
  late final ControladorPerfilPaciente _controlador;

  @override
  void initState() {
    super.initState();
    _controladorNombre = TextEditingController(
      text: widget.perfilInicial?.nombre ?? '',
    );
    _controladorApellido = TextEditingController(
      text: widget.perfilInicial?.apellido ?? '',
    );
    _controlador = ControladorPerfilPaciente(
      servicio: widget.servicio,
      servicioSesion: widget.servicioSesion,
      perfilInicial: widget.perfilInicial,
    );
    _controlador.addListener(_actualizarVista);
    if (widget.perfilInicial == null) {
      unawaited(_cargarDesdeServidor());
    }
  }

  Future<void> _cargarDesdeServidor() async {
    final perfil = await _controlador.cargarPerfil();
    if (!mounted || perfil == null) return;
    _controladorNombre.text = perfil.nombre;
    _controladorApellido.text = perfil.apellido;
    widget.alActualizarPerfil?.call(perfil);
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
    _controladorNombre.dispose();
    _controladorApellido.dispose();
    super.dispose();
  }

  Future<void> _guardarCambios() async {
    if (_controlador.ocupado ||
        !(_claveFormulario.currentState?.validate() ?? false)) {
      return;
    }
    FocusScope.of(context).unfocus();

    final exito = await _controlador.guardarPerfil(
      nombre: _controladorNombre.text,
      apellido: _controladorApellido.text,
    );
    if (!mounted) return;

    final perfilActualizado = _controlador.perfil;
    if (exito && perfilActualizado != null) {
      _controladorNombre.text = perfilActualizado.nombre;
      _controladorApellido.text = perfilActualizado.apellido;
      widget.alActualizarPerfil?.call(perfilActualizado);
      _mostrarMensaje(
        _controlador.mensajeExito ?? 'Perfil actualizado correctamente.',
        esError: false,
      );
    } else if (_controlador.mensajeError != null) {
      _mostrarMensaje(_controlador.mensajeError!, esError: true);
    }
  }

  Future<void> _confirmarCierreSesion() async {
    if (_controlador.ocupado) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (contextoDialogo) => AlertDialog(
        backgroundColor: TemaPsicobloom.colorSuperficie,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Cerrar sesión'),
        content: const Text('¿Deseas cerrar tu sesión actual en PsicoBloom?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contextoDialogo, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: TemaPsicobloom.colorError,
              minimumSize: const Size(120, 42),
            ),
            onPressed: () => Navigator.pop(contextoDialogo, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;
    await _controlador.cerrarSesion();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(builder: (_) => const PantallaOpcionesAcceso()),
      (_) => false,
    );
  }

  void _mostrarMensaje(String texto, {required bool esError}) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: esError
            ? TemaPsicobloom.colorError
            : TemaPsicobloom.colorExito,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          texto,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }

  void _gestionarCambioPestana(int nuevoIndice) {
    if (nuevoIndice == 4 || _controlador.ocupado) return;
    final perfil = _controlador.perfil ?? widget.perfilInicial;

    switch (nuevoIndice) {
      case 0:
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => PantallaInicioPaciente(
                nombrePaciente: perfil?.nombre ?? 'Paciente',
                perfilInicial: perfil,
                servicioSesion: widget.servicioSesion,
              ),
            ),
          );
        }
        break;
      case 1:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const PantallaBuscarProfesionales(),
          ),
        );
        break;
      case 2:
        _mostrarMensaje(
          'El Mapa interactivo de profesionales se encuentra en la pestaña de consulta.',
          esError: false,
        );
        break;
      case 3:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => PantallaMisCitasPaciente(
              perfilInicial: perfil,
              servicioSesion: widget.servicioSesion,
            ),
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final perfil = _controlador.perfil ?? widget.perfilInicial;
    final correoMostrado = (perfil?.correo.isNotEmpty ?? false)
        ? perfil!.correo
        : 'Sincronizado con tu cuenta de acceso';

    return Scaffold(
      backgroundColor: TemaPsicobloom.colorFondo,
      bottomNavigationBar: BarraNavegacionPaciente(
        indiceSeleccionado: 4,
        alCambiarPestana: _gestionarCambioPestana,
      ),
      body: FondoDecorativoBloom(
        mostrarHojas: false,
        mostrarCorazones: false,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: 20.0,
              vertical: 16.0,
            ),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Mi perfil',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: TemaPsicobloom.colorTexto,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Recargar perfil',
                    onPressed: _controlador.ocupado
                        ? null
                        : _cargarDesdeServidor,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_controlador.estaCargando)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: TemaPsicobloom.colorPrincipal,
                    ),
                  ),
                )
              else ...[
                _construirTarjetaEncabezado(perfil, correoMostrado),
                const SizedBox(height: 20),
                _construirFormularioDatos(correoMostrado),
                const SizedBox(height: 20),
                _construirSeccionSesion(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _seleccionarFotoGaleria() async {
    FocusScope.of(context).unfocus();
    final seleccionada = await _controlador.seleccionarFotografiaVistaPrevia();
    if (!mounted) return;
    if (!seleccionada && _controlador.mensajeErrorFoto != null) {
      _mostrarMensaje(_controlador.mensajeErrorFoto!, esError: true);
    }
  }

  void _cancelarVistaPreviaFoto() {
    _controlador.cancelarSeleccionFotografia();
  }

  String? _resolverFotoActual(PerfilUsuario? perfil) {
    final fotoPerfil = perfil?.fotoUrl?.trim();
    if (fotoPerfil != null && fotoPerfil.isNotEmpty) {
      return fotoPerfil;
    }
    final fotoSesion = widget.servicioSesion.obtenerFotoUsuarioActual()?.trim();
    if (fotoSesion != null && fotoSesion.isNotEmpty) {
      return fotoSesion;
    }
    return null;
  }

  Widget _construirTarjetaEncabezado(
    PerfilUsuario? perfil,
    String correoMostrado,
  ) {
    final nombre = perfil?.nombreCompleto.isNotEmpty == true
        ? perfil!.nombreCompleto
        : 'Paciente PsicoBloom';
    final fotoActual = _resolverFotoActual(perfil);
    final vistaPrevia = _controlador.fotoVistaPrevia;

    return Container(
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
              AvatarPaciente(
                key: const Key('avatarPacientePerfil'),
                nombreCompleto: nombre,
                fotoUrl: fotoActual,
                bytesVistaPrevia: vistaPrevia?.bytes,
                diametro: 72,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: TemaPsicobloom.colorTexto,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      correoMostrado,
                      style: const TextStyle(
                        fontSize: 13,
                        color: TemaPsicobloom.colorTextoSecundario,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: TemaPsicobloom.colorFondoExito,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Rol: Paciente • Cuenta activa',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: TemaPsicobloom.colorExito,
                            ),
                          ),
                        ),
                        if (vistaPrevia != null)
                          Container(
                            key: const Key('insigniaVistaPreviaFoto'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: TemaPsicobloom.colorFondoAdvertencia,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: TemaPsicobloom.colorAdvertencia
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Text(
                              'Vista previa local (sin guardar)',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: TemaPsicobloom.colorAdvertencia,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: TemaPsicobloom.colorBorde),
          const SizedBox(height: 14),
          const Text(
            'Fotografía de perfil',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            vistaPrevia != null
                ? 'Estás viendo una vista previa local${vistaPrevia.nombreArchivo != null && vistaPrevia.nombreArchivo!.trim().isNotEmpty ? ' (${vistaPrevia.nombreArchivo!.trim()})' : ''}. Formatos admitidos: JPG o PNG (máximo 5 MB).'
                : 'Selecciona una fotografía JPG o PNG (máximo 5 MB) desde tu galería para previsualizar cómo se verá en tu perfil.',
            style: const TextStyle(
              fontSize: 12.5,
              color: TemaPsicobloom.colorTextoSecundario,
              height: 1.35,
            ),
          ),
          if (_controlador.mensajeErrorFoto != null) ...[
            const SizedBox(height: 10),
            Container(
              key: const Key('errorFotografiaPaciente'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: TemaPsicobloom.colorFondoError,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: TemaPsicobloom.colorError,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _controlador.mensajeErrorFoto!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: TemaPsicobloom.colorError,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, restricciones) {
              final enFila = restricciones.maxWidth >= 420;
              final botonSeleccionar = OutlinedButton.icon(
                key: const Key('botonSeleccionarFotoPaciente'),
                onPressed: _controlador.ocupado
                    ? null
                    : _seleccionarFotoGaleria,
                icon: _controlador.estaSeleccionandoFoto
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: TemaPsicobloom.colorPrincipal,
                        ),
                      )
                    : Icon(
                        vistaPrevia != null
                            ? Icons.swap_horiz_rounded
                            : Icons.photo_library_outlined,
                        size: 18,
                      ),
                label: Text(
                  _controlador.estaSeleccionandoFoto
                      ? 'Abriendo galería...'
                      : vistaPrevia != null
                      ? 'Elegir otra foto'
                      : 'Seleccionar de la galería',
                ),
              );

              final botonCancelar = vistaPrevia != null
                  ? OutlinedButton.icon(
                      key: const Key('botonCancelarFotoPaciente'),
                      onPressed: _controlador.ocupado
                          ? null
                          : _cancelarVistaPreviaFoto,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: TemaPsicobloom.colorTextoSecundario,
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Cancelar selección'),
                    )
                  : null;

              if (botonCancelar == null) {
                return SizedBox(
                  width: double.infinity,
                  child: botonSeleccionar,
                );
              }
              if (enFila) {
                return Row(
                  children: [
                    Expanded(child: botonSeleccionar),
                    const SizedBox(width: 10),
                    Expanded(child: botonCancelar),
                  ],
                );
              }
              return Column(
                children: [
                  SizedBox(width: double.infinity, child: botonSeleccionar),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: botonCancelar),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, restricciones) {
              final enFila = restricciones.maxWidth >= 420;
              const botonGuardarDeshabilitado = ElevatedButton(
                key: Key('botonGuardarFotoPaciente'),
                onPressed: null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_upload_outlined, size: 18),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Guardar fotografía',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
              const botonEliminarDeshabilitado = OutlinedButton(
                key: Key('botonEliminarFotoPaciente'),
                onPressed: null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.delete_outline_rounded, size: 18),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Eliminar fotografía',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );

              if (enFila) {
                return const Row(
                  children: [
                    Expanded(child: botonGuardarDeshabilitado),
                    SizedBox(width: 10),
                    Expanded(child: botonEliminarDeshabilitado),
                  ],
                );
              }
              return const Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: botonGuardarDeshabilitado,
                  ),
                  SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: botonEliminarDeshabilitado,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Container(
            key: const Key('avisoAlmacenamientoFotoPendiente'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: TemaPsicobloom.colorFondoInformacion,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: TemaPsicobloom.colorInformacion.withValues(alpha: 0.25),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: TemaPsicobloom.colorInformacion,
                  size: 18,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Guardar y eliminar fotografía requieren integrar el almacenamiento en Supabase y Cloudinary en una etapa posterior. Tu fotografía actual no se modifica.',
                    style: TextStyle(
                      fontSize: 12,
                      color: TemaPsicobloom.colorTexto,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirFormularioDatos(String correoMostrado) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Form(
        key: _claveFormulario,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Datos personales',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: TemaPsicobloom.colorTexto,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Actualiza tu nombre y apellido. Los cambios se guardan directamente en Supabase.',
              style: TextStyle(
                fontSize: 13,
                color: TemaPsicobloom.colorTextoSecundario,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Nombre',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: TemaPsicobloom.colorTexto,
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('campoNombrePaciente'),
              controller: _controladorNombre,
              enabled: !_controlador.ocupado,
              decoration: const InputDecoration(
                hintText: 'Ingresa tu nombre',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (valor) =>
                  ControladorPerfilPaciente.validarNombreOApellido(
                    valor,
                    'nombre',
                  ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Apellido',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: TemaPsicobloom.colorTexto,
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('campoApellidoPaciente'),
              controller: _controladorApellido,
              enabled: !_controlador.ocupado,
              decoration: const InputDecoration(
                hintText: 'Ingresa tu apellido',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              validator: (valor) =>
                  ControladorPerfilPaciente.validarNombreOApellido(
                    valor,
                    'apellido',
                  ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Correo electrónico (gestionado por Supabase Auth)',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: TemaPsicobloom.colorTexto,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: TemaPsicobloom.colorFondo,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: TemaPsicobloom.colorBorde),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.mail_outline_rounded,
                    color: TemaPsicobloom.colorTextoSecundario,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      correoMostrado,
                      style: const TextStyle(
                        fontSize: 14,
                        color: TemaPsicobloom.colorTextoSecundario,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_controlador.mensajeError != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: TemaPsicobloom.colorFondoError,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: TemaPsicobloom.colorError,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _controlador.mensajeError!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: TemaPsicobloom.colorError,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_controlador.mensajeExito != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: TemaPsicobloom.colorFondoExito,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      color: TemaPsicobloom.colorExito,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _controlador.mensajeExito!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: TemaPsicobloom.colorExito,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton.icon(
              key: const Key('botonGuardarPerfilPaciente'),
              onPressed: _controlador.ocupado ? null : _guardarCambios,
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
                    ? 'Guardando cambios...'
                    : 'Guardar cambios',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirSeccionSesion() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Seguridad y sesión',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Al cerrar sesión se limpiarán tus datos temporales en este dispositivo.',
            style: TextStyle(
              fontSize: 13,
              color: TemaPsicobloom.colorTextoSecundario,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const Key('botonCerrarSesionPaciente'),
            onPressed: _controlador.ocupado ? null : _confirmarCierreSesion,
            style: OutlinedButton.styleFrom(
              foregroundColor: TemaPsicobloom.colorError,
              side: const BorderSide(
                color: TemaPsicobloom.colorError,
                width: 1.2,
              ),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: Text(
              _controlador.estaCerrandoSesion
                  ? 'Cerrando sesión...'
                  : 'Cerrar sesión',
            ),
          ),
        ],
      ),
    );
  }
}
