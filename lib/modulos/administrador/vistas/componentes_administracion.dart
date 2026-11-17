import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:boom/modulos/administrador/modelos/modelos_administracion.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

/// Tarjeta compacta de indicador para el Panel general del administrador.
class TarjetaKpiAdministracion extends StatelessWidget {
  final IconData icono;
  final Color colorIcono;
  final Color colorFondoIcono;
  final String etiqueta;
  final int valor;
  final VoidCallback? alTocar;

  const TarjetaKpiAdministracion({
    super.key,
    required this.icono,
    required this.colorIcono,
    required this.colorFondoIcono,
    required this.etiqueta,
    required this.valor,
    this.alTocar,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TemaPsicobloom.colorSuperficie,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: alTocar,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: TemaPsicobloom.colorBorde),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorFondoIcono,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icono, color: colorIcono, size: 20),
              ),
              const SizedBox(height: 10),
              Text(
                etiqueta,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: TemaPsicobloom.colorTextoSecundario,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$valor',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: TemaPsicobloom.colorTexto,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grafico circular tipo donut para la distribucion real de citas por estado.
class GraficoDonutCitas extends StatelessWidget {
  final ResumenAdministracion resumen;

  const GraficoDonutCitas({super.key, required this.resumen});

  @override
  Widget build(BuildContext context) {
    final segmentos = <_SegmentoDonut>[
      _SegmentoDonut(
        etiqueta: 'Confirmadas',
        cantidad: resumen.citasConfirmadas,
        color: TemaPsicobloom.colorExito,
      ),
      _SegmentoDonut(
        etiqueta: 'Pendientes',
        cantidad: resumen.citasPendientes,
        color: const Color(0xFFE5A93B),
      ),
      _SegmentoDonut(
        etiqueta: 'Rechazadas',
        cantidad: resumen.citasRechazadas,
        color: TemaPsicobloom.colorError,
      ),
      _SegmentoDonut(
        etiqueta: 'Canceladas',
        cantidad: resumen.citasCanceladas,
        color: const Color(0xFFD85B8E),
      ),
      _SegmentoDonut(
        etiqueta: 'Finalizadas',
        cantidad: resumen.citasFinalizadas,
        color: TemaPsicobloom.colorInformacion,
      ),
    ];

    return Container(
      key: const Key('tarjetaDonutCitasAdmin'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Citas por estado',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, restricciones) {
              final compacto = restricciones.maxWidth < 310;
              final grafico = SizedBox(
                width: 118,
                height: 118,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(118, 118),
                      painter: _DonutPainter(
                        segmentos: segmentos,
                        total: resumen.totalCitas,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${resumen.totalCitas}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: TemaPsicobloom.colorTexto,
                          ),
                        ),
                        const Text(
                          'citas',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: TemaPsicobloom.colorTextoSecundario,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );

              final leyenda = Column(
                children: segmentos
                    .map(
                      (s) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: s.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.etiqueta,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: TemaPsicobloom.colorTexto,
                                ),
                              ),
                            ),
                            Text(
                              '${s.cantidad}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: TemaPsicobloom.colorTexto,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              );

              if (compacto) {
                return Column(
                  children: [grafico, const SizedBox(height: 12), leyenda],
                );
              }
              return Row(
                children: [
                  grafico,
                  const SizedBox(width: 18),
                  Expanded(child: leyenda),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SegmentoDonut {
  final String etiqueta;
  final int cantidad;
  final Color color;

  const _SegmentoDonut({
    required this.etiqueta,
    required this.cantidad,
    required this.color,
  });
}

class _DonutPainter extends CustomPainter {
  final List<_SegmentoDonut> segmentos;
  final int total;

  const _DonutPainter({required this.segmentos, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    const grosor = 18.0;
    final centro = Offset(size.width / 2, size.height / 2);
    final radio = (math.min(size.width, size.height) - grosor) / 2;
    final rect = Rect.fromCircle(center: centro, radius: radio);

    if (total <= 0) {
      canvas.drawArc(
        rect,
        0,
        2 * math.pi,
        false,
        Paint()
          ..color = TemaPsicobloom.colorBorde
          ..style = PaintingStyle.stroke
          ..strokeWidth = grosor,
      );
      return;
    }

    var anguloInicial = -math.pi / 2;
    for (final s in segmentos) {
      if (s.cantidad <= 0) continue;
      final barrido = (s.cantidad / total) * 2 * math.pi;
      canvas.drawArc(
        rect,
        anguloInicial,
        barrido,
        false,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = grosor
          ..strokeCap = StrokeCap.butt,
      );
      anguloInicial += barrido;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.total != total || oldDelegate.segmentos != segmentos;
}

/// Etiqueta de estado reutilizable en tarjetas administrativas.
class EtiquetaEstadoAdministracion extends StatelessWidget {
  final String texto;
  final Color colorTexto;
  final Color colorFondo;

  const EtiquetaEstadoAdministracion({
    super.key,
    required this.texto,
    required this.colorTexto,
    required this.colorFondo,
  });

  factory EtiquetaEstadoAdministracion.desdeCuenta({
    required bool activa,
    String? rol,
    String? aprobacion,
  }) {
    if (!activa) {
      return const EtiquetaEstadoAdministracion(
        texto: 'Inactivo',
        colorTexto: TemaPsicobloom.colorError,
        colorFondo: TemaPsicobloom.colorFondoError,
      );
    }
    if (rol == 'profesional' && aprobacion == 'pendiente') {
      return const EtiquetaEstadoAdministracion(
        texto: 'Pendiente',
        colorTexto: TemaPsicobloom.colorAdvertencia,
        colorFondo: TemaPsicobloom.colorFondoAdvertencia,
      );
    }
    if (rol == 'profesional' && aprobacion == 'rechazado') {
      return const EtiquetaEstadoAdministracion(
        texto: 'Rechazado',
        colorTexto: TemaPsicobloom.colorError,
        colorFondo: TemaPsicobloom.colorFondoError,
      );
    }
    return const EtiquetaEstadoAdministracion(
      texto: 'Activo',
      colorTexto: TemaPsicobloom.colorExito,
      colorFondo: TemaPsicobloom.colorFondoExito,
    );
  }

  factory EtiquetaEstadoAdministracion.desdeCita(String estado) {
    switch (estado) {
      case 'confirmada':
        return const EtiquetaEstadoAdministracion(
          texto: 'Confirmada',
          colorTexto: TemaPsicobloom.colorExito,
          colorFondo: TemaPsicobloom.colorFondoExito,
        );
      case 'pendiente':
        return const EtiquetaEstadoAdministracion(
          texto: 'Pendiente',
          colorTexto: TemaPsicobloom.colorAdvertencia,
          colorFondo: TemaPsicobloom.colorFondoAdvertencia,
        );
      case 'finalizada':
        return const EtiquetaEstadoAdministracion(
          texto: 'Finalizada',
          colorTexto: TemaPsicobloom.colorInformacion,
          colorFondo: TemaPsicobloom.colorFondoInformacion,
        );
      case 'cancelada':
        return const EtiquetaEstadoAdministracion(
          texto: 'Cancelada',
          colorTexto: TemaPsicobloom.colorError,
          colorFondo: TemaPsicobloom.colorFondoError,
        );
      case 'rechazada':
        return const EtiquetaEstadoAdministracion(
          texto: 'Rechazada',
          colorTexto: TemaPsicobloom.colorError,
          colorFondo: TemaPsicobloom.colorFondoError,
        );
      default:
        return EtiquetaEstadoAdministracion(
          texto: estado,
          colorTexto: TemaPsicobloom.colorTextoSecundario,
          colorFondo: TemaPsicobloom.colorFondo,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorFondo,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: colorTexto,
        ),
      ),
    );
  }
}

/// Avatar circular con fotografia real o iniciales del usuario.
class AvatarInicialesOFotoAdmin extends StatelessWidget {
  final String nombre;
  final String? fotoUrl;
  final double diametro;

  const AvatarInicialesOFotoAdmin({
    super.key,
    required this.nombre,
    this.fotoUrl,
    this.diametro = 44,
  });

  String _iniciales() {
    final partes = nombre
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (partes.isEmpty) return 'U';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = fotoUrl?.trim() ?? '';
    Widget respaldo() => Container(
      color: TemaPsicobloom.colorLavanda,
      alignment: Alignment.center,
      child: Text(
        _iniciales(),
        style: TextStyle(
          fontSize: diametro * 0.35,
          fontWeight: FontWeight.bold,
          color: TemaPsicobloom.colorPrincipalOscuro,
        ),
      ),
    );

    return Container(
      width: diametro,
      height: diametro,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: ClipOval(
        child: url.isNotEmpty
            ? Image.network(
                url,
                width: diametro,
                height: diametro,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => respaldo(),
              )
            : respaldo(),
      ),
    );
  }
}
