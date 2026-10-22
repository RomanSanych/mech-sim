from pathlib import Path
from PIL import Image, ImageDraw
import base64
import html
from io import BytesIO

OUT = Path(__file__).resolve().parent
OUT.mkdir(parents=True, exist_ok=True)


def load_photo(name, size=(280, 280)):
    p = OUT / name
    if not p.exists():
        return None
    try:
        im = Image.open(p).convert("RGB")
        im.thumbnail(size, Image.Resampling.LANCZOS)
        canvas = Image.new("RGB", size, (255, 255, 255))
        x = (size[0] - im.width) // 2
        y = (size[1] - im.height) // 2
        canvas.paste(im, (x, y))
        return canvas
    except Exception:
        return None


def save_ugo(name, draw_fn, size=(280, 160)):
    im = Image.new("RGB", size, (255, 255, 255))
    d = ImageDraw.Draw(im)
    d.rectangle([1, 1, size[0] - 2, size[1] - 2], outline=(200, 200, 200))
    draw_fn(d, size)
    path = OUT / f"ugo_{name}.png"
    im.save(path)
    return path


def line(d, pts, w=3, fill=(20, 20, 20)):
    d.line(pts, fill=fill, width=w)


def ugo_contact_no(d, s):
    cy = s[1] // 2
    line(d, [(30, cy), (95, cy)])
    line(d, [(185, cy), (250, cy)])
    line(d, [(95, cy), (175, cy - 28)])
    line(d, [(95, cy - 8), (95, cy + 8)])
    line(d, [(185, cy - 8), (185, cy + 8)])


def ugo_contact_nc(d, s):
    cy = s[1] // 2
    line(d, [(30, cy), (95, cy)])
    line(d, [(185, cy), (250, cy)])
    line(d, [(95, cy + 22), (185, cy)])
    line(d, [(95, cy - 8), (95, cy + 8)])
    line(d, [(185, cy - 8), (185, cy + 8)])


def ugo_button_nc(d, s):
    ugo_contact_nc(d, s)
    cy = s[1] // 2
    line(d, [(125, cy - 50), (155, cy - 50)], w=4)
    line(d, [(140, cy - 50), (140, cy - 18)])
    line(d, [(140, cy - 18), (140, cy + 5)], w=2)


def ugo_button_no(d, s):
    ugo_contact_no(d, s)
    cy = s[1] // 2
    line(d, [(125, cy - 50), (155, cy - 50)], w=4)
    line(d, [(140, cy - 50), (140, cy - 22)])


def ugo_estop(d, s):
    ugo_button_nc(d, s)
    d.ellipse([122, 18, 158, 54], outline=(180, 30, 30), width=3)


def ugo_switch(d, s):
    ugo_contact_no(d, s)
    cy = s[1] // 2
    d.arc([128, cy - 48, 152, cy - 24], 200, 340, fill=(20, 20, 20), width=3)
    line(d, [(140, cy - 36), (140, cy - 18)])


def ugo_lamp(d, s):
    w, h = s
    cx, cy = w // 2, h // 2
    line(d, [(30, cy), (cx - 36, cy)])
    line(d, [(cx + 36, cy), (250, cy)])
    d.ellipse([cx - 36, cy - 36, cx + 36, cy + 36], outline=(20, 20, 20), width=3)
    line(d, [(cx - 22, cy - 22), (cx + 22, cy + 22)], w=2)
    line(d, [(cx + 22, cy - 22), (cx - 22, cy + 22)], w=2)


def ugo_coil(d, s):
    w, h = s
    cx, cy = w // 2, h // 2
    line(d, [(30, cy), (cx - 50, cy)])
    line(d, [(cx + 50, cy), (250, cy)])
    d.rectangle([cx - 50, cy - 22, cx + 50, cy + 22], outline=(20, 20, 20), width=3)


def ugo_timer(d, s):
    ugo_coil(d, s)
    w, h = s
    cx, cy = w // 2, h // 2
    d.arc([cx - 18, cy - 14, cx + 18, cy + 14], 200, 340, fill=(20, 20, 20), width=2)


