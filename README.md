# Notificaciones interactivas para Claude Code

Un mod para Windows que reemplaza los avisos de Claude Code por una mascota en pixel art. Entra caminando por la esquina inferior derecha de la pantalla con un globo de texto que te dice qué pasó:

- **Respuesta lista**: un ultraresumen de lo que hizo Claude y cuánto tardó.
- **Pide permiso**: ojos bien abiertos y un **!** encima.
- **Te pregunta algo**: un **?** flotando sobre la cabeza.
- **Algo falló**: cara triste y globo rojo.

<p align="center">
  <img src="docs/demo.svg" width="474" alt="Dos mascotas llegan una encima de otra, cada vez con otro estilo: primero una respuesta lista y otra con lentes pidiendo permiso; luego una con gorro de Navidad bostezando y otra que pregunta algo; al final una con sombrero de bruja y otra con gorro de fiesta avisando un error. Cada una se va caminando al hacerle clic.">
</p>

## Qué hace

- **Te lleva de vuelta**: haz clic en la mascota y se abre la ventana de donde vino el aviso, sea la app de escritorio, la terminal o VS Code. Si estaba minimizada la restaura; si la app estaba cerrada en la bandeja, la abre.
- **No molesta**: si ya estás mirando esa ventana, no aparece.
- **Tiene vida propia**: saluda, parpadea y bosteza. Si no le haces caso se sienta, cabecea y se queda dormida (z z z). Al irse se levanta y sale caminando.
- **Cambia cada vez**: expresiones y accesorios al azar (gorro de Navidad, de fiesta, sombrero de bruja, lentes con cigarro).
- **Suena suave**: una gota al terminar, un pop cuando te necesita. Se generan al vuelo, sin archivos de audio.
- **Se apila**: si terminan varias sesiones a la vez, las mascotas salen una encima de otra.

| Pide permiso | Te pregunta algo |
| --- | --- |
| <img src="docs/permiso.svg" alt="La mascota con un signo de exclamación encima pide permiso para usar Bash"> | <img src="docs/pregunta.svg" alt="La mascota con gorro de Navidad y un signo de pregunta flotando te hace una pregunta"> |

| Algo falló | Si no le haces caso |
| --- | --- |
| <img src="docs/error.svg" alt="La mascota triste, con lentes y cigarro humeante, avisa que algo falló"> | <img src="docs/se-duerme.svg" alt="La mascota se sienta, cabecea y se queda dormida soltando zetas, luego se levanta y se va"> |

## Instalación

> [!TIP]
> ### La forma más fácil: pídeselo a Claude
>
> Abre Claude Code (la app de escritorio, la terminal o VS Code), copia este mensaje, pégalo en el chat y envíalo:
>
> ```text
> Instala el plugin interactive-notify del marketplace de GitHub mark-quispe/claude-interactive-notify, con alcance de usuario. Si estás en la app de escritorio, desactiva también sus notificaciones de tarea completada.
> ```
>
> Claude hace el resto. Te pedirá permiso antes de ejecutar los comandos y antes de cambiar la configuración de la app: acéptalo. Así no te llegan dos avisos (el de la app y la mascota) cada vez que termina. Cuando termine, **abre una sesión nueva**, mándale un mensaje y cambia a otra ventana mientras responde: la mascota aparecerá al terminar.

### Requisitos

- Windows 10 u 11. Usa Windows PowerShell, que ya viene con Windows.
- Claude Code: la app de escritorio, la CLI en la terminal o la extensión de VS Code.

### Otras formas de instalarlo

En el prompt de una sesión de Claude Code en la terminal:

```
/plugin install interactive-notify --marketplace mark-quispe/claude-interactive-notify
```

Responde `y` para agregar el marketplace y elige el alcance (usuario, para todas tus sesiones).

Desde una terminal:

```bash
claude plugin install interactive-notify --marketplace mark-quispe/claude-interactive-notify
```

En la app de escritorio, donde `/plugin` no funciona: haz clic en **+** junto al cuadro de texto, luego **Plugins**, **Add marketplace** con `mark-quispe/claude-interactive-notify`, y después **Add plugin**.

La mascota aparece en una sesión nueva.

> [!NOTE]
> Si lo instalaste por alguno de estos caminos y usas la app de escritorio, saldrán dos avisos: el de la app y la mascota. Para quedarte solo con la mascota, pídele a Claude en la app que desactive sus notificaciones de tarea completada, o desactiva **Task complete notifications** en su configuración.

## Desinstalar

```bash
claude plugin uninstall interactive-notify
```

## Regenerar las animaciones

Las animaciones de `docs/` son SVG animados grabados del aviso real, cuadro por cuadro: cada cuadro guarda las figuras de la mascota y del globo como vectores. Si cambias la mascota, vuelve a generarlas (necesita Python 3):

```bash
powershell -ExecutionPolicy Bypass -File tools/grabar-svgs.ps1
```
