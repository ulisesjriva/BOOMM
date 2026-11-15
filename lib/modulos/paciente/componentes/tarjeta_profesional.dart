import 'package:flutter/material.dart';

import '../../../nucleo/tema/tema_psicobloom.dart';
import '../../../modelos/profesional.dart';

/// Tarjeta reutilizable que presenta la informacion clave de un profesional
/// de la salud mental en las pantallas de Inicio y Buscar profesionales.
class TarjetaProfesional extends StatelessWidget {
  final Profesional profesional;
  final bool esFavorito;
  final VoidCallback alAlternarFavorito;
  final VoidCallback alVerPerfil;
  final bool mostrarDireccionConsultorio;

  const TarjetaProfesional({
    super.key,
    required this.profesional,
    required this.esFavorito,
    required this.alAlternarFavorito,
    required this.alVerPerfil,
    this.mostrarDireccionConsultorio = false,
  });

  String get _textoEspecialidades {
    if (mostrarDireccionConsultorio && profesional.especialidades.isNotEmpty) {
      return profesional.especialidades.join(', ');
    }
    return profesional.especialidad;
  }

  String get _textoUbicacion {
    if (mostrarDireccionConsultorio) {
      final direccion = profesional.direccionConsultorio.trim();
      if (direccion.isNotEmpty) {
        return direccion;
      }
      if (profesional.modalidad.trim().toLowerCase() == 'virtual') {
        return 'Modalidad virtual';
      }
      return 'Dirección por confirmar en Riobamba';
    }
    return profesional.distanciaTexto;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: TemaPsicobloom.colorBorde.withValues(alpha: 0.8),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: TemaPsicobloom.colorTexto.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar con iniciales y punto de disponibilidad
              Stack(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: TemaPsicobloom.colorLavanda,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: TemaPsicobloom.colorBorde,
                        width: 1.0,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child:
                          (profesional.fotoUrl != null &&
                              profesional.fotoUrl!.trim().isNotEmpty)
                          ? Image.network(
                              profesional.fotoUrl!.trim(),
                              width: 58,
                              height: 58,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Center(
                                child: Text(
                                  _obtenerIniciales(profesional.nombre),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: TemaPsicobloom.colorPrincipal,
                                  ),
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                _obtenerIniciales(profesional.nombre),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: TemaPsicobloom.colorPrincipal,
                                ),
                              ),
                            ),
                    ),
                  ),
                  if (profesional.estaDisponible)
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: TemaPsicobloom.colorExito,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: TemaPsicobloom.colorSuperficie,
                            width: 2.0,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // Informacion del profesional
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profesional.nombre,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: TemaPsicobloom.colorTexto,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _textoEspecialidades,
                      style: const TextStyle(
                        fontSize: 13,
                        color: TemaPsicobloom.colorTextoSecundario,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: TemaPsicobloom.colorTextoSecundario,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            _textoUbicacion,
                            style: const TextStyle(
                              fontSize: 12,
                              color: TemaPsicobloom.colorTextoSecundario,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: TemaPsicobloom.colorFondo,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: TemaPsicobloom.colorBorde,
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            profesional.modalidad,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: TemaPsicobloom.colorTextoSecundario,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Boton de favorito
              IconButton(
                icon: Icon(
                  esFavorito
                      ? Icons.favorite_rounded
                      : Icons.favorite_outline_rounded,
                  color: esFavorito
                      ? TemaPsicobloom.colorPrincipal
                      : TemaPsicobloom.colorTextoSecundario,
                  size: 22,
                ),
                tooltip: esFavorito
                    ? 'Quitar de favoritos'
                    : 'Agregar a favoritos',
                onPressed: alAlternarFavorito,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: TemaPsicobloom.colorBorde),
          const SizedBox(height: 10),
          // Fila inferior: Disponibilidad y boton Ver perfil
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: profesional.estaDisponible
                        ? TemaPsicobloom.colorFondoExito
                        : TemaPsicobloom.colorFondoAdvertencia,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 13,
                        color: profesional.estaDisponible
                            ? TemaPsicobloom.colorExito
                            : TemaPsicobloom.colorAdvertencia,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          profesional.disponibilidadTexto,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: profesional.estaDisponible
                                ? TemaPsicobloom.colorExito
                                : TemaPsicobloom.colorAdvertencia,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: alVerPerfil,
                style: ElevatedButton.styleFrom(
                  backgroundColor: TemaPsicobloom.colorPrincipal,
                  foregroundColor: TemaPsicobloom.colorSobrePrincipal,
                  minimumSize: const Size(104, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ver perfil',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded, size: 13),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _obtenerIniciales(String nombreCompleto) {
    final partes = nombreCompleto
        .replaceAll('Dra. ', '')
        .replaceAll('Dr. ', '')
        .replaceAll('Lic. ', '')
        .trim()
        .split(' ');
    if (partes.length >= 2) {
      return '${partes[0][0]}${partes[1][0]}';
    } else if (partes.isNotEmpty && partes[0].isNotEmpty) {
      return partes[0][0];
    }
    return 'PB';
  }
}
