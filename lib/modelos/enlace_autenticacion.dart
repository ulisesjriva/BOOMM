enum TipoEnlaceAutenticacion { confirmacion, recuperacion, abrirAcceso, invalido }

/// Datos de un enlace propio. El token solo vive en memoria y nunca se imprime.
class EnlaceAutenticacion {
  static const dominio = 'psicobloom-7201a.web.app';
  static const ruta = '/autenticacion.html';

  final TipoEnlaceAutenticacion tipo;
  final String? tokenHash;

  const EnlaceAutenticacion._(this.tipo, [this.tokenHash]);

  String get identidadEnMemoria => '${tipo.name}:${tokenHash ?? ''}';

  static bool esUrlWebPropia(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == dominio &&
      (!uri.hasPort || uri.port == 443) &&
      uri.userInfo.isEmpty &&
      uri.path == ruta;

  static EnlaceAutenticacion? desdeUri(Uri uri) {
    final esAcceso = uri.scheme == 'psicobloom' &&
        uri.host == 'acceso' &&
        !uri.hasPort &&
        uri.userInfo.isEmpty &&
        (uri.path.isEmpty || uri.path == '/');
    if (!esUrlWebPropia(uri) && !esAcceso) return null;

    try {
      final clavesFragmento = <String>{};
      for (final parte in uri.fragment.split('&')) {
        if (parte.isEmpty) continue;
        final clave = Uri.decodeQueryComponent(parte.split('=').first);
        if (!clavesFragmento.add(clave)) {
          return const EnlaceAutenticacion._(TipoEnlaceAutenticacion.invalido);
        }
      }
      final fragmento = Uri.splitQueryString(uri.fragment);
      final consulta = uri.queryParametersAll;
      // Evita parametros duplicados o credenciales ambiguas entre query y hash.
      for (final clave in ['tipo', 'token_hash']) {
        if ((consulta[clave]?.length ?? 0) > 1 ||
            (consulta.containsKey(clave) && fragmento.containsKey(clave))) {
          return const EnlaceAutenticacion._(TipoEnlaceAutenticacion.invalido);
        }
      }
      final valores = <String, String>{...uri.queryParameters, ...fragmento};
      if (esAcceso && valores.isEmpty) {
        return const EnlaceAutenticacion._(TipoEnlaceAutenticacion.abrirAcceso);
      }
      // Los callbacks OAuth antiguos siguen siendo responsabilidad del SDK.
      if (esAcceso && !valores.containsKey('token_hash') &&
          (valores.containsKey('code') || valores.containsKey('access_token'))) {
        return null;
      }
      if (valores.keys.any((clave) => !['tipo', 'token_hash'].contains(clave))) {
        return const EnlaceAutenticacion._(TipoEnlaceAutenticacion.invalido);
      }
      final token = valores['token_hash'];
      if (token == null || token.isEmpty || token.length > 2048 ||
          !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(token)) {
        return const EnlaceAutenticacion._(TipoEnlaceAutenticacion.invalido);
      }
      final tipo = switch (valores['tipo']) {
        'signup' => TipoEnlaceAutenticacion.confirmacion,
        'recovery' => TipoEnlaceAutenticacion.recuperacion,
        _ => TipoEnlaceAutenticacion.invalido,
      };
      return EnlaceAutenticacion._(tipo, token);
    } on FormatException {
      return const EnlaceAutenticacion._(TipoEnlaceAutenticacion.invalido);
    }
  }

  @override
  String toString() => 'EnlaceAutenticacion(${tipo.name}, token oculto)';
}
