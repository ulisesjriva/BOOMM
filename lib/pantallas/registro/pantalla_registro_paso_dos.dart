import 'package:flutter/material.dart';

import '../../tema/tema_psicobloom.dart';
import '../../componentes/fondo_decorativo_bloom.dart';
import 'pantalla_verificar_correo.dart';
import '../../servicios/servicio_registro.dart';

/// Enum que define los dos unicos tipos de usuario disponibles en el registro publico.
enum TipoUsuario { paciente, profesional }

/// Segundo paso del registro publico para definir contrasena, rol y terminos.
class PantallaRegistroPasoDos extends StatefulWidget {
  final String nombre;
  final String apellido;
  final String correo;
  final ServicioRegistro servicio;

  const PantallaRegistroPasoDos({
    super.key,
    required this.nombre,
    required this.apellido,
    required this.correo,
    this.servicio = const ServicioRegistro(),
  });

  @override
  State<PantallaRegistroPasoDos> createState() =>
      _PantallaRegistroPasoDosState();
}

class _PantallaRegistroPasoDosState extends State<PantallaRegistroPasoDos> {
  final _claveFormulario = GlobalKey<FormState>();
  final _controladorClave = TextEditingController();
  final _controladorConfirmarClave = TextEditingController();

  TipoUsuario _tipoUsuario = TipoUsuario.paciente;
  bool _mostrarClave = false;
  bool _mostrarConfirmarClave = false;
  bool _aceptaTerminos = false;
  bool _estaRegistrando = false;

  @override
  void dispose() {
    _controladorClave.dispose();
    _controladorConfirmarClave.dispose();
    super.dispose();
  }

