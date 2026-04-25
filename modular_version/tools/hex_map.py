#!/usr/bin/env python3
"""
tools/hex_map.py  —  Patrician III/IV hex map renderer

Pulls city data live from the database — edit seed.sql, re-run
latlon_to_hex.sh, then run this script to get a fresh map.

Usage:
    python3 tools/hex_map.py                        # display on screen
    python3 tools/hex_map.py --save map.png         # save to file
    python3 tools/hex_map.py --save map.png --dpi 200

Environment variables (inherit from app.sh, or set manually):
    P3_DB     database name  (default: traderdude)
    P3_USER   postgres user  (default: postgres)
    P3_HOST   host           (default: localhost)
    P3_PORT   port           (default: 5432)

Dependencies:
    pip install matplotlib psycopg2-binary
"""

import math
import os
import sys
import argparse
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon

# ── Database ──────────────────────────────────────────────────────────────────

def load_cities():
    """
    Query p3_cities joined with p3_hex_tiles for terrain.
    Returns list of tuples: (name, q, r, league, region, terrain, population)
    """
    try:
        import psycopg2
    except ImportError:
        sys.exit(
            "Error: psycopg2 is not installed.\n"
            "Run:  pip install psycopg2-binary"
        )

    conn_args = dict(
        dbname = os.environ.get("P3_DB",   "traderdude"),
        user   = os.environ.get("P3_USER", "postgres"),
        host   = os.environ.get("P3_HOST", "localhost"),
        port   = os.environ.get("P3_PORT", "5432"),
    )

    try:
        conn = psycopg2.connect(**conn_args)
    except psycopg2.OperationalError as e:
        sys.exit(
            f"Error: could not connect to '{conn_args['dbname']}' "
            f"as '{conn_args['user']}@{conn_args['host']}:{conn_args['port']}'.\n"
            f"Details: {e}\n\n"
            "Set P3_DB / P3_USER / P3_HOST / P3_PORT to override defaults."
        )

    query = """
        SELECT
            ci.name,
            ci.hex_q,
            ci.hex_r,
            ci.league,
            ci.region,
            COALESCE(ht.terrain, 'coast') AS terrain,
            ci.population
        FROM  p3_cities ci
        LEFT  JOIN p3_hex_tiles ht ON ht.city_id = ci.city_id
        WHERE ci.hex_q IS NOT NULL
          AND ci.hex_r IS NOT NULL
        ORDER BY ci.league, ci.name;
    """

    try:
        cur = conn.cursor()
        cur.execute(query)
        rows = cur.fetchall()
    except psycopg2.Error as e:
        conn.close()
        sys.exit(
            f"Error: query failed.\n{e}\n\n"
            f"Has schema.sql been applied?  "
            f"psql -d {conn_args['dbname']} -f sql/schema.sql"
        )
    finally:
        conn.close()

    if not rows:
        sys.exit(
            "No cities with hex coordinates found.\n"
            "Run the full setup first:\n"
            "  psql -d traderdude -f sql/schema.sql\n"
            "  psql -d traderdude -f sql/seed.sql\n"
            "  bash scripts/latlon_to_hex.sh"
        )

    return rows

# ── Hex geometry ──────────────────────────────────────────────────────────────

SQ3 = math.sqrt(3)

def hex_to_xy(q, r, size=1.0):
    """
    Pointy-top axial → cartesian.
    Negate y because r increases southward in the game grid, but
    matplotlib's y-axis increases upward — without this, the map is upside-down.
    """
    x =  size * (SQ3 * q + SQ3 / 2 * r)
    y = -size * (3 / 2 * r)
    return x, y

def hex_corners(cx, cy, size=1.0, gap=0.03):
    """6 corner points of a pointy-top hex, slightly inset by gap."""
    s = size * (1 - gap)
    return [
        (cx + s * math.cos(math.radians(60 * i - 30)),
         cy + s * math.sin(math.radians(60 * i - 30)))
        for i in range(6)
    ]

# ── Visual config ─────────────────────────────────────────────────────────────

BG          = "#06101e"
TERRAIN_COL = {"coast": "#122840", "land": "#1a2e14", "sea": "#07131f"}
GRID_CITY   = "#1c3a5a"
GRID_SEA    = "#0c1e2e"
HANSE_COL   = "#d4a547"
MED_COL     = "#c04428"
LABEL_HANSE = "#e0b84a"
LABEL_MED   = "#d8654a"

def pop_size(pop):
    """Population → matplotlib scatter marker size (points²)."""
    if pop > 200_000: return 140
    if pop >  80_000: return 100
    if pop >  30_000: return  70
    if pop >  10_000: return  50
    return 35

# ── Renderer ──────────────────────────────────────────────────────────────────

