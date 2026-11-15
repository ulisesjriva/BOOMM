import 'package:flutter/material.dart';

import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_sesion.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_opciones_acceso.dart';
import 'package:boom/nucleo/componentes/fondo_decorativo_bloom.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

/// Pantalla mostrada cuando una cuenta esta inactiva o cuando un rol no tiene permiso
/// para acceder a una pantalla protegida.
class PantallaEstadoCuenta extends StatefulWidget {
  final PerfilUsuario? perfil;
  final String titulo;
  final String mensaje;
  final ServicioSesion servicioSesion;
  final VoidCallback? alReintentar;

  const PantallaEstadoCuenta({
    super.key,
    this.perfil,
    this.titulo = 'Cuenta inactiva',
    this.mensaje = 'Tu cuenta se encuentra desactivada temporalmente. Contacta al administrador de PsicoBloom para revisar tu acceso.',
    this.servicioSesion = const ServicioSesion(),
    this.alReintentar,
  });

  @override
  State<PantallaEstadoCuenta> createState() => _PantallaEstadoCuentaState();
}

class _PantallaEstadoCuentaState extends State<PantallaEstadoCuenta> {
  bool _estaCerrando = false;

  Future<void> _salirAlInicio() async {
    if (_estaCerrando) return;
    setState(() => _estaCerrando = true);
    try {
      await widget.servicioSesion.cerrarSesion();
    } finally {
      if (mounted) {
        setState(() => _estaCerrando = false);
        Navigator.of(context).pushAndRemoveUntil<void>(
          MaterialPageRoute<void>(
            builder: (_) => const PantallaOpcionesAcceso(),
          ),
          (_) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final esErrorRed = widget.alReintentar != null;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: TemaPsicobloom.colorFondo,
        body: FondoDecorativoBloom(
          mostrarHojas: true,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Container(
                  padding: const EdgeInsets.all(24.0),
                  decoration: BoxDecoration(
                    color: TemaPsicobloom.colorSuperficie,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: TemaPsicobloom.colorBorde),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: esErrorRed
                              ? TemaPsicobloom.colorFondoAdvertencia
                              : TemaPsicobloom.colorFondoError,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          esErrorRed
                              ? Icons.wifi_off_rounded
                              : Icons.lock_person_outlined,
                          size: 36,
                          color: esErrorRed
                              ? TemaPsicobloom.colorAdvertencia
                              : TemaPsicobloom.colorError,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        widget.titulo,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: TemaPsicobloom.colorTexto,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.mensaje,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14.5,
                          color: TemaPsicobloom.colorTextoSecundario,
                          height: 1.4,
                        ),
                      ),
                      if (widget.perfil != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: TemaPsicobloom.colorFondo,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: TemaPsicobloom.colorBorde,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                widget.perfil!.nombreCompleto,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: TemaPsicobloom.colorTexto,
                                ),
                              ),
                              if (widget.perfil!.correo.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  widget.perfil!.correo,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: TemaPsicobloom.colorTextoSecundario,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (widget.alReintentar != null) ...[
                        ElevatedButton.icon(
                          onPressed: _estaCerrando ? null : widget.alReintentar,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Reintentar conexión'),
                        ),
                        const SizedBox(height: 12),
                      ],
                      OutlinedButton.icon(
                        onPressed: _estaCerrando ? null : _salirAlInicio,
                        icon: const Icon(Icons.logout_rounded),
                        label: Text(
                          _estaCerrando
                              ? 'Cerrando sesión...'
                              : 'Volver al inicio de acceso',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
