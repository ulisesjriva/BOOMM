import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:boom/nucleo/tema/tema_psicobloom.dart';

/// Avatar circular reutilizable para el paciente en las pantallas de Inicio y Perfil.
/// Prioriza: 1) vista previa local en memoria (si se proporciona),
/// 2) fotografia disponible (por ejemplo Google OAuth o perfil),
/// 3) iniciales del paciente, 4) icono por defecto.
class AvatarPaciente extends StatelessWidget {
  final String nombreCompleto;
  final String? fotoUrl;
  final Uint8List? bytesVistaPrevia;
  final double diametro;
  final Color? colorBorde;
  final double anchoBorde;

  const AvatarPaciente({
    super.key,
    required this.nombreCompleto,
    this.fotoUrl,
    this.bytesVistaPrevia,
    this.diametro = 68,
    this.colorBorde,
    this.anchoBorde = 1.5,
  });

  static String obtenerIniciales(String nombreCompleto) {
    final partes = nombreCompleto
        .trim()
        .split(RegExp(r'\s+'))
        .where((parte) => parte.isNotEmpty)
        .toList();
    if (partes.length >= 2) {
      return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
    }
    if (partes.isNotEmpty) {
      return partes[0][0].toUpperCase();
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final urlLimpia = fotoUrl?.trim() ?? '';
    final tieneVistaPrevia =
        bytesVistaPrevia != null && bytesVistaPrevia!.isNotEmpty;
    final tieneFotoUrl = urlLimpia.isNotEmpty;
    final iniciales = obtenerIniciales(nombreCompleto);

    Widget construirRespaldo() {
      return Container(
        color: TemaPsicobloom.colorLavanda,
        alignment: Alignment.center,
        child: iniciales.isNotEmpty
            ? Text(
                iniciales,
                style: TextStyle(
                  fontSize: diametro * 0.32,
                  fontWeight: FontWeight.bold,
                  color: TemaPsicobloom.colorPrincipalOscuro,
                ),
              )
            : Icon(
                Icons.person_rounded,
                color: TemaPsicobloom.colorPrincipal,
                size: diametro * 0.5,
              ),
      );
    }

    Widget contenido;
    if (tieneVistaPrevia) {
      contenido = Image.memory(
        bytesVistaPrevia!,
        width: diametro,
        height: diametro,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => construirRespaldo(),
      );
    } else if (tieneFotoUrl) {
      contenido = Image.network(
        urlLimpia,
        width: diametro,
        height: diametro,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => construirRespaldo(),
      );
    } else {
      contenido = construirRespaldo();
    }

    return Container(
      width: diametro,
      height: diametro,
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorLavanda,
        shape: BoxShape.circle,
        border: Border.all(
          color:
              colorBorde ??
              TemaPsicobloom.colorPrincipal.withValues(alpha: 0.25),
          width: anchoBorde,
        ),
      ),
      child: ClipOval(child: contenido),
    );
  }
}
