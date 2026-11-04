import 'package:flutter/material.dart';
import '../../nucleo/tema/tema_psicobloom.dart';
import '../../nucleo/componentes/fondo_decorativo_bloom.dart';
import '../../nucleo/componentes/icono_google.dart';
import 'pantalla_registro_paso_dos.dart';

/// Pantalla para usuarios que inician por primera vez con Google y deben completar rol y datos basicos.
class PantallaCompletarPerfil extends StatefulWidget {
  final String correoGoogle;
  final String nombreSugerido;

  const PantallaCompletarPerfil({
    super.key,
    this.correoGoogle = 'usuario@gmail.com',
    this.nombreSugerido = '',
  });

  @override
  State<PantallaCompletarPerfil> createState() => _PantallaCompletarPerfilState();
}

class _PantallaCompletarPerfilState extends State<PantallaCompletarPerfil> {
  final _claveFormulario = GlobalKey<FormState>();
  late final TextEditingController _controladorNombre;
  final _controladorApellido = TextEditingController();

  TipoUsuario _tipoUsuario = TipoUsuario.paciente;
  bool _aceptaTerminos = false;
  bool _estaGuardando = false;

  @override
  void initState() {
    super.initState();
    _controladorNombre = TextEditingController(text: widget.nombreSugerido);
  }

  @override
  void dispose() {
    _controladorNombre.dispose();
    _controladorApellido.dispose();
    super.dispose();
  }

  void _guardarPerfil() {
    if (!_claveFormulario.currentState!.validate()) {
      return;
    }

    if (!_aceptaTerminos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: TemaPsicobloom.colorAdvertencia,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: const Text(
            'Debes aceptar los términos y condiciones para continuar.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }

    setState(() {
      _estaGuardando = true;
    });

    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() {
        _estaGuardando = false;
      });

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: TemaPsicobloom.colorSuperficie,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          icon: Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: TemaPsicobloom.colorFondoExito,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              color: TemaPsicobloom.colorExito,
              size: 36,
            ),
          ),
          title: const Text(
            'Perfil completado',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
          content: Text(
            'Se configuró tu cuenta como ${_tipoUsuario == TipoUsuario.paciente ? "Paciente" : "Profesional"}.\n\nAl integrar Supabase, tu sesión se iniciará y accederás directamente a la pantalla principal.',
            style: const TextStyle(
              color: TemaPsicobloom.colorTexto,
              height: 1.4,
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Cierra dialogo
                Navigator.pop(context); // Vuelve a pantalla anterior
              },
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    });
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
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Regresar',
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                  child: Form(
                    key: _claveFormulario,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                const SizedBox(height: 8),

                // Tarjeta indicadora de cuenta Google vinculada
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: TemaPsicobloom.colorSuperficie,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: TemaPsicobloom.colorBorde),
                  ),
                  child: Row(
                    children: [
                      const IconoGoogle(tamano: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Cuenta de Google conectada',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: TemaPsicobloom.colorSecundario,
                              ),
                            ),
                            Text(
                              widget.correoGoogle,
                              style: const TextStyle(
                                fontSize: 14,
                                color: TemaPsicobloom.colorTexto,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.check_circle_rounded,
                        color: TemaPsicobloom.colorSecundario,
                        size: 20,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                const Text(
                  'Solo la primera vez',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Elige tu rol para configurar tu experiencia en PsicoBloom.',
                  style: TextStyle(
                    fontSize: 14,
                    color: TemaPsicobloom.colorTextoSecundario,
                  ),
                ),
                const SizedBox(height: 24),

                // Campo Nombre
                const Text(
                  'Nombre',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _controladorNombre,
                  decoration: const InputDecoration(
                    hintText: 'Tu nombre',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (valor) {
                    if (valor == null || valor.trim().isEmpty) {
                      return 'Por favor ingresa tu nombre';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),

                // Campo Apellido
                const Text(
                  'Apellido',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _controladorApellido,
                  decoration: const InputDecoration(
                    hintText: 'Tu apellido',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (valor) {
                    if (valor == null || valor.trim().isEmpty) {
                      return 'Por favor ingresa tu apellido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Tipo de usuario
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
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _tipoUsuario = TipoUsuario.paciente;
                          });
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                          decoration: BoxDecoration(
                            color: _tipoUsuario == TipoUsuario.paciente
                                ? TemaPsicobloom.colorLavanda
                                : TemaPsicobloom.colorSuperficie,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _tipoUsuario == TipoUsuario.paciente
                                  ? TemaPsicobloom.colorPrincipal
                                  : TemaPsicobloom.colorBorde,
                              width: _tipoUsuario == TipoUsuario.paciente ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.person_rounded,
                                color: _tipoUsuario == TipoUsuario.paciente
                                    ? TemaPsicobloom.colorPrincipal
                                    : TemaPsicobloom.colorTextoSecundario,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Paciente',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _tipoUsuario == TipoUsuario.paciente
                                      ? TemaPsicobloom.colorPrincipalOscuro
                                      : TemaPsicobloom.colorTexto,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _tipoUsuario = TipoUsuario.profesional;
                          });
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                          decoration: BoxDecoration(
                            color: _tipoUsuario == TipoUsuario.profesional
                                ? TemaPsicobloom.colorLavanda
                                : TemaPsicobloom.colorSuperficie,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _tipoUsuario == TipoUsuario.profesional
                                  ? TemaPsicobloom.colorPrincipal
                                  : TemaPsicobloom.colorBorde,
                              width: _tipoUsuario == TipoUsuario.profesional ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.medical_services_outlined,
                                color: _tipoUsuario == TipoUsuario.profesional
                                    ? TemaPsicobloom.colorPrincipal
                                    : TemaPsicobloom.colorTextoSecundario,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Profesional',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _tipoUsuario == TipoUsuario.profesional
                                      ? TemaPsicobloom.colorPrincipalOscuro
                                      : TemaPsicobloom.colorTexto,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Terminos
                Row(
                  children: [
                    Checkbox(
                      value: _aceptaTerminos,
                      activeColor: TemaPsicobloom.colorPrincipal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      onChanged: (valor) {
                        setState(() {
                          _aceptaTerminos = valor ?? false;
                        });
                      },
                    ),
                    const Expanded(
                      child: Text(
                        'Acepto los términos de servicio de PsicoBloom.',
                        style: TextStyle(
                          fontSize: 13,
                          color: TemaPsicobloom.colorTexto,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Boton Guardar y continuar
                ElevatedButton(
                  onPressed: _estaGuardando ? null : _guardarPerfil,
                  child: _estaGuardando
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Completar perfil'),
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
}

