#!/usr/bin/env python3
"""Trim the OurAirports CSV (public domain) to the few fields Contrail needs.

Usage: python3 -I build_airports.py INPUT_CSV OUTPUT_JSON

Keeps large, medium and small airports that have a three-letter IATA code.
Output rows: [name, code, city, latitude, longitude, size] where size is
2 = large, 1 = medium, 0 = small.
"""
import csv
import json
import sys

SIZES = {"large_airport": 2, "medium_airport": 1, "small_airport": 0}


def main(src, dst):
    rows, seen = [], set()
    with open(src, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            size = SIZES.get(r["type"])
            code = (r["iata_code"] or "").strip().upper()
            if size is None or len(code) != 3 or not code.isalpha() or code in seen:
                continue
            try:
                lat, lon = round(float(r["latitude_deg"]), 4), round(float(r["longitude_deg"]), 4)
            except ValueError:
                continue
            seen.add(code)
            rows.append([r["name"].strip()[:80], code, (r["municipality"] or "").strip()[:60], lat, lon, size])
    rows.sort(key=lambda x: (-x[5], x[1]))
    with open(dst, "w", encoding="utf-8") as f:
        json.dump({"source": "OurAirports (public domain), https://ourairports.com/data/", "airports": rows},
                  f, ensure_ascii=False, separators=(",", ":"))
    print(f"{len(rows)} airports -> {dst}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
