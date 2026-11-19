param(
    [string]$Titulo = "",
    [string]$Mensaje = "",
    [string]$Tipo = "",        # fin | permiso | pregunta | error (si no, se deduce)
    [string]$Accesorio = "",   # navidad | fiesta | bruja | lentes | pirata | audifonos | ninguno (si no, al azar)
    [string]$Mascota = "",     # clasica | cangrejo (si no, la de $MASCOTA_CONFIGURADA)
    [string]$Expresion = "",   # al terminar: feliz | pesados | bostezo (si no, al azar)
    [switch]$Siempre,          # mostrar aunque estes mirando Claude (para probar)
    [double]$ClicTras = 0,     # solo pruebas: simula un clic tras N segundos
    [string]$CapturaPNG = '',  # solo documentacion: guarda el popup como PNG y se cierra
    [string]$CapturaSVG = ''   # solo documentacion: graba la animacion en este .json (ver tools/armar_svg.py)
)

# Registros de errores y depuracion: en la carpeta temporal del usuario
$dirLogs = Join-Path $env:TEMP 'claude-mascota'
try { New-Item -ItemType Directory -Force $dirLogs | Out-Null } catch {}

# =============================================================================
# 1. Datos de entrada (JSON por stdin: del mod turn-mascota o del hook Notification)
# =============================================================================
$proyecto = ""; $transcript = ""; $ultimo = ""; $recapEntrada = ""; $duracionMs = 0
$tipoNotif = ""
try {
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
    $entrada = [Console]::In.ReadToEnd()
    if ($entrada) {
        $datos = $entrada | ConvertFrom-Json
        if ($datos.message) { $Mensaje = $datos.message; $tipoNotif = "notificacion" }
        if ($datos.notification_type) { $tipoNotif = "$($datos.notification_type)" }
        if ($datos.last_assistant_message) { $ultimo = $datos.last_assistant_message }
        if ($datos.transcript_path) { $transcript = $datos.transcript_path }
        if ($datos.recap) { $recapEntrada = $datos.recap }
        if ($datos.duracion_ms) { $duracionMs = [double]$datos.duracion_ms }
        if ($datos.tipo -and -not $Tipo) { $Tipo = "$($datos.tipo)" }
        if ($datos.cwd) { $proyecto = Split-Path $datos.cwd -Leaf }
    }
} catch {}

if (-not $Tipo) {
    if ($tipoNotif) {
        if ("$tipoNotif $Mensaje" -match 'permission|permiso') { $Tipo = 'permiso' } else { $Tipo = 'pregunta' }
    } else { $Tipo = 'fin' }
}

# =============================================================================
# 2. Origen del aviso y "no molestar"
# =============================================================================
# De donde viene: claude-desktop (app), cli (terminal), algo con vscode (VS Code)
$origen = "$env:CLAUDE_CODE_ENTRYPOINT"

# Cadena de procesos padres: lleva hasta la ventana que lanzo a Claude
# (la app, la terminal o VS Code). Tarda ~0,4 s, por eso solo se usa cuando hace falta.
function Buscar-Ancestros([int]$desde) {
    $todos = @{}
    Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId | ForEach-Object { $todos[[int]$_.ProcessId] = [int]$_.ParentProcessId }
    $cadena = @(); $id = $desde
    for ($i = 0; $i -lt 25 -and $todos.ContainsKey($id) -and $id -gt 4; $i++) { $cadena += $id; $id = $todos[$id] }
    return $cadena
}

# Si ya estas mirando la ventana de donde viene el aviso, no aparece
if (-not $Siempre) {
    try {
        Add-Type -AssemblyName UIAutomationClient
        $idEnfocado = [System.Windows.Automation.AutomationElement]::FocusedElement.Current.ProcessId
        $nombreEnfocado = (Get-Process -Id $idEnfocado -ErrorAction Stop).ProcessName
        $mirando = $false
        if ($origen -eq 'claude-desktop' -and $nombreEnfocado -eq 'claude') { $mirando = $true }
        elseif ($origen -like '*vscode*' -and $nombreEnfocado -eq 'Code') { $mirando = $true }
        elseif ($nombreEnfocado -in @('WindowsTerminal', 'OpenConsole', 'conhost', 'cmd', 'powershell', 'pwsh', 'Code',
                                      'Cursor', 'wezterm-gui', 'alacritty', 'mintty', 'Hyper', 'Tabby', 'claude')) {
            # Terminal o editor enfocado: solo cuenta si es el que lanzo a Claude
            if ((Buscar-Ancestros $PID) -contains $idEnfocado) { $mirando = $true }
        }
        if ($mirando) { exit 0 }
    } catch {}
}

# =============================================================================
# 3. Textos
# =============================================================================
function Resumir([string]$t, [int]$max = 90) {
    $t = ($t -replace '\[([^\]]*)\]\([^)]*\)', '$1' -replace '[#*`>_|]', '' -replace '\s+', ' ').Trim()
    $frase = ($t -split '(?<=[\.\!\?])\s+')[0]
    if ($frase.Length -ge 15) { $t = $frase }
    if ($t.Length -gt $max) { $t = $t.Substring(0, $max).TrimEnd() + [char]0x2026 }
    return $t
}

$recap = "$recapEntrada"
if ($Tipo -eq 'fin' -and -not $Mensaje -and -not $recap -and $transcript -and (Test-Path -LiteralPath $transcript)) {
    # Respaldo para cuando no viene el recap: buscarlo en el historial del turno
    try {
        $lineas = Get-Content -LiteralPath $transcript -Tail 300 -Encoding UTF8
        for ($i = $lineas.Count - 1; $i -ge 0; $i--) {
            $l = $lineas[$i]
            if ($l -notmatch '"type":"(user|assistant)"') { continue }
            $o = $l | ConvertFrom-Json
            $c = $o.message.content
            if ($o.type -eq 'user') {
                if ($c -is [string]) { break }
                if (@($c | Where-Object { $_.type -eq 'text' }).Count -gt 0) { break }
                continue
            }
            foreach ($p in @($c)) {
                if ($p.type -eq 'tool_use' -and $p.name -like '*wrap_up' -and $p.input.recap) { $recap = $p.input.recap; break }
            }
            if ($recap) { break }
        }
    } catch {}
}

if (-not $Mensaje) {
    if ($recap) { $Mensaje = Resumir $recap }
    elseif ($ultimo) { $Mensaje = Resumir $ultimo }
    elseif ($Tipo -eq 'error') { $Mensaje = "La respuesta se corto por un error" }
    else { $Mensaje = "Listo para tu siguiente mensaje" }
} else { $Mensaje = Resumir $Mensaje 110 }

