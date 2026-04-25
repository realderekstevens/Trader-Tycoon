#!/usr/bin/env bash
# =============================================================================
#  app.sh  —  Patrician III / IV  ·  Modular CLI Edition
#
#  This file is the ONLY entrypoint. It sources all modules in dependency
#  order, then calls run_app().
#
#  Directory layout:
#    app.sh              ← you are here
#    lib/
#      db.sh             ← psql wrapper, pickers, sail, buy, sell, NPC tick
#      ui.sh             ← gum helpers, breadcrumbs, section_header
#      tick.sh           ← day-advance, real-time daemon, buildings/orders
#    screens/
#      dashboard.sh      ← p3_main_dashboard, p3_city_intel_panel
#      trade.sh          ← p3_interactive_buy, p3_interactive_sell
#      admin.sh          ← p3_admin_menu (init, reseed, tick control)
#      npc.sh            ← p3_npc_menu  (admin-only NPC fleet view)
#      med.sh            ← p3_p4_menu  (Mediterranean expansion)
#      buildings.sh      ← p3_buildings_menu, limit orders
#      elasticity.sh     ← p3_elasticity_menu
#      hex.sh            ← p3_hex_menu
#      main_menu.sh      ← patrician_menu (top-level action dispatcher)
#    sql/
#      schema.sql        ← CREATE TABLE / VIEW / FUNCTION  (apply with psql -f)
#      seed.sql          ← INSERT reference data            (apply with psql -f)
#
#  DEPENDENCIES: psql  gum
#
#  QUICK START:
#    psql -d traderdude -f sql/schema.sql
#    psql -d traderdude -f sql/seed.sql
#    bash app.sh
# =============================================================================

# Do NOT use set -e here — gum returns exit 1 on ESC/empty selection, and
# psql subshells return non-zero on empty results. Both are normal game events.
# Individual functions handle their own errors via || fallback patterns.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Load order matters: ui before db (db calls warn/error), tick after both ──
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/db.sh"
source "$SCRIPT_DIR/lib/tick.sh"

source "$SCRIPT_DIR/screens/dashboard.sh"
source "$SCRIPT_DIR/screens/trade.sh"
source "$SCRIPT_DIR/screens/npc.sh"
source "$SCRIPT_DIR/screens/admin.sh"
source "$SCRIPT_DIR/screens/med.sh"
source "$SCRIPT_DIR/screens/buildings.sh"
source "$SCRIPT_DIR/screens/elasticity.sh"
source "$SCRIPT_DIR/screens/hex.sh"
source "$SCRIPT_DIR/screens/main_menu.sh"

# ─────────────────────────────────────────────────────────────────────────────
#  Schema bootstrap helpers  (thin wrappers around sql/ files)
#  The full SQL lives in sql/schema.sql and sql/seed.sql.
#  These functions exist so the Admin > Initialise menu still works without
#  requiring the operator to run psql manually.
# ─────────────────────────────────────────────────────────────────────────────
p3_create_tables() {
    info "Applying schema from sql/schema.sql..."
    psql -X --username="$P3_USER" --dbname="$P3_DB" \
         -f "$SCRIPT_DIR/sql/schema.sql" >/dev/null \
    && success "Schema applied." \
    || error "Schema apply failed — check sql/schema.sql and your DB connection."
}

p3_seed_all() {
    info "Applying seed data from sql/seed.sql..."
    psql -X --username="$P3_USER" --dbname="$P3_DB" \
         -f "$SCRIPT_DIR/sql/seed.sql" >/dev/null \
    && success "Seed data applied." \
    || error "Seed apply failed — check sql/seed.sql."
}

