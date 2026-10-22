# -*- coding: utf-8 -*-
"""Таблица рефов: УГО = проверенные кропы ГОСТ / electricalschool."""
from __future__ import annotations

import base64
import html
import json
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
CROPS = ROOT / "ugo_crops"


def b64(path: Path) -> str:
    mime = "image/png" if path.suffix.lower() == ".png" else "image/jpeg"
    return f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode()


def find(name: str) -> Path | None:
    for base in (CROPS, ROOT, ROOT / "gost"):
        p = base / name
        if p.exists() and p.stat().st_size > 300:
            return p
    return None


def photo_cell(photo: str | None, note: str) -> tuple[str, bool]:
    if photo:
        p = ROOT / photo
        if p.exists() and p.stat().st_size > 5000:
            try:
                im = Image.open(p).convert("RGB")
                im.thumbnail((280, 280))
                canvas = Image.new("RGB", (280, 280), (255, 255, 255))
                canvas.paste(im, ((280 - im.width) // 2, (280 - im.height) // 2))
                bio = BytesIO()
                canvas.save(bio, format="JPEG", quality=88)
                return "data:image/jpeg;base64," + base64.b64encode(bio.getvalue()).decode(), False
            except Exception:
                pass
    im = Image.new("RGB", (280, 280), (248, 248, 248))
    d = ImageDraw.Draw(im)
    d.rectangle([6, 6, 273, 273], outline=(190, 190, 190), width=2)
    d.multiline_text((24, 110), "3D фото TBD\n" + note, fill=(110, 110, 110), spacing=4)
    bio = BytesIO()
    im.save(bio, format="JPEG", quality=85)
    return "data:image/jpeg;base64," + base64.b64encode(bio.getvalue()).decode(), True


rows = [
    {
        "id": "1",
        "title": "Контакт НО (замыкающий)",
        "ugo": ["gost_contact_no.png", "gost_contact_base_block.png", "es_strip_contacts_base.png"],
        "ugo_src": "ГОСТ 2.755-87 п.1.3.1; electricalschool рис.1",
        "photo": None,
        "photo_note": "— только 2D",
    },
    {
        "id": "2",
        "title": "Контакт НЗ (размыкающий)",
        "ugo": ["gost_contact_nc.png", "gost_contact_base_block.png"],
        "ugo_src": "ГОСТ 2.755-87 п.1.3.2 (два допустимых варианта)",
        "photo": None,
        "photo_note": "— только 2D",
    },
    {
        "id": "3",
        "title": "Переключающий контакт",
        "ugo": ["gost_contact_change.png", "gost_contact_neutral.png"],
        "ugo_src": "ГОСТ 2.755-87 п.1.3.3–1.3.4",
        "photo": None,
        "photo_note": "— только 2D",
    },
    {
        "id": "4",
        "title": "Кнопка нажимная",
        "ugo": ["gost_button_push.png", "es_strip_actuators.png", "gost_table3_devices.png"],
        "ugo_src": "ГОСТ 2.755 табл.3 п.3; ES рис.2 (актуаторы д/е)",
        "photo": "3d_btn_xb4.jpg",
        "photo_note": "Schneider XB4BA*",
    },
    {
        "id": "5",
        "title": "Аварийный гриб",
        "ugo": ["es_strip_actuators.png", "gost_button_push.png"],
        "ugo_src": "ES рис.2е (гриб) + кнопочная база ГОСТ табл.3",
        "photo": "3d_estop.jpg",
        "photo_note": "Schneider XB4BS* (проверить кадр)",
    },
    {
        "id": "6",
        "title": "Переключатель 2 поз.",
        "ugo": ["gost_contact_change.png", "es_switch.jpg"],
        "ugo_src": "ГОСТ 2.755 п.1.3.3 + ES переключатель",
        "photo": "3d_switch.jpg",
        "photo_note": "Schneider XB4BD",
    },
    {
        "id": "7",
        "title": "Лампа сигнальная",
        "ugo": ["gost_lamp_general.png", "gost_lamp_table2.png"],
        "ugo_src": "ГОСТ 2.732-68 табл.2 п.1 (круг+крест; цвета С2/С4/С5/С9)",
        "photo": None,
        "photo_note": "Schneider XB4BV — TBD",
    },
    {
        "id": "8",
        "title": "Катушка реле / ЭМ / контактора",
        "ugo": ["gost_coil_general.png", "gost_coil_table.png"],
        "ugo_src": "ГОСТ 2.756-76 табл.1 п.1",
        "photo": None,
        "photo_note": "Finder 55.34 — TBD",
    },
    {
        "id": "9",
        "title": "Реле времени",
        "ugo": ["gost_coil_delay_page.png", "es_strip_actuators.png"],
        "ugo_src": "ГОСТ 2.756 п.16–18 + дуги на контакте 2.755 п.15–16 / ES л–р",
        "photo": None,
        "photo_note": "Schneider RE22 — TBD",
    },
    {
        "id": "10",
        "title": "Автомат",
        "ugo": ["gost_breaker_3p.png", "gost_switch_1p.png", "es_strip_breakers.png"],
        "ugo_src": "ГОСТ 2.755 табл.3 п.1–2 (X, I>); ES рис.3",
        "photo": "3d_mcb_abb_s201.jpg",
        "photo_note": "ABB S201-C16",
    },
    {
        "id": "11",
        "title": "УЗО / дифавтомат",
        "ugo": ["gost_breaker_3p.png", "gost_qualifiers_table1.png"],
        "ugo_src": "База = выключатель ГОСТ 2.755; отдельного знака IΔn в 2.755 нет — форма на утверждении",
        "photo": None,
        "photo_note": "ABB F202/DS201 — TBD",
    },
    {
        "id": "12",
        "title": "Контактор (группа)",
        "ugo": ["es_strip_devices.png", "gost_coil_general.png"],
        "ugo_src": "ES рис.4б (3 НО + катушка + штриховая связь); катушка 2.756",
        "photo": None,
        "photo_note": "Schneider LC1D — TBD",
    },
    {
        "id": "13",
        "title": "Тепловое реле",
        "ugo": ["gost_thermal.png", "es_strip_actuators.png"],
        "ugo_src": "ГОСТ 2.756 п.21 + контакт t° (ES и/к)",
        "photo": None,
        "photo_note": "Schneider LRD — TBD",
    },
    {
        "id": "14",
        "title": "Клемма / контактные соединения",
        "ugo": ["gost_conn_p08.png", "gost_conn_p09.png"],
        "ugo_src": "ГОСТ 2.755 табл.5–6",
        "photo": None,
        "photo_note": "Phoenix UT — TBD",
    },
    {
        "id": "15",
        "title": "Квалификаторы (шпаргалка)",
        "ugo": ["gost_qualifiers_table1.png", "es_strip_actuators.png"],
        "ugo_src": "ГОСТ 2.755 табл.1 + ES рис.2",
        "photo": None,
        "photo_note": "— справочно",
    },
]

parts = []
meta = []
for row in rows:
    ugo_html = []
    for fname in row["ugo"]:
        p = find(fname)
        if p is None:
            continue
        ugo_html.append(
            f'<div class="ugo-item"><img src="{b64(p)}" alt="{html.escape(fname)}">'
            f'<div class="fn">{html.escape(p.name)}</div></div>'
        )
    if not ugo_html:
        ugo_html = ['<div class="miss">кроп не найден</div>']
    photo_b64, missing = photo_cell(row.get("photo"), row.get("photo_note", ""))
    miss = '<div class="miss">нет валидного 3D фото</div>' if missing else ""
    parts.append(
        f"""
<tr>
  <td class="num">{row['id']}</td>
  <td class="name"><strong>{html.escape(row['title'])}</strong>
    <div class="note">{html.escape(row['ugo_src'])}</div></td>
  <td class="ugo"><div class="ugo-row">{''.join(ugo_html)}</div></td>
  <td class="img"><img src="{photo_b64}" alt="3D"><div class="cap">{html.escape(row['photo_note'])}{miss}</div></td>
</tr>"""
    )
    meta.append(row)

html_doc = f"""<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8"/>
<title>Electro refs — ГОСТ кропы</title>
<style>
body {{ font-family: Segoe UI, Arial, sans-serif; margin: 20px; background:#f4f4f4; color:#111; }}
h1 {{ font-size: 22px; margin: 0 0 8px; }}
.legend {{ background:#fff; border:1px solid #ddd; padding:12px 14px; margin: 0 0 16px; max-width: 1100px; }}
.legend p {{ margin: 6px 0; color:#444; }}
table {{ border-collapse: collapse; width: 100%; background:#fff; }}
th, td {{ border: 1px solid #ddd; padding: 10px; vertical-align: top; }}
th {{ background:#eee; text-align:left; }}
td.num {{ width:36px; color:#666; }}
td.name {{ width:240px; }}
.ugo-row {{ display:flex; flex-wrap:wrap; gap:10px; align-items:flex-start; }}
.ugo-item img {{ max-width: 420px; max-height: 260px; border:1px solid #e5e5e5; background:#fff; }}
.fn {{ font-size:11px; color:#777; margin-top:3px; word-break:break-all; }}
td.img {{ width:300px; text-align:center; }}
td.img > img {{ width:280px; height:280px; object-fit:contain; border:1px solid #eee; background:#fff; }}
.cap,.note {{ font-size:12px; color:#555; margin-top:6px; }}
.miss {{ color:#a33; font-size:12px; margin-top:4px; }}
code {{ background:#f0f0f0; padding:1px 4px; }}
</style>
</head>
<body>
<h1>Референсы УГО = кропы ГОСТ / electricalschool</h1>
<div class="legend">
  <p>Колонка УГО — <strong>только вырезки</strong> из PDF ГОСТ 2.755 / 2.756 / 2.732 и рисунки electricalschool. Скетчей нет.</p>
  <p>Кропы: <code>out/electro_refs/ugo_crops/</code> · PDF: <code>out/electro_refs/gost/</code></p>
  <p>Утвердите строки (или правки) — затем перестрою <code>electro_symbols.gd</code> по этим кропам.</p>
</div>
<table>
<thead><tr><th>#</th><th>Элемент</th><th>УГО (реф-кроп)</th><th>3D фото</th></tr></thead>
<tbody>
{''.join(parts)}
</tbody>
</table>
</body>
</html>
"""

(ROOT / "refs_table.html").write_text(html_doc, encoding="utf-8")
(ROOT / "refs_meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
print("Wrote", ROOT / "refs_table.html", (ROOT / "refs_table.html").stat().st_size)
