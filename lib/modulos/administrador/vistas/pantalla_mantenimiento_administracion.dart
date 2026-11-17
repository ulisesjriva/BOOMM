import 'package:flutter/material.dart';

import 'package:boom/nucleo/tema/tema_psicobloom.dart';

/// Pantalla de Mantenimiento de informacion del modulo Administrador.
/// Agrupa accesos a Especialidades, Profesionales deshabilitados, referencia de
/// estados validos, aviso sobre registros de prueba y correcciones autorizadas.
class PantallaMantenimientoAdministracion extends StatelessWidget {
  final VoidCallback alAbrirEspecialidades;
  final VoidCallback alAbrirProfesionalesDeshabilitados;
  final VoidCallback alAbrirUsuariosParaCorreccion;

  const PantallaMantenimientoAdministracion({
    super.key,
    required this.alAbrirEspecialidades,
    required this.alAbrirProfesionalesDeshabilitados,
    required this.alAbrirUsuariosParaCorreccion,
  });

  void _mostrarGestionEstados(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (contextoDialogo) => AlertDialog(
        backgroundColor: TemaPsicobloom.colorSuperficie,
        title: const Text('Estados válidos del sistema'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Flujo de citas:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                '• pendiente → confirmada / rechazada / cancelada\n'
                '• confirmada → cancelada / finalizada\n'
                '• rechazada, cancelada y finalizada son estados finales.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              SizedBox(height: 12),
              Text(
                'Aprobación profesional (separada de activación):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                '• pendiente → aprobado / rechazado (con motivo).\n'
                '• Reactivar una cuenta deshabilitada no aprueba automáticamente su perfil.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              SizedBox(height: 12),
              Text(
                'Control de cuentas:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                '• El modelo actual distingue únicamente cuenta activa o inactiva (cuenta_activa), conservando historiales y protegiendo al último administrador.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(contextoDialogo),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  void _mostrarRegistrosDePrueba(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (contextoDialogo) => AlertDialog(
        backgroundColor: TemaPsicobloom.colorSuperficie,
        title: const Text('Registros de prueba'),
        content: const SingleChildScrollView(
          child: Text(
            'El esquema actual de PsicoBloom no incluye una marca explícita '
            'y fiable (como un campo booleano dedicado en base de datos) para '
            'distinguir registros de prueba de cuentas reales.\n\n'
            'Por seguridad e integridad, no se deducen registros por nombre, '
            'correo o fecha ni se habilita una eliminación masiva sin esa '
            'identificación explícita en el servidor.',
            style: TextStyle(fontSize: 13.5, height: 1.4),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(contextoDialogo),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaPsicobloom.colorFondo,
      appBar: AppBar(title: const Text('Mantenimiento de información')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Administra la información general de la aplicación.',
            style: TextStyle(
              fontSize: 13.5,
              color: TemaPsicobloom.colorTextoSecundario,
            ),
          ),
          const SizedBox(height: 16),
          _TarjetaMantenimiento(
            key: const Key('mantenimiento_especialidades'),
            icono: Icons.menu_book_outlined,
            colorIcono: TemaPsicobloom.colorPrincipal,
            colorFondo: TemaPsicobloom.colorLavanda.withValues(alpha: 0.65),
            titulo: 'Gestión de especialidades',
            subtitulo: 'Crear, editar, activar o desactivar especialidades.',
            alPresionar: () {
              Navigator.pop(context);
              alAbrirEspecialidades();
            },
          ),
          const SizedBox(height: 12),
          _TarjetaMantenimiento(
            key: const Key('mantenimiento_estados'),
            icono: Icons.flag_outlined,
            colorIcono: TemaPsicobloom.colorSecundario,
            colorFondo: TemaPsicobloom.colorMenta.withValues(alpha: 0.75),
            titulo: 'Gestión de estados',
            subtitulo: 'Consultar las transiciones válidas de citas y cuentas.',
            alPresionar: () => _mostrarGestionEstados(context),
          ),
          const SizedBox(height: 12),
          _TarjetaMantenimiento(
            key: const Key('mantenimiento_registrosPrueba'),
            icono: Icons.science_outlined,
            colorIcono: TemaPsicobloom.colorAdvertencia,
            colorFondo: TemaPsicobloom.colorFondoAdvertencia,
            titulo: 'Registros de prueba',
            subtitulo: 'Requiere marca explícita en servidor antes de depurar.',
            alPresionar: () => _mostrarRegistrosDePrueba(context),
          ),
          const SizedBox(height: 12),
          _TarjetaMantenimiento(
            key: const Key('mantenimiento_profDeshabilitados'),
            icono: Icons.medical_services_outlined,
            colorIcono: TemaPsicobloom.colorError,
            colorFondo: TemaPsicobloom.colorFondoError.withValues(alpha: 0.8),
            titulo: 'Profesionales deshabilitados',
            subtitulo: 'Revisar y reactivar cuentas deshabilitadas.',
            alPresionar: () {
              Navigator.pop(context);
              alAbrirProfesionalesDeshabilitados();
            },
          ),
          const SizedBox(height: 12),
          _TarjetaMantenimiento(
            key: const Key('mantenimiento_correcciones'),
            icono: Icons.edit_note_rounded,
            colorIcono: TemaPsicobloom.colorPrincipalOscuro,
            colorFondo: TemaPsicobloom.colorLavanda.withValues(alpha: 0.5),
            titulo: 'Correcciones de información',
            subtitulo: 'Ajustar nombre, apellido o registro desde Usuarios.',
            alPresionar: () {
              Navigator.pop(context);
              alAbrirUsuariosParaCorreccion();
            },
          ),
        ],
      ),
    );
  }
}

class _TarjetaMantenimiento extends StatelessWidget {
  final IconData icono;
  final Color colorIcono;
  final Color colorFondo;
  final String titulo;
  final String subtitulo;
  final VoidCallback alPresionar;

  const _TarjetaMantenimiento({
    super.key,
    required this.icono,
    required this.colorIcono,
    required this.colorFondo,
    required this.titulo,
    required this.subtitulo,
    required this.alPresionar,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colorFondo,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: alPresionar,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: TemaPsicobloom.colorBorde.withValues(alpha: 0.7),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: TemaPsicobloom.colorSuperficie,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icono, color: colorIcono, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: TemaPsicobloom.colorTexto,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitulo,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: TemaPsicobloom.colorTextoSecundario,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: TemaPsicobloom.colorTextoSecundario,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
