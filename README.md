# PAPOI Survives

Juego web 2D de supervivencia por oleadas (HTML5 canvas) con cuentas, progreso en la nube,
ranking global y multijugador online de hasta 4 jugadores.

## Contenido
- `index.html` — el juego (un solo archivo, v1.5 online)
- `mapas/` — principal, rocosa, desierto y marino; se descargan al empezar una partida
- `supabase/migrations/` — SQL de la base de datos (cuentas, progreso, salas, ranking, con RLS)
- **Falta añadir:** los `.mp3` (menu, click, gp, boss, hurt, levelup) junto a `index.html`

## Puesta en marcha con tu propio Supabase
1. Crea un proyecto en supabase.com.
2. En **SQL Editor** ejecuta `001_schema.sql` y luego `002_list_rooms.sql`.
3. En **Authentication → Sign In / Providers → Email** desactiva **Confirm email**
   (el juego usa emails inventados `usuario@papoi.game` que no reciben correos).
4. En `index.html`, dentro de `window.Cloud`, cambia `URL` y `KEY` por la URL del proyecto y su clave `sb_publishable_…`.

## Seguridad
La clave `sb_publishable_…` es pública por diseño; la protección está en las políticas RLS.
Nunca subas la `service_role` ni la contraseña de la base de datos.

## Cómo funciona lo online
- **Cuentas:** usuario + contraseña. Sin correo real, así que no hay recuperación de contraseña.
- **Progreso:** tienda, mejoras, skins, logros y récords se guardan por cuenta.
- **Salas:** la lista está en Supabase; la partida va directa entre jugadores (PeerJS/WebRTC).
- **Ranking:** mejor partida de cada jugador, por dificultad.
- El ranking y el progreso los envía el navegador: los límites del servidor frenan abusos burdos, pero no son a prueba de trampas.

## Jugar en local
Usa un servidor estático (`python -m http.server`) para que carguen los mapas.
