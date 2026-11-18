import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boom/nucleo/componentes/icono_google.dart';

void main() {
  testWidgets('IconoGoogle se renderiza correctamente con el tamano solicitado', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: IconoGoogle(tamano: 24.0),
          ),
        ),
      ),
    );

    expect(find.byType(IconoGoogle), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);

    final widgetTamano = tester.getSize(find.byType(IconoGoogle));
    expect(widgetTamano.width, 24.0);
    expect(widgetTamano.height, 24.0);
  });
}
