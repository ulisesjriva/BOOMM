import 'package:flutter/material.dart';

/// Define el tema visual y la paleta de colores normalizada para PsicoBloom.
class TemaPsicobloom {
  // Paleta de colores base
  static const Color colorPrincipal = Color(0xFF6D4BC3);
  static const Color colorPrincipalOscuro = Color(0xFF4C328F);
  static const Color colorLavanda = Color(0xFFEDE6FA);
  static const Color colorFondo = Color(0xFFFAF8FD);
  static const Color colorSuperficie = Color(0xFFFFFFFF);
  static const Color colorSecundario = Color(0xFF2F7D62);
  static const Color colorMenta = Color(0xFFE4F3EC);
  static const Color colorTexto = Color(0xFF2D253A);
  static const Color colorTextoSecundario = Color(0xFF655D70);
  static const Color colorBorde = Color(0xFFD8D0E5);
  static const Color colorSobrePrincipal = Color(0xFFFFFFFF);

  // Colores semanticos
  static const Color colorExito = Color(0xFF246B45);
  static const Color colorFondoExito = Color(0xFFE7F4EB);
  static const Color colorAdvertencia = Color(0xFF805600);
  static const Color colorFondoAdvertencia = Color(0xFFFFF3D6);
  static const Color colorError = Color(0xFFB3261E);
  static const Color colorFondoError = Color(0xFFFCE8E6);
  static const Color colorInformacion = Color(0xFF305F9E);
  static const Color colorFondoInformacion = Color(0xFFEAF1FB);

  /// Construye y retorna la configuracion global de ThemeData para la aplicacion.
  static ThemeData obtenerTema() {
    final esquemaColores = ColorScheme.fromSeed(
      seedColor: colorPrincipal,
      primary: colorPrincipal,
      onPrimary: colorSobrePrincipal,
      secondary: colorSecundario,
      surface: colorSuperficie,
      onSurface: colorTexto,
      error: colorError,
      onError: colorSobrePrincipal,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: esquemaColores,
      scaffoldBackgroundColor: colorFondo,
      fontFamily:
          null, // Usa la fuente estandar del sistema para mantener ligereza
      appBarTheme: const AppBarTheme(
        backgroundColor: colorFondo,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: colorTexto),
        titleTextStyle: TextStyle(
          color: colorTexto,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorPrincipal,
          foregroundColor: colorSobrePrincipal,
          disabledBackgroundColor: colorBorde,
          disabledForegroundColor: colorTextoSecundario,
          elevation: 0,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorPrincipal,
          backgroundColor: colorSuperficie,
          side: const BorderSide(color: colorBorde, width: 1.5),
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorPrincipal,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorSuperficie,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: const TextStyle(color: colorTextoSecundario, fontSize: 15),
        labelStyle: const TextStyle(color: colorTextoSecundario, fontSize: 15),
        prefixIconColor: colorTextoSecundario,
        suffixIconColor: colorTextoSecundario,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: colorBorde, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: colorPrincipal, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: colorError, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: colorError, width: 2),
        ),
      ),
      cardTheme: CardThemeData(
        color: colorSuperficie,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: colorBorde, width: 1),
        ),
      ),
    );
  }
}
