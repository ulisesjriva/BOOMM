import 'package:flutter/material.dart';

import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/nucleo/componentes/fondo_decorativo_bloom.dart';
import 'package:boom/modulos/paciente/componentes/barra_navegacion_paciente.dart';
import 'package:boom/modulos/paciente/componentes/tarjeta_profesional.dart';
import 'package:boom/modelos/profesional.dart';
import 'package:boom/modelos/filtro_profesional.dart';
import 'package:boom/datos/gestor_favoritos.dart';
import 'package:boom/repositorios/repositorio_profesionales.dart';
import 'package:boom/repositorios/repositorio_profesionales_simulado.dart';

import 'pantalla_inicio_paciente.dart';

/// Pantalla 6: Buscar profesionales.
/// Directorio interactivo de atencion psicologica con busqueda textual,
/// filtros por especialidad, disponibilidad y modalidad, y ordenamiento.
class PantallaBuscarProfesionales extends StatefulWidget {
  final RepositorioProfesionales? repositorio;

  const PantallaBuscarProfesionales({super.key, this.repositorio});

  @override
  State<PantallaBuscarProfesionales> createState() =>
      _PantallaBuscarProfesionalesState();
}

class _PantallaBuscarProfesionalesState
    extends State<PantallaBuscarProfesionales> {
  late final RepositorioProfesionales _repositorio;
  final TextEditingController _controladorBusqueda = TextEditingController();

  FiltroProfesional _filtro = FiltroProfesional.inicial();
  List<Profesional> _profesionales = <Profesional>[];
  bool _estaCargando = true;

  List<String> _opcionesEspecialidades = const ['Todas'];
  List<String> _opcionesModalidades = const ['Todas'];
  List<String> _opcionesDisponibilidades = const ['Todas'];

  @override
  void initState() {
    super.initState();
    _repositorio = widget.repositorio ?? RepositorioProfesionalesSimulado();
    _inicializarCatalogosYCargar();
  }

  @override
  void dispose() {
    _controladorBusqueda.dispose();
    super.dispose();
  }

  Future<void> _inicializarCatalogosYCargar() async {
    final especialidades = await _repositorio.obtenerEspecialidades();
    final modalidades = await _repositorio.obtenerModalidades();
    final disponibilidades = await _repositorio.obtenerDisponibilidades();

    if (!mounted) return;

    setState(() {
      _opcionesEspecialidades = especialidades;
      _opcionesModalidades = modalidades;
      _opcionesDisponibilidades = disponibilidades;
    });

    await _ejecutarBusqueda();
  }

  Future<void> _ejecutarBusqueda() async {
    setState(() {
      _estaCargando = true;
    });

    final resultados = await _repositorio.buscarProfesionales(_filtro);

    if (!mounted) return;

    setState(() {
      _profesionales = resultados;
      _estaCargando = false;
    });
  }

  void _actualizarTextoBusqueda(String nuevoTexto) {
    _filtro = _filtro.copiarCon(textoBusqueda: nuevoTexto);
    _ejecutarBusqueda();
  }

  void _limpiarFiltros() {
    _controladorBusqueda.clear();
    setState(() {
      _filtro = FiltroProfesional.inicial();
    });
    _ejecutarBusqueda();
    _mostrarMensajeInformativo(
      'Se restablecieron todos los filtros de búsqueda.',
    );
  }

  void _cambiarEspecialidad(String nuevaEspecialidad) {
    setState(() {
      _filtro = _filtro.copiarCon(especialidad: nuevaEspecialidad);
    });
    _ejecutarBusqueda();
  }

  void _cambiarModalidad(String nuevaModalidad) {
    setState(() {
      _filtro = _filtro.copiarCon(modalidad: nuevaModalidad);
    });
    _ejecutarBusqueda();
  }

  void _cambiarDisponibilidad(String nuevaDisponibilidad) {
    setState(() {
      _filtro = _filtro.copiarCon(disponibilidad: nuevaDisponibilidad);
    });
    _ejecutarBusqueda();
  }

  void _cambiarOrdenamiento(CriterioOrdenamiento nuevoOrden) {
    setState(() {
      _filtro = _filtro.copiarCon(ordenamiento: nuevoOrden);
    });
    _ejecutarBusqueda();
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
        _mostrarMensajeInformativo(
          'El Mapa interactivo de profesionales se implementará en la Etapa 4.',
        );
        break;
      case 3:
        _mostrarMensajeInformativo(
          'El módulo de Mis citas corresponde a etapas posteriores del equipo.',
        );
        break;
      case 4:
        _mostrarMensajeInformativo(
          'El perfil del paciente corresponde a etapas posteriores del equipo.',
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
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: TemaPsicobloom.colorLavanda.withValues(alpha: 0.6),
              shape: BoxShape.circle,
              border: Border.all(color: TemaPsicobloom.colorBorde, width: 1.0),
            ),
            child: const Icon(
              Icons.search_rounded,
              color: TemaPsicobloom.colorPrincipal,
              size: 30,
            ),
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

  /// Fila de los tres filtros rapidos tipo tarjeta interactiva.
  Widget _construirFilaFiltros() {
    return LayoutBuilder(
      builder: (context, restricciones) {
        return Row(
          children: [
            Expanded(
              child: _construirBotonFiltro(
                etiqueta: 'Especialidad',
                valorActual: _filtro.especialidad,
                icono: Icons.health_and_safety_outlined,
                colorIcono: TemaPsicobloom.colorPrincipal,
                opciones: _opcionesEspecialidades,
                alSeleccionar: _cambiarEspecialidad,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _construirBotonFiltro(
                etiqueta: 'Disponibilidad',
                valorActual: _filtro.disponibilidad,
                icono: Icons.calendar_today_outlined,
                colorIcono: TemaPsicobloom.colorSecundario,
                opciones: _opcionesDisponibilidades,
                alSeleccionar: _cambiarDisponibilidad,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _construirBotonFiltro(
                etiqueta: 'Modalidad',
                valorActual: _filtro.modalidad,
                icono: Icons.people_outline_rounded,
                colorIcono: TemaPsicobloom.colorInformacion,
                opciones: _opcionesModalidades,
                alSeleccionar: _cambiarModalidad,
              ),
            ),
          ],
        );
      },
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
    final bool estaActivo = valorActual != 'Todas';

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
    final cantidad = _profesionales.length;
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
            if (_filtro.tieneFiltrosActivos) ...[
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
              initialValue: _filtro.ordenamiento,
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
                        fontWeight: criterio == _filtro.ordenamiento
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: criterio == _filtro.ordenamiento
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
    if (_estaCargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40.0),
        child: Center(
          child: CircularProgressIndicator(
            color: TemaPsicobloom.colorPrincipal,
          ),
        ),
      );
    }

    if (_profesionales.isEmpty) {
      return _construirEstadoVacio();
    }

    return ValueListenableBuilder<Set<String>>(
      valueListenable: GestorFavoritos.instancia.favoritos,
      builder: (context, conjuntoFavoritos, child) {
        return Column(
          children: _profesionales.map((profesional) {
            final bool esFavorito = conjuntoFavoritos.contains(profesional.id);

            return Padding(
              padding: const EdgeInsets.only(bottom: 14.0),
              child: TarjetaProfesional(
                profesional: profesional,
                esFavorito: esFavorito,
                alAlternarFavorito: () => _alternarFavorito(profesional.id),
                alVerPerfil: () {
                  _mostrarMensajeInformativo(
                    'La visualización de perfil detallado se implementará en etapas posteriores.',
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
