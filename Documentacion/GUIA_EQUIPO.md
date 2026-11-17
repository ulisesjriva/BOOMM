# Guía de configuración y trabajo en equipo — PsicoBloom

Esta guía explica cómo descargar, configurar y ejecutar la versión actual integrada de **PsicoBloom** (incluye autenticación y roles, perfiles, agenda, citas, fotografías con Cloudinary, avisos por Telegram, mapas Geoapify, rutas En auto / Caminando con OpenRouteService, cuestionario de orientación y módulo Administrador).

## 1. Requisitos de desarrollo
- **Git** instalado.
- **Flutter SDK** estable (Dart con *null safety*).
- **Android Studio** (con SDK de Android y emulador configurado) o dispositivo físico Android con depuración USB habilitada.
- Editor recomendado: **VS Code** o **Android Studio**.

## 2. Rama oficial de esta versión integrada
- **Repositorio:** `https://github.com/ulisesjriva/BOOMM.git`
- **Rama:** `integracion/modulo-administrador`

### Clonar por primera vez
```powershell
git clone -b integracion/modulo-administrador https://github.com/ulisesjriva/BOOMM.git
cd BOOMM
flutter pub get
```

### Actualizar una copia existente
Si ya tienes el repositorio clonado localmente y sin cambios pendientes:
```powershell
git fetch origin
git switch integracion/modulo-administrador
git pull origin integracion/modulo-administrador
flutter pub get
```

## 3. Configuración local (`configuracion_supabase.json`)
La aplicación lee su configuración pública en tiempo de compilación desde el archivo local `configuracion_supabase.json` (ignorado por Git; nunca lo subas al repositorio).

Crea el archivo `configuracion_supabase.json` en la raíz del proyecto con esta estructura (solicitando los valores públicos al equipo):

```json
{
  "SUPABASE_URL": "https://tu-proyecto.supabase.co",
  "SUPABASE_ANON_KEY": "tu_clave_publica_anon_aqui"
}
```

> **Nota de seguridad:** Las claves privadas de terceros (`GEOAPIFY_API_KEY`, `ORS_API_KEY`, `CLOUDINARY_API_SECRET`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_WEBHOOK_SECRET`, claves de IA y `SUPABASE_SERVICE_ROLE_KEY`) viven únicamente en los secretos de **Supabase Edge Functions** y nunca deben colocarse en Flutter ni en Git.

## 4. Ejecutar la aplicación
Desde la raíz del proyecto en PowerShell o terminal:

```powershell
flutter run --dart-define-from-file=configuracion_supabase.json
```

También puedes ejecutarla desde **VS Code** seleccionando la configuración **`PsicoBloom (con Supabase)`** en el panel de depuración (`.vscode/launch.json`).

## 5. Proyecto Supabase compartido (¡muy importante!)
Todo el equipo trabaja conectado al **mismo proyecto de Supabase**.

- **No vuelvas a ejecutar migraciones SQL** ni **despliegues de Edge Functions** que ya estén instalados en el proyecto compartido, para evitar sobrescribir tablas, políticas RLS o datos de prueba del equipo.
- Si estás colaborando en una pantalla Flutter, basta con tener tu `configuracion_supabase.json` local y ejecutar `flutter pub get` + `flutter run`.
- Únicamente la persona encargada del backend debe aplicar (una sola vez, si aún no se han ejecutado) los scripts nuevos pendientes en `supabase/sql/` o desplegar Edge Functions nuevas siguiendo el orden documentado.