p3_drop_tables() {
    info "Dropping all Patrician III + IV objects..."
    p3_psql <<'SQL'
DROP VIEW IF EXISTS p3_npc_fleet_summary        CASCADE;
DROP VIEW IF EXISTS p3_visible_npc_ships        CASCADE;
DROP VIEW IF EXISTS p3_admin_crossleague_view   CASCADE;
DROP VIEW IF EXISTS p3_admin_arbitrage_view     CASCADE;
DROP VIEW IF EXISTS p3_lubeck_market_view       CASCADE;
DROP VIEW IF EXISTS p3_visible_market_view      CASCADE;
DROP VIEW IF EXISTS p3_market_view              CASCADE;
DROP VIEW IF EXISTS p3_fleet_view               CASCADE;
DROP FUNCTION IF EXISTS p3_notify_tick()                          CASCADE;
DROP FUNCTION IF EXISTS p3_marginal_price(INT,INT,TEXT,INT,INT)   CASCADE;
DROP FUNCTION IF EXISTS p3_player_visible_city_ids()              CASCADE;
DROP FUNCTION IF EXISTS p3_counting_house_cost(TEXT)              CASCADE;
DROP FUNCTION IF EXISTS p3_travel_days(INT,INT,NUMERIC)           CASCADE;
DROP FUNCTION IF EXISTS p3_hex_neighbors(INT,INT)                 CASCADE;
DROP FUNCTION IF EXISTS p3_hex_distance(INT,INT,INT,INT)          CASCADE;
DROP TABLE IF EXISTS p3_npc_trade_log        CASCADE;
DROP TABLE IF EXISTS p3_npc_ships            CASCADE;
DROP TABLE IF EXISTS p3_npc_factions         CASCADE;
DROP TABLE IF EXISTS p3_counting_houses      CASCADE;
DROP TABLE IF EXISTS p3_trade_log            CASCADE;
DROP TABLE IF EXISTS p3_limit_orders         CASCADE;
DROP TABLE IF EXISTS p3_ship_orders          CASCADE;
DROP TABLE IF EXISTS p3_ship_routes          CASCADE;
DROP TABLE IF EXISTS p3_route_orders         CASCADE;
DROP TABLE IF EXISTS p3_routes               CASCADE;
DROP TABLE IF EXISTS p3_cargo                CASCADE;
DROP TABLE IF EXISTS p3_ships                CASCADE;
DROP TABLE IF EXISTS p3_player_buildings     CASCADE;
DROP TABLE IF EXISTS p3_building_types       CASCADE;
DROP TABLE IF EXISTS p3_price_history        CASCADE;
DROP TABLE IF EXISTS p3_market               CASCADE;
DROP TABLE IF EXISTS p3_city_goods           CASCADE;
DROP TABLE IF EXISTS p3_hex_tiles            CASCADE;
DROP TABLE IF EXISTS p3_good_elasticity      CASCADE;
DROP TABLE IF EXISTS p3_cities               CASCADE;
DROP TABLE IF EXISTS p3_goods                CASCADE;
DROP TABLE IF EXISTS p3_player               CASCADE;
SQL
    success "All Patrician objects dropped."
}

p3_setup_all() {
    p3_drop_tables
    p3_create_tables
    p3_seed_all
    echo
    success "Patrician III + IV fully initialised!"
    info    "    Hanseatic cities: 24  |  Mediterranean cities: 10"
    info    "    Goods: 28  |  Building types: 25  |  NPC ships: 13"
    info    "    Hex: pointy-top axial, 1 hex = 50 nm, origin Lubeck (0,0)"
    info    "    Starting: 2 000 gold  ship 'Henrietta'  Year 1300 Day 1"
    info    "    Fog of war: ON — sail to cities to reveal market prices"
    info    "    Admin mode: UPDATE p3_player SET is_admin = TRUE;"
}

# ─────────────────────────────────────────────────────────────────────────────
#  ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────
run_app() {
    clear
    gum style \
        --border double \
        --margin "1" \
        --padding "1 4" \
        --border-foreground 33 \
        --bold \
        "PATRICIAN III / IV" \
        "$(gum style --foreground 244 'Hanseatic Trading Simulation — CLI Edition')"
    patrician_menu
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require gum
    require psql
    run_app
fi
