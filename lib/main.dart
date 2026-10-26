import 'package:flutter/material.dart';
import 'tema/tema_psicobloom.dart';
import 'pantallas/acceso/pantalla_bienvenida.dart';

void main() {
  runApp(const AplicacionPsicoBloom());
}

/// Punto de entrada principal de la aplicacion movil PsicoBloom.
class AplicacionPsicoBloom extends StatelessWidget {
  const AplicacionPsicoBloom({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PsicoBloom',
      debugShowCheckedModeBanner: false,
      theme: TemaPsicobloom.obtenerTema(),
      home: const PantallaBienvenida(),
    );
  }
}
