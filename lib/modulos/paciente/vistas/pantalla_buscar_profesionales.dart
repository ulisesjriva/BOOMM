import 'dart:async';

import 'package:flutter/material.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/nucleo/componentes/fondo_decorativo_bloom.dart';
import 'package:boom/modulos/paciente/componentes/barra_navegacion_paciente.dart';
import 'package:boom/modulos/paciente/componentes/tarjeta_profesional.dart';
import 'package:boom/modelos/filtro_profesional.dart';
import 'package:boom/modulos/paciente/controladores/gestor_favoritos.dart';
import 'package:boom/modulos/paciente/servicios/servicio_rutas_consultorio.dart';
import 'package:boom/modulos/profesional/servicios/servicio_ubicacion_consultorio.dart';
import 'package:boom/repositorios/repositorio_profesionales.dart';
import 'package:boom/repositorios/repositorio_profesionales_simulado.dart';
import 'package:boom/repositorios/repositorio_profesionales_supabase.dart';

import 'pantalla_inicio_paciente.dart';
import 'pantalla_mapa_profesionales.dart';
import 'pantalla_mis_citas_paciente.dart';
import 'pantalla_perfil_paciente.dart';
import 'pantalla_perfil_publico_profesional.dart';
import '../controladores/controlador_buscar_profesionales.dart';

/// Pantalla 6: Buscar profesionales.
/// Directorio interactivo de atencion psicologica con busqueda textual,
/// filtros por especialidad, disponibilidad, modalidad y cercania, y ordenamiento.
class PantallaBuscarProfesionales extends StatefulWidget {
  final RepositorioProfesionales? repositorio;
  final ServicioUbicacionConsultorio servicioUbicacion;
  final ServicioRutasConsultorio servicioRutas;

  const PantallaBuscarProfesionales({
    super.key,
    this.repositorio,
    this.servicioUbicacion = const ServicioUbicacionConsultorio(),
    this.servicioRutas = const ServicioRutasConsultorio(),
  });

  @override
  State<PantallaBuscarProfesionales> createState() =>
      _PantallaBuscarProfesionalesState();
}

