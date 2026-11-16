import 'package:flutter/material.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'pantalla_cuestionario_orientacion.dart';

/// Pantalla de aviso antes del cuestionario de orientación.
/// Muestra información al usuario y, al presionar "Continuar",
/// navega a la pantalla del cuestionario.
class PantallaAvisoOrientacion extends StatelessWidget {
  const PantallaAvisoOrientacion({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aviso'),
        backgroundColor: TemaPsicobloom.colorPrincipal,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Este cuestionario es una guía orientativa y no sustituye la consulta con un profesional de salud. La información será analizada por la IA para recomendar el centro de salud más adecuado.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => const PantallaCuestionarioOrientacion(),
                    ),
                  );
                },
                child: const Text('Continuar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: TemaPsicobloom.colorMenta,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
