#!/usr/bin/env python3
"""Generate test/electro_cabinet_all.mechsim.json — all electro types on one cabinet."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RECIPES = ROOT / "data" / "electric" / "recipes.json"
OUT = Path(__file__).resolve().parent / "electro_cabinet_all.mechsim.json"

DIN_RAILS = 3
DIN_HALFS = 48
SCH_GRID = 10.0


def din_width(rec: dict) -> int:
    cls = str(rec.get("electro_class", ""))
    poles = max(int(rec.get("poles", 1)), 1)
    ports = rec.get("ports", []) or []
    if cls == "mcb":
        return poles * 2
    if cls in ("rcd", "rcbo"):
        return 8 if poles >= 4 else 4
    if cls == "contactor":
        return 5  # КМИ-10910 = 45 mm
    if cls == "thermal":
        return 6
    if cls == "psu":
        return 4
    if cls == "busbar":
        return 2
    if cls == "relay":
        return 3  # Finder 58.34 ≈ 27 mm
    if cls == "timer_relay":
        return 3  # МРП-6 / РВО ≈ 22.5 mm
    if cls == "voltage_relay":
        return 2
    if cls == "terminal":
        return max(len(ports), 1)
    if cls == "din_stop":
        return 1
    return poles * 2


def contact_units(contacts: list) -> list:
    """Pair contact defs into units like ElectroLibrary._contact_units."""
    if not contacts:
        return []
    units: list = []
    i = 0
    while i < len(contacts):
        c = contacts[i]
        t = str(c.get("type", "no")) if isinstance(c, dict) else "no"
        if t == "co":
            units.append([c])
            i += 1
            continue
        # pair NO/NC of same name family if possible
        if i + 1 < len(contacts):
            c2 = contacts[i + 1]
            t2 = str(c2.get("type", "no")) if isinstance(c2, dict) else "no"
            if t2 != "co":
                units.append([c, c2])
                i += 2
                continue
        units.append([c])
        i += 1
    return units


BASE = {
    "kind": "electro",
    "tag_offset": [0, 0],
    "rotation_quad": 0,
    "action": "none",
    "bore_mm": 32.0,
    "rod_mm": 12.0,
    "stroke_mm": 100.0,
    "spring_rate": 0.0,
    "spring_preload": 0.0,
    "mass_kg": 1.0,
    "friction_n": 5.0,
    "load_n": 0.0,
    "open_ports": False,
    "cushion": False,
    "piston_kind": "simple",
    "cush_cap": "none",
    "cush_rod": "none",
    "cush_open_cap": 0.35,
    "cush_open_rod": 0.35,
    "spring_side": "none",
    "rod_mode": "single",
    "rod_end": "plain",
    "brake": "none",
    "port_cap": "connect",
    "port_rod": "connect",
    "carriage": "none",
    "bump_end": "none",
    "mount": "clevis",
    "guide": "none",
    "seal_leak": 0.0,
    "catalog_id": "",
    "variant_id": "ppv",
    "cushion_mm": 17.0,
    "through_rod": False,
    "body_style": "profile",
    "body_style_user": False,
    "order_code": "",
    "port_name": "G1/8",
    "rod_thread": "",
    "pressure_bar": 6.0,
    "temperature_c": 20.0,
    "world_pos": [0.0, 0.0, 0.0],
    "world_basis": [[1, 0, 0], [0, 1, 0], [0, 0, 1]],
    "valve_ways": 5,
    "valve_positions": 2,
    "valve_center": "none",
    "valve_nc_no": "nc",
    "rest_pos": 0,
    "valve_pos": 0,
    "op_left": "solenoid_pilot",
    "op_right": "spring",
    "pilot_supply": "internal",
    "valve_cv": 1.0,
    "command_left": False,
    "command_right": False,
    "port_3": "muffler",
    "port_5": "muffler",
    "override_left": True,
    "override_right": True,
    "spool_envelopes": [],
    "port_mass": {},
    "port_press": {},
    "port_q": {},
    "junction_style": "tee",
    "junction_ports": 3,
    "switch_pos": 0,
    "switch_map": [],
    "switch_labels": [],
    "energized": False,
    "pressed": False,
    "lit": False,
    "timer_armed": False,
    "timer_elapsed": 0.0,
    "detached": False,
    "linked_valve_side": "",
    "door_slot": -1,
}


# One of each class + variants that look different on the cabinet.
SHOWCASE = [
    # supply / bus / PSU
    "supply_1ph",
    "supply_3ph_pe",
    "bus_bar",
    "psu_24",
    # door
    "lamp",
    "btn_no",
    "btn_nc",
    "btn_no_nc",
    "switch_2pos",
    "estop_nc",
    # relay / timer
    "relay_4c",
    "relay_2c",
    "timer_relay",
    "solenoid_coil",
    # power
    "mcb_1p_c16",
    "mcb_3p_c16",
    "rcd_2p_30",
    "rcd_4p_30",
    "rcbo_1p_n",
    "contactor_3p",
    "thermal_relay",
    # din misc
    "term_block_1",
    "term_block_4",
    "din_stop",
]


def main() -> None:
    data = json.loads(RECIPES.read_text(encoding="utf-8"))
    by_id = {r["id"]: r for r in data["recipes"]}

    elements: list[dict] = []
    next_id = 1
    tag_counts: dict[str, int] = {}

    # Pack DIN: rail cursor in half-slots
    rail_off = [0, 0, 0]
    door_i = 0
    # Schematic layout columns
    sch_col = 0
    sch_row_y = 40.0

    # Extra bus PE
    extra_buses = [("bus_bar", "PE", "PE")]

    def alloc_tag(prefix: str) -> str:
        n = tag_counts.get(prefix, 0) + 1
        tag_counts[prefix] = n
        return f"{prefix}{n}"

    def place_din(w_slots: int) -> int:
        nonlocal rail_off
        for r in range(DIN_RAILS):
            if rail_off[r] + w_slots <= DIN_HALFS:
                slot = r * DIN_HALFS + rail_off[r]
                rail_off[r] += w_slots + 1  # gap 0.5 module
                return slot
        # overflow rail 2
        slot = 2 * DIN_HALFS + min(rail_off[2], DIN_HALFS - w_slots)
        rail_off[2] = min(rail_off[2] + w_slots + 1, DIN_HALFS)
        return slot

    def door_xy(i: int) -> list[float]:
        # DoorGrid pitch ~62 mm, cols 4 — match cabinet defaults roughly
        pitch = 0.062
        cols = 4
        c = i % cols
        r = i // cols
        # area roughly ±0.2
        x = -0.186 + c * pitch
        y = 0.186 - r * pitch
        return [x, y]

    def make_el(rec: dict, *, phase: str | None = None, caption: str | None = None) -> dict:
        nonlocal next_id, sch_col, sch_row_y, door_i
        el = dict(BASE)
        eid = next_id
        next_id += 1
        prefix = str(rec.get("tag_prefix", "E"))
        tag = alloc_tag(prefix)
        cls = str(rec.get("electro_class", "terminal"))
        mount = str(rec.get("electro_mount", "din"))
        ports = list(rec.get("ports", []) or [])
        contacts = list(rec.get("contacts", []) or [])
        coil_ports = list(rec.get("coil_ports", []) or [])

        el.update(
            {
                "id": eid,
                "tag": tag,
                "recipe_id": rec["id"],
                "catalog_id": rec["id"],
                "electro_class": cls,
                "electro_mount": mount,
                "tag_prefix": prefix,
                "lamp_color": str(rec.get("lamp_color", "white")),
                "btn_color": "red" if cls == "e_stop" else str(rec.get("btn_color", "white")),
                "caption": caption if caption is not None else str(rec.get("caption", "")),
                "delay_on": float(rec.get("delay_on", 0.0)),
                "delay_off": float(rec.get("delay_off", 0.0)),
                "poles": int(rec.get("poles", 1)),
                "curve": str(rec.get("curve", "C")),
                "rating_a": float(rec.get("rating_a", 16.0)),
                "i_delta_ma": float(rec.get("i_delta_ma", 30.0)),
                "u_min": float(rec.get("u_min", 180.0)),
                "u_max": float(rec.get("u_max", 6.0 if cls in ("mcb", "rcd", "rcbo") else 260.0)),
                "phase": phase if phase is not None else str(rec.get("phase", "AC" if cls in ("rcd", "rcbo") else "")),
                "voltage": float(rec.get("voltage", 24.0 if cls == "psu" else (220.0 if cls == "lamp" else 230.0))),
                "link_valve": bool(rec.get("link_valve", False)),
                "group_template": "" if cls == "switch" else str(rec.get("group_template", "")),
                "electro_ports": ports,
                "coil_ports": coil_ports,
                "contact_defs": contacts,
                "switch_positions": max(int(rec.get("switch_positions", 2)), 2),
                "latching": bool(rec.get("latching", cls == "e_stop")),
                "closed": True,
                "member_role": "main" if rec.get("group_template") or cls in ("button", "e_stop", "relay", "timer_relay", "contactor", "thermal") else "device",
                "member_index": 0,
                "group_id": eid if rec.get("group_template") or cls in ("button", "e_stop", "relay", "timer_relay", "contactor", "thermal") else -1,
                "group_tag": tag if rec.get("group_template") or cls in ("button", "e_stop", "relay", "timer_relay", "contactor", "thermal") else "",
                "din_slot": -1,
                "door_xy": [-1, -1],
            }
        )

        # Schematic position — grid of primaries
        px = 40.0 + (sch_col % 6) * 140.0
        py = sch_row_y + (sch_col // 6) * 180.0
        el["position"] = [px, py]
        sch_col += 1

        if mount == "din":
            el["din_slot"] = place_din(din_width(rec))
        elif mount == "door":
            el["door_xy"] = door_xy(door_i)
            door_i += 1

        elements.append(el)

        # Contact members for groups
        tmpl = el["group_template"]
        if tmpl and contacts:
            units = contact_units(contacts)
            for ui, unit in enumerate(units):
                cid = next_id
                next_id += 1
                child = dict(BASE)
                child.update(
                    {
                        "id": cid,
                        "tag": f"{tag}.{ui + 1}",
                        "recipe_id": rec["id"],
                        "catalog_id": rec["id"],
                        "electro_class": "contact",
                        "electro_mount": "none",
                        "tag_prefix": prefix,
                        "contact_defs": unit,
                        "delay_on": el["delay_on"],
                        "delay_off": el["delay_off"],
                        "group_id": eid,
                        "group_tag": tag,
                        "member_role": "contact",
                        "member_index": ui + 1,
                        "position": [px, py + 40.0 + ui * 30.0],
                        "din_slot": -1,
                        "door_xy": [-1, -1],
                        "electro_ports": [],
                        "coil_ports": [],
                        "poles": 1,
                        "curve": "C",
                        "rating_a": el["rating_a"],
                        "i_delta_ma": 30.0,
                        "u_min": 180.0,
                        "u_max": 260.0,
                        "phase": "",
                        "voltage": el["voltage"],
                        "link_valve": False,
                        "group_template": "",
                        "lamp_color": "white",
                        "btn_color": "white",
                        "caption": "",
                        "latching": False,
                        "closed": True,
                        "switch_positions": 2,
                    }
                )
                elements.append(child)
        return el

    for rid in SHOWCASE:
        if rid not in by_id:
            raise SystemExit(f"missing recipe {rid}")
        make_el(by_id[rid])

    # Second bus color PE
    for _rid, phase, cap in extra_buses:
        make_el(by_id[_rid], phase=phase, caption=cap)

    scene = {
        "format": "mechsim-scene",
        "version": 1,
        "title": "Тест: все электроэлементы на щите",
        "note": "Открыть через Файл → Открыть. DIN + дверца + вводы для проверки 3D моделей.",
        "elements": elements,
        "wires": [],
        "next_id": next_id,
        "schematic": {"zoom": 0.85, "pan": [48, 56]},
    }
    OUT.write_text(json.dumps(scene, ensure_ascii=False, indent="\t"), encoding="utf-8")
    print(f"Wrote {OUT} ({len(elements)} elements)")


if __name__ == "__main__":
    main()
