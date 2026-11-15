import 'package:flutter/material.dart';

import 'package:boom/nucleo/componentes/fondo_decorativo_bloom.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

import '../controladores/controlador_disponibilidad_profesional.dart';
import '../modelos/horario_disponibilidad.dart';
import '../servicios/servicio_disponibilidad_profesional.dart';

class PantallaDisponibilidadProfesional extends StatefulWidget {
  const PantallaDisponibilidadProfesional({
    super.key,
    this.controlador,
    this.servicio,
    this.estaPendienteAprobacion = false,
    this.esVistaIntegrada = false,
    this.alIrASolicitudes,
  });

  final ControladorDisponibilidadProfesional? controlador;
  final ServicioDisponibilidadProfesional? servicio;
  final bool estaPendienteAprobacion;
  final bool esVistaIntegrada;
  final VoidCallback? alIrASolicitudes;

  @override
  State<PantallaDisponibilidadProfesional> createState() =>
      _PantallaDisponibilidadProfesionalState();
}

class _PantallaDisponibilidadProfesionalState
    extends State<PantallaDisponibilidadProfesional>
    with WidgetsBindingObserver {
  static const int _minutosMinimosHorarioHoy = 30;
  static const int _ultimoMinutoDelDia = 23 * 60 + 59;
  static const String _mensajeSinHorasHoy =
      'Ya no quedan horas disponibles para agregar hoy. Elige otro día.';

  late final ControladorDisponibilidadProfesional _controlador;
  late final bool _esControladorPropio;

  late final TextEditingController _controladorFecha;
  late final TextEditingController _controladorHoraInicio;
  late final TextEditingController _controladorHoraFin;
  late final TextEditingController _controladorDuracionMinutos;
  late final TextEditingController _controladorDescansoMinutos;
  late final TextEditingController _controladorMotivoDiaNoLaborable;

  final GlobalKey _claveTarjetaHoy = GlobalKey();
  late DateTime _lunesSemanaVisible;
  late String _ultimaFechaObservadaIso;
  String? _idHorarioEnEdicion;
  String? _errorFormularioLocal;
  bool _usarIntervaloUnicoLibre = false;
  bool _hayModalAbierto = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.controlador != null) {
      _controlador = widget.controlador!;
      _esControladorPropio = false;
    } else {
      _controlador = ControladorDisponibilidadProfesional(
        servicio: widget.servicio,
      );
      _esControladorPropio = true;
    }

    final ahoraEcuador = _controlador.ahoraEnEcuador;
    _ultimaFechaObservadaIso = HorarioDisponibilidad.formatearFechaIso(
      ahoraEcuador,
    );
    _lunesSemanaVisible = HorarioDisponibilidad.obtenerLunesDeSemana(
      ahoraEcuador,
    );

    final mananaEcuador = ahoraEcuador.add(const Duration(days: 1));
    _controladorFecha = TextEditingController(
      text: HorarioDisponibilidad.formatearFechaIso(mananaEcuador),
    );
    _controladorHoraInicio = TextEditingController(text: '09:00');
    _controladorHoraFin = TextEditingController(text: '12:00');
    _controladorDuracionMinutos = TextEditingController(text: '60');
    _controladorDescansoMinutos = TextEditingController(text: '0');
    _controladorMotivoDiaNoLaborable = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_esControladorPropio ||
          (!_controlador.tieneHorarios && !_controlador.estaCargando)) {
        _controlador.cargarHorarios().then((_) {
          _programarDesplazamientoATarjetaHoy();
        });
      } else {
        _programarDesplazamientoATarjetaHoy();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controladorFecha.dispose();
    _controladorHoraInicio.dispose();
    _controladorHoraFin.dispose();
    _controladorDuracionMinutos.dispose();
    _controladorDescansoMinutos.dispose();
    _controladorMotivoDiaNoLaborable.dispose();
    if (_esControladorPropio) {
      _controlador.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _sincronizarConFechaActualAlReanudar();
    }
  }

  void _sincronizarConFechaActualAlReanudar() {
    final ahoraEcuador = _controlador.ahoraEnEcuador;
    final hoyIsoActual = HorarioDisponibilidad.formatearFechaIso(ahoraEcuador);
    final lunesActual = HorarioDisponibilidad.normalizarFechaSoloDia(
      HorarioDisponibilidad.obtenerLunesDeSemana(ahoraEcuador),
    );
    final lunesVisible = HorarioDisponibilidad.normalizarFechaSoloDia(
      _lunesSemanaVisible,
    );

    final cambioDia = hoyIsoActual != _ultimaFechaObservadaIso;
    final semanaVisibleQuedoPasada = lunesVisible.isBefore(lunesActual);

    setState(() {
      _ultimaFechaObservadaIso = hoyIsoActual;
      if (semanaVisibleQuedoPasada) {
        _lunesSemanaVisible = lunesActual;
      }
    });
    if (cambioDia || semanaVisibleQuedoPasada) {
      _programarDesplazamientoATarjetaHoy();
    }
  }

  void _programarDesplazamientoATarjetaHoy() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final contextoHoy = _claveTarjetaHoy.currentContext;
      if (contextoHoy != null) {
        Scrollable.ensureVisible(
          contextoHoy,
          duration: const Duration(milliseconds: 220),
          alignment: 0.05,
        );
      }
    });
  }

  bool _esFechaDeHoy(DateTime fecha) {
    final hoy = HorarioDisponibilidad.normalizarFechaSoloDia(
      _controlador.ahoraEnEcuador,
    );
    return HorarioDisponibilidad.normalizarFechaSoloDia(fecha) == hoy;
  }

  bool _quedanHorasDisponiblesHoy([DateTime? referencia]) {
    final ahora = referencia ?? _controlador.ahoraEnEcuador;
    final minutosActuales = ahora.hour * 60 + ahora.minute;
    return minutosActuales + _minutosMinimosHorarioHoy <= _ultimoMinutoDelDia;
  }

  String _formatearMinutosAHora(int minutosTotales) {
    final horas = (minutosTotales ~/ 60).toString().padLeft(2, '0');
    final minutos = (minutosTotales % 60).toString().padLeft(2, '0');
    return '$horas:$minutos';
  }

  ({String inicio, String fin, String duracion}) _proponerHorarioParaFecha(
    DateTime fechaBase,
  ) {
    if (!_esFechaDeHoy(fechaBase)) {
      return (inicio: '09:00', fin: '12:00', duracion: '60');
    }

    final ahora = _controlador.ahoraEnEcuador;
    final minutosActuales = ahora.hour * 60 + ahora.minute;
    if (!_quedanHorasDisponiblesHoy(ahora)) {
      return (inicio: '23:30', fin: '23:59', duracion: '30');
    }

    int inicioMinutos = (ahora.hour + 1) * 60;
    if (inicioMinutos + _minutosMinimosHorarioHoy > _ultimoMinutoDelDia) {
      inicioMinutos = ((minutosActuales ~/ 15) + 1) * 15;
      if (inicioMinutos <= minutosActuales) {
        inicioMinutos = minutosActuales + 1;
      }
    }

    final duracion = (inicioMinutos + 60 <= _ultimoMinutoDelDia) ? 60 : 30;
    var finMinutos = inicioMinutos + 180;
    if (finMinutos > _ultimoMinutoDelDia) {
      finMinutos = _ultimoMinutoDelDia;
    }
    if (finMinutos - inicioMinutos < duracion) {
      finMinutos = (inicioMinutos + duracion <= _ultimoMinutoDelDia)
          ? inicioMinutos + duracion
          : _ultimoMinutoDelDia;
    }

    return (
      inicio: _formatearMinutosAHora(inicioMinutos),
      fin: _formatearMinutosAHora(finMinutos),
      duracion: duracion.toString(),
    );
  }

  void _cambiarSemana(int desplazamientoSemanas) {
    final lunesActual = HorarioDisponibilidad.normalizarFechaSoloDia(
      HorarioDisponibilidad.obtenerLunesDeSemana(_controlador.ahoraEnEcuador),
    );
    final destino = DateTime(
      _lunesSemanaVisible.year,
      _lunesSemanaVisible.month,
      _lunesSemanaVisible.day + (desplazamientoSemanas * 7),
    );
    final destinoFinal = destino.isBefore(lunesActual) ? lunesActual : destino;

    _controlador.limpiarMensajes();
    setState(() {
      _errorFormularioLocal = null;
      _lunesSemanaVisible = destinoFinal;
    });
  }

  void _irASemanaActual() {
    _controlador.limpiarMensajes();
    setState(() {
      _errorFormularioLocal = null;
      _lunesSemanaVisible = HorarioDisponibilidad.obtenerLunesDeSemana(
        _controlador.ahoraEnEcuador,
      );
    });
    _programarDesplazamientoATarjetaHoy();
  }

  DateTime? _parsearFechaTexto(String texto) {
    final limpio = texto.trim();
    final partes = limpio.split('-');
    if (partes.length != 3) {
      return null;
    }
    final anio = int.tryParse(partes[0]);
    final mes = int.tryParse(partes[1]);
    final dia = int.tryParse(partes[2]);
    if (anio == null ||
        mes == null ||
        dia == null ||
        mes < 1 ||
        mes > 12 ||
        dia < 1 ||
        dia > 31) {
      return null;
    }
    final fecha = DateTime(anio, mes, dia);
    if (fecha.year != anio || fecha.month != mes || fecha.day != dia) {
      return null;
    }
    return fecha;
  }

  Future<void> _seleccionarFechaConCalendario({
    VoidCallback? alActualizarModal,
  }) async {
    final hoyEcuador = HorarioDisponibilidad.normalizarFechaSoloDia(
      _controlador.ahoraEnEcuador,
    );
    final fechaActualCampo =
        _parsearFechaTexto(_controladorFecha.text) ??
        hoyEcuador.add(const Duration(days: 1));
    final fechaLimite = hoyEcuador.add(const Duration(days: 365));
    final fechaInicial = fechaActualCampo.isBefore(hoyEcuador)
        ? hoyEcuador
        : (fechaActualCampo.isAfter(fechaLimite)
              ? fechaLimite
              : fechaActualCampo);

    final seleccionada = await showDatePicker(
      context: context,
      initialDate: fechaInicial,
      firstDate: hoyEcuador,
      lastDate: fechaLimite,
      helpText: 'Selecciona la fecha del horario',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (seleccionada != null && mounted) {
      setState(() {
        _controladorFecha.text = HorarioDisponibilidad.formatearFechaIso(
          seleccionada,
        );
        _errorFormularioLocal = null;
      });
      alActualizarModal?.call();
    }
  }

  Future<void> _seleccionarHoraConReloj({
    required bool esInicio,
    VoidCallback? alActualizarModal,
  }) async {
    final textoActual = esInicio
        ? _controladorHoraInicio.text
        : _controladorHoraFin.text;
    final minutos = HorarioDisponibilidad.convertirHoraAMinutos(textoActual);
    final horaInicial = minutos != null
        ? TimeOfDay(hour: minutos ~/ 60, minute: minutos % 60)
        : (esInicio
              ? const TimeOfDay(hour: 9, minute: 0)
              : const TimeOfDay(hour: 12, minute: 0));

    final seleccionada = await showTimePicker(
      context: context,
      initialTime: horaInicial,
      helpText: esInicio
          ? 'Selecciona la hora de inicio'
          : 'Selecciona la hora de finalización',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (seleccionada != null && mounted) {
      final textoFormateado =
          '${seleccionada.hour.toString().padLeft(2, '0')}:'
          '${seleccionada.minute.toString().padLeft(2, '0')}';
      setState(() {
        if (esInicio) {
          _controladorHoraInicio.text = textoFormateado;
        } else {
          _controladorHoraFin.text = textoFormateado;
        }
        _errorFormularioLocal = null;
      });
      alActualizarModal?.call();
    }
  }

  void _prepararNuevoHorario({DateTime? fechaPreseleccionada}) {
    final fechaBase =
        fechaPreseleccionada ??
        _controlador.ahoraEnEcuador.add(const Duration(days: 1));
    final propuesta = _proponerHorarioParaFecha(fechaBase);
    _controlador.limpiarMensajes();
    setState(() {
      _idHorarioEnEdicion = null;
      _usarIntervaloUnicoLibre = false;
      _controladorFecha.text = HorarioDisponibilidad.formatearFechaIso(
        fechaBase,
      );
      _controladorHoraInicio.text = propuesta.inicio;
      _controladorHoraFin.text = propuesta.fin;
      _controladorDuracionMinutos.text = propuesta.duracion;
      _controladorDescansoMinutos.text = '0';
      _errorFormularioLocal = null;
    });
  }

  Future<void> _abrirModalFormularioHorario({
    HorarioDisponibilidad? horarioParaEditar,
    DateTime? fechaPreseleccionada,
  }) async {
    if (horarioParaEditar != null) {
      _controlador.limpiarMensajes();
      setState(() {
        _idHorarioEnEdicion = horarioParaEditar.idDisponibilidad;
        _usarIntervaloUnicoLibre = true;
        _controladorFecha.text = horarioParaEditar.fechaIso;
        _controladorHoraInicio.text = horarioParaEditar.horaInicioNormalizada;
        _controladorHoraFin.text = horarioParaEditar.horaFinNormalizada;
        _controladorDuracionMinutos.text = horarioParaEditar.duracionMinutos
            .toString();
        _controladorDescansoMinutos.text = '0';
        _errorFormularioLocal = null;
      });
    } else if (fechaPreseleccionada != null || _idHorarioEnEdicion != null) {
      _prepararNuevoHorario(fechaPreseleccionada: fechaPreseleccionada);
    } else {
      _controlador.limpiarMensajes();
      setState(() {
        _errorFormularioLocal = null;
      });
    }

    setState(() => _hayModalAbierto = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: TemaPsicobloom.colorSuperficie,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (contextoModal) {
          return StatefulBuilder(
            builder: (contextoEstadoModal, actualizarModal) {
              return AnimatedBuilder(
                animation: _controlador,
                builder: (_, _) {
                  final rellenoTeclado = MediaQuery.viewInsetsOf(contextoModal)
                      .bottom;
                  return Padding(
                    padding: EdgeInsets.only(bottom: rellenoTeclado),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                      child: _construirContenidoFormularioModal(
                        contextoModal: contextoModal,
                        alActualizarModal: () => actualizarModal(() {}),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      );
    } finally {
      if (mounted) {
        if (_controlador.mensajeError != null) {
          _controlador.limpiarMensajes();
        }
        setState(() {
          _hayModalAbierto = false;
          _errorFormularioLocal = null;
        });
      }
    }
  }

  Future<void> _guardarHorarioDesdeFormulario({
    BuildContext? contextoModal,
    VoidCallback? alActualizarModal,
  }) async {
    final fechaParseada = _parsearFechaTexto(_controladorFecha.text);
    if (fechaParseada == null) {
      setState(() {
        _errorFormularioLocal = 'Ingresa una fecha válida en formato AAAA-MM-DD (por ejemplo, 2026-11-20).';
      });
      alActualizarModal?.call();
      return;
    }

    final hoySoloDia = HorarioDisponibilidad.normalizarFechaSoloDia(
      _controlador.ahoraEnEcuador,
    );
    if (HorarioDisponibilidad.normalizarFechaSoloDia(fechaParseada)
        .isBefore(hoySoloDia)) {
      setState(() {
        _errorFormularioLocal =
            'No puedes seleccionar una fecha anterior a hoy.';
      });
      alActualizarModal?.call();
      return;
    }

    if (_idHorarioEnEdicion == null &&
        _esFechaDeHoy(fechaParseada) &&
        !_quedanHorasDisponiblesHoy()) {
      setState(() {
        _errorFormularioLocal = _mensajeSinHorasHoy;
      });
      alActualizarModal?.call();
      return;
    }

    setState(() {
      _errorFormularioLocal = null;
    });
    alActualizarModal?.call();

    final horaInicio = _controladorHoraInicio.text.trim();
    final horaFin = _controladorHoraFin.text.trim();

    if (_idHorarioEnEdicion != null) {
      final exito = await _controlador.editarHorario(
        idDisponibilidad: _idHorarioEnEdicion!,
        fecha: fechaParseada,
        horaInicio: horaInicio,
        horaFin: horaFin,
      );
      if (exito && mounted) {
        setState(() {
          _idHorarioEnEdicion = null;
          _lunesSemanaVisible = HorarioDisponibilidad.obtenerLunesDeSemana(
            fechaParseada,
          );
        });
        if (contextoModal != null && contextoModal.mounted) {
          Navigator.of(contextoModal).pop();
        }
      } else {
        alActualizarModal?.call();
      }
      return;
    }

    if (_usarIntervaloUnicoLibre) {
      final exito = await _controlador.crearHorario(
        fecha: fechaParseada,
        horaInicio: horaInicio,
        horaFin: horaFin,
      );
      if (exito && mounted) {
        setState(() {
          _lunesSemanaVisible = HorarioDisponibilidad.obtenerLunesDeSemana(
            fechaParseada,
          );
        });
        if (contextoModal != null && contextoModal.mounted) {
          Navigator.of(contextoModal).pop();
        }
      } else {
        alActualizarModal?.call();
      }
      return;
    }

    final duracionMinutos = int.tryParse(
      _controladorDuracionMinutos.text.trim(),
    );
    final descansoMinutos = int.tryParse(
      _controladorDescansoMinutos.text.trim(),
    );

    if (duracionMinutos == null || duracionMinutos <= 0) {
      setState(() {
        _errorFormularioLocal =
            'Ingresa una duración válida mayor a 0 minutos para cada cita.';
      });
      alActualizarModal?.call();
      return;
    }
    if (descansoMinutos == null || descansoMinutos < 0) {
      setState(() {
        _errorFormularioLocal =
            'Ingresa un descanso válido mayor o igual a 0 minutos.';
      });
      alActualizarModal?.call();
      return;
    }

    final exito = await _controlador.crearHorariosEnJornada(
      fecha: fechaParseada,
      horaInicio: horaInicio,
      horaFin: horaFin,
      duracionMinutos: duracionMinutos,
      descansoMinutos: descansoMinutos,
    );
    if (exito && mounted) {
      setState(() {
        _lunesSemanaVisible = HorarioDisponibilidad.obtenerLunesDeSemana(
          fechaParseada,
        );
      });
      if (contextoModal != null && contextoModal.mounted) {
        Navigator.of(contextoModal).pop();
      }
    } else {
      alActualizarModal?.call();
    }
  }

  Future<bool> _confirmarYEliminarHorario(HorarioDisponibilidad horario) async {
    if (!horario.puedeEliminar || _controlador.estaProcesandoAccion) {
      return false;
    }

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contextoDialogo) {
        return AlertDialog(
          key: const Key('dialogoConfirmarEliminacionHorario'),
          backgroundColor: TemaPsicobloom.colorSuperficie,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Row(
            children: <Widget>[
              Icon(
                Icons.delete_outline_rounded,
                color: TemaPsicobloom.colorError,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Eliminar horario',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            '¿Deseas eliminar el intervalo ${horario.rangoHorarioCompacto} del ${horario.fechaCompletaDia}?\n\n'
            'Esta acción se guardará de inmediato.',
            style: const TextStyle(
              fontSize: 14,
              color: TemaPsicobloom.colorTexto,
              height: 1.35,
            ),
          ),
          actions: <Widget>[
            TextButton(
              key: const Key('botonCancelarEliminacionHorario'),
              onPressed: () => Navigator.of(contextoDialogo).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              key: const Key('botonConfirmarEliminacionHorario'),
              style: ElevatedButton.styleFrom(
                backgroundColor: TemaPsicobloom.colorError,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(contextoDialogo).pop(true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirmado != true || !mounted) {
      return false;
    }

    return _controlador.eliminarHorario(horario);
  }

  Future<void> _abrirModalDetalleHorario(HorarioDisponibilidad horario) async {
    _controlador.limpiarMensajes();
    setState(() {
      _hayModalAbierto = true;
    });

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: TemaPsicobloom.colorSuperficie,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (contextoModal) {
          return AnimatedBuilder(
            animation: _controlador,
            builder: (_, _) {
              final horarioActual =
                  _controlador.horarios
                      .where(
                        (item) =>
                            item.idDisponibilidad == horario.idDisponibilidad,
                      )
                      .firstOrNull ??
                  horario;
              final referenciaUtc = _controlador.ahoraUtcReferencia;
              final esNoLaborable = _controlador.esDiaNoLaborable(
                horarioActual.fecha,
              );
              final puedeEditar = horarioActual.puedeEditar(
                referenciaUtc: referenciaUtc,
                esDiaNoLaborable: esNoLaborable,
              );
              final puedeCambiarBloqueo = horarioActual.puedeCambiarBloqueo(
                referenciaUtc: referenciaUtc,
                esDiaNoLaborable: esNoLaborable,
              );
              final esFuturo = horarioActual.esFuturoEnEcuador(
                referenciaUtc: referenciaUtc,
              );
              final deshabilitado = _controlador.estaProcesandoAccion;
              final estiloEstado = _obtenerEstiloEstado(horarioActual);

              return Padding(
                key: Key(
                  'modalDetalleHorario_${horarioActual.idDisponibilidad}',
                ),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: TemaPsicobloom.colorBorde,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.schedule_rounded,
                          color: TemaPsicobloom.colorPrincipal,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Detalle del intervalo',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: TemaPsicobloom.colorTexto,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          onPressed: deshabilitado
                              ? null
                              : () => Navigator.of(contextoModal).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: TemaPsicobloom.colorFondo,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: TemaPsicobloom.colorBorde),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            horarioActual.fechaCompletaDia,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: TemaPsicobloom.colorTextoSecundario,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  '${horarioActual.rangoHorarioCompacto} (${horarioActual.duracionMinutos} min)',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: TemaPsicobloom.colorTexto,
                                  ),
                                ),
                              ),
                              _construirInsigniaEstado(
                                horario: horarioActual,
                                estilo: estiloEstado,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (esNoLaborable) ...<Widget>[
                      const SizedBox(height: 12),
                      _construirNotaEstadoModal(
                        icono: Icons.event_busy_rounded,
                        color: TemaPsicobloom.colorAdvertencia,
                        texto: 'No atiendes este día. Primero vuelve a habilitarlo para cambiar sus horarios.',
                      ),
                    ],
                    if (horarioActual.esReservada) ...<Widget>[
                      const SizedBox(height: 12),
                      _construirNotaEstadoModal(
                        icono: Icons.lock_outline_rounded,
                        color: TemaPsicobloom.colorInformacion,
                        texto: 'Horario reservado por una cita activa. No se puede editar, bloquear ni eliminar.',
                      ),
                    ] else if (horarioActual.tieneCitaVinculada) ...<Widget>[
                      const SizedBox(height: 12),
                      _construirNotaEstadoModal(
                        icono: Icons.lock_outline_rounded,
                        color: TemaPsicobloom.colorInformacion,
                        texto: 'Tiene historial de citas vinculado y no puede eliminarse.',
                      ),
                    ] else if (!esFuturo) ...<Widget>[
                      const SizedBox(height: 12),
                      _construirNotaEstadoModal(
                        icono: Icons.history_rounded,
                        color: TemaPsicobloom.colorTextoSecundario,
                        texto: 'Horario pasado (solo lectura).',
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (puedeEditar) ...<Widget>[
                      ElevatedButton.icon(
                        key: Key(
                          'botonEditarHorario_${horarioActual.idDisponibilidad}',
                        ),
                        onPressed: deshabilitado
                            ? null
                            : () {
                                Navigator.of(contextoModal).pop();
                                _abrirModalFormularioHorario(
                                  horarioParaEditar: horarioActual,
                                );
                              },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Editar horario'),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (puedeCambiarBloqueo) ...<Widget>[
                      OutlinedButton.icon(
                        key: Key(
                          'botonBloqueoHorario_${horarioActual.idDisponibilidad}',
                        ),
                        onPressed: deshabilitado
                            ? null
                            : () async {
                                final exito = await _controlador
                                    .alternarBloqueoHorario(horarioActual);
                                if (exito && contextoModal.mounted) {
                                  Navigator.of(contextoModal).pop();
                                }
                              },
                        icon: Icon(
                          horarioActual.esBloqueada
                              ? Icons.lock_open_outlined
                              : Icons.block_outlined,
                          size: 18,
                        ),
                        label: Text(
                          horarioActual.esBloqueada
                              ? 'Desbloquear horario'
                              : 'Bloquear horario',
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (horarioActual.puedeEliminar)
                      TextButton.icon(
                        key: Key(
                          'botonEliminarDetalleHorario_${horarioActual.idDisponibilidad}',
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: TemaPsicobloom.colorError,
                        ),
                        onPressed: deshabilitado
                            ? null
                            : () async {
                                Navigator.of(contextoModal).pop();
                                await _confirmarYEliminarHorario(horarioActual);
                              },
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        label: const Text('Eliminar horario'),
                      ),
                  ],
                ),
              );
            },
          );
        },
      );
    } finally {
      if (mounted) {
        if (_controlador.mensajeError != null) {
          _controlador.limpiarMensajes();
        }
        setState(() {
          _hayModalAbierto = false;
        });
      }
    }
  }

  Future<void> _abrirModalDiaNoLaborable(DateTime fechaDia) async {
    _controlador.limpiarMensajes();
    final fechaIso = HorarioDisponibilidad.formatearFechaIso(fechaDia);
    final yaEsNoLaborable = _controlador.esDiaNoLaborable(fechaDia);

    if (yaEsNoLaborable) {
      await _confirmarYRetirarDiaNoLaborable(fechaDia);
      return;
    }

    _controladorMotivoDiaNoLaborable.clear();
    final libresPorBloquear = _controlador.contarDisponiblesEnFecha(fechaDia);
    final reservadosAfectados = _controlador.contarReservadosEnFecha(fechaDia);

    setState(() => _hayModalAbierto = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: TemaPsicobloom.colorSuperficie,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (contextoModal) {
          return AnimatedBuilder(
            animation: _controlador,
            builder: (_, _) {
              final rellenoTeclado = MediaQuery.viewInsetsOf(contextoModal)
                  .bottom;
              final deshabilitado = _controlador.estaProcesandoAccion;

              return Padding(
                key: Key('modalDiaNoLaborable_$fechaIso'),
                padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + rellenoTeclado),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: TemaPsicobloom.colorBorde,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: <Widget>[
                          const Icon(
                            Icons.event_busy_rounded,
                            color: TemaPsicobloom.colorPrincipal,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Marcar día no laborable',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: TemaPsicobloom.colorTexto,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: deshabilitado
                                ? null
                                : () => Navigator.of(contextoModal).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        HorarioDisponibilidad.formatearFechaCompletaDia(
                          fechaDia,
                        ),
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: TemaPsicobloom.colorPrincipalOscuro,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        key: Key('resumenImpactoDiaNoLaborable_$fechaIso'),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: TemaPsicobloom.colorFondo,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: TemaPsicobloom.colorBorde),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                const Icon(
                                  Icons.block_outlined,
                                  size: 17,
                                  color: TemaPsicobloom.colorAdvertencia,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Horarios libres por bloquear: $libresPorBloquear',
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: TemaPsicobloom.colorTexto,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: <Widget>[
                                const Icon(
                                  Icons.event_note_outlined,
                                  size: 17,
                                  color: TemaPsicobloom.colorInformacion,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Citas activas (pendientes o confirmadas): $reservadosAfectados',
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: TemaPsicobloom.colorTexto,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Las citas activas se conservan para gestionarlas en Solicitudes. '
                              'No se permitirán nuevas reservas ni horarios.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: TemaPsicobloom.colorTextoSecundario,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Motivo (opcional)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: TemaPsicobloom.colorTexto,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        key: const Key('campoMotivoDiaNoLaborable'),
                        controller: _controladorMotivoDiaNoLaborable,
                        enabled: !deshabilitado,
                        decoration: const InputDecoration(
                          hintText: 'Ej. Congreso, feriado o descanso personal',
                          prefixIcon: Icon(Icons.notes_rounded),
                        ),
                      ),
                      if (_controlador.mensajeError != null) ...<Widget>[
                        const SizedBox(height: 12),
                        _construirBannerMensaje(
                          mensaje: _controlador.mensajeError!,
                          esError: true,
                        ),
                      ],
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        key: const Key('botonConfirmarDiaNoLaborable'),
                        onPressed: deshabilitado
                            ? null
                            : () async {
                                final exito = await _controlador
                                    .registrarDiaNoLaborable(
                                      fecha: fechaDia,
                                      motivo:
                                          _controladorMotivoDiaNoLaborable.text,
                                    );
                                if (exito && contextoModal.mounted) {
                                  Navigator.of(contextoModal).pop();
                                }
                              },
                        icon: const Icon(Icons.event_busy_rounded, size: 18),
                        label: const Text('Confirmar día no laborable'),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        key: const Key('botonCancelarDiaNoLaborable'),
                        onPressed: deshabilitado
                            ? null
                            : () => Navigator.of(contextoModal).pop(),
                        child: const Text('Cancelar'),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      if (mounted) {
        if (_controlador.mensajeError != null) {
          _controlador.limpiarMensajes();
        }
        setState(() => _hayModalAbierto = false);
      }
    }
  }

  Future<void> _confirmarYRetirarDiaNoLaborable(DateTime fechaDia) async {
    if (_controlador.estaProcesandoAccion) {
      return;
    }

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contextoDialogo) {
        return AlertDialog(
          key: const Key('dialogoConfirmarRetiroDiaNoLaborable'),
          backgroundColor: TemaPsicobloom.colorSuperficie,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Row(
            children: <Widget>[
              Icon(
                Icons.event_available_rounded,
                color: TemaPsicobloom.colorPrincipal,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Retirar día no laborable',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            '¿Retirar día no laborable del '
            '${HorarioDisponibilidad.formatearFechaCompletaDia(fechaDia)}?\n\n'
            'Los horarios bloqueados seguirán bloqueados hasta que los habilites.',
            style: const TextStyle(
              fontSize: 14,
              color: TemaPsicobloom.colorTexto,
              height: 1.35,
            ),
          ),
          actions: <Widget>[
            TextButton(
              key: const Key('botonCancelarRetiroDiaNoLaborable'),
              onPressed: () => Navigator.of(contextoDialogo).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              key: const Key('botonConfirmarRetiroDiaNoLaborable'),
              onPressed: () => Navigator.of(contextoDialogo).pop(true),
              child: const Text('Retirar excepción'),
            ),
          ],
        );
      },
    );

    if (confirmado == true && mounted) {
      await _controlador.retirarDiaNoLaborable(fechaDia);
    }
  }

  Future<void> _abrirModalRepetirEstaSemana() async {
    _controlador.limpiarMensajes();
    var semanasSeleccionadas = 1;
    var cargandoVistaPrevia = true;
    VistaPreviaRepeticionSemana? vistaPreviaActual;

    Future<void> cargarVistaPreviaEnModal(
      void Function(void Function()) actualizarModal,
    ) async {
      actualizarModal(() {
        cargandoVistaPrevia = true;
      });
      final resultado = await _controlador.previsualizarRepeticionSemana(
        lunesOrigen: _lunesSemanaVisible,
        semanasPosteriores: semanasSeleccionadas,
      );
      if (mounted) {
        actualizarModal(() {
          vistaPreviaActual = resultado;
          cargandoVistaPrevia = false;
        });
      }
    }

    var inicioCargaDisparado = false;

    setState(() => _hayModalAbierto = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: TemaPsicobloom.colorSuperficie,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (contextoModal) {
          return StatefulBuilder(
            builder: (contextoEstado, actualizarModal) {
              if (!inicioCargaDisparado) {
                inicioCargaDisparado = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (contextoModal.mounted) {
                    cargarVistaPreviaEnModal(actualizarModal);
                  }
                });
              }

              return AnimatedBuilder(
                animation: _controlador,
                builder: (_, _) {
                  final deshabilitado =
                      _controlador.estaProcesandoAccion || cargandoVistaPrevia;
                  final puedeConfirmar =
                      !deshabilitado &&
                      vistaPreviaActual != null &&
                      vistaPreviaActual!.tieneIntervalosParaCrear;

                  return Padding(
                    key: const Key('modalRepetirEstaSemana'),
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: TemaPsicobloom.colorBorde,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: <Widget>[
                              const Icon(
                                Icons.repeat_rounded,
                                color: TemaPsicobloom.colorPrincipal,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Repetir esta semana',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: TemaPsicobloom.colorTexto,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Cerrar',
                                onPressed: _controlador.estaProcesandoAccion
                                    ? null
                                    : () => Navigator.of(contextoModal).pop(),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Semana origen: ${HorarioDisponibilidad.formatearRangoSemana(_lunesSemanaVisible)}',
                            key: const Key('textoSemanaOrigenRepeticion'),
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: TemaPsicobloom.colorPrincipalOscuro,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Repite tus horarios en las próximas semanas. No se copiarán las citas ni los horarios bloqueados.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: TemaPsicobloom.colorTextoSecundario,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            '¿Por cuántas semanas quieres repetir estos horarios?',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: TemaPsicobloom.colorTexto,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: List<Widget>.generate(4, (indice) {
                              final numeroSemanas = indice + 1;
                              final seleccionado =
                                  semanasSeleccionadas == numeroSemanas;
                              return ChoiceChip(
                                key: Key(
                                  'selectorSemanasRepeticion_$numeroSemanas',
                                ),
                                label: Text(
                                  numeroSemanas == 1
                                      ? '1 semana'
                                      : '$numeroSemanas semanas',
                                ),
                                selected: seleccionado,
                                onSelected: _controlador.estaProcesandoAccion
                                    ? null
                                    : (valor) {
                                        if (!valor ||
                                            semanasSeleccionadas ==
                                                numeroSemanas) {
                                          return;
                                        }
                                        semanasSeleccionadas = numeroSemanas;
                                        cargarVistaPreviaEnModal(
                                          actualizarModal,
                                        );
                                      },
                              );
                            }),
                          ),
                          const SizedBox(height: 14),
                          if (_controlador.mensajeError != null) ...<Widget>[
                            _construirBannerMensaje(
                              clave: const Key('bannerErrorModalRepeticion'),
                              mensaje: _controlador.mensajeError!,
                              esError: true,
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (cargandoVistaPrevia)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: TemaPsicobloom.colorPrincipal,
                                ),
                              ),
                            )
                          else if (vistaPreviaActual != null)
                            _construirResumenVistaPreviaRepeticion(
                              vistaPreviaActual!,
                            ),
                          const SizedBox(height: 14),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: OutlinedButton.icon(
                                  key: const Key(
                                    'botonActualizarVistaPreviaRepeticion',
                                  ),
                                  onPressed: _controlador.estaProcesandoAccion
                                      ? null
                                      : () => cargarVistaPreviaEnModal(
                                          actualizarModal,
                                        ),
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Actualizar vista previa'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            key: const Key('botonConfirmarRepeticionSemana'),
                            onPressed: !puedeConfirmar
                                ? null
                                : () async {
                                    final exito = await _controlador
                                        .confirmarRepeticionSemana(
                                          lunesOrigen: _lunesSemanaVisible,
                                          semanasPosteriores:
                                              semanasSeleccionadas,
                                          huellaVistaPrevia: vistaPreviaActual!
                                              .huellaVistaPrevia,
                                        );
                                    if (exito && contextoModal.mounted) {
                                      Navigator.of(contextoModal).pop();
                                    } else {
                                      actualizarModal(() {});
                                    }
                                  },
                            icon: _controlador.estaProcesandoAccion
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: TemaPsicobloom.colorSobrePrincipal,
                                    ),
                                  )
                                : const Icon(
                                    Icons.check_circle_outline_rounded,
                                    size: 18,
                                  ),
                            label: Text(
                              vistaPreviaActual != null &&
                                      vistaPreviaActual!
                                          .tieneIntervalosParaCrear
                                  ? 'Agregar ${vistaPreviaActual!.totalCrear} horarios'
                                  : 'Sin horarios para crear',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      );
    } finally {
      if (mounted) {
        if (_controlador.mensajeError != null) {
          _controlador.limpiarMensajes();
        }
        setState(() => _hayModalAbierto = false);
      }
    }
  }

  Widget _construirResumenVistaPreviaRepeticion(
    VistaPreviaRepeticionSemana vistaPrevia,
  ) {
    if (vistaPrevia.items.isEmpty) {
      return Container(
        key: const Key('contenedorVistaPreviaRepeticionVacia'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: TemaPsicobloom.colorFondo,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: TemaPsicobloom.colorBorde),
        ),
        child: const Text(
          'No hay horarios futuros disponibles para copiar en esta semana.',
          style: TextStyle(
            fontSize: 13,
            color: TemaPsicobloom.colorTextoSecundario,
          ),
        ),
      );
    }

    return Container(
      key: const Key('contenedorVistaPreviaRepeticion'),
      constraints: const BoxConstraints(maxHeight: 260),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorFondo,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Horarios que se agregarán (${vistaPrevia.totalCrear}):',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: TemaPsicobloom.colorExito,
              ),
            ),
            const SizedBox(height: 6),
            if (vistaPrevia.itemsACrear.isEmpty)
              const Text(
                'Estos horarios ya están registrados. No hay horarios nuevos para agregar.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: TemaPsicobloom.colorTextoSecundario,
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: vistaPrevia.itemsACrear
                    .map((item) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: TemaPsicobloom.colorFondoExito,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${HorarioDisponibilidad.formatearDiaCortoConNumero(item.fechaDestino)}: ${item.rangoHorarioCompacto}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: TemaPsicobloom.colorExito,
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            if (vistaPrevia.itemsOmitidos.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                'Horarios que no se agregarán (${vistaPrevia.totalOmitidos}):',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: TemaPsicobloom.colorAdvertencia,
                ),
              ),
              const SizedBox(height: 6),
              ...vistaPrevia.itemsOmitidos.map((item) {
                final motivoLimpio = item.motivo.replaceFirst(
                  RegExp(r'^Omitido:\s*', caseSensitive: false),
                  '',
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 15,
                        color: TemaPsicobloom.colorAdvertencia,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${HorarioDisponibilidad.formatearDiaCortoConNumero(item.fechaDestino)} (${item.rangoHorarioCompacto}): $motivoLimpio',
                          style: const TextStyle(
                            fontSize: 12,
                            color: TemaPsicobloom.colorTextoSecundario,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _construirNotaEstadoModal({
    required IconData icono,
    required Color color,
    required String texto,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 12.5,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cuerpo = AnimatedBuilder(
      animation: _controlador,
      builder: (context, _) {
        return RefreshIndicator(
          color: TemaPsicobloom.colorPrincipal,
          onRefresh: () => _controlador.cargarHorarios(),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            children: <Widget>[
              _construirEncabezadoAgenda(),
              const SizedBox(height: 10),
              _construirSelectorSemana(),
              if (widget.estaPendienteAprobacion) ...<Widget>[
                const SizedBox(height: 12),
                _construirAvisoProfesionalPendiente(),
              ],
              if (!_hayModalAbierto &&
                  _errorFormularioLocal != null) ...<Widget>[
                const SizedBox(height: 12),
                _construirBannerMensaje(
                  mensaje: _errorFormularioLocal!,
                  esError: true,
                ),
              ],
              if (!_hayModalAbierto &&
                  _controlador.mensajeError != null) ...<Widget>[
                const SizedBox(height: 12),
                _construirBannerMensaje(
                  clave: const Key('bannerErrorDisponibilidad'),
                  mensaje: _controlador.mensajeError!,
                  esError: true,
                ),
              ],
              if (_controlador.mensajeExito != null) ...<Widget>[
                const SizedBox(height: 12),
                _construirBannerMensaje(
                  clave: const Key('bannerExitoDisponibilidad'),
                  mensaje: _controlador.mensajeExito!,
                  esError: false,
                ),
              ],
              const SizedBox(height: 14),
              _construirSeccionSemanalHorarios(),
              const SizedBox(height: 12),
              _construirPieAgendaYRepetirSemana(),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );

    if (widget.esVistaIntegrada) {
      return cuerpo;
    }

    return Scaffold(
      backgroundColor: TemaPsicobloom.colorFondo,
      appBar: AppBar(title: const Text('Mis horarios')),
      body: FondoDecorativoBloom(
        mostrarHojas: false,
        child: SafeArea(child: cuerpo),
      ),
    );
  }

  Widget _construirEncabezadoAgenda() {
    final deshabilitado =
        _controlador.estaProcesandoAccion || _controlador.estaCargando;

    return Row(
      children: <Widget>[
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Mis horarios',
                key: Key('tituloMisHorariosAgenda'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: TemaPsicobloom.colorPrincipalOscuro,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Hora de Ecuador (UTC-05:00)',
                style: TextStyle(
                  fontSize: 11.5,
                  color: TemaPsicobloom.colorTextoSecundario,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          key: const Key('botonActualizarListaHorarios'),
          tooltip: 'Actualizar horarios',
          onPressed: _controlador.estaCargando
              ? null
              : () => _controlador.cargarHorarios(),
          icon: const Icon(
            Icons.refresh_rounded,
            size: 20,
            color: TemaPsicobloom.colorPrincipal,
          ),
        ),
        IconButton(
          key: const Key('botonAbrirFormularioHorario'),
          tooltip: 'Agregar horario',
          onPressed: deshabilitado
              ? null
              : () {
                  _prepararNuevoHorario();
                  _abrirModalFormularioHorario();
                },
          icon: const Icon(
            Icons.add_circle_outline_rounded,
            size: 22,
            color: TemaPsicobloom.colorPrincipal,
          ),
        ),
      ],
    );
  }

  Widget _construirSelectorSemana() {
    final lunesActual = HorarioDisponibilidad.normalizarFechaSoloDia(
      HorarioDisponibilidad.obtenerLunesDeSemana(_controlador.ahoraEnEcuador),
    );
    final lunesVisibleNormalizado =
        HorarioDisponibilidad.normalizarFechaSoloDia(_lunesSemanaVisible);
    final estaEnSemanaActual = lunesVisibleNormalizado == lunesActual;
    final puedeRetrocederSemana = lunesVisibleNormalizado.isAfter(lunesActual);

    return Container(
      key: const Key('selectorSemanaAgenda'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            key: const Key('botonSemanaAnteriorAgenda'),
            tooltip: 'Semana anterior',
            visualDensity: VisualDensity.compact,
            onPressed: puedeRetrocederSemana ? () => _cambiarSemana(-1) : null,
            icon: Icon(
              Icons.chevron_left_rounded,
              color: puedeRetrocederSemana
                  ? TemaPsicobloom.colorPrincipalOscuro
                  : TemaPsicobloom.colorTextoSecundario.withValues(alpha: 0.45),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: TemaPsicobloom.colorLavanda.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                HorarioDisponibilidad.formatearRangoSemana(_lunesSemanaVisible),
                key: const Key('textoRangoSemanaAgenda'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: TemaPsicobloom.colorPrincipalOscuro,
                ),
              ),
            ),
          ),
          IconButton(
            key: const Key('botonSemanaSiguienteAgenda'),
            tooltip: 'Semana siguiente',
            visualDensity: VisualDensity.compact,
            onPressed: () => _cambiarSemana(1),
            icon: const Icon(
              Icons.chevron_right_rounded,
              color: TemaPsicobloom.colorPrincipalOscuro,
            ),
          ),
          const SizedBox(width: 4),
          OutlinedButton(
            key: const Key('botonSemanaHoyAgenda'),
            onPressed: estaEnSemanaActual ? null : _irASemanaActual,
            style: OutlinedButton.styleFrom(
              backgroundColor: TemaPsicobloom.colorLavanda.withValues(
                alpha: 0.4,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Hoy'),
          ),
        ],
      ),
    );
  }

  Widget _construirAvisoProfesionalPendiente() {
    return Container(
      key: const Key('avisoDisponibilidadProfesionalPendiente'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorFondoAdvertencia,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: TemaPsicobloom.colorAdvertencia.withValues(alpha: 0.35),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.info_outline,
            color: TemaPsicobloom.colorAdvertencia,
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tu perfil está pendiente de aprobación. Tus horarios serán visibles para pacientes cuando sea aprobado.',
              style: TextStyle(
                fontSize: 13,
                color: TemaPsicobloom.colorAdvertencia,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirContenidoFormularioModal({
    required BuildContext contextoModal,
    required VoidCallback alActualizarModal,
  }) {
    final estaEditando = _idHorarioEnEdicion != null;
    final deshabilitado =
        _controlador.estaProcesandoAccion || _controlador.estaCargando;
    final fechaSeleccionada =
        _parsearFechaTexto(_controladorFecha.text) ??
        _controlador.ahoraEnEcuador.add(const Duration(days: 1));
    final nombreDiaMinuscula =
        HorarioDisponibilidad.formatearNombreDiaMinuscula(fechaSeleccionada);

    final duracionMinutos =
        int.tryParse(_controladorDuracionMinutos.text.trim()) ?? 0;
    final descansoMinutos =
        int.tryParse(_controladorDescansoMinutos.text.trim()) ?? 0;

    final intervalosPrevisualizados =
        (!estaEditando && !_usarIntervaloUnicoLibre)
        ? _controlador.previsualizarIntervalosJornada(
            fecha: fechaSeleccionada,
            horaInicio: _controladorHoraInicio.text,
            horaFin: _controladorHoraFin.text,
            duracionMinutos: duracionMinutos,
            descansoMinutos: descansoMinutos,
          )
        : const <IntervaloHorarioPropuesto>[];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: TemaPsicobloom.colorBorde,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Icon(
              estaEditando
                  ? Icons.edit_calendar_outlined
                  : Icons.add_alarm_outlined,
              color: TemaPsicobloom.colorPrincipal,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                estaEditando
                    ? 'Editar horario'
                    : 'Agregar horarios al $nombreDiaMinuscula',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: TemaPsicobloom.colorPrincipalOscuro,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Cerrar',
              onPressed: deshabilitado
                  ? null
                  : () => Navigator.of(contextoModal).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_errorFormularioLocal != null) ...<Widget>[
          _construirBannerMensaje(
            mensaje: _errorFormularioLocal!,
            esError: true,
          ),
          const SizedBox(height: 12),
        ],
        if (_controlador.mensajeError != null) ...<Widget>[
          _construirBannerMensaje(
            mensaje: _controlador.mensajeError!,
            esError: true,
          ),
          const SizedBox(height: 12),
        ],
        const Text(
          'Fecha (AAAA-MM-DD)',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: TemaPsicobloom.colorTexto,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          key: const Key('campoFechaHorario'),
          controller: _controladorFecha,
          enabled: !deshabilitado,
          onChanged: (_) => alActualizarModal(),
          decoration: InputDecoration(
            hintText: '2026-11-20',
            prefixIcon: const Icon(Icons.calendar_today_outlined),
            suffixIcon: IconButton(
              key: const Key('botonSeleccionarFechaHorario'),
              tooltip: 'Seleccionar fecha en calendario',
              onPressed: deshabilitado
                  ? null
                  : () => _seleccionarFechaConCalendario(
                      alActualizarModal: alActualizarModal,
                    ),
              icon: const Icon(Icons.date_range_outlined),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Desde:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: TemaPsicobloom.colorTexto,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    key: const Key('campoHoraInicioHorario'),
                    controller: _controladorHoraInicio,
                    enabled: !deshabilitado,
                    onChanged: (_) => alActualizarModal(),
                    decoration: InputDecoration(
                      hintText: '09:00',
                      suffixIcon: IconButton(
                        key: const Key('botonSeleccionarHoraInicio'),
                        tooltip: 'Seleccionar hora de inicio',
                        onPressed: deshabilitado
                            ? null
                            : () => _seleccionarHoraConReloj(
                                esInicio: true,
                                alActualizarModal: alActualizarModal,
                              ),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Hasta:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: TemaPsicobloom.colorTexto,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    key: const Key('campoHoraFinHorario'),
                    controller: _controladorHoraFin,
                    enabled: !deshabilitado,
                    onChanged: (_) => alActualizarModal(),
                    decoration: InputDecoration(
                      hintText: '12:00',
                      suffixIcon: IconButton(
                        key: const Key('botonSeleccionarHoraFin'),
                        tooltip: 'Seleccionar hora de fin',
                        onPressed: deshabilitado
                            ? null
                            : () => _seleccionarHoraConReloj(
                                esInicio: false,
                                alActualizarModal: alActualizarModal,
                              ),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!estaEditando) ...<Widget>[
          const SizedBox(height: 12),
          if (!_usarIntervaloUnicoLibre)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Cada cita (min):',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: TemaPsicobloom.colorTexto,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        key: const Key('campoDuracionCitaMinutos'),
                        controller: _controladorDuracionMinutos,
                        enabled: !deshabilitado,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => alActualizarModal(),
                        decoration:
                            PopupMenuButton<int>(
                              tooltip: 'Elegir duración',
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                              ),
                              onSelected: (valor) {
                                _controladorDuracionMinutos.text = valor
                                    .toString();
                                alActualizarModal();
                              },
                              itemBuilder: (_) => const <PopupMenuEntry<int>>[
                                PopupMenuItem<int>(
                                  value: 30,
                                  child: Text('30 min'),
                                ),
                                PopupMenuItem<int>(
                                  value: 45,
                                  child: Text('45 min'),
                                ),
                                PopupMenuItem<int>(
                                  value: 60,
                                  child: Text('60 min'),
                                ),
                                PopupMenuItem<int>(
                                  value: 90,
                                  child: Text('90 min'),
                                ),
                              ],
                            ).let(
                              (menu) => InputDecoration(
                                hintText: '60',
                                suffixIcon: menu,
                              ),
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Descanso (min):',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: TemaPsicobloom.colorTexto,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        key: const Key('campoDescansoCitaMinutos'),
                        controller: _controladorDescansoMinutos,
                        enabled: !deshabilitado,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => alActualizarModal(),
                        decoration:
                            PopupMenuButton<int>(
                              tooltip: 'Elegir descanso',
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                              ),
                              onSelected: (valor) {
                                _controladorDescansoMinutos.text = valor
                                    .toString();
                                alActualizarModal();
                              },
                              itemBuilder: (_) => const <PopupMenuEntry<int>>[
                                PopupMenuItem<int>(
                                  value: 0,
                                  child: Text('0 min'),
                                ),
                                PopupMenuItem<int>(
                                  value: 10,
                                  child: Text('10 min'),
                                ),
                                PopupMenuItem<int>(
                                  value: 15,
                                  child: Text('15 min'),
                                ),
                                PopupMenuItem<int>(
                                  value: 30,
                                  child: Text('30 min'),
                                ),
                              ],
                            ).let(
                              (menu) => InputDecoration(
                                hintText: '0',
                                suffixIcon: menu,
                              ),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 6),
          SwitchListTile.adaptive(
            key: const Key('switchIntervaloUnicoLibre'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text(
              'Intervalo único (duración libre)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: TemaPsicobloom.colorTexto,
              ),
            ),
            subtitle: const Text(
              'Un solo bloque con el rango Desde–Hasta.',
              style: TextStyle(
                fontSize: 11.5,
                color: TemaPsicobloom.colorTextoSecundario,
              ),
            ),
            value: _usarIntervaloUnicoLibre,
            onChanged: deshabilitado
                ? null
                : (valor) {
                    setState(() {
                      _usarIntervaloUnicoLibre = valor;
                    });
                    alActualizarModal();
                  },
          ),
          if (!_usarIntervaloUnicoLibre) ...<Widget>[
            const SizedBox(height: 8),
            const Text(
              'Se crearán estos intervalos:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: TemaPsicobloom.colorTexto,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              key: const Key('vistaPreviaIntervalosJornada'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: TemaPsicobloom.colorFondo,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: TemaPsicobloom.colorBorde),
              ),
              child: intervalosPrevisualizados.isEmpty
                  ? const Text(
                      'Elige las horas y la duración para ver los horarios.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: TemaPsicobloom.colorTextoSecundario,
                      ),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: intervalosPrevisualizados
                          .map((intervalo) {
                            final colorFondo = intervalo.enConflicto
                                ? TemaPsicobloom.colorFondoError
                                : TemaPsicobloom.colorLavanda.withValues(
                                    alpha: 0.55,
                                  );
                            final colorTexto = intervalo.enConflicto
                                ? TemaPsicobloom.colorError
                                : TemaPsicobloom.colorPrincipalOscuro;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: colorFondo,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  if (intervalo.enConflicto) ...<Widget>[
                                    const Icon(
                                      Icons.warning_amber_rounded,
                                      size: 14,
                                      color: TemaPsicobloom.colorError,
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(
                                    intervalo.rangoCompacto,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: colorTexto,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          })
                          .toList(growable: false),
                    ),
            ),
          ],
        ],
        const SizedBox(height: 16),
        if (!estaEditando &&
            _esFechaDeHoy(fechaSeleccionada) &&
            !_quedanHorasDisponiblesHoy()) ...<Widget>[
          _construirNotaEstadoModal(
            icono: Icons.schedule_rounded,
            color: TemaPsicobloom.colorAdvertencia,
            texto: _mensajeSinHorasHoy,
          ),
          const SizedBox(height: 12),
        ],
        ElevatedButton.icon(
          key: const Key('botonGuardarHorarioDisponibilidad'),
          onPressed:
              (deshabilitado ||
                  (!estaEditando &&
                      _esFechaDeHoy(fechaSeleccionada) &&
                      !_quedanHorasDisponiblesHoy()))
              ? null
              : () => _guardarHorarioDesdeFormulario(
                  contextoModal: contextoModal,
                  alActualizarModal: alActualizarModal,
                ),
          icon: _controlador.estaProcesandoAccion
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: TemaPsicobloom.colorSobrePrincipal,
                  ),
                )
              : Icon(estaEditando ? Icons.save_outlined : Icons.add_outlined),
          label: Text(
            estaEditando ? 'Guardar cambios' : 'Agregar al $nombreDiaMinuscula',
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            key: Key(
              estaEditando
                  ? 'botonCancelarEdicionHorario'
                  : 'botonCancelarFormularioHorario',
            ),
            onPressed: deshabilitado
                ? null
                : () {
                    _controlador.limpiarMensajes();
                    setState(() {
                      _errorFormularioLocal = null;
                    });
                    if (estaEditando) {
                      _prepararNuevoHorario();
                    }
                    Navigator.of(contextoModal).pop();
                  },
            child: Text(estaEditando ? 'Cancelar edición' : 'Cancelar'),
          ),
        ),
        if (!estaEditando)
          const Text(
            'Puedes añadir varios horarios de una vez',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: TemaPsicobloom.colorTextoSecundario,
            ),
          ),
      ],
    );
  }

  Widget _construirBannerMensaje({
    Key? clave,
    required String mensaje,
    required bool esError,
  }) {
    final colorFondo = esError
        ? TemaPsicobloom.colorFondoError
        : TemaPsicobloom.colorFondoExito;
    final colorTexto = esError
        ? TemaPsicobloom.colorError
        : TemaPsicobloom.colorExito;
    final icono = esError ? Icons.error_outline : Icons.check_circle_outline;

    return Container(
      key: clave,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorFondo,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorTexto.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icono, color: colorTexto, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: TextStyle(
                color: colorTexto,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirSeccionSemanalHorarios() {
    if (_controlador.estaCargando && !_controlador.tieneHorarios) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: Column(
            children: <Widget>[
              CircularProgressIndicator(color: TemaPsicobloom.colorPrincipal),
              SizedBox(height: 12),
              Text(
                'Cargando tus horarios de disponibilidad...',
                style: TextStyle(color: TemaPsicobloom.colorTextoSecundario),
              ),
            ],
          ),
        ),
      );
    }

    if (_controlador.mensajeError != null && !_controlador.tieneHorarios) {
      return Container(
        key: const Key('estadoErrorCargaHorarios'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: TemaPsicobloom.colorSuperficie,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: TemaPsicobloom.colorBorde),
        ),
        child: Column(
          children: <Widget>[
            const Icon(
              Icons.cloud_off_outlined,
              size: 40,
              color: TemaPsicobloom.colorError,
            ),
            const SizedBox(height: 10),
            Text(
              _controlador.mensajeError!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: TemaPsicobloom.colorTexto,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const Key('botonReintentarCargaHorarios'),
              onPressed: () => _controlador.cargarHorarios(),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    final diasDeSemana = HorarioDisponibilidad.obtenerDiasDeSemana(
      _lunesSemanaVisible,
    );
    final hoySoloDia = HorarioDisponibilidad.normalizarFechaSoloDia(
      _controlador.ahoraEnEcuador,
    );
    final hoyIso = HorarioDisponibilidad.formatearFechaIso(hoySoloDia);
    final diasVisibles = diasDeSemana
        .where(
          (fechaDia) =>
              !HorarioDisponibilidad.normalizarFechaSoloDia(fechaDia)
                  .isBefore(hoySoloDia),
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!_controlador.tieneHorarios)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              key: const Key('estadoListaVaciaHorarios'),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: TemaPsicobloom.colorSuperficie,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: TemaPsicobloom.colorBorde),
              ),
              child: const Row(
                children: <Widget>[
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: TemaPsicobloom.colorTextoSecundario,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sin horarios registrados. Pulsa + en cualquier día para agregar.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: TemaPsicobloom.colorTextoSecundario,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ...diasVisibles.map((fechaDia) {
          final fechaIso = HorarioDisponibilidad.formatearFechaIso(fechaDia);
          final esHoy = fechaIso == hoyIso;
          final horariosDelDia = _controlador.horariosPorFecha(fechaDia);
          final tarjeta = _construirTarjetaDiaSemana(
            fechaDia: fechaDia,
            fechaIso: fechaIso,
            esHoy: esHoy,
            horariosDelDia: horariosDelDia,
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: esHoy
                ? KeyedSubtree(key: _claveTarjetaHoy, child: tarjeta)
                : tarjeta,
          );
        }),
      ],
    );
  }

  Widget _construirTarjetaDiaSemana({
    required DateTime fechaDia,
    required String fechaIso,
    required bool esHoy,
    required List<HorarioDisponibilidad> horariosDelDia,
  }) {
    final tituloDiaCorto = HorarioDisponibilidad.formatearDiaCortoConNumero(
      fechaDia,
    );
    final diaNoLaborable = _controlador.obtenerDiaNoLaborable(fechaDia);
    final esNoLaborable = diaNoLaborable != null;
    final tieneCitasPorGestionarEnDia =
        esNoLaborable &&
        (diaNoLaborable.tieneCitasPorGestionar ||
            horariosDelDia.any((h) => h.esReservada));
    final deshabilitado =
        _controlador.estaProcesandoAccion || _controlador.estaCargando;

    final sinHorasDisponiblesHoy = esHoy && !_quedanHorasDisponiblesHoy();
    final bloquearBotonAgregar =
        deshabilitado || esNoLaborable || sinHorasDisponiblesHoy;

    return Container(
      key: Key('tarjetaDiaAgenda_$fechaIso'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: esNoLaborable
            ? TemaPsicobloom.colorFondoAdvertencia.withValues(alpha: 0.45)
            : TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: esHoy
              ? TemaPsicobloom.colorPrincipal
              : (esNoLaborable
                    ? TemaPsicobloom.colorAdvertencia.withValues(alpha: 0.5)
                    : TemaPsicobloom.colorBorde),
          width: esHoy ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        key: Key('grupoFechaAgenda_$fechaIso'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: InkWell(
                  key: Key('encabezadoDiaAgenda_$fechaIso'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: deshabilitado
                      ? null
                      : () => _abrirModalDiaNoLaborable(fechaDia),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Text(
                              tituloDiaCorto,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: TemaPsicobloom.colorPrincipalOscuro,
                              ),
                            ),
                            if (esHoy) ...<Widget>[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: TemaPsicobloom.colorPrincipal,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Hoy',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: TemaPsicobloom.colorSobrePrincipal,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                key: Key('botonGestionarDiaNoLaborable_$fechaIso'),
                tooltip: esNoLaborable
                    ? 'Retirar día no laborable'
                    : 'Marcar día no laborable',
                visualDensity: VisualDensity.compact,
                onPressed: deshabilitado
                    ? null
                    : () => _abrirModalDiaNoLaborable(fechaDia),
                icon: Icon(
                  esNoLaborable
                      ? Icons.event_busy_rounded
                      : Icons.event_available_outlined,
                  size: 19,
                  color: esNoLaborable
                      ? TemaPsicobloom.colorAdvertencia
                      : TemaPsicobloom.colorTextoSecundario,
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                key: Key('botonAgregarHorarioDia_$fechaIso'),
                tooltip: esNoLaborable
                    ? 'Día no laborable (retira la excepción para agregar horarios)'
                    : (sinHorasDisponiblesHoy
                          ? _mensajeSinHorasHoy
                          : 'Agregar horarios al día'),
                style: IconButton.styleFrom(
                  minimumSize: const Size(38, 38),
                  padding: EdgeInsets.zero,
                  side: BorderSide(
                    color: (esNoLaborable || sinHorasDisponiblesHoy)
                        ? TemaPsicobloom.colorBorde
                        : TemaPsicobloom.colorPrincipal,
                    width: 1.3,
                  ),
                  shape: const CircleBorder(),
                ),
                onPressed: bloquearBotonAgregar
                    ? null
                    : () => _abrirModalFormularioHorario(
                        fechaPreseleccionada: fechaDia,
                      ),
                icon: Icon(
                  Icons.add_rounded,
                  size: 20,
                  color: (esNoLaborable || sinHorasDisponiblesHoy)
                      ? TemaPsicobloom.colorTextoSecundario
                      : TemaPsicobloom.colorPrincipal,
                ),
              ),
            ],
          ),
          if (sinHorasDisponiblesHoy && !esNoLaborable) ...<Widget>[
            const SizedBox(height: 6),
            const Text(
              _mensajeSinHorasHoy,
              style: TextStyle(
                fontSize: 12,
                color: TemaPsicobloom.colorTextoSecundario,
              ),
            ),
          ],
          if (esNoLaborable) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              key: Key(
                tieneCitasPorGestionarEnDia
                    ? 'insigniaDiaNoLaborableCitas_$fechaIso'
                    : 'insigniaDiaNoLaborable_$fechaIso',
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: TemaPsicobloom.colorFondoAdvertencia,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: TemaPsicobloom.colorAdvertencia.withValues(alpha: 0.4),
                ),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        Icons.event_busy_rounded,
                        size: 15,
                        color: TemaPsicobloom.colorAdvertencia,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          tieneCitasPorGestionarEnDia
                              ? 'Día no laborable · Citas por gestionar'
                              : (diaNoLaborable.motivo.isNotEmpty
                                    ? 'Día no laborable · ${diaNoLaborable.motivo}'
                                    : 'Día no laborable'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: TemaPsicobloom.colorAdvertencia,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (tieneCitasPorGestionarEnDia &&
                          widget.alIrASolicitudes != null)
                        TextButton(
                          key: Key(
                            'botonIrASolicitudesDiaNoLaborable_$fechaIso',
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            minimumSize: const Size(0, 26),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: widget.alIrASolicitudes,
                          child: const Text(
                            'Ver Solicitudes',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      TextButton(
                        key: Key('botonRetirarDiaNoLaborable_$fechaIso'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          minimumSize: const Size(0, 26),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: deshabilitado
                            ? null
                            : () => _confirmarYRetirarDiaNoLaborable(fechaDia),
                        child: const Text(
                          'Retirar',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (horariosDelDia.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'Sin horarios',
                style: TextStyle(
                  fontSize: 13,
                  color: TemaPsicobloom.colorTextoSecundario,
                ),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: horariosDelDia
                  .map(_construirChipIntervaloCompacto)
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }

  Widget _construirPieAgendaYRepetirSemana() {
    final deshabilitado =
        _controlador.estaProcesandoAccion || _controlador.estaCargando;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        OutlinedButton.icon(
          key: const Key('botonRepetirEstaSemana'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            side: const BorderSide(
              color: TemaPsicobloom.colorPrincipal,
              width: 1.4,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: deshabilitado ? null : _abrirModalRepetirEstaSemana,
          icon: const Icon(Icons.sync_rounded, size: 20),
          label: const Text(
            'Repetir esta semana',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Elige cuántas semanas al continuar',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: TemaPsicobloom.colorTextoSecundario,
          ),
        ),
      ],
    );
  }

  _EstiloVisualEstadoHorario _obtenerEstiloEstado(
    HorarioDisponibilidad horario,
  ) {
    if (horario.esReservada) {
      return const _EstiloVisualEstadoHorario(
        colorFondo: TemaPsicobloom.colorFondoInformacion,
        colorTexto: TemaPsicobloom.colorInformacion,
        icono: Icons.lock_clock_outlined,
      );
    }
    if (horario.esBloqueada) {
      return const _EstiloVisualEstadoHorario(
        colorFondo: TemaPsicobloom.colorFondoAdvertencia,
        colorTexto: TemaPsicobloom.colorAdvertencia,
        icono: Icons.block_outlined,
      );
    }
    return const _EstiloVisualEstadoHorario(
      colorFondo: TemaPsicobloom.colorFondoExito,
      colorTexto: TemaPsicobloom.colorExito,
      icono: Icons.check_circle_outline_rounded,
    );
  }

  Widget _construirInsigniaEstado({
    required HorarioDisponibilidad horario,
    required _EstiloVisualEstadoHorario estilo,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: estilo.colorFondo,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(estilo.icono, size: 13, color: estilo.colorTexto),
          const SizedBox(width: 3),
          Text(
            horario.etiquetaEstado,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: estilo.colorTexto,
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirChipIntervaloCompacto(HorarioDisponibilidad horario) {
    final deshabilitado = _controlador.estaProcesandoAccion;
    final estiloEstado = _obtenerEstiloEstado(horario);

    return Material(
      color: TemaPsicobloom.colorLavanda.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: Key('tarjetaHorario_${horario.idDisponibilidad}'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => _abrirModalDetalleHorario(horario),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: estiloEstado.colorTexto.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                horario.rangoHorarioCompacto,
                key: Key('textoRangoCompacto_${horario.idDisponibilidad}'),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: TemaPsicobloom.colorPrincipalOscuro,
                ),
              ),
              const SizedBox(width: 6),
              _construirInsigniaEstado(horario: horario, estilo: estiloEstado),
              const SizedBox(width: 4),
              if (horario.puedeEliminar)
                InkWell(
                  key: Key('botonEliminarHorario_${horario.idDisponibilidad}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: deshabilitado
                      ? null
                      : () => _confirmarYEliminarHorario(horario),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.close_rounded,
                      size: 17,
                      color: TemaPsicobloom.colorPrincipalOscuro,
                    ),
                  ),
                )
              else
                Tooltip(
                  message:
                      'Protegido por reserva o historial de citas vinculadas',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      key: Key(
                        'iconoCandadoHorario_${horario.idDisponibilidad}',
                      ),
                      size: 16,
                      color: TemaPsicobloom.colorInformacion,
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

class _EstiloVisualEstadoHorario {
  const _EstiloVisualEstadoHorario({
    required this.colorFondo,
    required this.colorTexto,
    required this.icono,
  });

  final Color colorFondo;
  final Color colorTexto;
  final IconData icono;
}

extension _ExtensionObjeto<T> on T {
  R let<R>(R Function(T valor) transformacion) => transformacion(this);
}