def ugo_mcb(d, s):
    ugo_contact_no(d, s)
    cy = s[1] // 2
    line(d, [(120, cy - 18), (132, cy - 6)], w=2)
    line(d, [(132, cy - 18), (120, cy - 6)], w=2)
    d.arc([148, cy - 20, 172, cy + 4], 200, 20, fill=(20, 20, 20), width=2)


def ugo_rcd(d, s):
    ugo_mcb(d, s)
    cy = s[1] // 2
    d.ellipse([200, cy - 28, 228, cy], outline=(20, 20, 20), width=2)


def ugo_terminal(d, s):
    cy = s[1] // 2
    line(d, [(40, cy), (120, cy)])
    line(d, [(160, cy), (240, cy)])
    d.ellipse([120, cy - 14, 148, cy + 14], outline=(20, 20, 20), width=3)
    line(d, [(132, cy - 22), (132, cy + 22)], w=2)


def ugo_bus(d, s):
    line(d, [(40, 40), (40, 120)], w=6)
    for y in (50, 70, 90, 110):
        line(d, [(40, y), (120, y)], w=2)


def ugo_supply(d, s):
    for i, lab in enumerate(["L", "N", "PE"]):
        y = 40 + i * 35
        line(d, [(40, y), (200, y)])
        d.ellipse([200, y - 10, 220, y + 10], outline=(20, 20, 20), width=2)
        d.text((230, y - 8), lab, fill=(20, 20, 20))


ugomap = {
    "contact_no": ugo_contact_no,
    "contact_nc": ugo_contact_nc,
    "button_no": ugo_button_no,
    "button_nc": ugo_button_nc,
    "estop": ugo_estop,
    "switch": ugo_switch,
    "lamp": ugo_lamp,
    "coil": ugo_coil,
    "timer": ugo_timer,
    "mcb": ugo_mcb,
    "rcd": ugo_rcd,
    "terminal": ugo_terminal,
    "bus": ugo_bus,
    "supply": ugo_supply,
}
for k, fn in ugomap.items():
    save_ugo(k, fn)

rows = [
    ("1", "Контакт НО", "contact_no", None, "ГОСТ 2.755 п.1.3 замыкающий", "— (только 2D)"),
    ("2", "Контакт НЗ", "contact_nc", None, "ГОСТ 2.755 п.1.3 размыкающий / SB2", "— (только 2D)"),
    ("3", "Кнопка НО/НЗ", "button_nc", "3d_btn_xb4.jpg", "ГОСТ 2.755 + кнопка; эталон SB2", "Schneider XB4BA*"),
    ("4", "Аварийный гриб", "estop", "3d_estop.jpg", "ГОСТ 2.755 НЗ + гриб", "Schneider XB4BS8442"),
    ("5", "Переключатель 2 поз.", "switch", "3d_switch.jpg", "ГОСТ 2.755 переключающий", "Schneider XB4BD"),
    ("6", "Лампа сигнальная", "lamp", None, "ГОСТ 2.732 круг+крест", "Schneider XB4BV — фото TBD"),
    ("7", "Катушка реле / ЭМ", "coil", None, "ГОСТ 2.756 прямоугольник A1/A2", "Finder 55.34 — фото TBD"),
    ("8", "Реле времени", "timer", None, "ГОСТ 2.756 + дуга задержки", "Schneider RE22 — фото TBD"),
    ("9", "Автомат", "mcb", "3d_mcb_abb_s201.jpg", "ГОСТ 2.755 + тепло/магнит", "ABB S201-C16"),
    ("10", "УЗО", "rcd", "3d_rcd.jpg", "ГОСТ 2.755 + IΔn", "ABB F202 / DIN-модуль"),
    ("11", "Дифавтомат", "rcd", "3d_rcbo.jpg", "автомат+УЗО", "ABB DS201 / аналог"),
    ("12", "Контактор 3P", "coil", "3d_contactor.jpg", "катушка 2.756 + силовые НО", "Schneider LC1D"),
    ("13", "Тепловое реле", "coil", None, "ГОСТ 2.756 + контакты 95-96", "Schneider LRD — фото TBD"),
    ("14", "Клемма L/N/PE", "terminal", None, "ГОСТ 2.755 разборное XT", "Phoenix UT — фото TBD"),
    ("15", "Шина N/PE", "bus", None, "шина с отводами", "шина щита — фото TBD"),
    ("16", "Ввод L/N/PE", "supply", None, "клеммная группа ввода", "ввод щита — фото TBD"),
]


