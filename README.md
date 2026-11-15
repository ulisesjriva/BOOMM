# PsicoBloom

Aplicación Flutter del proyecto de Computación Móvil e Interoperabilidad de Plataformas. El código se organiza mediante MVC por módulos, con servicios y repositorios de apoyo.

El nombre del producto es **PsicoBloom**. El paquete Dart conserva el nombre técnico `boom` y la carpeta local puede llamarse `BOOMM`; esta reorganización no los renombra.

## Estructura y estado

Consultar [Organización del código y responsabilidades MVC](Documentacion/arquitectura_mvc.md).

- `lib/modulos/autenticacion/`: acceso, registro, recuperación, confirmación, sesión persistente, enrutamiento por rol y coordinación de enlaces.
- `lib/modulos/paciente/`: inicio, búsqueda conectada, perfil del paciente, perfil público del profesional, componentes y favoritos.
- `lib/modulos/profesional/`: inicio del profesional, perfil profesional, fotografía en Supabase Storage, especialidades, servicios y ubicación del consultorio.
- `lib/modulos/administrador/`: inicio administrativo, revisión de profesionales pendientes y gestión de estado de cuentas.
- `lib/nucleo/`: componentes y tema compartidos.
- `lib/modelos/`, `lib/repositorios/`, `lib/datos/`: modelos, repositorios reales (`RepositorioEspecialidadesSupabase`, `RepositorioProfesionalesSupabase`) y datos de demostración compartidos.
- `supabase/sql/`: scripts de estructura, RLS, funciones RPC, migración `05_perfiles_especialidades_ubicacion.sql` y verificación transaccional `04_verificacion.sql`.
- `web_autenticacion/`: sitio auxiliar de autenticación publicado mediante Firebase Hosting.
- `test/`: verificaciones de modelos, controladores, repositorios y widgets con dependencias simuladas.

En el commit base `4b3b059`, la desarrolladora informó `flutter analyze` sin incidencias y 83 pruebas aprobadas. Las pruebas reales finales de autenticación se registran como pendientes en la documentación; una prueba simulada no equivale a una confirmación de correo real.

## Verificar el proyecto

Ejecutar desde la carpeta que contiene `pubspec.yaml`:

```powershell
flutter pub get
flutter analyze
flutter test
```

## Ejecutar la aplicación principal

La configuración se lee mediante `SUPABASE_URL` y `SUPABASE_ANON_KEY`, usando `--dart-define`. En PowerShell, introducir los valores del proyecto y consultar los dispositivos:

```powershell
$urlSupabase = Read-Host "Pega la URL de Supabase"
$clavePublicaSupabase = Read-Host "Pega la clave publica de Supabase"
flutter devices
$dispositivo = Read-Host "Escribe el identificador del dispositivo Android mostrado"
flutter run -d $dispositivo -t lib/main.dart --dart-define="SUPABASE_URL=$urlSupabase" --dart-define="SUPABASE_ANON_KEY=$clavePublicaSupabase"
```

Si no aparece ningún dispositivo Android, abrir primero un emulador o conectar el dispositivo. Utilizar valores públicos del cliente, nunca claves administrativas. No guardar contraseñas de usuarios en archivos de ejecución o en el repositorio.

`lib/main_desarrollo.dart` es una entrada independiente para previsualizar el paciente con datos simulados. No sustituye a `lib/main.dart` para comprobar Auth o los enlaces del correo.

## Trabajo por etapas

Seguir `AGENTS.md`. Actualizar rutas, importaciones y pruebas en el mismo cambio. Formatear los archivos modificados y ejecutar análisis y pruebas antes del commit. Revisar `git status` y trabajar en la rama acordada por el equipo; los cambios de reorganización están en `refactor/estructura-mvc`.

La reorganización del cliente Flutter no requiere por sí sola desplegar de nuevo el sitio `web_autenticacion`. Los cambios en el sitio se revisan y despliegan por separado.