if (-not $Titulo) {
    $Titulo = switch ($Tipo) {
        'permiso'  { "Claude necesita permiso" }
        'pregunta' { "Claude te pregunta algo" }
        'error'    { "Algo fallo" }
        default    { "Respuesta lista" }
    }
}

$pie = "Claude Code"
if ($proyecto -and $proyecto -notlike 'scratch-*') { $pie += " " + [char]0x00B7 + " " + $proyecto }
if ($duracionMs -gt 0) {
    $s = [int][math]::Round($duracionMs / 1000)
    if ($s -lt 60) { $dur = "$s s" }
    elseif ($s -lt 3600) { $dur = "{0} min {1} s" -f [int][math]::Floor($s / 60), ($s % 60) }
    else { $dur = "{0} h {1} min" -f [int][math]::Floor($s / 3600), [int][math]::Floor(($s % 3600) / 60) }
    $pie = "Listo en $dur " + [char]0x00B7 + " " + $pie
}

# Colores segun el caso
$colores = @{
    fin      = @(217, 119, 87)   # naranja
    permiso  = @(232, 190, 70)   # amarillo
    pregunta = @(110, 170, 240)  # celeste
    error    = @(225, 80, 80)    # rojo
}
$rgb = $colores[$Tipo]; if (-not $rgb) { $rgb = $colores['fin'] }

# Accesorio: uno al azar en cada aviso, sin importar la fecha
if (-not $Accesorio) {
    # De cada 100: 46 sin accesorio, 20 lentes, 14 navidad, 5 fiesta, 5 bruja, 5 pirata, 5 audifonos
    $dado = Get-Random -Maximum 100
    $Accesorio = $(if ($dado -lt 46) { 'ninguno' } elseif ($dado -lt 66) { 'lentes' } elseif ($dado -lt 80) { 'navidad' }
                   elseif ($dado -lt 85) { 'fiesta' } elseif ($dado -lt 90) { 'bruja' } elseif ($dado -lt 95) { 'pirata' } else { 'audifonos' })
}
# Forma de la mascota: cambia esta linea a 'cangrejo' si la quieres con tenazas
$MASCOTA_CONFIGURADA = 'clasica'
if (-not $Mascota) { $Mascota = $MASCOTA_CONFIGURADA }
if (-not $Expresion) {
    # De cada 20: 9 ojos pesados, 6 bostezo, 4 ojos normales, 1 ojos ^ ^
    $dado = Get-Random -Maximum 20
    $Expresion = $(if ($dado -le 8) { 'pesados' } elseif ($dado -le 14) { 'bostezo' } elseif ($dado -le 18) { 'normal' } else { 'feliz' })
}
if ($Tipo -ne 'fin') { $Expresion = 'normal' }

# =============================================================================
# 4. Sonido: "gota" y "pop" (ondas suaves generadas al vuelo, sin archivos)
# =============================================================================
# Cada nota: f = frecuencia inicial, t = inicio (s), dur = duracion (s),
# barrido = hasta donde sube/baja el tono, vol = volumen, onda = seno | triangulo
function Crear-Sonido($notas) {
    $tasa = 22050
    $fin = 0.0
    foreach ($n in $notas) { $fin = [math]::Max($fin, $n.t + $n.dur) }
    $total = [int]($tasa * ($fin + 0.03))
    $mezcla = New-Object 'double[]' $total
    foreach ($n in $notas) {
        $ini = [int]($n.t * $tasa); $cant = [int]($n.dur * $tasa)
        $ataque = [int](0.005 * $tasa)
        $fase = 0.0
        $piso = [math]::Log(0.0001 / $n.vol)
        for ($i = 0; $i -lt $cant -and ($ini + $i) -lt $total; $i++) {
            $x = $i / $cant
            $f = $n.f * [math]::Pow($n.barrido, [math]::Min($x / 0.6, 1.0))
            $fase += 2 * [math]::PI * $f / $tasa
            $onda = [math]::Sin($fase)
            if ($n.onda -eq 'triangulo') { $onda = (2 / [math]::PI) * [math]::Asin($onda) }
            if ($i -lt $ataque) { $g = $n.vol * $i / $ataque } else { $g = $n.vol * [math]::Exp($piso * $x) }
            $mezcla[$ini + $i] += $onda * $g
        }
    }
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter $ms
    $bytes = $total * 2
    $bw.Write([Text.Encoding]::ASCII.GetBytes("RIFF")); $bw.Write([int](36 + $bytes))
    $bw.Write([Text.Encoding]::ASCII.GetBytes("WAVEfmt ")); $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1)
    $bw.Write([int]$tasa); $bw.Write([int]($tasa * 2)); $bw.Write([int16]2); $bw.Write([int16]16)
    $bw.Write([Text.Encoding]::ASCII.GetBytes("data")); $bw.Write([int]$bytes)
    foreach ($v in $mezcla) { $bw.Write([int16][math]::Max(-32767, [math]::Min(32767, $v * 26000))) }
    $ms.Position = 0
    return $ms
}
function Gota($t, $f = 500, $barrido = 2.6) { @{ f = $f; t = $t; dur = 0.18; barrido = $barrido; vol = 0.3; onda = 'seno' } }
function Pop($t) { @{ f = 180; t = $t; dur = 0.09; barrido = 0.4; vol = 0.5; onda = 'triangulo' } }
$sonidos = @{
    fin      = @((Gota 0))                    # gota que sube
    pregunta = @((Pop 0))                     # un pop
    permiso  = @((Pop 0), (Pop 0.14))         # pop pop: te esta esperando
    error    = @((Gota 0 900 0.45))           # gota que baja
}
$melodia = $sonidos[$Tipo]; if (-not $melodia) { $melodia = $sonidos['fin'] }

# =============================================================================
# 5. Popup
# =============================================================================
# Puesto en la fila: si ya hay mascotas en pantalla, esta sale encima
$dirPuestos = Join-Path $env:TEMP 'claude-mascota'
$puesto = 0; $candado = $null
try {
    New-Item -ItemType Directory -Force $dirPuestos | Out-Null
    for ($i = 0; $i -lt 6; $i++) {
        try {
            $candado = [System.IO.File]::Open((Join-Path $dirPuestos "puesto$i.lock"), 'OpenOrCreate', 'ReadWrite', 'None')
            $puesto = $i; break
        } catch {}
    }
} catch {}

