import 'package:flutter/material.dart';

import 'nucleo/tema/tema_psicobloom.dart';

import 'package:boom/modulos/paciente/vistas/pantalla_inicio_paciente.dart';

void main() {
  runApp(const AplicacionPsicoBloomDesarrollo());
}

/// Punto de entrada exclusivo para desarrollo y pruebas de las pantallas del paciente.
/// Permite ejecutar y validar las interfaces sin interferir con el flujo
/// de autenticacion ni con el archivo main.dart de produccion.
class AplicacionPsicoBloomDesarrollo extends StatelessWidget {
  const AplicacionPsicoBloomDesarrollo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PsicoBloom (Modo Desarrollo)',
      debugShowCheckedModeBanner: false,
      theme: TemaPsicobloom.obtenerTema(),
      home: const PantallaInicioPaciente(nombrePaciente: 'María'),
    );
  }
}
