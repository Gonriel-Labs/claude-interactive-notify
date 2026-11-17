"""Arma un SVG animado a partir de una grabacion de notify.ps1 -CapturaSVG.

Uso: python armar_svg.py <grabacion.json> <salida.svg>

Cada cuadro es un grupo de figuras; una animacion CSS en pasos muestra un solo grupo a la vez,
igual que un GIF pero vectorial: se ve nitido a cualquier tamano y con fondo transparente.
La imagen simula la esquina inferior derecha de la pantalla: la mascota entra por el borde derecho.
"""
import json
import sys
from html import escape
from pathlib import Path

entrada, salida = Path(sys.argv[1]), Path(sys.argv[2])
datos = json.loads(entrada.read_text(encoding="utf-8-sig"))
cuadros = datos["cuadros"]
ancho = datos["ancho"]

PAUSA_INICIO, PAUSA_FIN = 400, 900   # ms de pantalla vacia antes de entrar y despues de irse


def n(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def figura(f):
    o = f"" if f["o"] >= 0.999 else f' opacity="{n(f["o"])}"'
    if f["t"] == "r":
        return f'<rect x="{n(f["x"])}" y="{n(f["y"])}" width="{n(f["w"])}" height="{n(f["h"])}" fill="{f["c"]}"{o}/>'
    if f["t"] == "b":
        m = f["sw"] / 2   # el trazo SVG va centrado en el borde; el de WPF va por dentro
        return (f'<rect x="{n(f["x"] + m)}" y="{n(f["y"] + m)}" width="{n(f["w"] - f["sw"])}" '
                f'height="{n(f["h"] - f["sw"])}" class="g" rx="{n(f["rx"] - m)}" fill="{f["f"]}" stroke="{f["s"]}" '
                f'stroke-width="{n(f["sw"])}"{o}/>')
    familia = "Consolas,Menlo,monospace" if "Consolas" in f["ff"] else "'Segoe UI',system-ui,-apple-system,sans-serif"
    return (f'<text x="{n(f["x"])}" y="{n(f["y"])}" fill="{f["c"]}" font-size="{n(f["fs"])}" '
            f'font-weight="{f["fw"]}" font-family="{familia}"{o}>{escape(f["s"])}</text>')


# Alto real ocupado por las figuras (la ventana es mas alta que el contenido)
alto = max(f["y"] + f.get("h", 0) for c in cuadros for f in c["f"]) + 6
# Mismo alto en todos los avisos, para que se vean parejos uno al lado del otro
arriba = alto - 142
W = ancho + 12 + 8
H = alto - arriba

# Figuras que no cambian en ningun cuadro: se dibujan una vez y se reutilizan
grupos = [[figura(f) for f in c["f"]] for c in cuadros]
fijas = set(grupos[0])
for g in grupos[1:]:
    fijas &= set(g)
fijas_orden = [s for s in grupos[0] if s in fijas]

# Tiempos: cada cuadro dura hasta el siguiente
t0 = cuadros[0]["t"]
inicios = [PAUSA_INICIO + c["t"] - t0 for c in cuadros]
fin_ultimo = inicios[-1] + 60
total = fin_ultimo + PAUSA_FIN


def pct(ms):
    return f"{ms / total * 100:.3f}".rstrip("0").rstrip(".") + "%"


css = [f".c{{opacity:0;animation:{total / 1000:.2f}s steps(1,end) infinite}}",
       "@media (prefers-reduced-motion:reduce){.c{animation:none}}",
       "rect{shape-rendering:crispEdges}.g{shape-rendering:geometricPrecision}"]
cuerpo = []
anterior = None
for i, (c, g) in enumerate(zip(cuadros, grupos)):
    desde = inicios[i]
    hasta = inicios[i + 1] if i + 1 < len(cuadros) else fin_ultimo
    clave = (c["x"], tuple(g))
    if clave == anterior:
        # Cuadro identico al anterior: alarga el anterior en vez de repetirlo
        ultimo_hasta[0] = hasta
        continue
    anterior = clave
    ultimo_hasta = [hasta]
    cuerpo.append((i, desde, ultimo_hasta, c["x"], [s for s in g if s not in fijas]))

# Con reduced-motion se queda quieta en su sitio, con el texto ya escrito
en_sitio = [k for k, c in enumerate(cuerpo) if abs(c[3] + ancho + 12) < 0.5]
quieto = max([k for k in en_sitio if cuerpo[k][1] <= inicios[0] + 4000] or en_sitio or [0])

partes = []
for k, (i, desde, hasta, x, variables) in enumerate(cuerpo):
    nombre = f"k{k}"
    claves = []
    if desde > 0:
        claves.append(f"0%{{opacity:0}}")
    claves.append(f"{pct(desde)}{{opacity:1}}")
    claves.append(f"{pct(hasta[0])}{{opacity:0}}")
    css.append(f"@keyframes {nombre}{{{''.join(claves)}}}")
    css.append(f".f{k}{{animation-name:{nombre}}}")
    dx = W + x
    partes.append(f'<g class="c f{k}" transform="translate({n(dx)} {n(-arriba)})">'
                  f'<use href="#fijo"/>{"".join(variables)}</g>')

css.append(f"@media (prefers-reduced-motion:reduce){{.f{quieto}{{opacity:1}}}}")

svg = (f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
       f'width="{n(W)}" height="{n(H)}" viewBox="0 0 {n(W)} {n(H)}" role="img">'
       f'<style>{"".join(css)}</style>'
       f'<defs><g id="fijo">{"".join(fijas_orden)}</g></defs>'
       f'<g xml:space="preserve">{"".join(partes)}</g></svg>')
salida.write_text(svg, encoding="utf-8")
print(f"{salida.name}: {len(cuerpo)} cuadros, {total / 1000:.1f} s, {salida.stat().st_size / 1024:.0f} KB, {n(W)}x{n(H)}")
