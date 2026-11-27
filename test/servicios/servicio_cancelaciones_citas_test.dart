import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boom/modelos/gestion_cancelacion_cita.dart';
import 'package:boom/nucleo/componentes/pantalla_gestion_cancelacion_cita.dart';
import 'package:boom/nucleo/servicios/servicio_cancelaciones_citas.dart';
import 'package:boom/nucleo/servicios/servicio_adelantos_citas.dart';

Map<String, dynamic> datos({bool cancelada = false, String pago = 'recibido',
    String devolucion = 'pendiente_devolucion', bool criterio = true, String rol = 'paciente'}) => {
  'id_cita': 'cita-prueba', 'rol': rol, 'estado_cita': cancelada ? 'cancelada' : 'confirmada',
  'puede_cancelar': !cancelada, 'version_previa': 'version-congelada',
  'monto_adelanto': '5.00', 'moneda': 'USD', 'corresponde_devolucion': criterio,
  'estado_pago': pago, 'estado_devolucion': devolucion,
  'cancelada_en': cancelada ? '2026-11-27T15:00:00Z' : null,
  'actor': cancelada ? 'paciente' : null, 'motivo': cancelada ? 'Motivo original' : null,
  'puede_revisar_pago': cancelada && rol == 'profesional' && pago == 'pendiente_verificacion',
  'puede_registrar_devolucion': cancelada && rol == 'profesional' && devolucion == 'pendiente_devolucion',
};

void main() {
  test('Rechaza importes inválidos sin convertirlos en cero', () {
    for (final importe in [null, -1, 'NaN', '5.001']) {
      expect(() => GestionCancelacionCita.desdeMapa({...datos(), 'monto_adelanto': importe}), throwsFormatException);
    }
  });

  test('Un pago reportado no se presenta como dinero recibido', () {
    final gestion = GestionCancelacionCita.desdeMapa(datos(cancelada: true,
      pago: 'pendiente_verificacion', devolucion: 'pendiente_verificacion'));
    expect(gestion.textoConsecuencia, contains('pendiente de verificación'));
    expect(gestion.puedeRegistrarDevolucion, isFalse);
    expect(gestion.textoMonto, contains('5.00'));
  });

  test('Devolución registrada no se presenta como verificación bancaria', () {
    final gestion = GestionCancelacionCita.desdeMapa(datos(cancelada: true, devolucion: 'registrada'));
    expect(gestion.etiquetaDevolucion, 'Devolución registrada por el profesional');
    expect(gestion.puedeCancelar, isFalse);
  });

  test('Exige sesión antes de invocar cualquier RPC', () async {
    var llamadas = 0;
    final servicio = ServicioCancelacionesCitas(lectorUsuarioActualId: () => null,
      ejecutorRpc: (nombre, {parametros}) async { llamadas++; return datos(); });
    await expectLater(servicio.obtener('cita-prueba'), throwsA(isA<ErrorAdelantoCita>()));
    expect(llamadas, 0);
  });

  test('La confirmación envía la versión y no permite importes elegidos por el cliente', () async {
    Map<String, dynamic>? enviados;
    final servicio = ServicioCancelacionesCitas(lectorUsuarioActualId: () => 'paciente',
      ejecutorRpc: (nombre, {parametros}) async {
        expect(nombre, 'cancelar_cita_con_tratamiento_adelanto'); enviados = parametros;
        return datos(cancelada: true, pago: 'pendiente_verificacion', devolucion: 'pendiente_verificacion');
      });
    final respuesta = await servicio.cancelar(GestionCancelacionCita.desdeMapa(datos()),
      '  Cambio de disponibilidad personal  ', pagoReportado: true);
    expect(enviados, {'p_id_cita': 'cita-prueba', 'p_motivo': 'Cambio de disponibilidad personal',
      'p_version_previa': 'version-congelada', 'p_pago_reportado': true});
    expect(respuesta.estadoCita, 'cancelada');
  });

  test('Motivos de 4 y 501 caracteres se rechazan antes de invocar la RPC', () {
    var llamadas = 0;
    final servicio = ServicioCancelacionesCitas(lectorUsuarioActualId: () => 'paciente',
      ejecutorRpc: (nombre, {parametros}) async { llamadas++; return datos(); });
    for (final motivo in ['abcd', List.filled(501, 'x').join()]) {
      expect(() => servicio.cancelar(GestionCancelacionCita.desdeMapa(datos()), motivo), throwsA(isA<ErrorAdelantoCita>()));
    }
    expect(llamadas, 0);
  });

  test('Verificar ingreso en una cancelación no llama a la RPC que confirma citas', () async {
    final servicio = ServicioCancelacionesCitas(lectorUsuarioActualId: () => 'profesional',
      ejecutorRpc: (nombre, {parametros}) async {
        expect(nombre, 'revisar_pago_cita_cancelada');
        expect(parametros!['p_recibido'], true);
        return datos(cancelada: true, rol: 'profesional');
      });
    final resultado = await servicio.revisarPago('cita-prueba', true, 'Ingreso comprobado en la cuenta');
    expect(resultado.estadoCita, 'cancelada');
  });

  test('Referencia demasiado larga no inicia un registro de devolución', () {
    final servicio = ServicioCancelacionesCitas(lectorUsuarioActualId: () => 'profesional');
    expect(() => servicio.registrarDevolucion('cita-prueba', 'ruta.png', List.filled(151, 'a').join()),
      throwsA(isA<ErrorAdelantoCita>()));
  });

  testWidgets('El paciente ve la revisión pendiente sin controles profesionales', (tester) async {
    final servicio = ServicioCancelacionesCitas(lectorUsuarioActualId: () => 'paciente',
      ejecutorRpc: (nombre, {parametros}) async => datos(cancelada: true,
        pago: 'pendiente_verificacion', devolucion: 'pendiente_verificacion'));
    await tester.pumpWidget(MaterialApp(home: PantallaGestionCancelacionCita(idCita: 'cita-prueba', servicio: servicio)));
    await tester.pumpAndSettle();
    expect(find.text('Ingreso pendiente de verificación'), findsOneWidget);
    expect(find.text('Ingreso recibido'), findsNothing);
    expect(find.text('Adjuntar y registrar devolución'), findsNothing);
    expect(find.text('Revisar y cancelar cita'), findsNothing);
  });

  testWidgets('Cancelar requiere una confirmación que muestra el monto', (tester) async {
    var cancelaciones = 0;
    final servicio = ServicioCancelacionesCitas(lectorUsuarioActualId: () => 'paciente',
      ejecutorRpc: (nombre, {parametros}) async {
        if (nombre == 'cancelar_cita_con_tratamiento_adelanto') { cancelaciones++; return datos(cancelada: true); }
        return datos();
      });
    await tester.pumpWidget(MaterialApp(home: PantallaGestionCancelacionCita(idCita: 'cita-prueba', servicio: servicio)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Cambio de horario personal');
    await tester.ensureVisible(find.text('Revisar y cancelar cita'));
    await tester.tap(find.text('Revisar y cancelar cita'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar cancelación'), findsOneWidget);
    expect(find.textContaining('5.00'), findsWidgets);
    expect(cancelaciones, 0);
    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();
    expect(cancelaciones, 0);
  });
}
