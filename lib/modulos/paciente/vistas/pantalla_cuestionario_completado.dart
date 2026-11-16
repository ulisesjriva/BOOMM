import 'package:flutter/material.dart';
import '../../../nucleo/componentes/fondo_decorativo_bloom.dart';
import '../../../nucleo/tema/tema_psicobloom.dart';
import '../controladores/gestor_resultado_orientacion.dart';
import 'pantalla_cuestionario_orientacion.dart';
import 'pantalla_resultado_orientacion.dart';

/// Pantalla informativa que se muestra cuando el usuario ya ha completado
/// el cuestionario de orientacion en su sesion actual, permitiendole
/// consultar sus recomendaciones o repetir la encuesta si lo desea.
class PantallaCuestionarioCompletado extends StatelessWidget {
  const PantallaCuestionarioCompletado({super.key});

  Future<void> _confirmarYRepetir(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TemaPsicobloom.colorSuperficie,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          '¿Deseas repetir el cuestionario?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: TemaPsicobloom.colorTexto,
          ),
        ),
        content: const Text(
          'Al iniciar un nuevo cuestionario, se descartarán los resultados temporales actuales y comenzarás una nueva evaluación desde el inicio.\n\n'
          'Recuerda que tus respuestas son confidenciales y se procesan en memoria.',
          style: TextStyle(color: TemaPsicobloom.colorTexto, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: TemaPsicobloom.colorPrincipal,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sí, repetir'),
          ),
        ],
      ),
    );

    if (confirmar == true && context.mounted) {
      GestorResultadoOrientacion.instancia.limpiar();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => const PantallaCuestionarioOrientacion(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final resultado = GestorResultadoOrientacion.instancia.resultadoActual;

    return Scaffold(
      backgroundColor: TemaPsicobloom.colorFondo,
      appBar: AppBar(
        title: const Text('Orientación psicológica'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Atrás',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: FondoDecorativoBloom(
        mostrarHojas: false,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),

                // Icono central e indicador de estado completado
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: TemaPsicobloom.colorLavanda,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: TemaPsicobloom.colorPrincipal.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.task_alt_rounded,
                      size: 46,
                      color: TemaPsicobloom.colorPrincipal,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                const Text(
                  'Cuestionario completado',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorTexto,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),

                const Text(
                  'Ya has completado tu cuestionario de orientación psicológica en esta sesión. Tus recomendaciones están listas para que las consultes.',
                  style: TextStyle(
                    fontSize: 14.5,
                    color: TemaPsicobloom.colorTextoSecundario,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Tarjeta resumen del resultado en memoria
                if (resultado != null) ...[
                  Container(
                    padding: const EdgeInsets.all(20.0),
                    decoration: BoxDecoration(
                      color: TemaPsicobloom.colorSuperficie,
                      borderRadius: BorderRadius.circular(18.0),
                      border: Border.all(
                        color: TemaPsicobloom.colorBorde,
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: TemaPsicobloom.colorTexto.withValues(alpha: 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: TemaPsicobloom.colorMenta,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.psychology_outlined,
                                color: TemaPsicobloom.colorSecundario,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Orientación actual disponible',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                  color: TemaPsicobloom.colorTexto,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Especialidad sugerida para tu caso:',
                          style: TextStyle(
                            fontSize: 13,
                            color: TemaPsicobloom.colorTextoSecundario,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          resultado.especialidadRecomendada,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: TemaPsicobloom.colorPrincipalOscuro,
                          ),
                        ),
                        if (resultado.categoriasDetectadas.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 6.0,
                            runSpacing: 6.0,
                            children: resultado.categoriasDetectadas
                                .map(
                                  (categoria) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10.0,
                                      vertical: 4.0,
                                    ),
                                    decoration: BoxDecoration(
                                      color: TemaPsicobloom.colorLavanda,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      categoria,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: TemaPsicobloom.colorPrincipalOscuro,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                ],

                // Boton principal: Ver recomendaciones
                ElevatedButton(
                  onPressed: () {
                    if (resultado != null) {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => PantallaResultadoOrientacion(
                            resultado: resultado,
                          ),
                        ),
                      );
                    }
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.visibility_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('Ver recomendaciones detalladas'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Boton secundario: Repetir cuestionario
                OutlinedButton(
                  onPressed: () => _confirmarYRepetir(context),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh_rounded, size: 20),
                      SizedBox(width: 8),
                      Text('Volver a realizar el cuestionario'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Enlace para volver al inicio
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Volver al inicio'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
