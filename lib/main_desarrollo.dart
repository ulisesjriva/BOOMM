import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'configuracion/configuracion_supabase.dart';
import 'nucleo/tema/tema_psicobloom.dart';

import 'package:boom/modulos/paciente/vistas/pantalla_inicio_paciente.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa Supabase si se inyectaron las credenciales en tiempo de
  // compilacion (--dart-define-from-file=configuracion_supabase.json).
  // Sin credenciales el modo desarrollo sigue funcionando con datos simulados.
  if (ConfiguracionSupabase.estaConfigurado) {
    await Supabase.initialize(
      url: ConfiguracionSupabase.url,
      publishableKey: ConfiguracionSupabase.claveAnon,
    );
  }

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
