import 'package:flutter/foundation.dart';

/// Gestor en memoria para sincronizar el estado de favoritos entre pantallas
/// durante la sesion local, sin requerir persistencia inmediata en Supabase.
class GestorFavoritos {
  static final GestorFavoritos instancia = GestorFavoritos._interno();

  GestorFavoritos._interno();

  final ValueNotifier<Set<String>> favoritos = ValueNotifier<Set<String>>(
    <String>{},
  );

  /// Comprueba si un profesional esta marcado como favorito.
  bool esFavorito(String idProfesional) {
    return favoritos.value.contains(idProfesional);
  }

  /// Alterna el estado de favorito de un profesional y notifica a los escuchas.
  bool alternarFavorito(String idProfesional) {
    final nuevoConjunto = Set<String>.from(favoritos.value);
    final bool seraFavorito;

    if (nuevoConjunto.contains(idProfesional)) {
      nuevoConjunto.remove(idProfesional);
      seraFavorito = false;
    } else {
      nuevoConjunto.add(idProfesional);
      seraFavorito = true;
    }

    favoritos.value = nuevoConjunto;
    return seraFavorito;
  }

  /// Limpia los favoritos en memoria (util para pruebas y reinicio).
  void limpiar() {
    favoritos.value = <String>{};
  }
}
