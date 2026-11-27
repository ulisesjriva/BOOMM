import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modelos/adelanto_cita.dart';
import 'package:boom/modelos/especialidad.dart';
import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/administrador/controladores/controlador_administracion.dart';
import 'package:boom/modulos/administrador/modelos/modelos_administracion.dart';
import 'package:boom/modulos/administrador/servicios/servicio_administracion.dart';
import 'package:boom/modulos/administrador/vistas/componentes_administracion.dart';
import 'package:boom/modulos/administrador/vistas/pantalla_mantenimiento_administracion.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_sesion.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_opciones_acceso.dart';
import 'package:boom/nucleo/componentes/fondo_decorativo_bloom.dart';
import 'package:boom/nucleo/servicios/servicio_adelantos_citas.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

/// Modulo completo de Administracion de PsicoBloom con navegacion en 5 pestanas:
/// Inicio (Panel general), Usuarios, Profesionales, Especialidades y Citas.
class PantallaInicioAdministrador extends StatefulWidget {
  final PerfilUsuario perfilInicial;
  final ServicioSesion servicioSesion;
  final ServicioAdministracion servicioAdministracion;
  final ServicioAdelantosCitas servicioAdelantos;

  const PantallaInicioAdministrador({
    super.key,
    required this.perfilInicial,
    this.servicioSesion = const ServicioSesion(),
    this.servicioAdministracion = const ServicioAdministracion(),
    this.servicioAdelantos = const ServicioAdelantosCitas(),
  });

  @override
  State<PantallaInicioAdministrador> createState() =>
      _PantallaInicioAdministradorState();
}

