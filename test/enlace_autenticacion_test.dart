import 'package:flutter_test/flutter_test.dart';
import 'package:boom/modelos/enlace_autenticacion.dart';

void main() {
  const base = 'https://psicobloom-7201a.web.app/autenticacion.html';

  test('Acepta el enlace HTTPS real del correo sin imprimir el token', () {
    final enlace = EnlaceAutenticacion.desdeUri(Uri.parse('$base#tipo=signup&token_hash=token_prueba_123'))!;
    expect(enlace.tipo, TipoEnlaceAutenticacion.confirmacion);
    expect(enlace.tokenHash, 'token_prueba_123');
    expect(enlace.toString(), isNot(contains('token_prueba_123')));
  });

  test('Acepta la recuperacion enviada por intent al paquete Android', () {
    final enlace = EnlaceAutenticacion.desdeUri(Uri.parse('$base?tipo=recovery&token_hash=token_prueba_123'))!;
    expect(enlace.tipo, TipoEnlaceAutenticacion.recuperacion);
  });

  test('Rechaza dominios parecidos, rutas diferentes y puertos no autorizados', () {
    for (final url in [
      'https://psicobloom-7201a.web.app.ejemplo.com/autenticacion.html',
      'http://psicobloom-7201a.web.app/autenticacion.html',
      'https://psicobloom-7201a.web.app/autenticacion.html/otra',
      'https://psicobloom-7201a.web.app:444/autenticacion.html',
      'https://usuario@psicobloom-7201a.web.app/autenticacion.html',
    ]) {
      expect(EnlaceAutenticacion.desdeUri(Uri.parse(url)), isNull);
    }
  });

  test('Sin token no autoriza ninguna recuperacion', () {
    expect(EnlaceAutenticacion.desdeUri(Uri.parse('$base#tipo=recovery'))!.tipo, TipoEnlaceAutenticacion.invalido);
    expect(EnlaceAutenticacion.desdeUri(Uri.parse('psicobloom://acceso/'))!.tipo, TipoEnlaceAutenticacion.abrirAcceso);
  });

  test('Rechaza duplicados y el intento de inyectar un rol', () {
    for (final url in [
      '$base?tipo=signup&tipo=recovery&token_hash=prueba',
      '$base#tipo=signup&tipo=recovery&token_hash=prueba',
      '$base?tipo=signup#tipo=recovery&token_hash=prueba',
      '$base#tipo=signup&token_hash=prueba&rol=administrador',
      '$base#tipo=recovery&token_hash=token%0Ainyectado',
      '$base#tipo=administrador&token_hash=prueba',
    ]) {
      expect(EnlaceAutenticacion.desdeUri(Uri.parse(url))!.tipo, TipoEnlaceAutenticacion.invalido);
    }
  });

  test('Conserva los callbacks antiguos para el SDK de Supabase', () {
    expect(EnlaceAutenticacion.desdeUri(Uri.parse('psicobloom://acceso/?code=solo_prueba')), isNull);
  });
}
