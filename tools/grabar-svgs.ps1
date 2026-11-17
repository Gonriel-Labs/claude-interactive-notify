# Regenera los SVG animados de docs/: graba cada aviso cuadro por cuadro y los arma con armar_svg.py
# Requiere Python 3. Uso: powershell -ExecutionPolicy Bypass -File tools\grabar-svgs.ps1
$R = Split-Path $PSScriptRoot -Parent
$script = Join-Path $R 'scripts\notify.ps1'
$tmp = Join-Path $env:TEMP 'claude-mascota'
$casos = @(
    @{ archivo = 'respuesta-lista'; json = '{"tipo":"fin","recap":"Agregue el login con Google y pasaron todas las pruebas.","duracion_ms":134000,"cwd":"C:/proyectos/mi-app"}'; acc = 'ninguno'; exp = 'normal'; clic = 4.5 },
    @{ archivo = 'permiso';         json = '{"message":"Claude needs your permission to use Bash","notification_type":"permission_prompt","cwd":"C:/proyectos/mi-app"}'; acc = 'ninguno'; exp = 'normal'; clic = 4 },
    @{ archivo = 'pregunta';        json = '{"message":"Que base de datos prefieres para el proyecto?","notification_type":"elicitation","cwd":"C:/proyectos/mi-app"}'; acc = 'navidad'; exp = 'normal'; clic = 4.5 },
    @{ archivo = 'error';           json = '{"tipo":"error","duracion_ms":5000,"cwd":"C:/proyectos/mi-app"}'; acc = 'lentes'; exp = 'normal'; clic = 5 },
    @{ archivo = 'se-duerme';       json = '{"tipo":"fin","recap":"Listo: el reporte quedo en la carpeta docs.","duracion_ms":48000,"cwd":"C:/proyectos/mi-app"}'; acc = 'ninguno'; exp = 'pesados'; clic = 0 }
)
foreach ($c in $casos) {
    $grabacion = Join-Path $tmp "$($c.archivo).json"
    $c.json | powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -Siempre -Accesorio $c.acc -Expresion $c.exp -ClicTras $c.clic -CapturaSVG $grabacion
    python (Join-Path $PSScriptRoot 'armar_svg.py') $grabacion (Join-Path $R "docs\$($c.archivo).svg")
}
