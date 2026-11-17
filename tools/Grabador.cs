// Solo para documentacion: describe un cuadro del aviso como una lista de figuras (rectangulos,
// bordes y textos con su posicion, color y opacidad) para armar despues un SVG animado.
// Lo carga notify.ps1 con -CapturaSVG.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Shapes;

public static class Grabador {
    static string N(double v) { return Math.Round(v, 2).ToString(CultureInfo.InvariantCulture); }
    static string Color(Brush b, out double alfa) {
        alfa = 0;
        var s = b as SolidColorBrush;
        if (s == null) return null;
        alfa = s.Color.A / 255.0 * s.Opacity;
        return string.Format("#{0:x2}{1:x2}{2:x2}", s.Color.R, s.Color.G, s.Color.B);
    }
    static string Txt(string s) {
        var sb = new StringBuilder();
        foreach (char c in s) {
            if (c == '"' || c == '\\') sb.Append('\\').Append(c);
            else if (c < 32) sb.Append(' ');
            else sb.Append(c);
        }
        return sb.ToString();
    }

    public static string Cuadro(FrameworkElement raiz) {
        var sb = new StringBuilder("[");
        Recorrer(raiz, raiz, 1.0, sb);
        if (sb.Length > 1) sb.Length--;
        return sb.Append("]").ToString();
    }

    static void Recorrer(FrameworkElement raiz, DependencyObject d, double op, StringBuilder sb) {
        var e = d as FrameworkElement;
        if (e != null) {
            if (e.Visibility != Visibility.Visible) return;
            op *= e.Opacity;
            if (op < 0.01) return;
            Rect r;
            try { r = e.TransformToAncestor(raiz).TransformBounds(new Rect(0, 0, e.ActualWidth, e.ActualHeight)); }
            catch { return; }
            double a;
            var rect = e as Rectangle;
            if (rect != null) {
                string c = Color(rect.Fill, out a);
                if (c != null && a * op > 0.01)
                    sb.AppendFormat("{{\"t\":\"r\",\"x\":{0},\"y\":{1},\"w\":{2},\"h\":{3},\"c\":\"{4}\",\"o\":{5}}},",
                        N(r.X), N(r.Y), N(r.Width), N(r.Height), c, N(a * op));
            }
            var borde = e as Border;
            if (borde != null) {
                double ab; string cb = Color(borde.BorderBrush, out ab);
                string cf = Color(borde.Background, out a);
                sb.AppendFormat("{{\"t\":\"b\",\"x\":{0},\"y\":{1},\"w\":{2},\"h\":{3},\"f\":\"{4}\",\"s\":\"{5}\",\"sw\":{6},\"rx\":{7},\"o\":{8}}},",
                    N(r.X), N(r.Y), N(r.Width), N(r.Height), cf ?? "none", cb ?? "none",
                    N(borde.BorderThickness.Left), N(borde.CornerRadius.TopLeft), N(op));
            }
            var tb = e as TextBlock;
            if (tb != null) { Texto(raiz, tb, op, sb); return; }
        }
        int n = VisualTreeHelper.GetChildrenCount(d);
        for (int i = 0; i < n; i++) Recorrer(raiz, VisualTreeHelper.GetChild(d, i), op, sb);
    }

    // Agrupa las letras por linea y color: cada grupo sale como un <text> en su posicion real
    static void Texto(FrameworkElement raiz, TextBlock tb, double op, StringBuilder sb) {
        var aRaiz = tb.TransformToAncestor(raiz);
        double baseRel = tb.FontFamily.Baseline;
        var p = tb.ContentStart;
        StringBuilder grupo = null; double gx = 0, gy = 0; string gc = null; double ga = 0;
        Action cerrar = () => {
            if (grupo != null && grupo.Length > 0 && grupo.ToString().Trim().Length > 0)
                sb.AppendFormat("{{\"t\":\"x\",\"x\":{0},\"y\":{1},\"c\":\"{2}\",\"o\":{3},\"fs\":{4},\"fw\":{5},\"ff\":\"{6}\",\"s\":\"{7}\"}},",
                    N(gx), N(gy), gc, N(ga * op), N(tb.FontSize), tb.FontWeight.ToOpenTypeWeight(),
                    Txt(tb.FontFamily.Source), Txt(grupo.ToString()));
            grupo = null;
        };
        while (p != null && p.CompareTo(tb.ContentEnd) < 0) {
            if (p.GetPointerContext(LogicalDirection.Forward) == TextPointerContext.Text) {
                string corrida = p.GetTextInRun(LogicalDirection.Forward);
                var run = p.Parent as TextElement;
                Brush pincel = run != null ? run.Foreground : tb.Foreground;
                double a; string c = Color(pincel, out a);
                for (int i = 0; i < corrida.Length; i++) {
                    var q = p.GetPositionAtOffset(i);
                    Rect cr = q.GetCharacterRect(LogicalDirection.Forward);
                    Point pt = aRaiz.Transform(new Point(cr.X, cr.Y));
                    double y = pt.Y + baseRel * tb.FontSize;
                    bool visible = c != null && a > 0.01;
                    if (grupo == null || !visible || Math.Abs(y - gy) > 0.5 || c != gc || a != ga) {
                        cerrar();
                        if (!visible) continue;
                        grupo = new StringBuilder(); gx = pt.X; gy = y; gc = c; ga = a;
                    }
                    grupo.Append(corrida[i]);
                }
                cerrar();
                p = p.GetPositionAtOffset(corrida.Length);
            } else {
                p = p.GetNextContextPosition(LogicalDirection.Forward);
            }
        }
        cerrar();
    }
}
