import 'package:flutter/material.dart';

import 'package:boom/modulos/paciente/controladores/controlador_info_economica_profesional.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

/// Tarjeta compacta de informacion economica para el paciente.
/// Se reutiliza en el perfil publico del profesional y en el resumen previo
/// al envio de una solicitud de cita.
/// En esta etapa solo muestra informacion economica (sin botones de pago,
/// sin adjuntar comprobantes y sin mostrar QR ni datos bancarios).
class TarjetaInfoEconomicaProfesional extends StatelessWidget {
  final ControladorInfoEconomicaProfesional controlador;
  final VoidCallback alReintentar;
  final bool mostrarAvisoResumenSolicitud;

  const TarjetaInfoEconomicaProfesional({
    super.key,
    required this.controlador,
    required this.alReintentar,
    this.mostrarAvisoResumenSolicitud = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('tarjetaInfoEconomicaProfesional'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.payments_outlined,
                size: 19,
                color: TemaPsicobloom.colorPrincipal,
              ),
              SizedBox(width: 8),
              Text(
                'Información económica',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: TemaPsicobloom.colorTexto,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _construirContenido(),
          if (mostrarAvisoResumenSolicitud &&
              controlador.info != null &&
              controlador.info!.exigeAdelanto) ...[
            const SizedBox(height: 10),
            Container(
              key: const Key('avisoCondicionesAdelantoSolicitud'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: TemaPsicobloom.colorFondo,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: TemaPsicobloom.colorBorde),
              ),
              child: const Text(
                'Al enviar esta solicitud con adelanto, si el profesional acepta podrás ver su QR privado y tendrás hasta exactamente 24 horas antes de la cita para transferir y adjuntar el comprobante. El profesional dispone de 12 horas para verificar el ingreso.',
                style: TextStyle(
                  fontSize: 12,
                  color: TemaPsicobloom.colorTextoSecundario,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _construirContenido() {
    if (controlador.estaCargando) {
      return const Row(
        key: Key('estadoCargandoInfoEconomica'),
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: TemaPsicobloom.colorPrincipal,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Consultando información económica...',
              style: TextStyle(
                fontSize: 13,
                color: TemaPsicobloom.colorTextoSecundario,
              ),
            ),
          ),
        ],
      );
    }

    if (controlador.mensajeError != null) {
      return Column(
        key: const Key('estadoErrorInfoEconomica'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            controlador.mensajeError!,
            style: const TextStyle(
              fontSize: 13,
              color: TemaPsicobloom.colorError,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('botonReintentarInfoEconomica'),
            onPressed: alReintentar,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(120, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Reintentar'),
          ),
        ],
      );
    }

    final info = controlador.info;
    if (info == null || !info.profesionalVisible) {
      return const Text(
        'Información económica no disponible para este profesional.',
        key: Key('estadoNoDisponibleInfoEconomica'),
        style: TextStyle(
          fontSize: 13,
          color: TemaPsicobloom.colorTextoSecundario,
        ),
      );
    }

    if (!info.tienePrecioConfigurado) {
      return const Text(
        'Precio por confirmar con el profesional',
        key: Key('estadoSinPrecioInfoEconomica'),
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: TemaPsicobloom.colorTextoSecundario,
        ),
      );
    }

    if (!info.exigeAdelanto) {
      return Column(
        key: const Key('estadoSinAdelantoInfoEconomica'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _construirLineaImporte(
            'Valor de consulta: ${info.textoPrecioConsulta}',
            destacado: true,
          ),
          const SizedBox(height: 4),
          const Text(
            'Este profesional no requiere adelanto',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: TemaPsicobloom.colorSecundario,
            ),
          ),
        ],
      );
    }

    return Column(
      key: const Key('estadoConAdelantoInfoEconomica'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _construirLineaImporte(
          'Valor de consulta: ${info.textoPrecioConsulta}',
          destacado: true,
        ),
        const SizedBox(height: 4),
        _construirLineaImporte(
          'Adelanto: ${info.textoMontoAdelanto}',
          color: TemaPsicobloom.colorPrincipalOscuro,
        ),
        const SizedBox(height: 4),
        _construirLineaImporte(
          'Saldo después del adelanto: ${info.textoSaldoDespuesAdelanto}',
          color: TemaPsicobloom.colorTextoSecundario,
        ),
      ],
    );
  }

  Widget _construirLineaImporte(
    String texto, {
    bool destacado = false,
    Color? color,
  }) {
    return Text(
      texto,
      style: TextStyle(
        fontSize: destacado ? 14 : 13.5,
        fontWeight: destacado ? FontWeight.bold : FontWeight.w600,
        color: color ?? TemaPsicobloom.colorTexto,
      ),
    );
  }
}