class _PantallaInicioAdministradorState
    extends State<PantallaInicioAdministrador> {
  late final ControladorAdministracion _controlador;
  final TextEditingController _controladorBusquedaUsuario =
      TextEditingController();

  int _indicePestana = 0;
  bool _estaCerrandoSesion = false;
  Map<String, ResumenAdelantoCita> _adelantosCitas = const {};
  String? _errorAdelantosAdmin;

  Future<void> _cargarResumenAdelantosAdmin() async {
    try {
      final mapa = await widget.servicioAdelantos
          .listarResumenAdelantosVisibles();
      if (mounted) {
        setState(() {
          _adelantosCitas = mapa;
          _errorAdelantosAdmin = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorAdelantosAdmin = ServicioAdelantosCitas.explicarError(error);
        });
      }
    }
  }

  Future<void> _recargarCitasYAdelantosAdmin() async {
    await Future.wait([
      _controlador.cargarCitas(reiniciar: true),
      _cargarResumenAdelantosAdmin(),
    ]);
  }

  bool get _esAdministrador => widget.perfilInicial.rol == 'administrador';

  bool get _debeCargar =>
      ConfiguracionSupabase.estaConfigurado ||
      widget.servicioAdministracion.ejecutorRpc != null ||
      widget.servicioAdministracion.runtimeType != ServicioAdministracion;

  @override
  void initState() {
    super.initState();
    _controlador = ControladorAdministracion(
      servicio: widget.servicioAdministracion,
    );
    _controlador.addListener(_actualizarVista);
    if (_esAdministrador && _debeCargar) {
      unawaited(_inicializarInicio());
    }
  }

  Future<void> _inicializarInicio() async {
    await _controlador.cargarPendientes();
    if (!mounted) return;
    if (ConfiguracionSupabase.estaConfigurado ||
        widget.servicioAdministracion.ejecutorRpc != null) {
      await _controlador.cargarResumen();
    }
  }

  void _actualizarVista() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controladorBusquedaUsuario.dispose();
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

  void _cambiarPestana(int nuevoIndice) {
    if (_indicePestana == nuevoIndice) return;
    _controlador.limpiarMensajes();
    setState(() => _indicePestana = nuevoIndice);
    if (!_debeCargar) return;

    switch (nuevoIndice) {
      case 0:
        unawaited(_inicializarInicio());
        break;
      case 1:
        if (_controlador.usuarios.isEmpty) {
          unawaited(_controlador.cargarUsuarios(reiniciar: true));
        }
        break;
      case 2:
        if (_controlador.profesionales.isEmpty) {
          unawaited(_controlador.cargarProfesionales());
        }
        break;
      case 3:
        if (_controlador.especialidades.isEmpty) {
          unawaited(_controlador.cargarEspecialidades());
        }
        break;
      case 4:
        if (_controlador.citas.isEmpty) {
          unawaited(_controlador.cargarCitas(reiniciar: true));
        }
        unawaited(_cargarResumenAdelantosAdmin());
        break;
    }
  }

  void _abrirMantenimiento() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PantallaMantenimientoAdministracion(
          alAbrirEspecialidades: () => _cambiarPestana(3),
          alAbrirProfesionalesDeshabilitados: () {
            setState(() => _indicePestana = 2);
            unawaited(
              _controlador.cargarProfesionales(estado: 'deshabilitado'),
            );
          },
          alAbrirUsuariosParaCorreccion: () => _cambiarPestana(1),
        ),
      ),
    );
  }

  Future<void> _aprobar(String idUsuario) async {
    final ok = await _controlador.decidirSolicitud(
      profesionalId: idUsuario,
      aprobar: true,
    );
    if (ok && mounted && _controlador.resumen != null) {
      unawaited(_controlador.cargarResumen());
    }
  }

  Future<void> _rechazar({
    required String idUsuario,
    required String nombreCompleto,
  }) async {
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
                  'Profesional: $nombreCompleto',
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
    final ok = await _controlador.decidirSolicitud(
      profesionalId: idUsuario,
      aprobar: false,
      motivo: motivo,
    );
    if (ok && mounted && _controlador.resumen != null) {
      unawaited(_controlador.cargarResumen());
    }
  }

  Future<void> _confirmarCambioEstadoCuenta({
    required String usuarioId,
    required String nombreCuenta,
    required String correoCuenta,
    required bool activar,
  }) async {
    var motivo = '';
    String? errorMotivo;
    final confirmado = await showDialog<String>(
      context: context,
      builder: (contextoDialogo) => StatefulBuilder(
        builder: (contextoEstado, actualizarEstado) => AlertDialog(
          backgroundColor: TemaPsicobloom.colorSuperficie,
          title: Text(activar ? 'Reactivar cuenta' : 'Desactivar cuenta'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cuenta afectada: $nombreCuenta ($correoCuenta)',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  activar
                      ? 'La cuenta volverá a tener acceso según su rol. Si es profesional, conservará su estado de aprobación previo (no se aprueba automáticamente).'
                      : 'La cuenta quedará restringida en el servidor conservando su perfil, citas y relaciones históricas.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: TemaPsicobloom.colorTextoSecundario,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (valor) {
                    motivo = valor;
                    if (errorMotivo != null) {
                      actualizarEstado(() => errorMotivo = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Motivo administrativo (mín. 5 caracteres)',
                    errorText: errorMotivo,
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
              style: ElevatedButton.styleFrom(
                backgroundColor: activar
                    ? TemaPsicobloom.colorSecundario
                    : TemaPsicobloom.colorError,
              ),
              onPressed: () {
                final limpio = motivo.trim();
                if (limpio.length < 5) {
                  actualizarEstado(
                    () => errorMotivo =
                        'Ingresa un motivo de al menos 5 caracteres.',
                  );
                  return;
                }
                Navigator.pop(contextoDialogo, limpio);
              },
              child: Text(activar ? 'Confirmar reactivación' : 'Desactivar'),
            ),
          ],
        ),
      ),
    );

    if (confirmado == null || !mounted) return;
    await _controlador.cambiarEstadoCuenta(
      usuarioId: usuarioId,
      activo: activar,
      motivo: confirmado,
    );
  }

  Future<void> _mostrarDialogoCorreccionUsuario(
    UsuarioAdministracion usuario,
  ) async {
    final ctrlNombre = TextEditingController(text: usuario.nombre);
    final ctrlApellido = TextEditingController(text: usuario.apellido);
    final ctrlRegistro = TextEditingController();
    String? errorLocal;

    final guardado = await showDialog<bool>(
      context: context,
      builder: (contextoDialogo) => StatefulBuilder(
        builder: (contextoEstado, actualizarEstado) => AlertDialog(
          backgroundColor: TemaPsicobloom.colorSuperficie,
          title: const Text('Corregir datos de cuenta'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrlNombre,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrlApellido,
                  decoration: const InputDecoration(labelText: 'Apellido'),
                ),
                if (usuario.rol == 'profesional') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: ctrlRegistro,
                    decoration: const InputDecoration(
                      labelText: 'Número de registro (opcional)',
                    ),
                  ),
                ],
                if (errorLocal != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorLocal!,
                    style: const TextStyle(
                      color: TemaPsicobloom.colorError,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(contextoDialogo, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (ctrlNombre.text.trim().length < 2 ||
                    ctrlApellido.text.trim().length < 2) {
                  actualizarEstado(
                    () => errorLocal =
                        'Nombre y apellido requieren al menos 2 caracteres.',
                  );
                  return;
                }
                final ok = await _controlador.corregirDatosUsuario(
                  usuarioId: usuario.id,
                  nombre: ctrlNombre.text,
                  apellido: ctrlApellido.text,
                  numeroRegistro: usuario.rol == 'profesional'
                      ? ctrlRegistro.text
                      : null,
                );
                if (!contextoDialogo.mounted) return;
                if (ok) {
                  Navigator.pop(contextoDialogo, true);
                } else {
                  actualizarEstado(
                    () => errorLocal = _controlador.mensajeError,
                  );
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    ctrlNombre.dispose();
    ctrlApellido.dispose();
    ctrlRegistro.dispose();

    if (guardado == true && mounted) {
      unawaited(_controlador.cargarUsuarios(reiniciar: true));
    }
  }

  Future<void> _mostrarDialogoEspecialidad([Especialidad? existente]) async {
    final ctrlNombre = TextEditingController(text: existente?.nombre ?? '');
    final ctrlDescripcion = TextEditingController(
      text: existente?.descripcion ?? '',
    );
    String? errorLocal;

    final guardada = await showDialog<bool>(
      context: context,
      builder: (contextoDialogo) => StatefulBuilder(
        builder: (contextoEstado, actualizarEstado) => AlertDialog(
          backgroundColor: TemaPsicobloom.colorSuperficie,
          title: Text(
            existente == null ? 'Nueva especialidad' : 'Editar especialidad',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('campoNombreEspecialidad'),
                  controller: ctrlNombre,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la especialidad',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('campoDescripcionEspecialidad'),
                  controller: ctrlDescripcion,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Descripción (opcional)',
                  ),
                ),
                if (errorLocal != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorLocal!,
                    style: const TextStyle(
                      color: TemaPsicobloom.colorError,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(contextoDialogo, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              key: const Key('botonGuardarEspecialidad'),
              onPressed: () async {
                final limpio = ctrlNombre.text.trim().replaceAll(
                  RegExp(r'\s+'),
                  ' ',
                );
                if (limpio.length < 3) {
                  actualizarEstado(
                    () => errorLocal =
                        'El nombre debe tener al menos 3 caracteres.',
                  );
                  return;
                }
                final duplicadoLocal = _controlador.especialidades.any(
                  (e) =>
                      e.nombre
                              .trim()
                              .replaceAll(RegExp(r'\s+'), ' ')
                              .toLowerCase() ==
                          limpio.toLowerCase() &&
                      e.id != existente?.id,
                );
                if (duplicadoLocal) {
                  actualizarEstado(
                    () => errorLocal =
                        'Ya existe una especialidad registrada con ese nombre.',
                  );
                  return;
                }
                final ok = await _controlador.guardarEspecialidad(
                  idEspecialidad: existente?.id,
                  nombre: limpio,
                  descripcion: ctrlDescripcion.text,
                );
                if (!contextoDialogo.mounted) return;
                if (ok) {
                  Navigator.pop(contextoDialogo, true);
                } else {
                  actualizarEstado(
                    () => errorLocal = _controlador.mensajeError,
                  );
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    ctrlNombre.dispose();
    ctrlDescripcion.dispose();
    if (guardada == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _exportarCitasCsv() async {
    final csv = _controlador.generarCsvCitas();
    unawaited(Clipboard.setData(ClipboardData(text: csv)).catchError((_) {}));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (contextoDialogo) => AlertDialog(
        backgroundColor: TemaPsicobloom.colorSuperficie,
        title: const Text('Exportación CSV lista'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Se generó el CSV con ${_controlador.citas.length} citas y se intentó copiar al portapapeles.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: TemaPsicobloom.colorFondo,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: TemaPsicobloom.colorBorde),
                ),
                child: SelectableText(
                  csv,
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(contextoDialogo),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_esAdministrador) {
      return Scaffold(
        body: FondoDecorativoBloom(
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 48,
                      color: TemaPsicobloom.colorError,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Acceso restringido',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: TemaPsicobloom.colorTexto,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Esta sección está disponible únicamente para cuentas de administrador.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: TemaPsicobloom.colorTextoSecundario,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: _cerrarSesion,
                      child: const Text('Cerrar sesión'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: TemaPsicobloom.colorFondo,
      body: FondoDecorativoBloom(
        child: SafeArea(
          child: Column(
            children: [
              _construirCabecera(),
              if (_controlador.mensajeError != null)
                _construirBanner(
                  mensaje: _controlador.mensajeError!,
                  esError: true,
                ),
              if (_controlador.mensajeExito != null)
                _construirBanner(
                  mensaje: _controlador.mensajeExito!,
                  esError: false,
                ),
              Expanded(
                child: IndexedStack(
                  index: _indicePestana,
                  children: [
                    _construirPestanaInicio(),
                    _construirPestanaUsuarios(),
                    _construirPestanaProfesionales(),
                    _construirPestanaEspecialidades(),
                    _construirPestanaCitas(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indicePestana,
        onDestinationSelected: _cambiarPestana,
        backgroundColor: TemaPsicobloom.colorSuperficie,
        indicatorColor: TemaPsicobloom.colorLavanda,
        destinations: const [
          NavigationDestination(
            key: Key('navAdmin_inicio'),
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Inicio',
          ),
          NavigationDestination(
            key: Key('navAdmin_usuarios'),
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Usuarios',
          ),
          NavigationDestination(
            key: Key('navAdmin_profesionales'),
            icon: Icon(Icons.medical_services_outlined),
            selectedIcon: Icon(Icons.medical_services_rounded),
            label: 'Profes.',
          ),
          NavigationDestination(
            key: Key('navAdmin_especialidades'),
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: 'Especial.',
          ),
          NavigationDestination(
            key: Key('navAdmin_citas'),
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today_rounded),
            label: 'Citas',
          ),
        ],
      ),
    );
  }

  Widget _construirCabecera() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: TemaPsicobloom.colorLavanda,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.admin_panel_settings_outlined,
              color: TemaPsicobloom.colorPrincipal,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Administración PsicoBloom',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorPrincipal,
                  ),
                ),
                Text(
                  widget.perfilInicial.nombreCompleto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: TemaPsicobloom.colorTextoSecundario,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('botonMantenimientoAdmin'),
            tooltip: 'Mantenimiento de información',
            onPressed: _abrirMantenimiento,
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            key: const Key('botonCerrarSesionAdministrador'),
            tooltip: 'Cerrar sesión',
            onPressed: _estaCerrandoSesion ? null : _cerrarSesion,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
    );
  }

  Widget _construirBanner({required String mensaje, required bool esError}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: esError
            ? TemaPsicobloom.colorFondoError
            : TemaPsicobloom.colorFondoExito,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        mensaje,
        style: TextStyle(
          fontSize: 13,
          color: esError
              ? TemaPsicobloom.colorError
              : TemaPsicobloom.colorExito,
        ),
      ),
    );
  }

  Widget _construirPestanaInicio() {
    final resumen = _controlador.resumen;

    return RefreshIndicator(
      onRefresh: _inicializarInicio,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        children: [
          const Text(
            'Panel de administración',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Resumen general del sistema',
            style: TextStyle(
              fontSize: 13.5,
              color: TemaPsicobloom.colorTextoSecundario,
            ),
          ),
          const SizedBox(height: 14),
          if (resumen != null) ...[
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.25,
              children: [
                TarjetaKpiAdministracion(
                  icono: Icons.people_outline_rounded,
                  colorIcono: TemaPsicobloom.colorPrincipal,
                  colorFondoIcono: TemaPsicobloom.colorLavanda,
                  etiqueta: 'Usuarios registrados',
                  valor: resumen.usuariosRegistrados,
                  alTocar: () => _cambiarPestana(1),
                ),
                TarjetaKpiAdministracion(
                  icono: Icons.verified_user_outlined,
                  colorIcono: TemaPsicobloom.colorSecundario,
                  colorFondoIcono: TemaPsicobloom.colorMenta,
                  etiqueta: 'Profesionales activos',
                  valor: resumen.profesionalesActivosAprobados,
                  alTocar: () => _cambiarPestana(2),
                ),
                TarjetaKpiAdministracion(
                  icono: Icons.pending_actions_outlined,
                  colorIcono: TemaPsicobloom.colorAdvertencia,
                  colorFondoIcono: TemaPsicobloom.colorFondoAdvertencia,
                  etiqueta: 'Prof. pendientes',
                  valor: resumen.profesionalesPendientes,
                  alTocar: () => _cambiarPestana(2),
                ),
                TarjetaKpiAdministracion(
                  icono: Icons.flag_outlined,
                  colorIcono: TemaPsicobloom.colorPrincipalOscuro,
                  colorFondoIcono: TemaPsicobloom.colorLavanda,
                  etiqueta: 'Solicitudes de cita',
                  valor: resumen.citasPendientes,
                  alTocar: () => _cambiarPestana(4),
                ),
                TarjetaKpiAdministracion(
                  icono: Icons.check_rounded,
                  colorIcono: TemaPsicobloom.colorExito,
                  colorFondoIcono: TemaPsicobloom.colorFondoExito,
                  etiqueta: 'Citas confirmadas',
                  valor: resumen.citasConfirmadas,
                  alTocar: () => _cambiarPestana(4),
                ),
                TarjetaKpiAdministracion(
                  icono: Icons.close_rounded,
                  colorIcono: TemaPsicobloom.colorError,
                  colorFondoIcono: TemaPsicobloom.colorFondoError,
                  etiqueta: 'Citas canceladas',
                  valor: resumen.citasCanceladas,
                  alTocar: () => _cambiarPestana(4),
                ),
              ],
            ),
            const SizedBox(height: 14),
            GraficoDonutCitas(resumen: resumen),
            const SizedBox(height: 16),
            const Text(
              'Actividad reciente',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: TemaPsicobloom.colorTexto,
              ),
            ),
            const SizedBox(height: 10),
            if (resumen.actividadReciente.isEmpty)
              const Text(
                'Sin actividad reciente registrada.',
                style: TextStyle(color: TemaPsicobloom.colorTextoSecundario),
              )
            else
              ...resumen.actividadReciente.map(
                (evento) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: TemaPsicobloom.colorSuperficie,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: TemaPsicobloom.colorBorde),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: TemaPsicobloom.colorLavanda,
                      child: Icon(
                        evento.tipo == 'solicitud_cita'
                            ? Icons.calendar_month_outlined
                            : evento.tipo == 'nuevo_profesional'
                            ? Icons.medical_services_outlined
                            : Icons.history_rounded,
                        color: TemaPsicobloom.colorPrincipal,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      evento.titulo,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      evento.detalle,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    trailing: evento.fecha != null
                        ? Text(
                            _formatearFechaCorta(evento.fecha!),
                            style: const TextStyle(
                              fontSize: 11,
                              color: TemaPsicobloom.colorTextoSecundario,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
          ],
          if (_controlador.pendientes.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Profesionales pendientes de revisión',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: TemaPsicobloom.colorTexto,
              ),
            ),
            const SizedBox(height: 10),
            ..._controlador.pendientes.map(
              (solicitud) => Container(
                margin: const EdgeInsets.only(bottom: 12),
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
                    if (solicitud.especialidad != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Especialidad: ${solicitud.especialidad}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                    if (solicitud.numeroRegistro != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Registro profesional: ${solicitud.numeroRegistro}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _controlador.ocupado
                                ? null
                                : () => _rechazar(
                                    idUsuario: solicitud.idUsuario,
                                    nombreCompleto: solicitud.nombreCompleto,
                                  ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: TemaPsicobloom.colorError,
                              minimumSize: const Size(0, 42),
                            ),
                            child: const Text('Rechazar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _controlador.ocupado
                                ? null
                                : () => _aprobar(solicitud.idUsuario),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(0, 42),
                            ),
                            child: const Text('Aprobar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ] else if (!_controlador.estaCargando) ...[
            const SizedBox(height: 12),
            const Text(
              'No hay solicitudes profesionales pendientes de revisión en este momento.',
              style: TextStyle(color: TemaPsicobloom.colorTextoSecundario),
            ),
            if (resumen == null) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _inicializarInicio,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _construirPestanaUsuarios() {
    return RefreshIndicator(
      onRefresh: () => _controlador.cargarUsuarios(reiniciar: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        children: [
          const Text(
            'Gestión de usuarios',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('buscadorUsuariosAdmin'),
            controller: _controladorBusquedaUsuario,
            onSubmitted: (valor) =>
                _controlador.cargarUsuarios(busqueda: valor, reiniciar: true),
            decoration: InputDecoration(
              hintText: 'Buscar por nombre o correo',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward_rounded),
                tooltip: 'Buscar',
                onPressed: () => _controlador.cargarUsuarios(
                  busqueda: _controladorBusquedaUsuario.text,
                  reiniciar: true,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final opcion in const [
                ('todos', 'Todos'),
                ('paciente', 'Pacientes'),
                ('profesional', 'Profesionales'),
              ])
                ChoiceChip(
                  key: Key('filtroRolUsuario_${opcion.$1}'),
                  label: Text(opcion.$2),
                  selected: _controlador.filtroRolUsuario == opcion.$1,
                  selectedColor: TemaPsicobloom.colorLavanda,
                  onSelected: (_) => _controlador.cargarUsuarios(
                    rol: opcion.$1,
                    reiniciar: true,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${_controlador.totalUsuarios} usuarios registrados',
            style: const TextStyle(
              fontSize: 12.5,
              color: TemaPsicobloom.colorTextoSecundario,
            ),
          ),
          const SizedBox(height: 10),
          if (_controlador.estaCargando && _controlador.usuarios.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_controlador.usuarios.isEmpty)
            _construirEstadoVacio(
              'No hay usuarios para el filtro actual.',
              () => _controlador.cargarUsuarios(reiniciar: true),
            )
          else
            ..._controlador.usuarios.map(
              (usuario) => Container(
                key: Key('tarjetaUsuarioAdmin_${usuario.id}'),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: TemaPsicobloom.colorSuperficie,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: TemaPsicobloom.colorBorde),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AvatarInicialesOFotoAdmin(
                          nombre: usuario.nombreCompleto,
                          fotoUrl: usuario.fotoUrl,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                usuario.nombreCompleto,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                ),
                              ),
                              Text(
                                usuario.correo,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: TemaPsicobloom.colorTextoSecundario,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  EtiquetaEstadoAdministracion(
                                    texto: usuario.rolLegible,
                                    colorTexto:
                                        TemaPsicobloom.colorPrincipalOscuro,
                                    colorFondo: TemaPsicobloom.colorLavanda,
                                  ),
                                  EtiquetaEstadoAdministracion.desdeCuenta(
                                    activa: usuario.cuentaActiva,
                                    rol: usuario.rol,
                                    aprobacion: usuario.aprobacion,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _controlador.ocupado
                                ? null
                                : () =>
                                      _mostrarDialogoCorreccionUsuario(usuario),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 38),
                            ),
                            child: const Text('Corregir datos'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            key: Key('botonEstadoCuenta_${usuario.id}'),
                            onPressed: _controlador.ocupado
                                ? null
                                : () => _confirmarCambioEstadoCuenta(
                                    usuarioId: usuario.id,
                                    nombreCuenta: usuario.nombreCompleto,
                                    correoCuenta: usuario.correo,
                                    activar: !usuario.cuentaActiva,
                                  ),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(0, 38),
                              backgroundColor: usuario.cuentaActiva
                                  ? TemaPsicobloom.colorError
                                  : TemaPsicobloom.colorSecundario,
                            ),
                            child: Text(
                              usuario.cuentaActiva ? 'Desactivar' : 'Reactivar',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (_controlador.hayMasUsuarios) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _controlador.estaCargando
                  ? null
                  : () => _controlador.cargarUsuarios(reiniciar: false),
              child: const Text('Cargar más usuarios'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _construirPestanaProfesionales() {
    return RefreshIndicator(
      onRefresh: () => _controlador.cargarProfesionales(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        children: [
          const Text(
            'Profesionales',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Gestiona aprobación y activación de profesionales.',
            style: TextStyle(
              fontSize: 13,
              color: TemaPsicobloom.colorTextoSecundario,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final filtro in const [
                ('todos', 'Todos'),
                ('pendiente', 'Pendientes'),
                ('aprobado', 'Aprobados'),
                ('rechazado', 'Rechazados'),
                ('deshabilitado', 'Deshabilitados'),
              ])
                ChoiceChip(
                  key: Key('filtroProfesional_${filtro.$1}'),
                  label: Text(filtro.$2),
                  selected: _controlador.filtroEstadoProfesional == filtro.$1,
                  selectedColor: TemaPsicobloom.colorLavanda,
                  onSelected: (_) =>
                      _controlador.cargarProfesionales(estado: filtro.$1),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_controlador.estaCargando && _controlador.profesionales.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_controlador.profesionales.isEmpty)
            _construirEstadoVacio(
              'No hay profesionales para este filtro.',
              () => _controlador.cargarProfesionales(),
            )
          else
            ..._controlador.profesionales.map(
              (prof) => Container(
                key: Key('tarjetaProfesionalAdmin_${prof.idUsuario}'),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: TemaPsicobloom.colorSuperficie,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: TemaPsicobloom.colorBorde),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AvatarInicialesOFotoAdmin(
                          nombre: prof.nombreCompleto,
                          fotoUrl: prof.fotoUrl,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                prof.nombreCompleto,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                prof.especialidad,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: TemaPsicobloom.colorTextoSecundario,
                                ),
                              ),
                            ],
                          ),
                        ),
                        EtiquetaEstadoAdministracion.desdeCuenta(
                          activa: prof.cuentaActiva,
                          rol: 'profesional',
                          aprobacion: prof.aprobacion,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Correo: ${prof.correo}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    if (prof.numeroRegistro != null &&
                        prof.numeroRegistro!.isNotEmpty)
                      Text(
                        'Registro: ${prof.numeroRegistro} · Modalidad: ${prof.modalidad}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    if (prof.direccionConsultorio != null &&
                        prof.direccionConsultorio!.isNotEmpty)
                      Text(
                        'Consultorio: ${prof.direccionConsultorio}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    if (prof.motivoRechazo != null &&
                        prof.motivoRechazo!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Motivo rechazo: ${prof.motivoRechazo}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: TemaPsicobloom.colorError,
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (prof.cuentaActiva && prof.aprobacion != 'aprobado')
                          ElevatedButton(
                            onPressed: _controlador.ocupado
                                ? null
                                : () => _aprobar(prof.idUsuario),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(110, 38),
                            ),
                            child: const Text('Aprobar'),
                          ),
                        if (prof.cuentaActiva && prof.aprobacion == 'pendiente')
                          OutlinedButton(
                            onPressed: _controlador.ocupado
                                ? null
                                : () => _rechazar(
                                    idUsuario: prof.idUsuario,
                                    nombreCompleto: prof.nombreCompleto,
                                  ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: TemaPsicobloom.colorError,
                              minimumSize: const Size(110, 38),
                            ),
                            child: const Text('Rechazar'),
                          ),
                        OutlinedButton(
                          onPressed: _controlador.ocupado
                              ? null
                              : () => _confirmarCambioEstadoCuenta(
                                  usuarioId: prof.idUsuario,
                                  nombreCuenta: prof.nombreCompleto,
                                  correoCuenta: prof.correo,
                                  activar: !prof.cuentaActiva,
                                ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(130, 38),
                          ),
                          child: Text(
                            prof.cuentaActiva
                                ? 'Desactivar cuenta'
                                : 'Reactivar cuenta',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _construirPestanaEspecialidades() {
    return RefreshIndicator(
      onRefresh: _controlador.cargarEspecialidades,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Especialidades',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: TemaPsicobloom.colorTexto,
                      ),
                    ),
                    Text(
                      'Gestiona las especialidades disponibles en la aplicación.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: TemaPsicobloom.colorTextoSecundario,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                key: const Key('botonNuevaEspecialidad'),
                onPressed: _controlador.ocupado
                    ? null
                    : () => _mostrarDialogoEspecialidad(),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Nueva'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_controlador.estaCargando && _controlador.especialidades.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_controlador.especialidades.isEmpty)
            _construirEstadoVacio(
              'No hay especialidades registradas.',
              () => _controlador.cargarEspecialidades(),
            )
          else
            ..._controlador.especialidades.map(
              (esp) => Container(
                key: Key('tarjetaEspecialidadAdmin_${esp.id}'),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: TemaPsicobloom.colorSuperficie,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: TemaPsicobloom.colorBorde),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: TemaPsicobloom.colorLavanda,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.menu_book_outlined,
                        color: TemaPsicobloom.colorPrincipal,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            esp.nombre,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                            ),
                          ),
                          if (esp.descripcion.isNotEmpty)
                            Text(
                              esp.descripcion,
                              style: const TextStyle(
                                fontSize: 12,
                                color: TemaPsicobloom.colorTextoSecundario,
                              ),
                            ),
                        ],
                      ),
                    ),
                    EtiquetaEstadoAdministracion(
                      texto: esp.activa ? 'Activo' : 'Desactivado',
                      colorTexto: esp.activa
                          ? TemaPsicobloom.colorExito
                          : TemaPsicobloom.colorError,
                      colorFondo: esp.activa
                          ? TemaPsicobloom.colorFondoExito
                          : TemaPsicobloom.colorFondoError,
                    ),
                    IconButton(
                      tooltip: 'Editar especialidad',
                      onPressed: _controlador.ocupado
                          ? null
                          : () => _mostrarDialogoEspecialidad(esp),
                      icon: const Icon(Icons.edit_outlined, size: 20),
                    ),
                    Switch(
                      key: Key('switchEspecialidad_${esp.id}'),
                      value: esp.activa,
                      onChanged: _controlador.ocupado
                          ? null
                          : (nuevo) => _controlador.cambiarEstadoEspecialidad(
                              idEspecialidad: esp.id,
                              activa: nuevo,
                            ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _construirPestanaCitas() {
    return RefreshIndicator(
      onRefresh: _recargarCitasYAdelantosAdmin,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Citas',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: TemaPsicobloom.colorTexto,
                      ),
                    ),
                    Text(
                      'Consulta y supervisa todas las citas registradas.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: TemaPsicobloom.colorTextoSecundario,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                key: const Key('botonExportarCitasCsv'),
                onPressed: _controlador.citas.isEmpty
                    ? null
                    : _exportarCitasCsv,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Exportar'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final estado in const [
                ('todas', 'Todas'),
                ('pendiente', 'Pendiente'),
                ('confirmada', 'Confirmada'),
                ('finalizada', 'Finalizada'),
                ('cancelada', 'Cancelada'),
                ('rechazada', 'Rechazada'),
              ])
                ChoiceChip(
                  key: Key('filtroCitaAdmin_${estado.$1}'),
                  label: Text(estado.$2),
                  selected: _controlador.filtroEstadoCita == estado.$1,
                  selectedColor: TemaPsicobloom.colorLavanda,
                  onSelected: (_) => _controlador.cargarCitas(
                    estado: estado.$1,
                    reiniciar: true,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Mostrando ${_controlador.citas.length} de ${_controlador.totalCitas} citas',
            style: const TextStyle(
              fontSize: 12.5,
              color: TemaPsicobloom.colorTextoSecundario,
            ),
          ),
          const SizedBox(height: 10),
          if (_controlador.estaCargando && _controlador.citas.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_controlador.citas.isEmpty)
            _construirEstadoVacio(
              'No hay citas para el filtro seleccionado.',
              () => _controlador.cargarCitas(reiniciar: true),
            )
          else
            ..._controlador.citas.map(
              (cita) => Container(
                key: Key('tarjetaCitaAdmin_${cita.idCita}'),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: TemaPsicobloom.colorSuperficie,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: TemaPsicobloom.colorBorde),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${cita.fecha} · ${cita.horaInicio} - ${cita.horaFin}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: TemaPsicobloom.colorTextoSecundario,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${cita.pacienteNombre} → ${cita.profesionalNombre}',
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: TemaPsicobloom.colorTexto,
                            ),
                          ),
                          if (_errorAdelantosAdmin != null)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                'Adelanto: estado no disponible (desliza para reintentar)',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: TemaPsicobloom.colorAdvertencia,
                                ),
                              ),
                            )
                          else if (_adelantosCitas[cita.idCita] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Adelanto: ${_adelantosCitas[cita.idCita]!.etiquetaEstado}',
                                key: Key('estadoAdelantoAdmin_${cita.idCita}'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      _adelantosCitas[cita.idCita]!
                                          .revisionDemorada
                                      ? TemaPsicobloom.colorAdvertencia
                                      : TemaPsicobloom.colorPrincipalOscuro,
                                ),
                              ),
                            ),
                          if (cita.motivoRespuesta != null &&
                              cita.motivoRespuesta!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                'Motivo: ${cita.motivoRespuesta}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: TemaPsicobloom.colorTextoSecundario,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    EtiquetaEstadoAdministracion.desdeCita(cita.estado),
                  ],
                ),
              ),
            ),
          if (_controlador.hayMasCitas) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _controlador.estaCargando
                  ? null
                  : () => _controlador.cargarCitas(reiniciar: false),
              child: const Text('Cargar más citas'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _construirEstadoVacio(String mensaje, VoidCallback alReintentar) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        children: [
          Text(
            mensaje,
            textAlign: TextAlign.center,
            style: const TextStyle(color: TemaPsicobloom.colorTextoSecundario),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: alReintentar,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  String _formatearFechaCorta(DateTime fecha) {
    final local = fecha.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d/$m $h:$min';
  }
}
