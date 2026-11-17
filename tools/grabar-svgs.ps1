# Regenera los SVG animados de docs/: graba cada aviso cuadro por cuadro y los arma con armar_svg.py
# Requiere Python 3. Uso: powershell -ExecutionPolicy Bypass -File tools\grabar-svgs.ps1
param([string[]]$Solo = @())   # opcional: grabar solo estos casos (por nombre)
$R = Split-Path $PSScriptRoot -Parent
$script = Join-Path $R 'scripts\notify.ps1'
$tmp = Join-Path $env:TEMP 'claude-mascota'
$cwd = '"cwd":"C:/proyectos/mi-app"'
$fin = { param($recap, $ms) "{""tipo"":""fin"",""recap"":""$recap"",""duracion_ms"":$ms,$cwd}" }
$permiso  = "{""message"":""Claude needs your permission to use Bash"",""notification_type"":""permission_prompt"",$cwd}"
$pregunta = "{""message"":""Que base de datos prefieres para el proyecto?"",""notification_type"":""elicitation"",$cwd}"
$error_   = "{""tipo"":""error"",""duracion_ms"":5000,$cwd}"

$casos = @(
    # Avisos sueltos de la tabla del README
    @{ n = 'permiso';   json = $permiso;  acc = 'ninguno'; exp = 'normal'; clic = 4 },
    @{ n = 'pregunta';  json = $pregunta; acc = 'navidad'; exp = 'normal'; clic = 4.5 },
    @{ n = 'error';     json = $error_;   acc = 'lentes';  exp = 'normal'; clic = 5 },
    @{ n = 'se-duerme'; json = (& $fin 'Listo: el reporte quedo en la carpeta docs.' 48000); acc = 'ninguno'; exp = 'pesados'; clic = 0 },
    # Demo de arriba: tres rondas de dos mascotas apiladas, cada una con otro estilo
    @{ n = 'demo-1a'; json = (& $fin 'Agregue el login con Google y pasaron todas las pruebas.' 134000); acc = 'ninguno'; exp = 'normal'; clic = 4.2 },
    @{ n = 'demo-1b'; json = $permiso;  acc = 'lentes';  exp = 'normal';  clic = 3.6 },
    @{ n = 'demo-2a'; json = (& $fin 'Corregi el bug del carrito: ya no duplica productos.' 52000); acc = 'navidad'; exp = 'bostezo'; clic = 4.2 },
    @{ n = 'demo-2b'; json = $pregunta; acc = 'ninguno'; exp = 'normal';  clic = 3.6 },
    @{ n = 'demo-3a'; json = (& $fin 'Listo: migre la base de datos a la version nueva.' 245000); acc = 'bruja'; exp = 'pesados'; clic = 4.2 },
    @{ n = 'demo-3b'; json = $error_;   acc = 'fiesta';  exp = 'normal';  clic = 3.6 }
)
foreach ($c in $casos) {
    if ($Solo.Count -and $c.n -notin $Solo) { continue }
    $c.json | powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -Siempre -Accesorio $c.acc -Expresion $c.exp -ClicTras $c.clic -CapturaSVG (Join-Path $tmp "$($c.n).json")
}

$armar = Join-Path $PSScriptRoot 'armar_svg.py'
function G($n) { Join-Path $tmp "$n.json" }
foreach ($n in 'permiso', 'pregunta', 'error', 'se-duerme') { python $armar (Join-Path $R "docs\$n.svg") (G $n) }
python $armar (Join-Path $R 'docs\demo.svg') "$(G 'demo-1a')+$(G 'demo-1b')" "$(G 'demo-2a')+$(G 'demo-2b')" "$(G 'demo-3a')+$(G 'demo-3b')"
