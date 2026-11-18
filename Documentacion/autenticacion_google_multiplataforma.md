# Acceso con Google en PsicoBloom

La aplicación usa **Supabase Auth como intermediario OAuth**. Flutter no contiene el secreto del cliente de Google. La pantalla envía al usuario al flujo seguro de Supabase y el SDK procesa el retorno. Los perfiles y permisos siguen saliendo de `perfil_del_usuario_actual`.

## Configurar Google Cloud

1. En Google Cloud Console, abre o crea un proyecto para PsicoBloom y configura la pantalla de consentimiento OAuth con el nombre, correo de soporte y dominios de la aplicación.
2. Crea un ID de cliente OAuth de tipo **Aplicación web**.
3. En **URI de redireccionamiento autorizados**, pega la URL de callback que muestra Supabase en Authentication > Sign In / Providers > Google. Tiene el formato `https://<project-ref>.supabase.co/auth/v1/callback`.
4. Registra como orígenes JavaScript el dominio web de producción y el origen local usado por Flutter Web, por ejemplo `https://psicobloom-7201a.web.app` y `http://localhost:7357`. El origen no incluye una ruta.

## Configurar Supabase

1. Abre Authentication > Sign In / Providers > Google, habilita el proveedor y copia el **Client ID** y el **Client Secret** de Google Cloud en los campos de Supabase.
2. En Authentication > URL Configuration, establece el Site URL como la URL base de la aplicación web publicada.
3. En Redirect URLs agrega la URL web de producción, el origen de desarrollo local y `psicobloom://acceso/`. En web, la app retorna a la URL actual sin query ni fragmento, por lo que autoriza también los entornos locales. Para puertos locales dinámicos, Supabase permite patrones; usa `http://localhost:*/**` solo en desarrollo.
4. Guarda los cambios. El Client Secret se queda en Supabase: no lo pegues en `configuracion_supabase.json`, `--dart-define`, Flutter ni GitHub.

## Retorno por plataforma

- **Android:** el intent filter `psicobloom://acceso` ya está en `AndroidManifest.xml`.
- **iOS y macOS:** el esquema `psicobloom` ya está declarado en `Info.plist`.
- **Windows:** el esquema debe registrarse con el empaquetado MSIX (`protocol_activation: psicobloom`) o en el registro por usuario para una instalación de desarrollo. `app_links` recibe el enlace; las ejecuciones sin empaquetar no registran el protocolo automáticamente.
- **Linux:** la aplicación necesita un archivo `.desktop` instalado con `MimeType=x-scheme-handler/psicobloom;` y registrado con `xdg-mime`. El ejecutable debe recibir `%u`. El `GApplication` del proyecto reenvía el enlace a la instancia activa.
- **Web:** no se usa el esquema móvil; Supabase retorna a la URL actual. En desarrollo, agrega a la lista de Redirect URLs el origen/puerto local que uses.

Para Windows y Linux el registro del protocolo es un paso del equipo/despliegue, no una clave API. La guía oficial del paquete `app_links` explica el registro para [Windows](https://github.com/llfbandit/app_links/blob/main/doc/README_windows.md) y [Linux](https://github.com/llfbandit/app_links/blob/main/doc/README_linux.md).

## Qué hace la aplicación

Los botones “Continuar con Google” de las pantallas de acceso e inicio de sesión llaman a `signInWithOAuth(OAuthProvider.google)`. En web se usa la URL actual como retorno; en las demás plataformas se solicita `psicobloom://acceso/`. Cuando Supabase confirma el retorno, la app valida la sesión y carga el perfil/rol desde el servidor antes de navegar.

El trigger actual de `supabase/sql/01_estructura.sql` crea a los nuevos usuarios sociales como pacientes por defecto. La asignación de roles de administrador sigue siendo exclusiva del backend. La pantalla simulada de “completar perfil” no forma parte del flujo real de Google.

## Comprobación manual

1. Inicia sesión en web, Android y iOS usando una cuenta de prueba de Google; confirma que vuelve a PsicoBloom y abre el módulo según el rol guardado.
2. Repite el flujo con una cuenta nueva y confirma que el trigger crea su perfil, que la sesión queda persistida y que cerrar sesión la elimina del dispositivo actual.
3. En Windows y Linux comprueba primero que `psicobloom://acceso/` está registrado para abrir la aplicación. Prueba el retorno tanto con la app abierta como cerrada.
4. No uses cuentas reales de pacientes para probar OAuth ni compartas capturas que muestren correo, tokens o claves.

# Mapas por plataforma

El mapa usa `flutter_map` y `http`, por lo que la misma vista Flutter se reutiliza en web, Android, iOS, macOS, Windows y Linux. Android ya declara `INTERNET`; macOS ya permite tráfico saliente en Debug, Profile y Release. La función `geoapify` incluye CORS para el acceso web y exige una sesión válida antes de consultar al proveedor.

Para que carguen teselas y direcciones en cualquier plataforma, el proyecto Supabase debe tener desplegada la función `geoapify`, los permisos de la función deben exigir JWT y el script `supabase/sql/19_consumo_geoapify.sql` debe estar aplicado. La clave `GEOAPIFY_API_KEY` se configura únicamente en Supabase Edge Function Secrets. El código local por sí solo no despliega esos componentes.

En cada plataforma verifica el mapa del directorio de profesionales, el perfil público, el selector de ubicación del profesional, el zoom, la selección de coordenadas, la ruta cuando haya origen GPS y los avisos sin sesión/sin conexión. Web requiere conexión HTTPS/CORS al proyecto Supabase; macOS requiere `com.apple.security.network.client`; los permisos de GPS solo son necesarios para centrar o calcular rutas desde la ubicación actual. El mapa debe seguir permitiendo explorar consultorios sin conceder GPS.

El icono G se dibuja en un único componente compartido para conservar la misma forma y antialiasing en las distintas ventanas y densidades. Google pide mantener su G multicolor estándar y un botón blanco claramente delimitado; revisa las [pautas oficiales de marca](https://developers.google.com/identity/branding-guidelines).

## Fuentes técnicas

- [Guía de Google OAuth para Supabase](https://supabase.com/docs/guides/auth/social-login/auth-google)
- [Referencia Flutter `signInWithOAuth`](https://supabase.com/docs/reference/dart/auth-signinwithoauth)
- [Redirect URLs de Supabase](https://supabase.com/docs/guides/auth/redirect-urls)
- [Compatibilidad de red de Flutter](https://docs.flutter.dev/data-and-backend/networking)
- [Documentación de `flutter_map`](https://docs.fleaflet.dev/)
