import 'package:flutter/material.dart';
import '../../nucleo/tema/tema_psicobloom.dart';
import '../../nucleo/componentes/fondo_decorativo_bloom.dart';
import '../acceso/pantalla_iniciar_sesion.dart';
import 'pantalla_registro_paso_dos.dart';

/// Primer paso del registro publico para ingresar datos personales basicos.
class PantallaRegistroPasoUno extends StatefulWidget {
  const PantallaRegistroPasoUno({super.key});

  @override
  State<PantallaRegistroPasoUno> createState() => _PantallaRegistroPasoUnoState();
}

class _PantallaRegistroPasoUnoState extends State<PantallaRegistroPasoUno> {
  final _claveFormulario = GlobalKey<FormState>();
  final _controladorNombre = TextEditingController();
  final _controladorApellido = TextEditingController();
  final _controladorCorreo = TextEditingController();

  @override
  void dispose() {
    _controladorNombre.dispose();
    _controladorApellido.dispose();
    _controladorCorreo.dispose();
    super.dispose();
  }

  void _avanzarAlSegundoPaso() {
    if (!_claveFormulario.currentState!.validate()) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PantallaRegistroPasoDos(
          nombre: _controladorNombre.text.trim(),
          apellido: _controladorApellido.text.trim(),
          correo: _controladorCorreo.text.trim(),
        ),
      ),
    );
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

                // Indicador de paso en el proceso de registro
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: TemaPsicobloom.colorLavanda,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Paso 1 de 2',
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
                          value: 0.5,
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
                  'Crear cuenta',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Comencemos con tus datos personales.',
                  style: TextStyle(
                    fontSize: 15,
                    color: TemaPsicobloom.colorTextoSecundario,
                  ),
                ),
                const SizedBox(height: 28),

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
                  keyboardType: TextInputType.name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Tu nombre',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (valor) {
                    if (valor == null || valor.trim().isEmpty) {
                      return 'Por favor ingresa tu nombre';
                    }
                    if (valor.trim().length < 2) {
                      return 'El nombre debe tener al menos 2 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

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
                  keyboardType: TextInputType.name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Tu apellido',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (valor) {
                    if (valor == null || valor.trim().isEmpty) {
                      return 'Por favor ingresa tu apellido';
                    }
                    if (valor.trim().length < 2) {
                      return 'El apellido debe tener al menos 2 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Campo Correo electronico
                const Text(
                  'Correo electrónico',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _controladorCorreo,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: 'tu@correo.com',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                  validator: (valor) {
                    if (valor == null || valor.trim().isEmpty) {
                      return 'Por favor ingresa tu correo electrónico';
                    }
                    if (!valor.contains('@') || !valor.contains('.')) {
                      return 'Ingresa un formato de correo válido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                // Boton Continuar
                ElevatedButton(
                  onPressed: _avanzarAlSegundoPaso,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Continuar'),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 20),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Enlace a inicio de sesion
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '¿Ya tienes una cuenta? ',
                      style: TextStyle(
                        color: TemaPsicobloom.colorTextoSecundario,
                        fontSize: 14,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const PantallaIniciarSesion(),
                          ),
                        );
                      },
                      child: const Text(
                        'Inicia sesión',
                        style: TextStyle(
                          color: TemaPsicobloom.colorPrincipal,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
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

