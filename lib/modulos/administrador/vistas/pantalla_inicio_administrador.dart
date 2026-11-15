import 'dart:async';

import 'package:flutter/material.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/administrador/controladores/controlador_administracion.dart';
import 'package:boom/modulos/administrador/servicios/servicio_administracion.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_sesion.dart';
import 'package:boom/modulos/autenticacion/vistas/navegador_roles.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_opciones_acceso.dart';
import 'package:boom/nucleo/componentes/fondo_decorativo_bloom.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

/// Inicio funcional del rol Administrador acorde a esta etapa.
/// Permite revisar solicitudes de profesionales pendientes y cerrar sesion.
class PantallaInicioAdministrador extends StatefulWidget {
  final PerfilUsuario perfilInicial;
  final ServicioSesion servicioSesion;
  final ServicioAdministracion servicioAdministracion;

  const PantallaInicioAdministrador({
    super.key,
    required this.perfilInicial,
    this.servicioSesion = const ServicioSesion(),
    this.servicioAdministracion = const ServicioAdministracion(),
  });

  @override
  State<PantallaInicioAdministrador> createState() =>
      _PantallaInicioAdministradorState();
}

class _PantallaInicioAdministradorState
    extends State<PantallaInicioAdministrador> {
  late final ControladorAdministracion _controlador;
  bool _estaCerrandoSesion = false;

  @override
  void initState() {
    super.initState();
    _controlador = ControladorAdministracion(
      servicio: widget.servicioAdministracion,
    );
    _controlador.addListener(_actualizarVista);
    if (ConfiguracionSupabase.estaConfigurado ||
        widget.servicioAdministracion.runtimeType != ServicioAdministracion) {
      unawaited(_controlador.cargarPendientes());
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
    _controlador.dispose();
    super.dispose();
  }

  Future<void> _cerrarSesion() async {
    if (_estaCerrandoSesion || _controlador.ocupado) return;
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

  Future<void> _aprobar(ProfesionalPendienteRevision solicitud) async {
    await _controlador.decidirSolicitud(
      profesionalId: solicitud.idUsuario,
      aprobar: true,
    );
  }

  Future<void> _rechazar(ProfesionalPendienteRevision solicitud) async {
    var textoMotivo = '';
    String? errorValidacionMotivo;
    final motivo = await showDialog<String>(
      context: context,
      builder: (contextoDialogo) => StatefulBuilder(
        builder: (contextoEstado, actualizarEstadoDialogo) => AlertDialog(
          backgroundColor: TemaPsicobloom.colorSuperficie,
          title: const Text('Rechazar solicitud'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profesional: ${solicitud.nombreCompleto}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: TemaPsicobloom.colorTextoSecundario,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  onChanged: (valor) {
                    textoMotivo = valor;
                    if (errorValidacionMotivo != null) {
                      actualizarEstadoDialogo(() {
                        errorValidacionMotivo = null;
                      });
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Motivo de rechazo (mínimo 5 caracteres)',
                    errorText: errorValidacionMotivo,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(contextoDialogo),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final texto = textoMotivo.trim();
                if (texto.length < 5) {
                  actualizarEstadoDialogo(() {
                    errorValidacionMotivo =
                        'Indica un motivo de rechazo de al menos 5 caracteres.';
                  });
                  return;
                }
                Navigator.pop(contextoDialogo, texto);
              },
              child: const Text('Confirmar rechazo'),
            ),
          ],
        ),
      ),
    );

    if (motivo == null || !mounted) return;
    await _controlador.decidirSolicitud(
      profesionalId: solicitud.idUsuario,
      aprobar: false,
      motivo: motivo,
    );
  }

  @override
  Widget build(BuildContext context) {
    return NavegadorRoles.protegerPorRol(
      perfil: widget.perfilInicial,
      rolRequerido: 'administrador',
      servicioSesion: widget.servicioSesion,
      constructorContenido: (perfilValido) {
        return PopScope(
          canPop: false,
          child: Scaffold(
            backgroundColor: TemaPsicobloom.colorFondo,
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: const Text('Administración PsicoBloom'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Actualizar solicitudes',
                  onPressed: _controlador.ocupado
                      ? null
                      : _controlador.cargarPendientes,
                ),
                IconButton(
                  key: const Key('botonCerrarSesionAdministrador'),
                  icon: const Icon(Icons.logout_rounded),
                  tooltip: 'Cerrar sesión',
                  onPressed: _estaCerrandoSesion ? null : _cerrarSesion,
                ),
              ],
            ),
            body: FondoDecorativoBloom(
              mostrarHojas: false,
              child: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(20.0),
                  children: [
                    _construirCabeceraAdmin(perfilValido),
                    const SizedBox(height: 20),
                    const Text(
                      'Solicitudes profesionales pendientes',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: TemaPsicobloom.colorTexto,
                      ),
                    ),
                    const SizedBox(height: 12),
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
                    if (_controlador.mensajeExito != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: TemaPsicobloom.colorFondoExito,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _controlador.mensajeExito!,
                          style: const TextStyle(
                            color: TemaPsicobloom.colorExito,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_controlador.estaCargando)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: TemaPsicobloom.colorPrincipal,
                          ),
                        ),
                      )
                    else if (_controlador.pendientes.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: TemaPsicobloom.colorSuperficie,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: TemaPsicobloom.colorBorde),
                        ),
                        child: const Text(
                          'No hay solicitudes profesionales pendientes de revisión en este momento.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: TemaPsicobloom.colorTextoSecundario,
                          ),
                        ),
                      )
                    else
                      ..._controlador.pendientes.map(
                        (solicitud) => Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: _construirTarjetaSolicitud(solicitud),
                        ),
                      ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _estaCerrandoSesion ? null : _cerrarSesion,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: TemaPsicobloom.colorError,
                        side: const BorderSide(
                          color: TemaPsicobloom.colorError,
                          width: 1.2,
                        ),
                      ),
                      icon: const Icon(Icons.logout_rounded),
                      label: Text(
                        _estaCerrandoSesion
                            ? 'Cerrando sesión...'
                            : 'Cerrar sesión',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _construirCabeceraAdmin(PerfilUsuario perfil) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: const BoxDecoration(
              color: TemaPsicobloom.colorLavanda,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: TemaPsicobloom.colorPrincipalOscuro,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  perfil.nombreCompleto,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Rol: Administrador • Cuenta autorizada',
                  style: TextStyle(
                    fontSize: 13,
                    color: TemaPsicobloom.colorSecundario,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirTarjetaSolicitud(ProfesionalPendienteRevision solicitud) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            solicitud.nombreCompleto,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            solicitud.correo,
            style: const TextStyle(
              fontSize: 13,
              color: TemaPsicobloom.colorTextoSecundario,
            ),
          ),
          if (solicitud.especialidad != null &&
              solicitud.especialidad!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Especialidad: ${solicitud.especialidad}',
              style: const TextStyle(
                fontSize: 13,
                color: TemaPsicobloom.colorTexto,
              ),
            ),
          ],
          if (solicitud.numeroRegistro != null &&
              solicitud.numeroRegistro!.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Registro profesional: ${solicitud.numeroRegistro}',
              style: const TextStyle(
                fontSize: 13,
                color: TemaPsicobloom.colorTexto,
              ),
            ),
          ],
          if (solicitud.creadoEn != null) ...[
            const SizedBox(height: 2),
            Text(
              'Solicitud registrada: ${_formatearFechaSolicitud(solicitud.creadoEn!)}',
              style: const TextStyle(
                fontSize: 12,
                color: TemaPsicobloom.colorTextoSecundario,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _controlador.ocupado
                      ? null
                      : () => _rechazar(solicitud),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: TemaPsicobloom.colorError,
                    side: const BorderSide(color: TemaPsicobloom.colorError),
                    minimumSize: const Size.fromHeight(42),
                  ),
                  child: const Text('Rechazar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _controlador.ocupado
                      ? null
                      : () => _aprobar(solicitud),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TemaPsicobloom.colorExito,
                    minimumSize: const Size.fromHeight(42),
                  ),
                  child: const Text('Aprobar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatearFechaSolicitud(DateTime fecha) {
    final local = fecha.toLocal();
    final dia = local.day.toString().padLeft(2, '0');
    final mes = local.month.toString().padLeft(2, '0');
    final anio = local.year.toString();
    return '$dia/$mes/$anio';
  }
}
