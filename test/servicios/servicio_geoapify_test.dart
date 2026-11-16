import 'package:flutter_test/flutter_test.dart';
import 'package:boom/nucleo/servicios/servicio_geoapify.dart';

void main() {
  test(
    'Solo admite resultados geograficos validos dentro de la zona de Riobamba',
    () {
      final resultados = ServicioGeoapify.interpretarRespuesta({
        'resultados': [
          {
            'direccion': 'Parque Maldonado, Riobamba',
            'latitud': -1.67098,
            'longitud': -78.64712,
          },
          {'direccion': 'Quito', 'latitud': -0.18, 'longitud': -78.46},
          {'direccion': 'Error', 'latitud': double.nan, 'longitud': -78.64},
          {'direccion': 'Error', 'latitud': -1.67, 'longitud': double.infinity},
          {'direccion': '', 'latitud': -1.67, 'longitud': -78.64},
          {'direccion': 'Error', 'latitud': '-1.67', 'longitud': -78.64},
        ],
      });
      expect(resultados, hasLength(1));
      expect(resultados.single.direccion, contains('Maldonado'));
    },
  );
  test(
    'Una busqueda sin resultados se conserva vacia; no inventa coordenadas',
    () {
      expect(
        ServicioGeoapify.interpretarRespuesta({'resultados': []}),
        isEmpty,
      );
      expect(
        () => ServicioGeoapify.interpretarRespuesta({'error': 'interno'}),
        throwsA(isA<ErrorGeoapify>()),
      );
    },
  );
  test('Distingue sesion caducada, cuota y cuenta inactiva sin filtrar errores tecnicos', () {
    expect(ServicioGeoapify.mensajeError(401), contains('sesión'));
    expect(ServicioGeoapify.mensajeError(403), contains('cuenta'));
    expect(
      ServicioGeoapify.mensajeError(429, 'CUOTA_MAPA'),
      contains('límite gratuito'),
    );
    expect(ServicioGeoapify.mensajeError(503), contains('todavía'));
  });
  test('Valida la direccion antes de hacer una llamada remota', () async {
    await expectLater(
      const ServicioGeoapify().buscarDireccion('a'),
      throwsA(isA<ErrorGeoapify>()),
    );
  });
}
