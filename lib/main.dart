import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'configuracion/configuracion_supabase.dart';
import 'tema/tema_psicobloom.dart';
import 'pantallas/acceso/pantalla_carga.dart';

/// Inicializa Supabase y luego ejecuta la aplicacion.
/// La URL y la clave anon deben proveerse mediante --dart-define en tiempo
/// de compilacion. Si faltan, la app avisa en consola pero no se bloquea;
/// las funciones que requieran Supabase fallarán con mensajes claros.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (ConfiguracionSupabase.estaConfigurado) {
    await Supabase.initialize(
      url: ConfiguracionSupabase.url,
      publishableKey: ConfiguracionSupabase.claveAnon,
    );
  } else {
    // En desarrollo sin --dart-define, Supabase no se inicializa.
    // Las pantallas de acceso y datos mostrarán errores funcionales
    // en etapas posteriores cuando se conecten al servicio real.
    debugPrint(
      '[PsicoBloom] AVISO: SUPABASE_URL o SUPABASE_ANON_KEY no '
      'fueron provistos. Ejecuta con --dart-define para conectar.',
    );
  }

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
      home: const PantallaCarga(),
    );
  }
}
