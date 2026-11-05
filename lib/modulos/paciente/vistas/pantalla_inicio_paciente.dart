import 'package:flutter/material.dart';

import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/nucleo/componentes/fondo_decorativo_bloom.dart';
import 'package:boom/modulos/paciente/componentes/barra_navegacion_paciente.dart';
import 'package:boom/modulos/paciente/componentes/tarjeta_profesional.dart';
import 'package:boom/modelos/profesional.dart';
import 'package:boom/datos/profesionales_simulados.dart';
import 'package:boom/modulos/paciente/controladores/gestor_favoritos.dart';

import 'pantalla_buscar_profesionales.dart';

/// Pantalla 5: Inicio del paciente.
/// Representa la interfaz principal a la que accede el paciente tras autenticarse.
/// Concentra las acciones clave: busqueda de profesionales, orientacion,
/// accesos rapidos y profesionales recomendados cercanos a Riobamba.
class PantallaInicioPaciente extends StatefulWidget {
  final String nombrePaciente;

  const PantallaInicioPaciente({super.key, this.nombrePaciente = 'María'});

  @override
  State<PantallaInicioPaciente> createState() => _PantallaInicioPacienteState();
}

class _PantallaInicioPacienteState extends State<PantallaInicioPaciente> {
  int _indicePestana = 0;

  void _alternarFavorito(String idProfesional) {
    final bool esFavorito = GestorFavoritos.instancia.alternarFavorito(
      idProfesional,
    );
    _mostrarMensajeInformativo(
      esFavorito
          ? 'Guardado en tus profesionales favoritos'
          : 'Eliminado de tus profesionales favoritos',
    );
  }