try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    function Pincel($r, $g, $b) { New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb($r, $g, $b)) }
    $cTema = Pincel $rgb[0] $rgb[1] $rgb[2]

    $area = [System.Windows.SystemParameters]::WorkArea
    $ancho = 450; $alto = 140
    $w = New-Object System.Windows.Window
    $w.WindowStyle = 'None'; $w.AllowsTransparency = $true
    $w.Background = [System.Windows.Media.Brushes]::Transparent
    $w.Topmost = $true; $w.ShowInTaskbar = $false; $w.ShowActivated = $false
    $w.ResizeMode = 'NoResize'; $w.Cursor = 'Hand'
    $w.Width = $ancho; $w.Height = $alto
    $w.Top = $area.Bottom - ($alto - 8) * ($puesto + 1) - 8
    $w.Left = $area.Right

    $fila = New-Object System.Windows.Controls.StackPanel
    $fila.Orientation = 'Horizontal'; $fila.VerticalAlignment = 'Bottom'

    # ---- Globo de texto ----
    $globo = New-Object System.Windows.Controls.Border
    $globo.Background = Pincel 38 38 36
    $globo.BorderBrush = $cTema
    $globo.BorderThickness = 2; $globo.CornerRadius = 12
    $globo.Padding = '14,10,14,10'; $globo.Margin = '0,0,4,24'
    $globo.Width = $ancho - 112; $globo.VerticalAlignment = 'Bottom'

    $textos = New-Object System.Windows.Controls.StackPanel
    $t1 = New-Object System.Windows.Controls.TextBlock
    $t1.Text = $Titulo; $t1.FontWeight = 'Bold'; $t1.FontSize = 14; $t1.Foreground = [System.Windows.Media.Brushes]::White
    # Resumen "escrito" letra por letra: la parte aun no escrita es transparente,
    # asi el globo tiene su tamano final desde el principio y no salta.
    $t2 = New-Object System.Windows.Controls.TextBlock
    $t2.FontSize = 12.5; $t2.TextWrapping = 'Wrap'; $t2.Margin = '0,3,0,3'
    $runVisible = New-Object System.Windows.Documents.Run ""
    $runVisible.Foreground = Pincel 220 218 210
    $runOculto = New-Object System.Windows.Documents.Run $Mensaje
    $runOculto.Foreground = [System.Windows.Media.Brushes]::Transparent
    $t2.Inlines.Add($runVisible); $t2.Inlines.Add($runOculto)
    $t3 = New-Object System.Windows.Controls.TextBlock
    $t3.Text = $pie; $t3.FontSize = 10.5; $t3.Foreground = $cTema; $t3.TextTrimming = 'CharacterEllipsis'
    [void]$textos.Children.Add($t1); [void]$textos.Children.Add($t2); [void]$textos.Children.Add($t3)
    $globo.Child = $textos

    # ---- Mascota hecha de bloques ----
    $px = 6
    $cNaranja = Pincel 217 119 87
    $cOscuro = Pincel 30 20 15
    function Bloque($padre, [double]$x, [double]$y, [double]$an, [double]$al, $color) {
        $r = New-Object System.Windows.Shapes.Rectangle
        $r.Width = $an * $px; $r.Height = $al * $px; $r.Fill = $color
        [System.Windows.Controls.Canvas]::SetLeft($r, $x * $px)
        [System.Windows.Controls.Canvas]::SetTop($r, $y * $px)
        [void]$padre.Children.Add($r)
        return $r
    }
    function PonerY($el, $y) { $el.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]$y) }

    $img = New-Object System.Windows.Controls.Canvas
    $img.Width = 16 * $px; $img.Height = 16 * $px; $img.VerticalAlignment = 'Bottom'
    $img.SnapsToDevicePixels = $true
    $salto = New-Object System.Windows.Media.TranslateTransform
    $img.RenderTransform = $salto

    $patas = @(
        (Bloque $img 4 10 1 2 $cNaranja), (Bloque $img 6 10 1 2 $cNaranja),
        (Bloque $img 9 10 1 2 $cNaranja), (Bloque $img 11 10 1 2 $cNaranja)
    )
    $cuerpo = New-Object System.Windows.Controls.Canvas
    $mueve = New-Object System.Windows.Media.TranslateTransform
    $cuerpo.RenderTransform = $mueve
    [void]$img.Children.Add($cuerpo)
    [void](Bloque $cuerpo 3 3 10 7 $cNaranja)

    # Un grupo de bloques que se muestra/oculta o se mueve junto. Celdas: x, y, ancho, alto
    function Grupo($padre, $celdas, $color) {
        $c = New-Object System.Windows.Controls.Canvas
        foreach ($k in $celdas) { [void](Bloque $c $k[0] $k[1] $k[2] $k[3] $color) }
        [void]$padre.Children.Add($c)
        return $c
    }
    # Levantar un brazo: 0 = reposo, 1 o 2 = filas hacia arriba
    function Levantar($brazo, $filas) { PonerY $brazo (-$filas * $px) }

    if ($Mascota -eq 'cangrejo') {
        # Pinzas abiertas en vez de brazos
        # Tenazas separadas (+2), naranja quemado con puntas terracota
        $cTenaza = Pincel 184 92 62; $cPunta = Pincel 154 74 48
        $brazoI = Grupo $cuerpo @(@(-2,4,3,1), @(-1,5,1,1), @(-1,6,4,1)) $cTenaza
        [void](Grupo $brazoI @(@(-2,3,1,1), @(0,3,1,1)) $cPunta)
        $brazoD = Grupo $cuerpo @(@(15,4,3,1), @(16,5,1,1), @(13,6,4,1)) $cTenaza
        [void](Grupo $brazoD @(@(17,3,1,1), @(15,3,1,1)) $cPunta)
        # Hacer sitio a las tenazas largas
        $img.Margin = '12,0,0,0'; $globo.Width = $globo.Width - 12
    } else {
        $brazoI = Grupo $cuerpo @(,@(1,6,2,2)) $cNaranja
        $brazoD = Grupo $cuerpo @(,@(13,6,2,2)) $cNaranja
    }

    # Ojos: la expresion va en los ojos. Tres juegos: abiertos, parpadeo y dormidos
    $celdasOjos = switch ($Tipo) {
        'fin'     {
            switch ($Expresion) {
                'pesados' { @(@(4,4.5,3,0.5), @(5,5,1,1), @(9,4.5,3,0.5), @(10,5,1,1)) }          # ojos pesados
                'bostezo' { @(@(4,5.5,3,0.5), @(9,5.5,3,0.5)) }                                     # ojos cerrados al bostezar
                'feliz'   { @(@(4,5,1,1), @(5,4,1,1), @(6,5,1,1), @(9,5,1,1), @(10,4,1,1), @(11,5,1,1)) }  # ^ ^ contentos
                default   { @(@(5,4,1,2), @(10,4,1,2)) }                                                      # ojos normales
            }
        }
        'permiso' { @(@(4,4,2,2), @(10,4,2,2)) }                                                     # bien abiertos
        'error'   { @(@(4,5,2,1), @(10,5,2,1)) }                                                     # tristes
        default   { @(@(5,4,1,2), @(10,4,1,2)) }
    }
    $ojosAbiertos = Grupo $cuerpo $celdasOjos $cOscuro
    $ojosParpadeo = Grupo $cuerpo @(@(4,5.5,3,0.5), @(9,5.5,3,0.5)) $cOscuro
    # Dormidos: parpados caidos y pesados
    $ojosDormidos = Grupo $cuerpo @(@(4,5,1,0.6), @(5,5.6,1,0.6), @(6,5,1,0.6), @(4,4.6,3,0.4),
                                    @(9,5,1,0.6), @(10,5.6,1,0.6), @(11,5,1,0.6), @(9,4.6,3,0.4)) $cOscuro
    $ojosPesados = Grupo $cuerpo @(@(4,4.5,3,0.5), @(5,5,1,1), @(9,4.5,3,0.5), @(10,5,1,1)) $cOscuro
    $ojosParpadeo.Visibility = 'Collapsed'; $ojosDormidos.Visibility = 'Collapsed'; $ojosPesados.Visibility = 'Collapsed'
    function Ojos($modo) {
        $ojosAbiertos.Visibility = $(if ($modo -eq 'abiertos') { 'Visible' } else { 'Collapsed' })
        $ojosParpadeo.Visibility = $(if ($modo -eq 'cerrados') { 'Visible' } else { 'Collapsed' })
        $ojosDormidos.Visibility = $(if ($modo -eq 'dormidos') { 'Visible' } else { 'Collapsed' })
        $ojosPesados.Visibility = $(if ($modo -eq 'pesados') { 'Visible' } else { 'Collapsed' })
    }

    # Boca: solo el error la tiene (triste)
    $boca = $null
    if ($Tipo -eq 'error') { $boca = Grupo $cuerpo @(@(6,8,1,1), @(7,7,2,1), @(9,8,1,1)) $cOscuro }

    # Accesorio
    $cigarro = $false; $musica = $false
    switch ($Accesorio) {
        'navidad' {
            $rojo = Pincel 200 40 45; $blanco = Pincel 245 245 245
            [void](Bloque $cuerpo 4 1 8 2 $rojo); [void](Bloque $cuerpo 6 0 5 1 $rojo); [void](Bloque $cuerpo 9 -1 3 1 $rojo)
            [void](Bloque $cuerpo 3 2.5 10 1 $blanco); [void](Bloque $cuerpo 12 -1.5 1.5 1.5 $blanco)
            # Barba de Papa Noel
            [void](Grupo $cuerpo @(@(3,6,1,2), @(12,6,1,2), @(3,8,10,1), @(4,9,8,1), @(5,10,6,1), @(6,11,4,0.7)) $blanco)
        }
        'fiesta' {
            $azul = Pincel 70 130 230; $amarillo = Pincel 250 210 60
            [void](Bloque $cuerpo 5 2 6 1 $azul); [void](Bloque $cuerpo 6 1 4 1 $azul); [void](Bloque $cuerpo 7 0 2 1 $azul)
            [void](Bloque $cuerpo 7 -1 2 1 $amarillo); [void](Bloque $cuerpo 6 1 1 1 $amarillo); [void](Bloque $cuerpo 9 2 1 1 $amarillo)
        }
        'bruja' {
            $morado = Pincel 90 50 140; $verde = Pincel 90 190 90
            [void](Bloque $cuerpo 2 2 12 1 $morado); [void](Bloque $cuerpo 5 0 6 2 $morado); [void](Bloque $cuerpo 7 -2 3 2 $morado)
            [void](Bloque $cuerpo 5 1.5 6 0.5 $verde)
        }
        'lentes' {
            [void](Bloque $cuerpo 4 4 3 2 $cOscuro); [void](Bloque $cuerpo 9 4 3 2 $cOscuro); [void](Bloque $cuerpo 7 4 2 1 $cOscuro)
            [void](Bloque $cuerpo 3 4 1 1 $cOscuro); [void](Bloque $cuerpo 12 4 1 1 $cOscuro)
            # Cigarro en la comisura
            [void](Bloque $cuerpo 9 7.6 3.4 0.7 (Pincel 240 238 230))
            [void](Bloque $cuerpo 9 7.6 0.8 0.7 (Pincel 200 150 90))
            $brasa = Bloque $cuerpo 12.4 7.6 0.7 0.7 (Pincel 235 80 40)
            $cigarro = $true
        }
        'pirata' {
            # Panuelo rojo con lunares, nudo al costado y parche en el ojo
            $rojo = Pincel 200 40 45; $blanco = Pincel 245 245 245
            [void](Grupo $cuerpo @(@(3,1.6,10,1.6), @(4,1,8,0.6), @(1.6,2.2,1.6,0.9), @(1.2,3.1,1,1.3)) $rojo)
            [void](Grupo $cuerpo @(@(5,2,0.6,0.6), @(8,1.6,0.6,0.6), @(10.6,2.2,0.6,0.6)) $blanco)
            [void](Grupo $cuerpo @(@(3.8,3.8,3.4,2.4), @(7.2,3.6,1.6,0.5), @(3,4.2,0.8,0.5)) $cOscuro)
        }
        'audifonos' {
            # Diadema sobre la cabeza y almohadillas a los costados
            $diadema = Pincel 55 55 60; $almohadilla = Pincel 60 200 190
            [void](Grupo $cuerpo @(@(3,2.1,10,0.9), @(2.3,2.5,1,1.1), @(12.7,2.5,1,1.1)) $diadema)
            [void](Grupo $cuerpo @(@(1.7,3.4,1.6,2.6), @(12.7,3.4,1.6,2.6)) $almohadilla)
            $musica = $true
        }
    }

    # Sentarse: esconde las patas y el cuerpo baja hasta el suelo
    function Sentarse($si) {
        $estado.sentado = $si
        foreach ($p in $patas) { $p.Visibility = $(if ($si) { 'Collapsed' } else { 'Visible' }) }
    }

    # Boca de bostezo encima de todo (asoma aunque haya barba)
    $bostezo = Bloque $cuerpo 7 7 2 2 $cOscuro
    $bostezo.Visibility = 'Collapsed'

    # Simbolo sobre la cabeza
    $simbolo = $null
    if ($Tipo -eq 'permiso' -or $Tipo -eq 'pregunta') {
        $simbolo = New-Object System.Windows.Controls.TextBlock
        $simbolo.Text = $(if ($Tipo -eq 'permiso') { '!' } else { '?' })
        $simbolo.FontFamily = 'Consolas'; $simbolo.FontWeight = 'Bold'; $simbolo.FontSize = 26
        $simbolo.Foreground = $cTema
        [System.Windows.Controls.Canvas]::SetLeft($simbolo, 13 * $px)
        PonerY $simbolo (-4 * $px)
        [void]$img.Children.Add($simbolo)
    }

    [void]$fila.Children.Add($globo); [void]$fila.Children.Add($img)
    $w.Content = $fila

    # ---- Comportamiento ----
    $dentro = $area.Right - $ancho - 12
    $fuera = $area.Right
    $duerme = ($Tipo -eq 'fin' -or $Tipo -eq 'error')
    $estado = @{ tick = 0; fase = 'caminar'; espera = 0; suenio = 0; dormido = $false; saliendo = $false; letras = 0; sentado = $false }
    $limiteEspera = $(if ($duerme) { 38 } else { 80 })   # ticks de 120 ms
    # Trabajo largo (1 min o mas): probablemente te fuiste, asi que no se va sola.
    # Tope de 9 min dormida (el mod la deja vivir 10 min, el maximo que acepta Claude)
    $quedarse = $duerme -and $duracionMs -ge 60000 -and -not $CapturaSVG -and -not $CapturaPNG
    $MAX_DORMIDA = [int](9 * 60 / 0.12)

    function Mover($desde, $hasta, $alTerminar, [switch]$Salida) {
        $estado.fase = 'caminar'
        if ($Salida) {
            # Al irse: un par de pasos en el sitio, arranca despacio y acelera
            $a = New-Object System.Windows.Media.Animation.DoubleAnimation $desde, $hasta, ([TimeSpan]::FromMilliseconds(1700))
            $a.BeginTime = [TimeSpan]::FromMilliseconds(350)
            $e = New-Object System.Windows.Media.Animation.QuadraticEase
            $e.EasingMode = 'EaseIn'
        } else {
            $a = New-Object System.Windows.Media.Animation.DoubleAnimation $desde, $hasta, ([TimeSpan]::FromMilliseconds(1100))
            $e = New-Object System.Windows.Media.Animation.QuadraticEase
            $e.EasingMode = 'EaseOut'
        }
        $a.EasingFunction = $e
        $a.Add_Completed($alTerminar)
        $w.BeginAnimation([System.Windows.Window]::LeftProperty, $a)
    }
    function Irse {
        if ($estado.saliendo) { return }
        $estado.saliendo = $true
        $estado.letras = $Mensaje.Length
        if ($estado.sentado -or $estado.dormido -or $estado.fase -eq 'dormir') {
            # Primero despierta y se para; el tick 'levantarse' la hace caminar despues
            $estado.fase = 'levantarse'; $estado.lev = 0
        } else {
            Mover $w.Left $fuera { $w.Close() } -Salida
        }
    }
    $zetas = New-Object System.Collections.ArrayList
    function Zeta {
        # Borra las que ya se desvanecieron (dormida horas, se acumularian)
        foreach ($v in @($zetas)) { if ($estado.tick - $v.t -gt 14) { $img.Children.Remove($v.z); $zetas.Remove($v) } }
        $z = New-Object System.Windows.Controls.TextBlock
        [void]$zetas.Add(@{ z = $z; t = $estado.tick })
        $z.Text = 'z'; $z.FontFamily = 'Consolas'; $z.FontWeight = 'Bold'
        $z.FontSize = 12 + (Get-Random -Maximum 6); $z.Foreground = Pincel 200 200 220
        [System.Windows.Controls.Canvas]::SetLeft($z, 12 * $px + (Get-Random -Maximum 8))
        PonerY $z (2 * $px)
        [void]$img.Children.Add($z)
        $sube = New-Object System.Windows.Media.Animation.DoubleAnimation (2 * $px), (-5 * $px), ([TimeSpan]::FromMilliseconds(1400))
        $borra = New-Object System.Windows.Media.Animation.DoubleAnimation 1, 0, ([TimeSpan]::FromMilliseconds(1400))
        $z.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, $sube)
        $z.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $borra)
    }

    # Humo del cigarro: sube por pasos en el mismo tick que el resto de la mascota.
    # (Con animaciones fluidas la ventana transparente se redibujaba sin parar y se trababa al irse)
    $humos = New-Object System.Collections.ArrayList
    $PASOS_HUMO = 13
    function Humo {
        $h = New-Object System.Windows.Shapes.Rectangle
        $h.Width = $px * 0.8; $h.Height = $px * 0.8
        $h.Fill = Pincel 190 190 195
        [void]$img.Children.Add($h)
        [void]$humos.Add(@{ r = $h; paso = 0 })
        Mover-Humo
    }
    function Mover-Humo {
        foreach ($b in @($humos)) {
            $f = $b.paso / $PASOS_HUMO
            if ($f -ge 1) { $img.Children.Remove($b.r); $humos.Remove($b); continue }
            [System.Windows.Controls.Canvas]::SetTop($b.r, (7 - 7 * $f) * $px)
            [System.Windows.Controls.Canvas]::SetLeft($b.r, (12.8 + 1.4 * $f) * $px)
            $b.r.Opacity = 0.8 * (1 - $f)
            $b.paso++
        }
    }

    # Notas musicales de los audifonos: suben por pasos, igual que el humo
    $notas = New-Object System.Collections.ArrayList
    function Nota {
        $n = New-Object System.Windows.Controls.TextBlock
        $n.Text = @([char]0x266A, [char]0x266B)[(Get-Random -Maximum 2)]
        $n.FontSize = 13; $n.FontWeight = 'Bold'; $n.Foreground = $almohadilla
        [void]$img.Children.Add($n)
        $lado = $(if ((Get-Random -Maximum 2) -eq 0) { -0.5 } else { 13.6 })
        [void]$notas.Add(@{ t = $n; paso = 0; x = $lado })
        Mover-Notas
    }
    function Mover-Notas {
        foreach ($b in @($notas)) {
            $f = $b.paso / 14
            if ($f -ge 1) { $img.Children.Remove($b.t); $notas.Remove($b); continue }
            [System.Windows.Controls.Canvas]::SetTop($b.t, (3 - 6 * $f) * $px)
            [System.Windows.Controls.Canvas]::SetLeft($b.t, ($b.x + [math]::Sin($f * 6) * 0.6) * $px)
            $b.t.Opacity = 1 - $f
            $b.paso++
        }
    }

    $anim = New-Object System.Windows.Threading.DispatcherTimer
    $anim.Interval = [TimeSpan]::FromMilliseconds(120)
    $anim.Add_Tick({
        $estado.tick++
        $t = $estado.tick
        $par = ($t % 2) -eq 0
        switch ($estado.fase) {
            'caminar' {
                if ($estado.sentado) { Sentarse $false }
                $bostezo.Visibility = 'Collapsed'
                for ($i = 0; $i -lt 4; $i++) {
                    $arriba = (($i % 2) -eq 0) -eq $par
                    $patas[$i].Height = $(if ($arriba) { $px } else { 2 * $px })
                }
                $mueve.Y = $(if ($par) { -$px / 2 } else { 0 })
                Levantar $brazoI $(if ($par) { 1 } else { 0 })
                Levantar $brazoD $(if ($par) { 0 } else { 1 })
            }
            'levantarse' {
                # Despierta, se para y recien ahi se va caminando
                $estado.lev++
                $estado.dormido = $false
                $bostezo.Visibility = 'Collapsed'
                if ($boca) { $boca.Visibility = 'Visible' }
                Levantar $brazoI 0; Levantar $brazoD 0
                switch ($estado.lev) {
                    1 { Ojos 'pesados'; $mueve.Y = 2 * $px }
                    2 { Ojos 'abiertos'; Sentarse $false; foreach ($p in $patas) { $p.Height = 2 * $px }; $mueve.Y = 1.2 * $px }
                    3 { $mueve.Y = 0.4 * $px }
                    4 { $mueve.Y = 0 }
                    5 { Mover $w.Left $fuera { $w.Close() } -Salida }
                }
            }
            'esperar' {
                foreach ($p in $patas) { $p.Height = 2 * $px }
                # Pregunta o permiso: tras un rato se sienta a esperarte
                if (-not $duerme -and $estado.espera -eq 30) { Sentarse $true }
                $base = $(if ($estado.sentado) { 2 * $px } else { 0 })
                $mueve.Y = $base + $(if ((($t / 4) % 2) -lt 1) { 0 } else { -$px / 2 })
                if ($Expresion -eq 'bostezo') {
                    # Bosteza cada tanto: brazos arriba y boca abierta
                    $bosteza = ($t % 20) -lt 8
                    $bostezo.Visibility = $(if ($bosteza) { 'Visible' } else { 'Collapsed' })
                    Levantar $brazoI $(if ($bosteza) { 2 } else { 0 })
                    Levantar $brazoD $(if ($bosteza) { 2 } else { 0 })
                } else {
                    $saludo = ($t % 16) -lt 6 -and $par
                    Levantar $brazoD $(if ($saludo) { 2 } else { 0 })
                    Levantar $brazoI 0
                }
                $estado.espera++
                if ($estado.espera -ge $limiteEspera) {
                    if ($duerme) { $estado.fase = 'dormir' } else { Irse }
                }
            }
            'dormir' {
                $estado.suenio++
                $s = $estado.suenio
                $bostezo.Visibility = 'Collapsed'
                Levantar $brazoI 0; Levantar $brazoD 0
                if ($s -le 6) {
                    # Se sienta, con los ojos pesados
                    if ($s -eq 1) { Sentarse $true }
                    Ojos 'pesados'
                    $mueve.Y = [math]::Min(2, $s * 0.5) * $px
                } elseif ($s -le 26) {
                    # Cabeceo: la cabeza se le va cayendo y despierta de golpe
                    $c = ($s - 7) % 10
                    if ($c -le 5) { $mueve.Y = (2 + $c * 0.25) * $px; Ojos 'cerrados' }
                    elseif ($c -eq 6) { $mueve.Y = 1.5 * $px; Ojos 'pesados' }
                    else { $mueve.Y = 2 * $px; Ojos 'pesados' }
                } else {
                    # Dormida sentada
                    if ($boca) { $boca.Visibility = 'Collapsed' }
                    $estado.dormido = $true
                    Ojos 'dormidos'
                    $mueve.Y = (2 + $(if ((($t / 8) % 2) -lt 1) { 0 } else { 0.7 })) * $px
                    if (($s % 7) -eq 0) { Zeta }
                }
                # Tras un trabajo largo se queda dormida hasta que le hagas clic (o vuelvas a Claude)
                if ($s -ge 50 -and (-not $quedarse -or $s -ge $MAX_DORMIDA)) { Irse }
            }
        }
        # Parpadeo (no cuando duerme)
        if (-not $estado.dormido -and $estado.fase -ne 'dormir' -and $estado.fase -ne 'levantarse') {
            if (($t % 25) -eq 0) { Ojos 'cerrados' } else { Ojos 'abiertos' }
        }
        # Humo del cigarro (no mientras duerme)
        if ($cigarro) {
            Mover-Humo
            if (-not $estado.dormido -and $estado.fase -ne 'dormir' -and ($t % 9) -eq 0) { Humo }
            $brasa.Opacity = $(if (($t % 6) -lt 3) { 1 } else { 0.6 })
        }
        # Cada medio segundo mira que ventana tienes al frente (no mientras camina, para no trabarla)
        if (($t % 4) -eq 0 -and -not $estado.saliendo -and $estado.fase -ne 'caminar' -and -not $CapturaSVG) {
            try { Mirar-Frente } catch {}
        }
        # Notas de los audifonos (no mientras duerme)
        if ($musica) {
            Mover-Notas
            if (-not $estado.dormido -and $estado.fase -ne 'dormir' -and ($t % 11) -eq 0) { Nota }
        }
        # El simbolo flota
        if ($simbolo) { PonerY $simbolo $(if ((($t / 3) % 2) -lt 1) { -4 * $px } else { -4.6 * $px }) }
    })

    # Texto letra por letra
    $escribe = New-Object System.Windows.Threading.DispatcherTimer
    $escribe.Interval = [TimeSpan]::FromMilliseconds(28)
    $escribe.Add_Tick({
        $paso = $(if ($Mensaje.Length -gt 70) { 2 } else { 1 })
        $estado.letras = [math]::Min($Mensaje.Length, $estado.letras + $paso)
        $runVisible.Text = $Mensaje.Substring(0, $estado.letras)
        $runOculto.Text = $Mensaje.Substring($estado.letras)
        if ($estado.letras -ge $Mensaje.Length) { $escribe.Stop() }
    })

    # Clic: la mascota se va y te lleva a la ventana de donde vino el aviso
    # (la app de Claude, la terminal o VS Code): la restaura si esta minimizada y la pone al frente
    $codigoVentana = @'