def draw_map(cities, save_path=None, dpi=150):
    city_index = {(c[1], c[2]): c for c in cities}

    all_q = [c[1] for c in cities]
    all_r = [c[2] for c in cities]
    q_min, q_max = min(all_q) - 3, max(all_q) + 3
    r_min, r_max = min(all_r) - 3, max(all_r) + 3
    SIZE = 1.0

    fig, ax = plt.subplots(figsize=(16, 12), facecolor=BG)
    ax.set_facecolor(BG)
    ax.set_aspect("equal")
    ax.axis("off")

    # ── Hex tile grid ─────────────────────────────────────────────────────────
    for r in range(r_min, r_max + 1):
        for q in range(q_min, q_max + 1):
            city_here = city_index.get((q, r))
            terrain   = city_here[5] if city_here else "sea"
            cx, cy    = hex_to_xy(q, r, SIZE)
            poly = Polygon(
                hex_corners(cx, cy, SIZE),
                closed=True,
                facecolor=TERRAIN_COL.get(terrain, TERRAIN_COL["sea"]),
                edgecolor=GRID_CITY if city_here else GRID_SEA,
                linewidth=0.5 if city_here else 0.3,
            )
            ax.add_patch(poly)

    # ── City dots + labels ────────────────────────────────────────────────────
    for name, q, r, league, region, terrain, pop in cities:
        cx, cy = hex_to_xy(q, r, SIZE)
        color  = HANSE_COL if league == "Hanseatic" else MED_COL
        lcolor = LABEL_HANSE if league == "Hanseatic" else LABEL_MED
        sz     = pop_size(pop)

        ax.scatter(cx, cy, s=sz * 2.2, color=color, alpha=0.18, zorder=3)
        ax.scatter(cx, cy, s=sz,       color=color,              zorder=4, linewidths=0)

        dot_r = math.sqrt(sz / math.pi) * 0.045
        ax.text(cx, cy + dot_r + 0.18, name,
                color=lcolor, fontsize=6.2, ha="center", va="bottom",
                fontfamily="monospace", zorder=5,
                bbox=dict(boxstyle="round,pad=0.1", fc=BG, ec="none", alpha=0.6))

    # ── Faint region watermarks ───────────────────────────────────────────────
    region_pts = {}
    for name, q, r, league, region, terrain, pop in cities:
        cx, cy = hex_to_xy(q, r, SIZE)
        region_pts.setdefault(region, []).append((cx, cy))
    for region, pts in region_pts.items():
        rx = sum(p[0] for p in pts) / len(pts)
        ry = sum(p[1] for p in pts) / len(pts)
        ax.text(rx, ry + 0.6, region.upper(),
                color="#ffffff", alpha=0.05, fontsize=8, ha="center",
                fontweight="bold", fontfamily="monospace", zorder=1)

    # ── Legend ────────────────────────────────────────────────────────────────
    lx, ly = 0.01, 0.99

    ax.annotate("LEAGUE", xy=(lx, ly), xycoords="axes fraction",
                color="#3a5868", fontsize=7, fontfamily="monospace",
                va="top", fontweight="bold")
    for i, (label, col) in enumerate([("Hanseatic", HANSE_COL),
                                       ("Mediterranean", MED_COL)]):
        ax.annotate(f"● {label}", xy=(lx, ly - 0.04 - i * 0.035),
                    xycoords="axes fraction", color=col,
                    fontsize=7.5, fontfamily="monospace", va="top")

    ax.annotate("TERRAIN", xy=(lx, ly - 0.135), xycoords="axes fraction",
                color="#3a5868", fontsize=7, fontfamily="monospace",
                va="top", fontweight="bold")
    for i, (label, col) in enumerate([("coast", TERRAIN_COL["coast"]),
                                       ("land",  TERRAIN_COL["land"]),
                                       ("sea",   TERRAIN_COL["sea"])]):
        ax.annotate(f"▪ {label}", xy=(lx, ly - 0.175 - i * 0.033),
                    xycoords="axes fraction", color=col,
                    fontsize=7, fontfamily="monospace", va="top")

    ax.annotate("DOT SIZE = POPULATION", xy=(lx, ly - 0.29),
                xycoords="axes fraction", color="#3a5868",
                fontsize=7, fontfamily="monospace",
                va="top", fontweight="bold")
    for i, (label, sz) in enumerate([("< 10k", 35), ("30k", 70),
                                      ("80k", 100), ("200k+", 140)]):
        ax.annotate(f"● {label}", xy=(lx, ly - 0.325 - i * 0.033),
                    xycoords="axes fraction", color="#4a6880",
                    fontsize=6.5 + sz / 60, fontfamily="monospace", va="top")

    # ── Title (city count comes from the DB query, not hardcoded) ─────────────
    league_counts = {}
    for c in cities:
        league_counts[c[3]] = league_counts.get(c[3], 0) + 1
    count_str = "  ·  ".join(
        f"{v} {k}" for k, v in sorted(league_counts.items())
    )

    ax.set_title(
        "PATRICIAN III / IV  —  Hanseatic World Map\n"
        f"pointy-top axial hex  ·  Lübeck (0,0)  ·  1 hex ≈ 50 nm  ·  {count_str}",
        color="#8aabbc", fontsize=10, fontfamily="monospace",
        pad=12, loc="center",
    )

    plt.tight_layout(pad=0.5)

    if save_path:
        fig.savefig(save_path, dpi=dpi, bbox_inches="tight",
                    facecolor=BG, edgecolor="none")
        print(f"Saved → {save_path}  ({len(cities)} cities)")
    else:
        plt.show()

    plt.close(fig)

# ── CLI ───────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Render the Patrician III/IV hex map from the live database."
    )
    parser.add_argument("--save", metavar="FILE",
                        help="Save to FILE instead of displaying  (e.g. map.png, map.pdf)")
    parser.add_argument("--dpi", type=int, default=150,
                        help="Output DPI when saving (default: 150)")
    args = parser.parse_args()

    print("Connecting to database…")
    cities = load_cities()
    print(f"Loaded {len(cities)} cities.")

    draw_map(cities, save_path=args.save, dpi=args.dpi)
