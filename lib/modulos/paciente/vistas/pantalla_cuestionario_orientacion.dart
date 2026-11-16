import 'package:flutter/material.dart';

import '../../../nucleo/tema/tema_psicobloom.dart';
import '../controladores/controlador_cuestionario_orientacion.dart';
import '../datos/preguntas_cuestionario.dart';
import '../modelos/cuestionario_orientacion.dart';
import 'pantalla_resultado_orientacion.dart';

/// Pantalla interactiva que guía al paciente por las 10 etapas del cuestionario de orientación.
/// Maneja las respuestas en memoria volátil y procesa la orientación con IA.
class PantallaCuestionarioOrientacion extends StatefulWidget {
  const PantallaCuestionarioOrientacion({super.key});

  @override
  State<PantallaCuestionarioOrientacion> createState() =>
      _PantallaCuestionarioOrientacionState();
}

class _PantallaCuestionarioOrientacionState
    extends State<PantallaCuestionarioOrientacion> {
  late final ControladorCuestionarioOrientacion _controlador;

  @override
  void initState() {
    super.initState();
    _controlador = ControladorCuestionarioOrientacion();
    _controlador.addListener(_actualizar);
  }

  void _actualizar() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controlador.removeListener(_actualizar);
    _controlador.dispose();
    super.dispose();
  }

  Future<bool> _confirmarSalida() async {
    if (_controlador.etapaActual == EtapaCuestionario.introduccion ||
        _controlador.etapaActual == EtapaCuestionario.resultado) {
      return true;
    }

    final respuesta = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TemaPsicobloom.colorSuperficie,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          '¿Deseas salir del cuestionario?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: TemaPsicobloom.colorTexto,
          ),
        ),
        content: const Text(
          'Tus respuestas temporales en memoria se descartarán y no se guardará ningún registro.',
          style: TextStyle(color: TemaPsicobloom.colorTexto, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continuar cuestionario'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: TemaPsicobloom.colorError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    return respuesta ?? false;
  }

  void _mostrarAvisoCrisis() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TemaPsicobloom.colorSuperficie,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(
              Icons.support_agent_rounded,
              color: TemaPsicobloom.colorPrincipal,
            ),
            SizedBox(width: 8),
            Text(
              'Líneas de ayuda y apoyo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'En situaciones de crisis o malestar emocional intenso, puedes comunicarte inmediatamente con:\n\n'
          '• Línea gratuita de contención emocional: 171 (Opción 6)\n'
          '• Emergencias y auxilio médico: ECU 911\n\n'
          'Recuerda que este servicio es confidencial y está disponible 24/7 en todo el Ecuador.',
          style: TextStyle(color: TemaPsicobloom.colorTexto, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _avanzarOSometer() async {
    if (!_controlador.puedeAvanzar()) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: TemaPsicobloom.colorAdvertencia,
          content: Text(
            'Por favor responde las preguntas visibles antes de continuar.',
          ),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_controlador.etapaActual == EtapaCuestionario.otrasAdicciones) {
      await _controlador.finalizarYAnalizar();
      if (!mounted) return;
      if (_controlador.resultado != null) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (context) => PantallaResultadoOrientacion(
              resultado: _controlador.resultado!,
            ),
          ),
        );
      }
    } else {
      _controlador.avanzar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navegador = Navigator.of(context);
        final salir = await _confirmarSalida();
        if (salir && mounted) {
          navegador.pop();
        }
      },
      child: Scaffold(
        backgroundColor: TemaPsicobloom.colorFondo,
        appBar: AppBar(
          title: Text(_controlador.etapaActual.titulo),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Atrás',
            onPressed: () async {
              if (_controlador.etapaActual == EtapaCuestionario.introduccion) {
                Navigator.of(context).pop();
              } else {
                _controlador.retroceder();
              }
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Salir',
              onPressed: () async {
                final navegador = Navigator.of(context);
                final salir = await _confirmarSalida();
                if (salir && mounted) {
                  navegador.pop();
                }
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(6.0),
            child: LinearProgressIndicator(
              value: _controlador.progreso,
              backgroundColor: TemaPsicobloom.colorBorde,
              valueColor: const AlwaysStoppedAnimation<Color>(
                TemaPsicobloom.colorPrincipal,
              ),
              minHeight: 5.0,
            ),
          ),
        ),
        body: _controlador.estaProcesando
            ? _construirVistaCargando()
            : _controlador.etapaActual == EtapaCuestionario.introduccion
            ? _construirVistaIntroduccion()
            : _construirVistaPreguntas(),
      ),
    );
  }

  Widget _construirVistaCargando() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              color: TemaPsicobloom.colorPrincipal,
            ),
            const SizedBox(height: 24),
            const Text(
              'Analizando tus respuestas con IA...',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: TemaPsicobloom.colorTexto,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Conectando con el asistente de orientación para sugerirte las mejores especialidades y centros en Riobamba.',
              style: TextStyle(
                fontSize: 13.5,
                color: TemaPsicobloom.colorTextoSecundario,
                height: 1.35,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirVistaIntroduccion() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 22.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Icono ilustrativo y titulo
            Center(
              child: Container(
                width: 90,
                height: 90,
                decoration: const BoxDecoration(
                  color: TemaPsicobloom.colorLavanda,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.explore_outlined,
                  size: 48,
                  color: TemaPsicobloom.colorPrincipal,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Cuestionario de Orientación',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: TemaPsicobloom.colorTexto,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Un breve recorrido para identificar tus necesidades de salud mental y conectarte con el especialista o centro adecuado en Riobamba.',
              style: TextStyle(
                fontSize: 14.5,
                color: TemaPsicobloom.colorTextoSecundario,
                height: 1.35,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // DESCARGO DE RESPONSABILIDAD OBLIGATORIO
            Container(
              padding: const EdgeInsets.all(18.0),
              decoration: BoxDecoration(
                color: TemaPsicobloom.colorFondoAdvertencia,
                borderRadius: BorderRadius.circular(16.0),
                border: Border.all(
                  color: TemaPsicobloom.colorAdvertencia.withValues(alpha: 0.4),
                  width: 1.2,
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: TemaPsicobloom.colorAdvertencia,
                    size: 26,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Aviso importante y descargo ético',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: TemaPsicobloom.colorAdvertencia,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Esta encuesta es exclusivamente una guía informativa de orientación para ayudarte a elegir qué tipo de profesional consultar.\n\n'
                          'NO constituye una respuesta médica ni un diagnóstico psicológico verídico, ni sustituye una evaluación clínica formal.',
                          style: TextStyle(
                            fontSize: 13,
                            color: TemaPsicobloom.colorTexto,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Tarjeta de confidencialidad y datos volatiles
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: TemaPsicobloom.colorSuperficie,
                borderRadius: BorderRadius.circular(16.0),
                border: Border.all(color: TemaPsicobloom.colorBorde),
              ),
              child: const Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        color: TemaPsicobloom.colorSecundario,
                        size: 22,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Privacidad garantizada',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: TemaPsicobloom.colorTexto,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Tus respuestas se mantienen únicamente en la memoria de tu dispositivo durante la sesión y no se almacenan permanentemente en la base de datos.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: TemaPsicobloom.colorTextoSecundario,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Boton para comenzar
            ElevatedButton(
              onPressed: () => _controlador.avanzar(),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Entendido y comenzar'),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 20),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _construirVistaPreguntas() {
    final etapa = _controlador.etapaActual;
    final preguntas = preguntasPorEtapa[etapa] ?? const [];
    final preguntasVisibles = preguntas
        .where((p) => p.estaVisible(_controlador.respuestas))
        .toList();

    return Column(
      children: [
        // Encabezado de la etapa
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          color: TemaPsicobloom.colorSuperficie,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: TemaPsicobloom.colorLavanda,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Etapa ${etapa.numero} de 10',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorPrincipalOscuro,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  etapa.titulo,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: TemaPsicobloom.colorTexto,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: TemaPsicobloom.colorBorde),

        // Lista deslizable de preguntas
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(
              horizontal: 20.0,
              vertical: 16.0,
            ),
            itemCount: preguntasVisibles.length,
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (context, indice) {
              final pregunta = preguntasVisibles[indice];
              return _construirTarjetaPregunta(pregunta, indice + 1);
            },
          ),
        ),

        // Barra inferior de navegacion
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
          decoration: BoxDecoration(
            color: TemaPsicobloom.colorSuperficie,
            border: Border(
              top: BorderSide(
                color: TemaPsicobloom.colorBorde.withValues(alpha: 0.8),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _controlador.retroceder(),
                  child: const Text('Anterior'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: ElevatedButton(
                  onPressed: _avanzarOSometer,
                  child: Text(
                    etapa == EtapaCuestionario.otrasAdicciones
                        ? 'Analizar con IA'
                        : 'Siguiente',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _construirTarjetaPregunta(
    PreguntaOrientacion pregunta,
    int numeroOrden,
  ) {
    final respuestaActual = _controlador.obtenerRespuesta(pregunta.id);

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: respuestaActual != null
              ? TemaPsicobloom.colorPrincipal.withValues(alpha: 0.35)
              : TemaPsicobloom.colorBorde,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: TemaPsicobloom.colorTexto.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pregunta.contexto != null) ...[
            Text(
              pregunta.contexto!,
              style: const TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: TemaPsicobloom.colorTextoSecundario,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            '$numeroOrden. ${pregunta.texto}',
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: TemaPsicobloom.colorTexto,
              height: 1.35,
            ),
          ),
          if (pregunta.textoExplicativo != null) ...[
            const SizedBox(height: 6),
            Text(
              pregunta.textoExplicativo!,
              style: const TextStyle(
                fontSize: 12.5,
                color: TemaPsicobloom.colorTextoSecundario,
                height: 1.3,
              ),
            ),
          ],
          if (pregunta.esSensible) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: _mostrarAvisoCrisis,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: TemaPsicobloom.colorFondoInformacion,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.phone_in_talk_rounded,
                      color: TemaPsicobloom.colorInformacion,
                      size: 16,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Línea de contención en crisis 171 (Opción 6)',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: TemaPsicobloom.colorInformacion,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),

          // Control de respuesta segun tipo
          if (pregunta.tipo == TipoPreguntaOrientacion.siNo)
            _construirOpcionesSiNo(pregunta.id, respuestaActual as String?)
          else
            _construirOpcionesMultiples(
              pregunta.id,
              pregunta.opciones,
              (respuestaActual as List<dynamic>?)?.cast<String>() ?? const [],
            ),
        ],
      ),
    );
  }

  Widget _construirOpcionesSiNo(String idPregunta, String? respuestaActual) {
    return Row(
      children: [
        Expanded(
          child: _botonAlternable(
            etiqueta: 'Sí',
            estaSeleccionado: respuestaActual == 'Sí',
            alPresionar: () => _controlador.responderSiNo(idPregunta, 'Sí'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _botonAlternable(
            etiqueta: 'No',
            estaSeleccionado: respuestaActual == 'No',
            alPresionar: () => _controlador.responderSiNo(idPregunta, 'No'),
          ),
        ),
      ],
    );
  }

  Widget _botonAlternable({
    required String etiqueta,
    required bool estaSeleccionado,
    required VoidCallback alPresionar,
  }) {
    return InkWell(
      onTap: alPresionar,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: estaSeleccionado
              ? TemaPsicobloom.colorPrincipal
              : TemaPsicobloom.colorFondo,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: estaSeleccionado
                ? TemaPsicobloom.colorPrincipal
                : TemaPsicobloom.colorBorde,
            width: estaSeleccionado ? 1.5 : 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          etiqueta,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.bold,
            color: estaSeleccionado ? Colors.white : TemaPsicobloom.colorTexto,
          ),
        ),
      ),
    );
  }

  Widget _construirOpcionesMultiples(
    String idPregunta,
    List<String> opciones,
    List<String> seleccionadas,
  ) {
    return Column(
      children: opciones.map((opcion) {
        final estaMarcada = seleccionadas.contains(opcion);
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            opcion,
            style: TextStyle(
              fontSize: 13,
              fontWeight: estaMarcada ? FontWeight.w600 : FontWeight.normal,
              color: estaMarcada
                  ? TemaPsicobloom.colorPrincipalOscuro
                  : TemaPsicobloom.colorTexto,
            ),
          ),
          value: estaMarcada,
          activeColor: TemaPsicobloom.colorPrincipal,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (_) =>
              _controlador.alternarOpcionMultiple(idPregunta, opcion),
        );
      }).toList(),
    );
  }
}
