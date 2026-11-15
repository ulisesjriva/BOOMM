import 'package:flutter/material.dart';

import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/administrador/vistas/pantalla_inicio_administrador.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_sesion.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_estado_cuenta.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_opciones_acceso.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_inicio_paciente.dart';
import 'package:boom/modulos/profesional/vistas/pantalla_inicio_profesional.dart';

/// Resuelve la pantalla de inicio correspondiente al rol y estado de la cuenta,
/// y provee proteccion de rutas por rol.
class NavegadorRoles {
  const NavegadorRoles._();

  static Widget construirDestinoPorPerfil(
    PerfilUsuario perfil, {
    ServicioSesion servicioSesion = const ServicioSesion(),
  }) {
    if (!perfil.cuentaActiva) {
      return PantallaEstadoCuenta(
        perfil: perfil,
        servicioSesion: servicioSesion,
      );
    }

    switch (perfil.rol) {
      case 'paciente':
        return PantallaInicioPaciente(
          nombrePaciente: perfil.nombre.trim().isEmpty
              ? 'Paciente'
              : perfil.nombre.trim(),
          perfilInicial: perfil,
          servicioSesion: servicioSesion,
        );
      case 'profesional':
        return PantallaInicioProfesional(
          perfilInicial: perfil,
          servicioSesion: servicioSesion,
        );
      case 'administrador':
        return PantallaInicioAdministrador(
          perfilInicial: perfil,
          servicioSesion: servicioSesion,
        );
      default:
        return PantallaEstadoCuenta(
          perfil: perfil,
          titulo: 'Rol no autorizado',
          mensaje: 'La cuenta no tiene un rol válido asignado en PsicoBloom.',
          servicioSesion: servicioSesion,
        );
    }
  }

  /// Verifica que el perfil tenga el rol requerido y cuenta activa; si no,
  /// muestra una pantalla de restriccion de acceso.
  static Widget protegerPorRol({
    required PerfilUsuario? perfil,
    required String rolRequerido,
    required Widget Function(PerfilUsuario perfilValido) constructorContenido,
    ServicioSesion servicioSesion = const ServicioSesion(),
  }) {
    if (perfil == null) {
      return const PantallaOpcionesAcceso();
    }
    if (!perfil.cuentaActiva) {
      return PantallaEstadoCuenta(
        perfil: perfil,
        servicioSesion: servicioSesion,
      );
    }
    if (perfil.rol != rolRequerido) {
      return PantallaEstadoCuenta(
        perfil: perfil,
        titulo: 'Acceso restringido',
        mensaje:
            'Tu cuenta tiene el rol de ${perfil.rol} y no tiene permisos para acceder al módulo de $rolRequerido.',
        servicioSesion: servicioSesion,
      );
    }
    return constructorContenido(perfil);
  }
}
