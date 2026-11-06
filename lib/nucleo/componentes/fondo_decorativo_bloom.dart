import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tema/tema_psicobloom.dart';

/// Lienzo vectorial nativo que dibuja ondas organicas, ramas con follaje
/// en las cuatro esquinas y sutiles corazones flotantes de la identidad PsicoBloom.
class FondoDecorativoBloom extends StatelessWidget {
  final Widget child;
  final bool mostrarHojas;
  final bool mostrarCorazones;

  const FondoDecorativoBloom({
    super.key,
    required this.child,
    this.mostrarHojas = true,
    this.mostrarCorazones = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: TemaPsicobloom.colorFondo,
      child: CustomPaint(
        painter: _PintorLienzoBloom(
          mostrarHojas: mostrarHojas,
          mostrarCorazones: mostrarCorazones,
        ),
        child: child,
      ),
    );
  }
}

class _PintorLienzoBloom extends CustomPainter {
  final bool mostrarHojas;
  final bool mostrarCorazones;

  _PintorLienzoBloom({
    required this.mostrarHojas,
    required this.mostrarCorazones,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ancho = size.width;
    final alto = size.height;

    // Pintura para las ondas lavanda de fondo
    final pincelOndaSuave = Paint()
      ..color = TemaPsicobloom.colorLavanda.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;

    final pincelOndaMedia = Paint()
      ..color = const Color(0xFFE5DCF7).withValues(alpha: 0.40)
      ..style = PaintingStyle.fill;

    // --- 1. ONDAS SUPERIORES ---
    final caminoOndaSuperior1 = Path()
      ..moveTo(0, 0)
      ..lineTo(ancho * 0.70, 0)
      ..cubicTo(
        ancho * 0.60,
        alto * 0.10,
        ancho * 0.30,
        alto * 0.14,
        0,
        alto * 0.18,
      )
      ..close();
    canvas.drawPath(caminoOndaSuperior1, pincelOndaSuave);

    final caminoOndaSuperior2 = Path()
      ..moveTo(0, 0)
      ..lineTo(ancho * 0.40, 0)
      ..cubicTo(
        ancho * 0.35,
        alto * 0.07,
        ancho * 0.12,
        alto * 0.10,
        0,
        alto * 0.12,
      )
      ..close();
    canvas.drawPath(caminoOndaSuperior2, pincelOndaMedia);

    // --- 2. ONDAS INFERIORES ---
    final caminoOndaInferior1 = Path()
      ..moveTo(0, alto)
      ..lineTo(0, alto * 0.82)
      ..cubicTo(
        ancho * 0.28,
        alto * 0.85,
        ancho * 0.62,
        alto * 0.74,
        ancho,
        alto * 0.80,
      )
      ..lineTo(ancho, alto)
      ..close();
    canvas.drawPath(caminoOndaInferior1, pincelOndaSuave);

    final caminoOndaInferior2 = Path()
      ..moveTo(ancho * 0.40, alto)
      ..cubicTo(
        ancho * 0.65,
        alto * 0.95,
        ancho * 0.82,
        alto * 0.88,
        ancho,
        alto * 0.89,
      )
      ..lineTo(ancho, alto)
      ..close();
    canvas.drawPath(caminoOndaInferior2, pincelOndaMedia);

    if (mostrarHojas) {
      // Pinceles para ramas y hojas en tonos lavanda y menta
      final colorLavandaHojas = const Color(0xFFBFA9E5).withValues(alpha: 0.70);
      final colorMentaHojas = const Color(0xFF90C8B6).withValues(alpha: 0.75);

      final pincelHojasLavanda = Paint()
        ..color = colorLavandaHojas
        ..style = PaintingStyle.fill;

      final pincelTalloLavanda = Paint()
        ..color = colorLavandaHojas
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;

      final pincelHojasMenta = Paint()
        ..color = colorMentaHojas
        ..style = PaintingStyle.fill;

      final pincelTalloMenta = Paint()
        ..color = colorMentaHojas
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;

      // 3. Rama Superior Izquierda (Lavanda)
      final caminoTalloSupIzq = Path()
        ..moveTo(-8, alto * 0.04)
        ..quadraticBezierTo(
          ancho * 0.12,
          alto * 0.09,
          ancho * 0.18,
          alto * 0.07,
        );
      canvas.drawPath(caminoTalloSupIzq, pincelTalloLavanda);
      _dibujarHoja(
        canvas,
        Offset(ancho * 0.08, alto * 0.06),
        math.pi * 0.22,
        28,
        12,
        pincelHojasLavanda,
      );
      _dibujarHoja(
        canvas,
        Offset(ancho * 0.14, alto * 0.08),
        math.pi * 0.15,
        26,
        11,
        pincelHojasLavanda,
      );
      _dibujarHoja(
        canvas,
        Offset(ancho * 0.04, alto * 0.10),
        math.pi * 0.35,
        24,
        10,
        pincelHojasLavanda,
      );

      // 4. Rama Superior Derecha (Menta)
      final caminoTalloSupDer = Path()
        ..moveTo(ancho + 8, alto * 0.04)
        ..quadraticBezierTo(
          ancho * 0.88,
          alto * 0.09,
          ancho * 0.82,
          alto * 0.06,
        );
      canvas.drawPath(caminoTalloSupDer, pincelTalloMenta);
      _dibujarHoja(
        canvas,
        Offset(ancho * 0.92, alto * 0.06),
        -math.pi * 0.25,
        28,
        12,
        pincelHojasMenta,
      );
      _dibujarHoja(
        canvas,
        Offset(ancho * 0.86, alto * 0.08),
        -math.pi * 0.18,
        26,
        11,
        pincelHojasMenta,
      );
      _dibujarHoja(
        canvas,
        Offset(ancho * 0.96, alto * 0.10),
        -math.pi * 0.38,
        24,
        10,
        pincelHojasMenta,
      );

      // 5. Rama Inferior Izquierda (Menta)
      final caminoTalloInfIzq = Path()
        ..moveTo(-8, alto * 0.96)
        ..quadraticBezierTo(
          ancho * 0.10,
          alto * 0.90,
          ancho * 0.16,
          alto * 0.82,
        );
      canvas.drawPath(caminoTalloInfIzq, pincelTalloMenta);
      _dibujarHoja(
        canvas,
        Offset(ancho * 0.06, alto * 0.92),
        -math.pi * 0.65,
        30,
        13,
        pincelHojasMenta,
      );
      _dibujarHoja(
        canvas,
        Offset(ancho * 0.12, alto * 0.87),
        -math.pi * 0.58,
        28,
        12,
        pincelHojasMenta,
      );
      _dibujarHoja(
        canvas,
        Offset(ancho * 0.16, alto * 0.80),
        -math.pi * 0.50,
        26,
        11,
        pincelHojasMenta,
      );

      // 6. Rama Inferior Derecha (Lavanda)
      final caminoTalloInfDer = Path()
        ..moveTo(ancho + 8, alto * 0.96)
        ..quadraticBezierTo(
          ancho * 0.90,
          alto * 0.90,
          ancho * 0.84,
          alto * 0.82,
        );
      canvas.drawPath(caminoTalloInfDer, pincelTalloLavanda);
      _dibujarHoja(
        canvas,
        Offset(ancho * 0.94, alto * 0.92),
        -math.pi * 0.35,
        30,
        13,
        pincelHojasLavanda,
      );
      _dibujarHoja(
        canvas,
        Offset(ancho * 0.88, alto * 0.87),
        -math.pi * 0.42,
        28,
        12,
        pincelHojasLavanda,
      );
      _dibujarHoja(
        canvas,
        Offset(ancho * 0.84, alto * 0.80),
        -math.pi * 0.50,
        26,
        11,
        pincelHojasLavanda,
      );
    }

    if (mostrarCorazones) {
      // 7. Sutiles corazones flotantes lavanda
      final pincelCorazon = Paint()
        ..color = const Color(0xFFC7B6E9).withValues(alpha: 0.55)
        ..style = PaintingStyle.fill;

      _dibujarCorazon(
        canvas,
        Offset(ancho * 0.78, alto * 0.15),
        9,
        pincelCorazon,
      );
      _dibujarCorazon(
        canvas,
        Offset(ancho * 0.50, alto * 0.85),
        11,
        pincelCorazon,
      );
    }
  }

  void _dibujarHoja(
    Canvas canvas,
    Offset posicion,
    double angulo,
    double longitud,
    double anchura,
    Paint pincel,
  ) {
    canvas.save();
    canvas.translate(posicion.dx, posicion.dy);
    canvas.rotate(angulo);

    final caminoHoja = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(longitud * 0.5, -anchura, longitud, 0)
      ..quadraticBezierTo(longitud * 0.5, anchura, 0, 0)
      ..close();

    canvas.drawPath(caminoHoja, pincel);
    canvas.restore();
  }

  void _dibujarCorazon(
    Canvas canvas,
    Offset centro,
    double radio,
    Paint pincel,
  ) {
    canvas.save();
    canvas.translate(centro.dx, centro.dy);

    final caminoCorazon = Path();
    caminoCorazon.moveTo(0, radio * 0.3);
    caminoCorazon.cubicTo(
      -radio * 0.8,
      -radio * 0.6,
      -radio * 1.5,
      radio * 0.2,
      0,
      radio * 1.3,
    );
    caminoCorazon.cubicTo(
      radio * 1.5,
      radio * 0.2,
      radio * 0.8,
      -radio * 0.6,
      0,
      radio * 0.3,
    );
    caminoCorazon.close();

    canvas.drawPath(caminoCorazon, pincel);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
