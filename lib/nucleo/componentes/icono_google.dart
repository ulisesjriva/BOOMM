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
    // Escala uniforme desde el lienzo vectorial estandar oficial de 24x24 puntos
    final double escala = size.width / 24.0;
    canvas.save();
    canvas.scale(escala, escala);

    final Paint pincel = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Colores oficiales de la marca Google
    const Color rojoGoogle = Color(0xFFEA4335);
    const Color amarilloGoogle = Color(0xFFFBBC05);
    const Color verdeGoogle = Color(0xFF34A853);
    const Color azulGoogle = Color(0xFF4285F4);

    // 1. Arco Rojo (cuadrante superior)
    final Path pathRojo = Path()
      ..moveTo(12.0, 4.75)
      ..cubicTo(14.07, 4.75, 15.93, 5.46, 17.39, 6.85)
      ..lineTo(20.81, 3.43)
      ..cubicTo(18.73, 1.49, 15.65, 0.0, 12.0, 0.0)
      ..cubicTo(7.33, 0.0, 3.26, 2.64, 1.25, 6.58)
      ..lineTo(5.28, 9.73)
      ..cubicTo(6.23, 6.9, 8.88, 4.75, 12.0, 4.75)
      ..close();
    pincel.color = rojoGoogle;
    canvas.drawPath(pathRojo, pincel);

    // 2. Arco Amarillo (lateral izquierdo)
    final Path pathAmarillo = Path()
      ..moveTo(5.28, 14.27)
      ..cubicTo(5.03, 13.55, 4.9, 12.78, 4.9, 12.0)
      ..cubicTo(4.9, 11.22, 5.03, 10.45, 5.28, 9.73)
      ..lineTo(1.25, 6.58)
      ..cubicTo(0.45, 8.16, 0.0, 9.98, 0.0, 12.0)
      ..cubicTo(0.0, 14.02, 0.45, 15.84, 1.25, 17.42)
      ..lineTo(5.28, 14.27)
      ..close();
    pincel.color = amarilloGoogle;
    canvas.drawPath(pathAmarillo, pincel);

    // 3. Arco Verde (cuadrante inferior)
    final Path pathVerde = Path()
      ..moveTo(12.0, 24.0)
      ..cubicTo(15.65, 24.0, 18.73, 22.8, 20.74, 20.93)
      ..lineTo(16.86, 17.88)
      ..cubicTo(15.78, 18.6, 14.07, 19.25, 12.0, 19.25)
      ..cubicTo(8.88, 19.25, 6.23, 17.1, 5.28, 14.27)
      ..lineTo(1.25, 17.42)
      ..cubicTo(3.26, 21.36, 7.33, 24.0, 12.0, 24.0)
      ..close();
    pincel.color = verdeGoogle;
    canvas.drawPath(pathVerde, pincel);

    // 4. Barra y cuadrante Azul (lateral derecho y centro)
    final Path pathAzul = Path()
      ..moveTo(23.75, 12.27)
      ..cubicTo(23.75, 11.48, 23.68, 10.73, 23.55, 10.0)
      ..lineTo(12.0, 10.0)
      ..lineTo(12.0, 14.75)
      ..lineTo(18.6, 14.75)
      ..cubicTo(18.31, 16.27, 17.46, 17.57, 16.86, 17.88)
      ..lineTo(20.74, 20.93)
      ..cubicTo(22.61, 19.2, 23.75, 16.0, 23.75, 12.27)
      ..close();
    pincel.color = azulGoogle;
    canvas.drawPath(pathAzul, pincel);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
