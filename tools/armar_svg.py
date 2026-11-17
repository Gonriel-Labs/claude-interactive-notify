"""Arma un SVG animado a partir de grabaciones de notify.ps1 -CapturaSVG.

Uso: python armar_svg.py <salida.svg> <ronda> [<ronda> ...]

Cada ronda es una grabacion (a.json) o dos apiladas (a.json+b.json): la segunda llega un poco
despues y se pone encima, como cuando terminan dos sesiones a la vez. Las rondas se reproducen
una tras otra y el conjunto se repite sin fin.

Cada cuadro es un grupo de figuras; una animacion CSS en pasos muestra un solo grupo a la vez,
igual que un GIF pero vectorial: se ve nitido a cualquier tamano y con fondo transparente.
La imagen simula la esquina inferior derecha de la pantalla: la mascota entra por el borde derecho.
"""
import json
import sys
from html import escape
from pathlib import Path

PAUSA_INICIO, PAUSA_FIN = 400, 900   # ms de pantalla vacia antes de entrar y despues de irse
RETRASO_APILADA = 1200               # ms que tarda en llegar la segunda mascota de una ronda
ALTO_PUESTO = 132                    # separacion vertical entre mascotas apiladas (como en notify.ps1)
ALTO_AVISO = 142


def n(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def figura(f):
    o = "" if f["o"] >= 0.999 else f' opacity="{n(f["o"])}"'
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


salida = Path(sys.argv[1])
rondas = [[Path(p) for p in r.split("+")] for r in sys.argv[2:]]
apiladas = max(len(r) for r in rondas)

# Pistas: cada grabacion con su momento de inicio y su puesto en la pila
pistas = []
inicio_ronda = 0
for ronda in rondas:
    fin_ronda = 0
    for puesto, archivo in enumerate(ronda):
        datos = json.loads(archivo.read_text(encoding="utf-8-sig"))
        cuadros = datos["cuadros"]
        # Si la grabacion se trabo, la mascota da un tiron: mejor volver a grabarla
        hueco = max(b["t"] - a["t"] for a, b in zip(cuadros, cuadros[1:]))
        if hueco > 250:
            print(f"AVISO: {archivo.name} tiene un hueco de {hueco} ms; vuelve a grabarla")
        retraso = PAUSA_INICIO + puesto * RETRASO_APILADA
        t0 = cuadros[0]["t"]
        inicios = [inicio_ronda + retraso + c["t"] - t0 for c in cuadros]
        fin = inicios[-1] + 60
        fin_ronda = max(fin_ronda, fin - inicio_ronda)
        pistas.append(dict(cuadros=cuadros, ancho=datos["ancho"], puesto=puesto, inicios=inicios, fin=fin,
                           primera=inicio_ronda == 0))
    inicio_ronda += fin_ronda + PAUSA_FIN
total = inicio_ronda

ancho = pistas[0]["ancho"]
W = ancho + 12 + 8
H = ALTO_AVISO + ALTO_PUESTO * (apiladas - 1)


def pct(ms):
    return f"{ms / total * 100:.3f}".rstrip("0").rstrip(".") + "%"


css = [f".c{{opacity:0;animation:{total / 1000:.2f}s steps(1,end) infinite}}",
       "@media (prefers-reduced-motion:reduce){.c{animation:none}}",
       "rect{shape-rendering:crispEdges}.g{shape-rendering:geometricPrecision}"]
defs, partes, quietos = [], [], []
k = 0
for j, p in enumerate(pistas):
    cuadros, inicios = p["cuadros"], p["inicios"]
    # Base de la mascota alineada abajo; la pila crece hacia arriba
    alto = max(f["y"] + f.get("h", 0) for c in cuadros for f in c["f"]) + 6
    dy = H - alto - p["puesto"] * ALTO_PUESTO

    # Figuras que no cambian en ningun cuadro de la pista: se dibujan una vez y se reutilizan
    grupos = [[figura(f) for f in c["f"]] for c in cuadros]
    fijas = set(grupos[0])
    for g in grupos[1:]:
        fijas &= set(g)
    defs.append(f'<g id="p{j}">{"".join(s for s in grupos[0] if s in fijas)}</g>')

    cuerpo, anterior = [], None
    for i, (c, g) in enumerate(zip(cuadros, grupos)):
        hasta = inicios[i + 1] if i + 1 < len(cuadros) else p["fin"]
        clave = (c["x"], tuple(g))
        if clave == anterior:
            cuerpo[-1][1] = hasta   # cuadro identico al anterior: alarga el anterior
            continue
        anterior = clave
        cuerpo.append([inicios[i], hasta, c["x"], [s for s in g if s not in fijas]])

    # Con reduced-motion se queda quieta en su sitio, con el texto ya escrito (solo la primera ronda)
    if p["primera"]:
        en_sitio = [i for i, c in enumerate(cuerpo) if abs(c[2] + ancho + 12) < 0.5]
        quietos.append(k + max([i for i in en_sitio if cuerpo[i][0] <= inicios[0] + 4000] or en_sitio or [0]))

    for desde, hasta, x, variables in cuerpo:
        claves = ("0%{opacity:0}" if desde > 0 else "") + f"{pct(desde)}{{opacity:1}}{pct(hasta)}{{opacity:0}}"
        css.append(f"@keyframes k{k}{{{claves}}}.f{k}{{animation-name:k{k}}}")
        partes.append(f'<g class="c f{k}" transform="translate({n(W + x)} {n(dy)})">'
                      f'<use href="#p{j}"/>{"".join(variables)}</g>')
        k += 1

css.append("@media (prefers-reduced-motion:reduce){" + ",".join(f".f{q}" for q in quietos) + "{opacity:1}}")

svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{n(W)}" height="{n(H)}" viewBox="0 0 {n(W)} {n(H)}" role="img">'
       f'<style>{"".join(css)}</style>'
       f'<defs>{"".join(defs)}</defs>'
       f'<g xml:space="preserve">{"".join(partes)}</g></svg>')
salida.write_text(svg, encoding="utf-8")
print(f"{salida.name}: {len(rondas)} ronda(s), {k} cuadros, {total / 1000:.1f} s, "
      f"{salida.stat().st_size / 1024:.0f} KB, {n(W)}x{n(H)}")