class _PantallaBuscarProfesionalesState
    extends State<PantallaBuscarProfesionales> {
  late final ControladorBuscarProfesionales _controlador;
  final TextEditingController _controladorBusqueda = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controlador = ControladorBuscarProfesionales(
      repositorio:
          widget.repositorio ??
          (ConfiguracionSupabase.estaConfigurado
              ? RepositorioProfesionalesSupabase()
              : RepositorioProfesionalesSimulado()),
      servicioUbicacion: widget.servicioUbicacion,
      servicioRutas: widget.servicioRutas,
    );
    _controlador.addListener(_actualizarVista);
    unawaited(_controlador.inicializar());
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
    _controladorBusqueda.dispose();
    super.dispose();
  }

  void _actualizarTextoBusqueda(String nuevoTexto) {
    unawaited(_controlador.actualizarTexto(nuevoTexto));
  }

  void _limpiarFiltros() {
    _controladorBusqueda.clear();
    unawaited(_controlador.limpiarFiltros());
    _mostrarMensajeInformativo(
      'Se restablecieron todos los filtros de búsqueda.',
    );
  }

  void _cambiarEspecialidad(String nuevaEspecialidad) {
    unawaited(_controlador.cambiarEspecialidad(nuevaEspecialidad));
  }

  void _cambiarModalidad(String nuevaModalidad) {
    unawaited(_controlador.cambiarModalidad(nuevaModalidad));
  }

  void _cambiarDisponibilidad(String nuevaDisponibilidad) {
    unawaited(_controlador.cambiarDisponibilidad(nuevaDisponibilidad));
  }

  void _cambiarCercania(String nuevaCercania) {
    unawaited(_controlador.cambiarCercania(nuevaCercania));
  }

  void _cambiarOrdenamiento(CriterioOrdenamiento nuevoOrden) {
    unawaited(_controlador.cambiarOrdenamiento(nuevoOrden));
  }

  void _alternarFavorito(String idProfesional) {
    final esFavorito = GestorFavoritos.instancia.alternarFavorito(
      idProfesional,
    );
    _mostrarMensajeInformativo(
      esFavorito
          ? 'Guardado en tus profesionales favoritos'
          : 'Eliminado de tus profesionales favoritos',
    );
  }

  void _mostrarMensajeInformativo(String mensaje) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: TemaPsicobloom.colorLavanda,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                mensaje,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: TemaPsicobloom.colorPrincipalOscuro,
        behavior: SnackBarBehavior.floating,
        elevation: 3,
        margin: const EdgeInsets.only(bottom: 12, left: 20, right: 20),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: TemaPsicobloom.colorLavanda.withValues(alpha: 0.35),
            width: 1.0,
          ),
        ),
        duration: const Duration(milliseconds: 2200),
      ),
    );
  }

  void _gestionarCambioPestana(int nuevoIndice) {
    if (nuevoIndice == 1) return; // Ya estamos en Buscar

    switch (nuevoIndice) {
      case 0:
        // Regresa a la pantalla de Inicio del paciente
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const PantallaInicioPaciente(),
            ),
          );
        }
        break;
      case 2:
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (context) =>
                PantallaMapaProfesionales(repositorio: widget.repositorio),
          ),
        );
        break;
      case 3:
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (context) =>
                PantallaMisCitasPaciente(repositorio: widget.repositorio),
          ),
        );
        break;
      case 4:
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (context) => const PantallaPerfilPaciente(),
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaPsicobloom.colorFondo,
      bottomNavigationBar: BarraNavegacionPaciente(
        indiceSeleccionado: 1,
        alCambiarPestana: _gestionarCambioPestana,
      ),
      body: FondoDecorativoBloom(
        mostrarHojas: false,
        mostrarCorazones: false,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 16.0,
                  ),
                  children: [
                    _construirCabeceraSuperior(),
                    const SizedBox(height: 18),
                    _construirSeccionTitulo(),
                    const SizedBox(height: 18),
                    _construirCampoBusqueda(),
                    const SizedBox(height: 16),
                    _construirFilaFiltros(),
                    if (_controlador.mensajeCercania != null) ...[
                      const SizedBox(height: 12),
                      _construirAvisoCercania(_controlador.mensajeCercania!),
                    ],
                    const SizedBox(height: 20),
                    _construirBarraResultadosYOrden(),
                    const SizedBox(height: 12),
                    _construirCuerpoResultados(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Barra superior con el logo institucional y campana de notificaciones.
  Widget _construirCabeceraSuperior() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: TemaPsicobloom.colorSuperficie,
                shape: BoxShape.circle,
                border: Border.all(
                  color: TemaPsicobloom.colorBorde,
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: TemaPsicobloom.colorPrincipal.withValues(
                      alpha: 0.08,
                    ),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/imagenes/icono_psicobloom.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.local_florist_rounded,
                    color: TemaPsicobloom.colorPrincipal,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'PsicoBloom',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: TemaPsicobloom.colorPrincipalOscuro,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        Stack(
          children: [
            IconButton(
              icon: const Icon(
                Icons.notifications_none_rounded,
                color: TemaPsicobloom.colorTexto,
                size: 24,
              ),
              tooltip: 'Notificaciones',
              onPressed: () {
                _mostrarMensajeInformativo('No tienes nuevas notificaciones.');
              },
            ),
            Positioned(
              top: 10,
              right: 12,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: TemaPsicobloom.colorPrincipal,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Titulo y subtitulo principal con ilustracion de bienestar emocional.
  Widget _construirSeccionTitulo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: TemaPsicobloom.colorBorde.withValues(alpha: 0.7),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: TemaPsicobloom.colorPrincipal.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Buscar profesional',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorTexto,
                    letterSpacing: -0.4,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Encuentra el apoyo que necesitas',
                  style: TextStyle(
                    fontSize: 14,
                    color: TemaPsicobloom.colorTextoSecundario,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            Icons.person_search_outlined,
            key: const Key('iconoEncabezadoBuscar'),
            color: TemaPsicobloom.colorPrincipal.withValues(alpha: 0.72),
            size: 28,
          ),
        ],
      ),
    );
  }

  /// Campo de texto para busqueda interactiva en tiempo real.
  Widget _construirCampoBusqueda() {
    return Container(
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TemaPsicobloom.colorBorde, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: TemaPsicobloom.colorTexto.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: _controladorBusqueda,
        onChanged: _actualizarTextoBusqueda,
        decoration: InputDecoration(
          hintText: 'Nombre, especialidad o palabra clave',
          hintStyle: const TextStyle(
            color: TemaPsicobloom.colorTextoSecundario,
            fontSize: 14,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: TemaPsicobloom.colorPrincipal,
            size: 22,
          ),
          suffixIcon: _controladorBusqueda.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: TemaPsicobloom.colorTextoSecundario,
                    size: 20,
                  ),
                  tooltip: 'Borrar búsqueda',
                  onPressed: () {
                    _controladorBusqueda.clear();
                    _actualizarTextoBusqueda('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  /// Zona de filtros rapidos (Especialidad, Disponibilidad, Modalidad y Cercania).
  Widget _construirFilaFiltros() {
    final filtroEspecialidad = _construirBotonFiltro(
      etiqueta: 'Especialidad',
      valorActual: _controlador.filtro.especialidad,
      icono: Icons.health_and_safety_outlined,
      colorIcono: TemaPsicobloom.colorPrincipal,
      opciones: _controlador.especialidades,
      alSeleccionar: _cambiarEspecialidad,
    );
    final filtroDisponibilidad = _construirBotonFiltro(
      etiqueta: 'Disponibilidad',
      valorActual: _controlador.filtro.disponibilidad,
      icono: Icons.calendar_today_outlined,
      colorIcono: TemaPsicobloom.colorSecundario,
      opciones: _controlador.disponibilidades,
      alSeleccionar: _cambiarDisponibilidad,
    );
    final filtroModalidad = _construirBotonFiltro(
      etiqueta: 'Modalidad',
      valorActual: _controlador.filtro.modalidad,
      icono: Icons.people_outline_rounded,
      colorIcono: TemaPsicobloom.colorInformacion,
      opciones: _controlador.modalidades,
      alSeleccionar: _cambiarModalidad,
    );
    final filtroCercania = _construirBotonFiltro(
      etiqueta: 'Cercanía',
      valorActual: _controlador.filtro.cercania,
      icono: Icons.near_me_outlined,
      colorIcono: TemaPsicobloom.colorPrincipalOscuro,
      opciones: _controlador.opcionesCercania,
      alSeleccionar: _cambiarCercania,
    );

    return LayoutBuilder(
      builder: (context, restricciones) {
        if (restricciones.maxWidth >= 560) {
          return Row(
            children: [
              Expanded(child: filtroEspecialidad),
              const SizedBox(width: 8),
              Expanded(child: filtroDisponibilidad),
              const SizedBox(width: 8),
              Expanded(child: filtroModalidad),
              const SizedBox(width: 8),
              Expanded(child: filtroCercania),
            ],
          );
        }

        return Column(
          children: [
            Row(
              children: [
                Expanded(child: filtroEspecialidad),
                const SizedBox(width: 8),
                Expanded(child: filtroDisponibilidad),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: filtroModalidad),
                const SizedBox(width: 8),
                Expanded(child: filtroCercania),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _construirAvisoCercania(String mensaje) {
    return Container(
      key: const Key('avisoCercaniaBusqueda'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorFondoInformacion,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: TemaPsicobloom.colorInformacion.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.location_off_outlined,
              size: 18,
              color: TemaPsicobloom.colorInformacion,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mensaje,
              style: const TextStyle(
                fontSize: 12.5,
                color: TemaPsicobloom.colorTexto,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirBotonFiltro({
    required String etiqueta,
    required String valorActual,
    required IconData icono,
    required Color colorIcono,
    required List<String> opciones,
    required ValueChanged<String> alSeleccionar,
  }) {
    final bool estaActivo =
        valorActual != 'Todas' &&
        valorActual != FiltroProfesional.opcionCercaniaTodos;

    return Material(
      color: estaActivo
          ? TemaPsicobloom.colorLavanda.withValues(alpha: 0.5)
          : TemaPsicobloom.colorSuperficie,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _mostrarDialogoSeleccionFiltro(
          titulo: etiqueta,
          valorActual: valorActual,
          opciones: opciones,
          alSeleccionar: alSeleccionar,
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 10.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: estaActivo
                  ? TemaPsicobloom.colorPrincipal
                  : TemaPsicobloom.colorBorde.withValues(alpha: 0.8),
              width: estaActivo ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icono, size: 18, color: colorIcono),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: estaActivo
                        ? TemaPsicobloom.colorPrincipal
                        : TemaPsicobloom.colorTextoSecundario,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                etiqueta,
                style: const TextStyle(
                  fontSize: 11,
                  color: TemaPsicobloom.colorTextoSecundario,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                valorActual,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: estaActivo
                      ? TemaPsicobloom.colorPrincipalOscuro
                      : TemaPsicobloom.colorTexto,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarDialogoSeleccionFiltro({
    required String titulo,
    required String valorActual,
    required List<String> opciones,
    required ValueChanged<String> alSeleccionar,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: TemaPsicobloom.colorSuperficie,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 16.0,
              horizontal: 20.0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: TemaPsicobloom.colorBorde,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Filtrar por $titulo',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    key: const Key('listaOpcionesFiltro'),
                    shrinkWrap: true,
                    itemCount: opciones.length,
                    itemBuilder: (context, indice) {
                      final opcion = opciones[indice];
                      final bool seleccionada = opcion == valorActual;

                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          opcion,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: seleccionada
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: seleccionada
                                ? TemaPsicobloom.colorPrincipal
                                : TemaPsicobloom.colorTexto,
                          ),
                        ),
                        trailing: seleccionada
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: TemaPsicobloom.colorPrincipal,
                                size: 20,
                              )
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          alSeleccionar(opcion);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Contador de resultados y opciones de ordenamiento / limpiar filtros.
  Widget _construirBarraResultadosYOrden() {
    final cantidad = _controlador.profesionales.length;
    final String textoContador = cantidad == 1
        ? '1 profesional encontrado'
        : '$cantidad profesionales encontrados';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            textoContador,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_controlador.filtro.tieneFiltrosActivos) ...[
              TextButton.icon(
                onPressed: _limpiarFiltros,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text(
                  'Limpiar filtros',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: TemaPsicobloom.colorPrincipal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 4),
            ],
            PopupMenuButton<CriterioOrdenamiento>(
              initialValue: _controlador.filtro.ordenamiento,
              tooltip: 'Ordenar resultados',
              onSelected: _cambiarOrdenamiento,
              color: TemaPsicobloom.colorSuperficie,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: TemaPsicobloom.colorBorde),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: TemaPsicobloom.colorSuperficie,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: TemaPsicobloom.colorBorde),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ordenar',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: TemaPsicobloom.colorTexto,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: TemaPsicobloom.colorTextoSecundario,
                    ),
                  ],
                ),
              ),
              itemBuilder: (context) {
                return CriterioOrdenamiento.values.map((criterio) {
                  return PopupMenuItem<CriterioOrdenamiento>(
                    value: criterio,
                    child: Text(
                      criterio.etiqueta,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: criterio == _controlador.filtro.ordenamiento
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: criterio == _controlador.filtro.ordenamiento
                            ? TemaPsicobloom.colorPrincipal
                            : TemaPsicobloom.colorTexto,
                      ),
                    ),
                  );
                }).toList();
              },
            ),
          ],
        ),
      ],
    );
  }

  /// Listado de resultados o estado vacio cuando no hay coincidencias.
  Widget _construirCuerpoResultados() {
    if (_controlador.estaCargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40.0),
        child: Center(
          child: CircularProgressIndicator(
            color: TemaPsicobloom.colorPrincipal,
          ),
        ),
      );
    }

    final mensajeError = _controlador.mensajeError;
    if (mensajeError != null) {
      return Column(
        children: [
          Text(mensajeError, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => unawaited(_controlador.inicializar()),
            child: const Text('Reintentar'),
          ),
        ],
      );
    }

    if (_controlador.profesionales.isEmpty) {
      return _construirEstadoVacio();
    }

    return ValueListenableBuilder<Set<String>>(
      valueListenable: GestorFavoritos.instancia.favoritos,
      builder: (context, conjuntoFavoritos, child) {
        return Column(
          children: _controlador.profesionales.map((profesional) {
            final bool esFavorito = conjuntoFavoritos.contains(profesional.id);

            return Padding(
              padding: const EdgeInsets.only(bottom: 14.0),
              child: TarjetaProfesional(
                profesional: profesional,
                esFavorito: esFavorito,
                textoUbicacionPersonalizado: _controlador
                    .obtenerResumenCercania(profesional.id),
                alAlternarFavorito: () => _alternarFavorito(profesional.id),
                alVerPerfil: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PantallaPerfilPublicoProfesional(
                        profesional: profesional,
                        mostrarMapaInteractivo:
                            ConfiguracionSupabase.estaConfigurado,
                      ),
                    ),
                  );
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }

  /// Mensaje visual claro cuando ningun profesional coincide con los filtros.
  Widget _construirEstadoVacio() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36.0, horizontal: 20.0),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: TemaPsicobloom.colorBorde.withValues(alpha: 0.8),
          width: 1.0,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: TemaPsicobloom.colorLavanda.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off_rounded,
              color: TemaPsicobloom.colorPrincipal,
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No encontramos profesionales',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Prueba buscando con otra palabra clave o restablece los filtros para ver todos los consultorios.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: TemaPsicobloom.colorTextoSecundario,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _limpiarFiltros,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Restablecer filtros'),
            style: ElevatedButton.styleFrom(
              backgroundColor: TemaPsicobloom.colorPrincipal,
              foregroundColor: TemaPsicobloom.colorSobrePrincipal,
              minimumSize: const Size(180, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