  void _navegarABuscar() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PantallaBuscarProfesionales(),
      ),
    );
  }

  void _mostrarMensajeInformativo(String mensaje) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: TemaPsicobloom.colorLavanda,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                mensaje,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: TemaPsicobloom.colorPrincipalOscuro,
        behavior: SnackBarBehavior.floating,
        elevation: 3,
        margin: const EdgeInsets.only(bottom: 12, left: 20, right: 20),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: TemaPsicobloom.colorLavanda.withValues(alpha: 0.35),
            width: 1.0,
          ),
        ),
        duration: const Duration(milliseconds: 2200),
      ),
    );
  }

  void _gestionarCambioPestana(int nuevoIndice) {
    if (nuevoIndice == _indicePestana) return;

    switch (nuevoIndice) {
      case 1:
        _navegarABuscar();
        break;
      case 2:
        _mostrarMensajeInformativo(
          'El Mapa interactivo de profesionales se implementará en la Etapa 4.',
        );
        break;
      case 3:
        _mostrarMensajeInformativo(
          'El módulo de Mis citas corresponde a etapas posteriores del equipo.',
        );
        break;
      case 4:
        _mostrarMensajeInformativo(
          'El perfil del paciente corresponde a etapas posteriores del equipo.',
        );
        break;
      default:
        setState(() {
          _indicePestana = nuevoIndice;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaPsicobloom.colorFondo,
      bottomNavigationBar: BarraNavegacionPaciente(
        indiceSeleccionado: _indicePestana,
        alCambiarPestana: _gestionarCambioPestana,
      ),
      body: FondoDecorativoBloom(
        mostrarHojas: false,
        mostrarCorazones: false,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: 20.0,
              vertical: 16.0,
            ),
            children: [
              _construirCabeceraSuperior(),
              const SizedBox(height: 20),
              _construirSeccionBienvenida(),
              const SizedBox(height: 22),
              _construirTarjetasAccionRapida(),
              const SizedBox(height: 26),
              _construirEncabezadoSeccionProfesionales(),
              const SizedBox(height: 12),
              _construirAvisoDemostracion(),
              const SizedBox(height: 14),
              _construirListaProfesionales(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  /// Barra superior con el logo oficial de PsicoBloom y la campana de notificaciones.
  Widget _construirCabeceraSuperior() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: TemaPsicobloom.colorSuperficie,
                shape: BoxShape.circle,
                border: Border.all(
                  color: TemaPsicobloom.colorBorde,
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: TemaPsicobloom.colorPrincipal.withValues(
                      alpha: 0.08,
                    ),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/imagenes/icono_psicobloom.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.local_florist_rounded,
                    color: TemaPsicobloom.colorPrincipal,
                    size: 22,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'PsicoBloom',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: TemaPsicobloom.colorPrincipalOscuro,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        Stack(
          children: [
            IconButton(
              icon: const Icon(
                Icons.notifications_none_rounded,
                color: TemaPsicobloom.colorTexto,
                size: 26,
              ),
              tooltip: 'Notificaciones',
              onPressed: () {
                _mostrarMensajeInformativo('No tienes nuevas notificaciones.');
              },
            ),
            Positioned(
              top: 10,
              right: 12,
              child: Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: TemaPsicobloom.colorPrincipal,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Saludo al paciente con ilustracion decorativa representativa de bienestar emocional.
  Widget _construirSeccionBienvenida() {
    return Container(
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: TemaPsicobloom.colorBorde.withValues(alpha: 0.7),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: TemaPsicobloom.colorPrincipal.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hola, ${widget.nombrePaciente} 👋',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorTexto,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '¿En qué podemos ayudarte?',
                  style: TextStyle(
                    fontSize: 15,
                    color: TemaPsicobloom.colorTextoSecundario,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: TemaPsicobloom.colorLavanda.withValues(alpha: 0.5),
              shape: BoxShape.circle,
              border: Border.all(color: TemaPsicobloom.colorBorde, width: 1.0),
            ),
            child: const Icon(
              Icons.self_improvement_rounded,
              color: TemaPsicobloom.colorPrincipal,
              size: 42,
            ),
          ),
        ],
      ),
    );
  }

  /// Tarjetas destacadas de accion rapida: Buscar profesional y Orientarme.
  Widget _construirTarjetasAccionRapida() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _construirTarjetaAccion(
              titulo: 'Buscar profesional',
              descripcion: 'Encuentra psicólogos y psicólogas cerca de ti.',
              icono: Icons.search_rounded,
              colorFondoIcono: TemaPsicobloom.colorLavanda,
              colorIcono: TemaPsicobloom.colorPrincipal,
              alPresionar: _navegarABuscar,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _construirTarjetaAccion(
              titulo: 'Orientarme',
              descripcion: 'Recibe recomendaciones según tus necesidades.',
              icono: Icons.explore_outlined,
              colorFondoIcono: TemaPsicobloom.colorMenta,
              colorIcono: TemaPsicobloom.colorSecundario,
              alPresionar: () {
                _mostrarMensajeInformativo(
                  'El cuestionario de orientación psicológica estará disponible en próximas etapas.',
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirTarjetaAccion({
    required String titulo,
    required String descripcion,
    required IconData icono,
    required Color colorFondoIcono,
    required Color colorIcono,
    required VoidCallback alPresionar,
  }) {
    return Material(
      color: TemaPsicobloom.colorSuperficie,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: alPresionar,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 14.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: TemaPsicobloom.colorBorde.withValues(alpha: 0.8),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: TemaPsicobloom.colorTexto.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colorFondoIcono,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icono, color: colorIcono, size: 22),
                  ),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: TemaPsicobloom.colorFondo,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: TemaPsicobloom.colorBorde,
                        width: 1.0,
                      ),
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      size: 15,
                      color: TemaPsicobloom.colorTextoSecundario,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: TemaPsicobloom.colorTexto,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                descripcion,
                style: const TextStyle(
                  fontSize: 12,
                  color: TemaPsicobloom.colorTextoSecundario,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Encabezado de la seccion con enlace "Ver todos".
  Widget _construirEncabezadoSeccionProfesionales() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Expanded(
          child: Text(
            'Profesionales cerca de ti',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
              letterSpacing: -0.2,
            ),
          ),
        ),
        TextButton(
          onPressed: _navegarABuscar,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            visualDensity: VisualDensity.compact,
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ver todos',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: TemaPsicobloom.colorPrincipal,
                ),
              ),
              SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_rounded,
                size: 14,
                color: TemaPsicobloom.colorPrincipal,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Mensaje para identificar datos simulados sin crear falsas expectativas de geolocalizacion.
  Widget _construirAvisoDemostracion() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorLavanda.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: TemaPsicobloom.colorBorde, width: 0.8),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: TemaPsicobloom.colorPrincipal,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Demostración con datos referenciales para Riobamba.',
              style: TextStyle(
                fontSize: 11.5,
                color: TemaPsicobloom.colorTextoSecundario,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Lista vertical de tarjetas de profesionales basada en el modelo simulado.
  Widget _construirListaProfesionales() {
    final List<Profesional> profesionalesMostrados = profesionalesSimulados
        .take(3)
        .toList();

    return ValueListenableBuilder<Set<String>>(
      valueListenable: GestorFavoritos.instancia.favoritos,
      builder: (context, conjuntoFavoritos, child) {
        return Column(
          children: profesionalesMostrados.map((profesional) {
            final bool esFavorito = conjuntoFavoritos.contains(profesional.id);

            return Padding(
              padding: const EdgeInsets.only(bottom: 14.0),
              child: TarjetaProfesional(
                profesional: profesional,
                esFavorito: esFavorito,
                alAlternarFavorito: () => _alternarFavorito(profesional.id),
                alVerPerfil: () {
                  _mostrarMensajeInformativo(
                    'La visualización de perfil detallado se implementará en etapas posteriores.',
                  );
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
