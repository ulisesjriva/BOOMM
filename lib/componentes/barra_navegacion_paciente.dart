import 'package:flutter/material.dart';

import '../tema/tema_psicobloom.dart';

/// Barra de navegacion inferior para las pantallas del paciente en PsicoBloom.
/// Mantiene las cinco opciones del boceto aprobado con indicador visual
/// de pestana activa.
class BarraNavegacionPaciente extends StatelessWidget {
  final int indiceSeleccionado;
  final ValueChanged<int> alCambiarPestana;

  const BarraNavegacionPaciente({
    super.key,
    required this.indiceSeleccionado,
    required this.alCambiarPestana,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        border: Border(
          top: BorderSide(
            color: TemaPsicobloom.colorBorde.withValues(alpha: 0.6),
            width: 1.0,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: TemaPsicobloom.colorTexto.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _construirBotonPestana(
                context: context,
                indice: 0,
                iconoActivo: Icons.home_rounded,
                iconoInactivo: Icons.home_outlined,
                etiqueta: 'Inicio',
              ),
              _construirBotonPestana(
                context: context,
                indice: 1,
                iconoActivo: Icons.search_rounded,
                iconoInactivo: Icons.search_rounded,
                etiqueta: 'Buscar',
              ),
              _construirBotonPestana(
                context: context,
                indice: 2,
                iconoActivo: Icons.map_rounded,
                iconoInactivo: Icons.map_outlined,
                etiqueta: 'Mapa',
              ),
              _construirBotonPestana(
                context: context,
                indice: 3,
                iconoActivo: Icons.calendar_month_rounded,
                iconoInactivo: Icons.calendar_today_outlined,
                etiqueta: 'Citas',
              ),
              _construirBotonPestana(
                context: context,
                indice: 4,
                iconoActivo: Icons.person_rounded,
                iconoInactivo: Icons.person_outline_rounded,
                etiqueta: 'Perfil',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _construirBotonPestana({
    required BuildContext context,
    required int indice,
    required IconData iconoActivo,
    required IconData iconoInactivo,
    required String etiqueta,
  }) {
    final bool esActiva = indice == indiceSeleccionado;
    final Color colorActual = esActiva
        ? TemaPsicobloom.colorPrincipal
        : TemaPsicobloom.colorTextoSecundario;

    return InkWell(
      onTap: () => alCambiarPestana(indice),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              esActiva ? iconoActivo : iconoInactivo,
              color: colorActual,
              size: 24,
            ),
            const SizedBox(height: 3),
            Text(
              etiqueta,
              style: TextStyle(
                color: colorActual,
                fontSize: 12,
                fontWeight: esActiva ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 3),
            // Punto indicador de la pestana activa segun el boceto
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: esActiva
                    ? TemaPsicobloom.colorPrincipal
                    : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