using System;
using System.Runtime.InteropServices;
public static class VentanaClaude {
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    public static bool Visible(IntPtr h) { return IsIconic(h) || IsWindowVisible(h); }
    public static bool Minimizada(IntPtr h) { return IsIconic(h); }
    public static IntPtr Frente() { return GetForegroundWindow(); }
    public static int PidDe(IntPtr h) { uint p; GetWindowThreadProcessId(h, out p); return (int)p; }
    // La ventana "de verdad" de un proceso: con titulo, sin duenio, visible o minimizada.
    // (MainWindowHandle puede apuntar a una ventana oculta cuando la app esta minimizada)
    public static IntPtr DeProceso(int pid) {
        IntPtr hallada = IntPtr.Zero;
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            // Fuera capas superpuestas: transparentes (0x20), de herramientas (0x80) o que no se activan (0x08000000)
            bool capa = (GetWindowLong(h, -20) & (0x20 | 0x80 | 0x08000000)) != 0;
            if (p == (uint)pid && !capa && GetWindow(h, 4) == IntPtr.Zero && GetWindowTextLength(h) > 0 && Visible(h)) { hallada = h; return false; }
            return true;
        }, IntPtr.Zero);
        return hallada;
    }
    public static void Traer(IntPtr h) {
        if (IsIconic(h)) ShowWindow(h, 9);   // SW_RESTORE
        if (SetForegroundWindow(h) && GetForegroundWindow() == h) return;
        // Si Windows no dejo cambiar de ventana, un toque de Alt lo destraba
        keybd_event(0x12, 0, 0, UIntPtr.Zero);
        keybd_event(0x12, 0, 2, UIntPtr.Zero);
        SetForegroundWindow(h);
    }
}
'@
    # En segundo plano al llegar: compila lo de arriba y busca la cadena de procesos padres,
    # asi el clic no congela la animacion
    function Preparar-Claude {
        try {
            if ($estado.preparando) { return }
            $estado.preparando = [powershell]::Create()
            [void]$estado.preparando.AddScript({
                param($codigo, $propio)
                if (-not ('VentanaClaude' -as [type])) { Add-Type -TypeDefinition $codigo }
                $todos = @{}
                Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId | ForEach-Object { $todos[[int]$_.ProcessId] = [int]$_.ParentProcessId }
                $id = $propio
                for ($i = 0; $i -lt 25 -and $todos.ContainsKey($id) -and $id -gt 4; $i++) { $id; $id = $todos[$id] }
            }).AddArgument($codigoVentana).AddArgument($PID)
            $estado.preparacion = $estado.preparando.BeginInvoke()
        } catch {}
    }
    # La primera ventana real subiendo por la cadena de padres es la de origen.
    # Nunca pasa del Explorador de Windows (el escritorio): eso seria traer la ventana equivocada.
    function Ventana-Origen {
        if (-not $estado.preparacion) { Preparar-Claude }
        if ($null -eq $estado.ancestros) { $estado.ancestros = @($estado.preparando.EndInvoke($estado.preparacion) | ForEach-Object { [int]$_ }) }
        foreach ($id in $estado.ancestros) {
            if ($id -eq $PID) { continue }
            $p = Get-Process -Id $id -ErrorAction SilentlyContinue
            if (-not $p -or $p.ProcessName -eq 'explorer') { break }
            if ($p.ProcessName -in @('powershell', 'pwsh', 'bash', 'sh', 'cmd', 'conhost') -and $origen -ne 'cli') { continue }
            $h = [VentanaClaude]::DeProceso($id)
            # Consola clasica: la ventana es de conhost, pero Windows la reporta como la del shell
            if ($h -eq [IntPtr]::Zero -and $origen -eq 'cli' -and $p.MainWindowHandle -ne 0 -and [VentanaClaude]::Visible($p.MainWindowHandle)) { $h = $p.MainWindowHandle }
            if ($h -ne [IntPtr]::Zero) { return $h }
        }
        return [IntPtr]::Zero
    }
    # Procesos de donde vino el aviso (la app, la terminal o VS Code), para saber si ya volviste ahi.
    # Se arma una sola vez, cuando la preparacion en segundo plano ya termino.
    function Pids-Origen {
        if ($null -ne $estado.pidsOrigen) { return $estado.pidsOrigen }
        if (-not $estado.preparacion -or -not $estado.preparacion.IsCompleted) { return $null }
        if ($null -eq $estado.ancestros) { $estado.ancestros = @($estado.preparando.EndInvoke($estado.preparacion) | ForEach-Object { [int]$_ }) }
        $ids = @()
        foreach ($id in $estado.ancestros) {
            if ($id -eq $PID) { continue }
            $p = Get-Process -Id $id -ErrorAction SilentlyContinue
            if (-not $p -or $p.ProcessName -eq 'explorer') { break }
            $ids += $id
        }
        if ($origen -eq 'claude-desktop') {
            $ids += @(Get-Process -Name claude -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*WindowsApps*' } | ForEach-Object { $_.Id })
        }
        $estado.pidsOrigen = $ids
        return $ids
    }
    # Ventana al frente que no sea la mascota, y si es la de origen
    function Mirar-Frente {
        if (-not ('VentanaClaude' -as [type])) { return }
        $ids = Pids-Origen
        if ($null -eq $ids) { return }
        $h = [VentanaClaude]::Frente()
        if ($h -eq [IntPtr]::Zero) { return }
        $pid2 = [VentanaClaude]::PidDe($h)
        if ($pid2 -eq $PID) { return }
        $estado.frente = $h
        $enOrigen = $ids -contains $pid2
        # Volviste por tu cuenta a Claude: la mascota ya no hace falta y se va sola
        if ($enOrigen -and $estado.fueraDeOrigen -and -not $estado.saliendo) {
            if ($env:MASCOTA_DEBUG) { "Volviste al origen (pid $pid2): se va sola" | Out-File (Join-Path $dirLogs 'notify-debug.log') -Append -Encoding UTF8 }
            Irse
        }
        if (-not $enOrigen) { $estado.fueraDeOrigen = $true }
    }

    function Clic {
        # Solo cuenta el primer clic: repetir todo en cada clic podia esconder o cerrar Claude
        if ($estado.clicado) { return }
        $estado.clicado = $true
        Irse
        try {
            $h = Ventana-Origen
            if ($h -eq [IntPtr]::Zero -and $origen -eq 'claude-desktop') {
                # Respaldo para la app: cualquier ventana real suya, o abrirla si esta en la bandeja
                foreach ($app in (Get-Process -Name claude -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*WindowsApps*' })) {
                    $h = [VentanaClaude]::DeProceso($app.Id)
                    if ($h -ne [IntPtr]::Zero) { break }
                }
                if ($h -eq [IntPtr]::Zero) {
                    # Buscar la app de Claude en el menu Inicio (sirve para cualquier instalacion)
                    $app = Get-StartApps | Where-Object { $_.Name -eq 'Claude' } | Select-Object -First 1
                    if ($app) { Start-Process "shell:AppsFolder\$($app.AppID)" }
                }
            }
            if ($env:MASCOTA_DEBUG) {
                "Clic: origen=$origen ventana=$h ancestros=$($estado.ancestros -join ',')" | Out-File (Join-Path $dirLogs 'notify-debug.log') -Append -Encoding UTF8
            }
            # Si ya la tienes al frente (la abriste tu), no se toca
            # (al hacer clic la mascota puede quedar al frente; entonces vale la ultima que se vio)
            $frente = [VentanaClaude]::Frente()
            if ([VentanaClaude]::PidDe($frente) -eq $PID) { $frente = $estado.frente }
            $yaAlFrente = $h -ne [IntPtr]::Zero -and $frente -eq $h -and -not [VentanaClaude]::Minimizada($h)
            if ($env:MASCOTA_DEBUG) { "Clic: ya al frente=$yaAlFrente (frente=$frente, pid=$([VentanaClaude]::PidDe([VentanaClaude]::Frente())))" | Out-File (Join-Path $dirLogs 'notify-debug.log') -Append -Encoding UTF8 }
            if ($h -ne [IntPtr]::Zero -and -not $yaAlFrente) { [VentanaClaude]::Traer($h) }
        } catch {
            "Clic: " + ($_ | Out-String) | Out-File (Join-Path $dirLogs 'notify-error.log') -Append -Encoding UTF8
        }
    }
    $w.Add_MouseLeftButtonUp({ Clic })

    if ($CapturaSVG) {
        # Graba cada cuadro como figuras (posicion, color, opacidad) con su tiempo y la posicion
        # de la ventana, para armar despues un SVG animado del aviso (ver tools/armar_svg.py)
        $refs = @([System.Windows.Window], [System.Windows.Media.Visual], [System.Windows.DependencyObject], [System.Xaml.XamlType], [System.ComponentModel.ISupportInitialize]) |
            ForEach-Object { $_.Assembly.Location } | Select-Object -Unique
        if (-not ('Grabador' -as [type])) { Add-Type -Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\Grabador.cs') -ReferencedAssemblies $refs }
        $estado.reloj = [Diagnostics.Stopwatch]::StartNew()
        $estado.cuadros = New-Object System.Collections.Generic.List[string]
        $estado.grabar = New-Object System.Windows.Threading.DispatcherTimer
        $estado.grabar.Interval = [TimeSpan]::FromMilliseconds(40)
        $estado.grabar.Add_Tick({
            $estado.cuadros.Add("{""t"":$($estado.reloj.ElapsedMilliseconds),""x"":$([math]::Round($w.Left - $area.Right, 2)),""f"":$([Grabador]::Cuadro($w.Content))}")
        })
        $w.Add_Closing({
            $estado.grabar.Stop()
            $txt = "{""ancho"":$ancho,""alto"":$alto,""cuadros"":[" + ($estado.cuadros -join ',') + "]}"
            [System.IO.File]::WriteAllText($CapturaSVG, $txt, (New-Object System.Text.UTF8Encoding $false))
        })
    }

    $w.Add_Loaded({
        if ($CapturaSVG) { $estado.grabar.Start() }
        $anim.Start()
        try {
            $script:sonido = New-Object System.Media.SoundPlayer (Crear-Sonido $melodia)
            $script:sonido.Play()
        } catch {}
        Mover $fuera $dentro {
            # Llego: saltito al frenar
            $estado.fase = 'esperar'
            $a = New-Object System.Windows.Media.Animation.DoubleAnimation 0, (-3 * $px), ([TimeSpan]::FromMilliseconds(170))
            $a.AutoReverse = $true
            $e = New-Object System.Windows.Media.Animation.QuadraticEase
            $e.EasingMode = 'EaseOut'; $a.EasingFunction = $e
            $salto.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $a)
            $escribe.Start()
            Preparar-Claude
            if ($CapturaPNG) {
                # Espera a que termine de escribir, guarda la imagen (al doble de resolucion) y se cierra
                $estado.captura = New-Object System.Windows.Threading.DispatcherTimer
                $estado.captura.Interval = [TimeSpan]::FromSeconds(2.4)
                $estado.captura.Add_Tick({
                    $estado.captura.Stop()
                    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ([int]($ancho * 2)), ([int]($alto * 2)), 192, 192, ([System.Windows.Media.PixelFormats]::Pbgra32)
                    $rtb.Render($w.Content)
                    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
                    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
                    $fs = [System.IO.File]::Create($CapturaPNG); $enc.Save($fs); $fs.Close()
                    $w.Close()
                })
                $estado.captura.Start()
            }
            if ($ClicTras -gt 0) {
                # Solo para pruebas: simula un clic tras unos segundos
                $estado.prueba = New-Object System.Windows.Threading.DispatcherTimer
                $estado.prueba.Interval = [TimeSpan]::FromSeconds($ClicTras)
                $estado.prueba.Add_Tick({ $estado.prueba.Stop(); if ($CapturaSVG) { Irse } else { Clic } })
                $estado.prueba.Start()
            }
        }
    })

    [void]$w.ShowDialog()
    if ($candado) { $candado.Dispose() }
    return
} catch {
    ($_ | Out-String) + $_.ScriptStackTrace | Out-File (Join-Path $dirLogs 'notify-error.log') -Encoding UTF8
}
if ($candado) { $candado.Dispose() }

# =============================================================================
# 6. Respaldo: globo clasico de la bandeja
# =============================================================================
try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $n = New-Object System.Windows.Forms.NotifyIcon
    $n.Icon = [System.Drawing.SystemIcons]::Information
    $n.Visible = $true
    $n.ShowBalloonTip(5000, $Titulo, $Mensaje, [System.Windows.Forms.ToolTipIcon]::Info)
    Start-Sleep -Seconds 5
    $n.Dispose()
} catch {}
