import 'package:flutter/material.dart';

/// Dibuja el icono oficial multicolor de Google respetando sus colores de marca.
class IconoGoogle extends StatelessWidget {
  final double tamano;

  const IconoGoogle({super.key, this.tamano = 22.0});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: tamano,
      height: tamano,
      child: CustomPaint(painter: _PintorLogoGoogle()),
    );
  }
}

class _PintorLogoGoogle extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double radio = size.width / 2;
    final Offset centro = Offset(radio, radio);
    final double grosor = size.width * 0.22;

    final rect = Rect.fromCircle(center: centro, radius: radio - grosor / 2);

    // Colores oficiales de la marca Google
    const Color azulGoogle = Color(0xFF4285F4);
    const Color verdeGoogle = Color(0xFF34A853);
    const Color amarilloGoogle = Color(0xFFFBBC05);
    const Color rojoGoogle = Color(0xFFEA4335);

    final Paint pincel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor
      ..strokeCap = StrokeCap.butt;

    // Arco Rojo (superior)
    pincel.color = rojoGoogle;
    canvas.drawArc(rect, -2.35, 1.35, false, pincel);

    // Arco Amarillo (izquierda)
    pincel.color = amarilloGoogle;
    canvas.drawArc(rect, -3.7, 1.4, false, pincel);

    // Arco Verde (inferior)
    pincel.color = verdeGoogle;
    canvas.drawArc(rect, 0.45, 1.45, false, pincel);

    // Arco Azul (derecha)
    pincel.color = azulGoogle;
    canvas.drawArc(rect, -0.95, 1.4, false, pincel);

    // Barra horizontal central azul
    final Paint pincelBarra = Paint()
      ..color = azulGoogle
      ..style = PaintingStyle.fill;

    final Rect barraAzul = Rect.fromLTWH(
      centro.dx - grosor * 0.1,
      centro.dy - grosor / 2,
      radio + grosor * 0.1,
      grosor,
    );
    canvas.drawRect(barraAzul, pincelBarra);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
