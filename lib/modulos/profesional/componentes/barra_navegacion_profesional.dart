import 'package:flutter/material.dart';

import 'package:boom/nucleo/tema/tema_psicobloom.dart';

/// Barra de navegacion inferior persistente para el modulo profesional.
/// Presenta cuatro destinos principales: Inicio, Solicitudes, Agenda y Perfil.
class BarraNavegacionProfesional extends StatelessWidget {
  final int indiceSeleccionado;
  final ValueChanged<int> alCambiarPestana;
  final int solicitudesPendientes;

  const BarraNavegacionProfesional({
    super.key,
    required this.indiceSeleccionado,
    required this.alCambiarPestana,
    this.solicitudesPendientes = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('barraNavegacionProfesional'),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        border: Border(
          top: BorderSide(
            color: TemaPsicobloom.colorBorde.withValues(alpha: 0.65),
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
          padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 6.0),
          child: Row(
            children: [
              Expanded(
                child: _construirBotonPestana(
                  clave: const Key('pestanaProfesional_inicio'),
                  indice: 0,
                  iconoActivo: Icons.home_rounded,
                  iconoInactivo: Icons.home_outlined,
                  etiqueta: 'Inicio',
                ),
              ),
              Expanded(
                child: _construirBotonPestana(
                  clave: const Key('pestanaProfesional_solicitudes'),
                  indice: 1,
                  iconoActivo: Icons.assignment_turned_in_rounded,
                  iconoInactivo: Icons.assignment_turned_in_outlined,
                  etiqueta: 'Solicitudes',
                  insigniaCantidad: solicitudesPendientes,
                ),
              ),
              Expanded(
                child: _construirBotonPestana(
                  clave: const Key('pestanaProfesional_agenda'),
                  indice: 2,
                  iconoActivo: Icons.calendar_month_rounded,
                  iconoInactivo: Icons.calendar_month_outlined,
                  etiqueta: 'Agenda',
                ),
              ),
              Expanded(
                child: _construirBotonPestana(
                  clave: const Key('pestanaProfesional_perfil'),
                  indice: 3,
                  iconoActivo: Icons.person_rounded,
                  iconoInactivo: Icons.person_outline_rounded,
                  etiqueta: 'Perfil',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _construirBotonPestana({
    required Key clave,
    required int indice,
    required IconData iconoActivo,
    required IconData iconoInactivo,
    required String etiqueta,
    int insigniaCantidad = 0,
  }) {
    final bool esActiva = indice == indiceSeleccionado;
    final Color colorActual = esActiva
        ? TemaPsicobloom.colorPrincipal
        : TemaPsicobloom.colorTextoSecundario;

    return InkWell(
      key: clave,
      onTap: () => alCambiarPestana(indice),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  esActiva ? iconoActivo : iconoInactivo,
                  color: colorActual,
                  size: 24,
                ),
                if (insigniaCantidad > 0)
                  Positioned(
                    right: -8,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: TemaPsicobloom.colorPrincipal,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 14,
                      ),
                      child: Text(
                        insigniaCantidad > 99 ? '99+' : '$insigniaCantidad',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              etiqueta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: esActiva ? FontWeight.bold : FontWeight.w500,
                color: colorActual,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 3,
              width: esActiva ? 20 : 0,
              decoration: BoxDecoration(
                color: esActiva
                    ? TemaPsicobloom.colorPrincipal
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
