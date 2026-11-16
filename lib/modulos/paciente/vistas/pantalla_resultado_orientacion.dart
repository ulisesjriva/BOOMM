import 'package:flutter/material.dart';
import '../../../nucleo/tema/tema_psicobloom.dart';
import '../modelos/cuestionario_orientacion.dart';
import 'pantalla_buscar_profesionales.dart';

/// Pantalla que presenta la orientacion analizada por la IA,
/// recomendando especialidades y centros de atencion en Riobamba.
class PantallaResultadoOrientacion extends StatelessWidget {
  final ResultadoOrientacion resultado;

  const PantallaResultadoOrientacion({
    super.key,
    required this.resultado,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: TemaPsicobloom.colorFondo,
        appBar: AppBar(
          title: const Text('Resultado de orientación'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Alerta de prioridad si se detecto ideacion o crisis
                if (resultado.requiereAtencionPrioritaria) ...[
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: TemaPsicobloom.colorFondoError,
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(
                        color: TemaPsicobloom.colorError.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.emergency_outlined,
                          color: TemaPsicobloom.colorError,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Acompañamiento prioritario',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: TemaPsicobloom.colorError,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Tus respuestas indican momentos de angustia severa. No estás solo/a. Puedes comunicarte de forma gratuita y confidencial a la línea 171 (Opción 6) o al ECU 911 para recibir contención en crisis inmediata.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: TemaPsicobloom.colorTexto,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                // Tarjeta principal con la especialidad recomendada
                Container(
                  padding: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    color: TemaPsicobloom.colorSuperficie,
                    borderRadius: BorderRadius.circular(20.0),
                    border: Border.all(
                      color: TemaPsicobloom.colorPrincipal.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: TemaPsicobloom.colorPrincipal.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: TemaPsicobloom.colorLavanda,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.psychology_outlined,
                              color: TemaPsicobloom.colorPrincipal,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Especialidad sugerida',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: TemaPsicobloom.colorTextoSecundario,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Orientación con IA',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: TemaPsicobloom.colorSecundario,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        resultado.especialidadRecomendada,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: TemaPsicobloom.colorPrincipalOscuro,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        resultado.descripcion,
                        style: const TextStyle(
                          fontSize: 14,
                          color: TemaPsicobloom.colorTexto,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1, color: TemaPsicobloom.colorBorde),
                      const SizedBox(height: 14),
                      const Text(
                        'Áreas de interés identificadas:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: TemaPsicobloom.colorTextoSecundario,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: resultado.categoriasDetectadas.map((cat) {
                          return Chip(
                            label: Text(cat),
                            backgroundColor: TemaPsicobloom.colorMenta,
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            labelStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: TemaPsicobloom.colorSecundario,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Tarjeta de profesional sugerido por coincidencia (Match)
                if (resultado.profesionalSugerido != null) ...[
                  Container(
                    padding: const EdgeInsets.all(18.0),
                    decoration: BoxDecoration(
                      color: TemaPsicobloom.colorSuperficie,
                      borderRadius: BorderRadius.circular(18.0),
                      border: Border.all(
                        color: TemaPsicobloom.colorSecundario.withValues(alpha: 0.4),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: TemaPsicobloom.colorMenta,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.person_search_rounded,
                                color: TemaPsicobloom.colorSecundario,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Profesional con mayor afinidad',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: TemaPsicobloom.colorTexto,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          resultado.profesionalSugerido!,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: TemaPsicobloom.colorPrincipalOscuro,
                          ),
                        ),
                        if (resultado.razonMatch != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            resultado.razonMatch!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: TemaPsicobloom.colorTextoSecundario,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Tarjeta de centros de atencion en Riobamba
                Container(
                  padding: const EdgeInsets.all(18.0),
                  decoration: BoxDecoration(
                    color: TemaPsicobloom.colorSuperficie,
                    borderRadius: BorderRadius.circular(18.0),
                    border: Border.all(color: TemaPsicobloom.colorBorde),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            color: TemaPsicobloom.colorSecundario,
                            size: 22,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Centros sugeridos en Riobamba',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: TemaPsicobloom.colorTexto,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...resultado.centrosRecomendadosRiobamba.map(
                        (centro) => Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 4.0),
                                child: Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 16,
                                  color: TemaPsicobloom.colorSecundario,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  centro,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    color: TemaPsicobloom.colorTexto,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Descargo legal / clinico
                Container(
                  padding: const EdgeInsets.all(14.0),
                  decoration: BoxDecoration(
                    color: TemaPsicobloom.colorFondoInformacion,
                    borderRadius: BorderRadius.circular(14.0),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: TemaPsicobloom.colorInformacion,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Aviso ético: Esta orientación tiene carácter estrictamente informativo y preliminar. No sustituye un diagnóstico psicológico formal.',
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
                const SizedBox(height: 28),

                // Botones de accion
                ElevatedButton(
                  onPressed: () {
                    // Navega al directorio general de profesionales
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (context) =>
                            const PantallaBuscarProfesionales(),
                      ),
                    );
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_rounded, size: 20),
                      SizedBox(width: 8),
                      Text('Buscar profesionales recomendados'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Volver al inicio'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
