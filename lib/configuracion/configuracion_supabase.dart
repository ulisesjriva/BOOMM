/// Configuracion centralizada de la conexion con el proyecto Supabase PSICOBLOOM.
///
/// La URL y la clave anon se inyectan en tiempo de compilacion mediante
/// --dart-define, de modo que no quedan escritas en el repositorio.
/// Estas variables son publicas en la app compilada; no son secretos de servidor.
library;

/// Contiene los valores necesarios para inicializar el cliente de Supabase.
class ConfiguracionSupabase {
  ConfiguracionSupabase._();

  /// URL del proyecto Supabase. Se establece con:
  ///   --dart-define=SUPABASE_URL=https://hteasqflwhfvlckubvio.supabase.co
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  /// Clave anon (publica) del proyecto Supabase. Se establece con:
  ///   --dart-define=SUPABASE_ANON_KEY=clave_anon_del_panel
  /// Esta clave es publica: aparece en cualquier cliente que use la app.
  /// Los permisos reales se controlan mediante Row Level Security en Supabase.
  static const String claveAnon = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Devuelve true si ambos valores fueron provistos en la compilacion.
  static bool get estaConfigurado => url.isNotEmpty && claveAnon.isNotEmpty;

  /// Clave de API de Google Maps inyectada opcionalmente con:
  ///   --dart-define=GOOGLE_MAPS_API_KEY=clave_google_maps
  static const String claveGoogleMaps = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  /// Devuelve true solo cuando se configuro una clave de Google Maps,
  /// evitando instanciar el PlatformView nativo de GoogleMap si no existe
  /// com.google.android.geo.API_KEY configurado en Android.
  static bool get tieneClaveGoogleMaps => claveGoogleMaps.trim().isNotEmpty;
}