def b64_img(path_or_im):
    if isinstance(path_or_im, Image.Image):
        bio = BytesIO()
        path_or_im.save(bio, format="JPEG", quality=85)
        return "data:image/jpeg;base64," + base64.b64encode(bio.getvalue()).decode()
    p = Path(path_or_im)
    mime = "image/png" if p.suffix.lower() == ".png" else "image/jpeg"
    return f"data:{mime};base64," + base64.b64encode(p.read_bytes()).decode()


def placeholder(text):
    im = Image.new("RGB", (280, 280), (245, 245, 245))
    d = ImageDraw.Draw(im)
    d.rectangle([8, 8, 271, 271], outline=(180, 180, 180), width=2)
    d.multiline_text((24, 110), "фото TBD\n" + text, fill=(120, 120, 120), spacing=4)
    return im


parts = []
for num, title, ugo_key, photo, ugo_note, photo_note in rows:
    ugo_b64 = b64_img(OUT / f"ugo_{ugo_key}.png")
    ph = load_photo(photo) if photo else None
    missing = ph is None
    if missing:
        ph = placeholder(photo_note)
    photo_b64 = b64_img(ph)
    miss_badge = (
        '<span class="miss">нет фото — утвердите модель текстом или пришлите снимок</span>'
        if missing
        else ""
    )
    parts.append(
        f"""
    <tr>
      <td class="num">{num}</td>
      <td class="name"><strong>{html.escape(title)}</strong><div class="note">{html.escape(ugo_note)}</div></td>
      <td class="img"><img src="{ugo_b64}" alt="UGO {html.escape(title)}"><div class="cap">УГО-реф</div></td>
      <td class="img"><img src="{photo_b64}" alt="3D {html.escape(title)}"><div class="cap">{html.escape(photo_note)}{miss_badge}</div></td>
    </tr>"""
    )

html_doc = f"""<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8"/>
<title>Electro refs — УГО + 3D</title>
<style>
body {{ font-family: Segoe UI, Arial, sans-serif; margin: 24px; background:#f7f7f7; color:#111; }}
h1 {{ font-size: 22px; margin: 0 0 8px; }}
p {{ color:#444; max-width: 960px; }}
table {{ border-collapse: collapse; width: 100%; background:#fff; }}
th, td {{ border: 1px solid #ddd; padding: 12px; vertical-align: top; }}
th {{ background:#eee; text-align:left; }}
td.num {{ width: 40px; color:#666; }}
td.name {{ width: 260px; }}
td.img {{ width: 300px; text-align:center; }}
td.img img {{ width: 280px; height: auto; background:#fff; border:1px solid #eee; }}
.cap {{ font-size: 12px; color:#555; margin-top: 6px; }}
.note {{ font-size: 12px; color:#666; margin-top: 6px; }}
.miss {{ color:#a33; display:block; margin-top:4px; }}
.legend {{ margin: 12px 0 20px; padding: 12px; background:#fff; border:1px solid #ddd; }}
</style>
</head>
<body>
<h1>Таблица референсов: УГО + 3D фото</h1>
<div class="legend">
  <p>УГО нарисованы по ГОСТ 2.755 / 2.756 / 2.732 (горизонтальная цепь). 3D — фото изделий, которые берутся за модель.</p>
  <p>Строки с «фото TBD» — утвердите модель текстом или пришлите своё фото.</p>
  <p>После «ОК» / правок по строкам перестрою УГО и 3D в симе.</p>
</div>
<table>
<thead><tr><th>#</th><th>Элемент</th><th>УГО (реф)</th><th>3D фото (реф)</th></tr></thead>
<tbody>
{"".join(parts)}
</tbody>
</table>
</body>
</html>
"""
html_path = OUT / "refs_table.html"
html_path.write_text(html_doc, encoding="utf-8")
print("Wrote", html_path, html_path.stat().st_size)