  Future<void> _finalizarRegistro() async {
    if (_estaRegistrando) return;
    if (!_claveFormulario.currentState!.validate()) {
      return;
    }

    if (!_aceptaTerminos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: TemaPsicobloom.colorAdvertencia,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: const Text(
            'Debes aceptar los términos y condiciones para continuar.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }

    setState(() {
      _estaRegistrando = true;
    });

    final esProfesional = _tipoUsuario == TipoUsuario.profesional;
    try {
      await widget.servicio.registrar(
        nombre: widget.nombre,
        apellido: widget.apellido,
        correo: widget.correo,
        clave: _controladorClave.text,
        esProfesional: esProfesional,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (context) => PantallaVerificarCorreo(
            correo: widget.correo,
            esProfesional: esProfesional,
            servicio: widget.servicio,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ServicioRegistro.explicarError(error))),
      );
    } finally {
      if (mounted) setState(() => _estaRegistrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FondoDecorativoBloom(
        mostrarHojas: true,
        mostrarCorazones: true,
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: TemaPsicobloom.colorTexto,
                    onPressed: _estaRegistrando
                        ? null
                        : () => Navigator.pop(context),
                    tooltip: 'Regresar',
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 8.0,
                  ),
                  child: Form(
                    key: _claveFormulario,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),

                        // Indicador de paso 2 de 2 completado
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: TemaPsicobloom.colorLavanda,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Paso 2 de 2',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: TemaPsicobloom.colorPrincipalOscuro,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: const LinearProgressIndicator(
                                  value: 1.0,
                                  backgroundColor: TemaPsicobloom.colorBorde,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    TemaPsicobloom.colorPrincipal,
                                  ),
                                  minHeight: 6,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        const Text(
                          'Protege tu cuenta',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: TemaPsicobloom.colorTexto,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Hola ${widget.nombre}, crea tu contraseña y elige tu rol.',
                          style: const TextStyle(
                            fontSize: 15,
                            color: TemaPsicobloom.colorTextoSecundario,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Campo Contrasena
                        const Text(
                          'Contraseña',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: TemaPsicobloom.colorTexto,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _controladorClave,
                          enabled: !_estaRegistrando,
                          obscureText: !_mostrarClave,
                          decoration: InputDecoration(
                            hintText: 'Mínimo 11 caracteres',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _mostrarClave
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                              onPressed: () {
                                setState(() {
                                  _mostrarClave = !_mostrarClave;
                                });
                              },
                              tooltip: _mostrarClave
                                  ? 'Ocultar contraseña'
                                  : 'Mostrar contraseña',
                            ),
                          ),
                          validator: (valor) {
                            if (valor == null || valor.isEmpty) {
                              return 'Por favor ingresa tu contraseña';
                            }
                            if (valor.length < 11) {
                              return 'La contraseña debe contener al menos 11 caracteres';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),

                        // Campo Confirmar contrasena
                        const Text(
                          'Confirmar contraseña',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: TemaPsicobloom.colorTexto,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _controladorConfirmarClave,
                          enabled: !_estaRegistrando,
                          obscureText: !_mostrarConfirmarClave,
                          decoration: InputDecoration(
                            hintText: 'Repite tu contraseña',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _mostrarConfirmarClave
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                              onPressed: () {
                                setState(() {
                                  _mostrarConfirmarClave =
                                      !_mostrarConfirmarClave;
                                });
                              },
                              tooltip: _mostrarConfirmarClave
                                  ? 'Ocultar contraseña'
                                  : 'Mostrar contraseña',
                            ),
                          ),
                          validator: (valor) {
                            if (valor == null || valor.isEmpty) {
                              return 'Por favor confirma tu contraseña';
                            }
                            if (valor != _controladorClave.text) {
                              return 'Las contraseñas no coinciden';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),

                        // Seleccion de tipo de usuario
                        const Text(
                          'Tipo de usuario',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: TemaPsicobloom.colorTexto,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _tarjetaOpcionRol(
                                titulo: 'Paciente',
                                descripcion: 'Busco atención',
                                icono: Icons.person_rounded,
                                esSeleccionado:
                                    _tipoUsuario == TipoUsuario.paciente,
                                alSeleccionar: () {
                                  setState(() {
                                    _tipoUsuario = TipoUsuario.paciente;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _tarjetaOpcionRol(
                                titulo: 'Profesional',
                                descripcion: 'Brindo atención',
                                icono: Icons.medical_services_outlined,
                                esSeleccionado:
                                    _tipoUsuario == TipoUsuario.profesional,
                                alSeleccionar: () {
                                  setState(() {
                                    _tipoUsuario = TipoUsuario.profesional;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Aviso de seguridad y verificacion cuando se elige rol Profesional
                        if (_tipoUsuario == TipoUsuario.profesional) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: TemaPsicobloom.colorFondoInformacion,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: TemaPsicobloom.colorInformacion
                                    .withOpacity(0.3),
                              ),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.verified_user_outlined,
                                  color: TemaPsicobloom.colorInformacion,
                                  size: 20,
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Por seguridad de los pacientes, el perfil profesional quedará en revisión. Un administrador aprobará tu cuenta antes de su publicación en el directorio.',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: TemaPsicobloom.colorTexto,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Casilla de terminos y condiciones
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Checkbox(
                              value: _aceptaTerminos,
                              activeColor: TemaPsicobloom.colorPrincipal,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              onChanged: _estaRegistrando
                                  ? null
                                  : (valor) {
                                      setState(() {
                                        _aceptaTerminos = valor ?? false;
                                      });
                                    },
                            ),
                            const Expanded(
                              child: Text(
                                'Acepto los términos de servicio y la política de privacidad de PsicoBloom.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: TemaPsicobloom.colorTexto,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Boton Crear cuenta
                        ElevatedButton(
                          onPressed: _estaRegistrando
                              ? null
                              : _finalizarRegistro,
                          child: _estaRegistrando
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Crear cuenta'),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaOpcionRol({
    required String titulo,
    required String descripcion,
    required IconData icono,
    required bool esSeleccionado,
    required VoidCallback alSeleccionar,
  }) {
    return InkWell(
      onTap: _estaRegistrando ? null : alSeleccionar,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: esSeleccionado
              ? TemaPsicobloom.colorLavanda
              : TemaPsicobloom.colorSuperficie,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: esSeleccionado
                ? TemaPsicobloom.colorPrincipal
                : TemaPsicobloom.colorBorde,
            width: esSeleccionado ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icono,
              size: 32,
              color: esSeleccionado
                  ? TemaPsicobloom.colorPrincipal
                  : TemaPsicobloom.colorTextoSecundario,
            ),
            const SizedBox(height: 8),
            Text(
              titulo,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: esSeleccionado
                    ? TemaPsicobloom.colorPrincipalOscuro
                    : TemaPsicobloom.colorTexto,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              descripcion,
              style: TextStyle(
                fontSize: 12,
                color: esSeleccionado
                    ? TemaPsicobloom.colorPrincipalOscuro
                    : TemaPsicobloom.colorTextoSecundario,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
