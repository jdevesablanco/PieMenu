# PieMenu

**Un menú circular junto al puntero: pulsa ⌃Tab, mueve el ratón hacia una porción y suelta. Abre apps, archivos, carpetas, flujos de Automator, atajos de Atajos y comandos de shell.**

[English](README.md) · macOS 13+ · Apple Silicon e Intel · licencia MIT · sin red, sin cuentas

<p align="center"><img src="docs/images/pie.png" width="368" alt="PieMenu abierto junto al puntero, con Música resaltada"></p>

Una versión gratis y open source de los menús circulares con atajo de teclado. Pon en hasta ocho porciones lo que abres todo el día y llega a cualquiera con un solo gesto, sin salir de la app en la que estás.

- **Mantén y suelta**: mantén ⌃, pulsa Tab, mueve el ratón hacia una porción y suelta ⌃. La porción se ejecuta.
- **O haz clic**: pulsa ⌃Tab y suelta (o suelta en el centro) y el menú se queda abierto; haz clic en una porción.
- **Cancelar**: Esc, ⌃Tab otra vez, un clic en el centro o fuera del menú.
- **Qué puede hacer una porción**: abrir una app, un archivo o una carpeta (también apps de Automator), ejecutar un `.workflow` de Automator, ejecutar un atajo de Atajos por su nombre o un comando de shell.
- **Aspecto nativo**: un anillo de cristal oscuro como los HUD del sistema, los iconos reales de las apps y el nombre de la porción en el centro. La app que estabas usando no pierde el foco.
- **Atajo configurable** (⌃Tab por defecto), **icono en la barra de menús** y **abrir al iniciar sesión** opcionales, español/inglés.

## Instalar

| Método | Para quién | |
|---|---|---|
| **[Instalador `.pkg`](https://github.com/jdevesablanco/PieMenu/releases/latest/download/PieMenu.pkg)** | Lo más fácil: doble clic, sin Terminal | Descarga directa |
| **[Imagen de disco `.dmg`](https://github.com/jdevesablanco/PieMenu/releases/latest/download/PieMenu.dmg)** | Arrastrar la app a *Aplicaciones* | Descarga directa |
| **Homebrew** | Quien usa Terminal | `brew install --cask jdevesablanco/tap/piemenu` |
| **Desde el código** | Desarrolladores | `git clone … && Scripts/install.sh` |

Al pulsar un enlace de descarga empieza al momento (última versión). Todas las versiones: [Releases](https://github.com/jdevesablanco/PieMenu/releases).
La app está firmada ad-hoc, sin notarizar por Apple, así que la primera vez: *Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente* (en macOS 13–14 también vale clic derecho → *Abrir*), o `xattr -dr com.apple.quarantine /Applications/PieMenu.app` (ver [docs/NOTARIZATION.md](docs/NOTARIZATION.md)).

**Desde el código** (Xcode Command Line Tools):

```bash
git clone https://github.com/jdevesablanco/PieMenu && cd PieMenu
Scripts/install.sh   # compila, copia la app a /Applications y la abre
```

PieMenu no tiene icono en el Dock: busca ◎ en la barra de menús. Haz clic → **Ajustes…** para preparar tus porciones. Puedes ocultar el icono en *Ajustes → General*; el atajo sigue funcionando y, si vuelves a abrir PieMenu (Spotlight, Launchpad, *Aplicaciones*), se abren los Ajustes.

## Porciones

Cada porción tiene un nombre, un icono (un SF Symbol, o déjalo vacío para usar el icono del propio archivo) y una acción:

| Acción | Destino | Cómo se ejecuta |
|---|---|---|
| Abrir | App, archivo, carpeta o app de Automator | Como hacer doble clic en Finder |
| Abrir | `.workflow` de Automator | `/usr/bin/automator <archivo>` (abrirlo solo lo enseñaría en Automator) |
| Ejecutar atajo | El nombre del atajo (elígelo de la lista) | `/usr/bin/shortcuts run <nombre>` |
| Ejecutar comando de shell | Un comando | `/bin/zsh -lc <comando>`, con tu `PATH` de inicio de sesión |

De 1 a 8 porciones, empezando a las 12 y en el sentido de las agujas del reloj. Cámbialas de orden con las flechas en *Ajustes → Porciones*. Si una acción falla, PieMenu te dice por qué.

**Truco:** una app de Automator o un atajo pueden hacer varias cosas a la vez, como abrir las tres apps que usas para un proyecto o cerrarlo todo. Ponlo en una porción y tendrás toda esa rutina a un gesto.

## Limitaciones

- El atajo global usa `RegisterEventHotKey`, así que no necesita permiso de Accesibilidad y la app activa nunca recibe esas teclas. Mientras PieMenu está abierto, ⌃Tab ya no cambia de pestaña en los navegadores; elige otro atajo en *Ajustes → General* si lo necesitas.
- Si otra app ya usa el mismo atajo (otro menú circular, por ejemplo), PieMenu te lo dice en *Ajustes → General*.
- Las apps de Automator y los atajos que controlan otras apps pueden pedir sus propios permisos de macOS la primera vez. Eso queda entre ellos y macOS.

Los ajustes se guardan en `~/Library/Application Support/PieMenu/config.json`.

## Privacidad

Todo ocurre en tu Mac. Sin telemetría. Solo se usa la red cuando *tú* pulsas **Instalar** en una de las apps del pack (API pública de GitHub / Homebrew).

## Combina bien con

Del mismo autor, gratis y open source:

| App | Qué hace | Estado |
|---|---|---|
| [SplitExercises](https://github.com/jdevesablanco/SplitExercises) | Divide PDFs de ejercicios en una hoja por ejercicio, con clic derecho | Disponible |
| [QuitAll](https://github.com/jdevesablanco/QuitAll) | Cierra todas las apps de un clic, menos las que elijas | Disponible |
| **PieMenu** | Un menú circular junto al puntero con tus apps, atajos y Automator | Esta app |

La app muestra las mismas tarjetas en *Ajustes → Combina bien con*, detecta cuáles tienes e instala las demás con Homebrew o con el último `.pkg` de GitHub.

## Desarrollo

- `Sources/PieMenu`: app SwiftUI/AppKit de barra de menús (atajo, panel circular, acciones, ajustes). `PackCatalog.swift` es idéntico en todas las apps del pack.
- `PIEMENU_CONFIG_DIR=/dir` aísla los ajustes; `PIEMENU_SNAPSHOT=/dir build/PieMenu.app/Contents/MacOS/PieMenu` renderiza el menú a PNG y sale (un tinte oscuro sustituye al desenfoque real del cristal).
- `Scripts/build-app.sh` compila `build/PieMenu.app`; `Scripts/make-dmg.sh` y `Scripts/make-pkg.sh` la empaquetan; `Scripts/install.sh` la instala en `/Applications`.
- Versiones: `Scripts/release.sh X.Y.Z` crea el tag y hace push; GitHub Actions compila la app universal y adjunta el DMG y el PKG a la release.

## Licencia

MIT © 2026 Julio Devesa Blanco
