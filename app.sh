#!/usr/bin/env bash
# =============================================================================
#  patrician3.sh  —  §14  Patrician III + IV  (drop-in replacement)
#
#  POINTY-TOP HEX EDITION  (converted from flat-top)
#  Reference: https://www.redblobgames.com/grids/hexagons/implementation.html
#
#  Hex system: pointy-top axial coordinates (q, r)
#    · q increases east  (roughly)
#    · r increases south (roughly)
#    · s = -q - r  (derived, never stored independently)
#    · Distance = max(|q₁-q₂|, |r₁-r₂|, |s₁-s₂|)
#    · 1 hex ≈ 50 nautical miles
#
#  Pointy-top neighbours (±q, ±r, and two mixed):
#    (+1,0) (+1,-1) (0,-1) (-1,0) (-1,+1) (0,+1)
#
#  Geo → hex formula (Lübeck as map origin 0,0):
#    At ~54 °N:  1° lat ≈ 60 nm  →  50 nm = 0.8333 ° lat per hex
#                1° lon ≈ 35.4 nm →  50 nm = 1.413  ° lon per hex
#    q = ROUND( (lon - 10.687) / 1.413 )
#    r = ROUND( (53.866 - lat) / 0.833 )   ← note negation: r↑ = south
#
#  Why pointy-top?
#    · N–S runs fall along vertical columns (intuitive for Baltic trade lanes)
#    · Cities at similar latitudes align cleanly in the same row (r)
#    · The tighter E–W hex spacing matches how the Baltic coast is shaped
#
#  Scale rationale (answering: "should Lübeck be hex 106×, 538y?"):
#    No — that 1:1 degree-to-hex mapping creates a ~500×600 tile grid, far
#    too sparse.  At 1 hex = 50 nm the entire Hanseatic world fits in roughly
#    ±15 q × ±10 r (30×20 tiles), which is tight and aesthetically readable.
#    The Mediterranean expansion sits below and overlaps slightly (r +10..+27),
#    sharing the same coordinate space without needing an artificial offset.
#
#  All features retained from original:
#    · Daily time system  (game_day 1–360, eta_days, travel_days)
#    · Ship speed matters (ETA = distance_nm ÷ speed_knots ÷ 24)
#    · Per-unit marginal elasticity on every buy/sell
#    · Rebalanced daily production rates (fractional, sensible ratios)
#    · Patrician IV Mediterranean expansion
#        – 10 Med cities (Venice, Genoa, Constantinople…)
#        – 8 Med goods  (Silk, Glass, Olive Oil, Ivory…)
#        – 3 new ships  (Cog 6kn, Galley 9kn, Carrack 5.5kn)
#        – Cross-league arbitrage view
#
#  HOW TO INTEGRATE INTO app.sh:
#    Replace your existing §14 block with this file.  Then:
#    1. Add  source "$(dirname "$0")/patrician3.sh"  near the top of app.sh,
#       after the existing source/config block.
#    2. Add  "🌊 Patrician IV"  to the patrician_menu choose list
#       and  "🌊 Patrician IV") p3_p4_menu ;;  to the case block.
#    3. Replace  "Advance One Month")  p3_advance_month  with
#                "Advance One Day")    p3_advance_day
#    4. Replace  "Give Sail Order" case body with a call to p3_sail_ship.
#
#  DEPENDENCIES: psql  gum
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
#  CONFIG  (inherits from app.sh; safe to source standalone too)
# ─────────────────────────────────────────────────────────────────────────────
P3_DB="${PSQL_DB:-traderdude}"
P3_USER="${PSQL_USER:-postgres}"

p3_psql() {
    psql -X --username="$P3_USER" --dbname="$P3_DB" --tuples-only "$@"
}

p3_gold() {
    p3_psql --tuples-only -c "SELECT gold FROM p3_player LIMIT 1;" | tr -d ' '
}

p3_pick_city() {
    p3_psql --tuples-only -c "SELECT name FROM p3_cities ORDER BY name;" \
        | sed 's/^ *//' | grep -v '^$' \
        | gum filter --placeholder "Select city…"
}

p3_pick_ship() {
    local ships
    ships=$(p3_psql --tuples-only -c "
        SELECT ship_id || ' – ' || name || ' (' || ship_type || ')  '
               || current_city || '  ' || status
               || CASE WHEN status='sailing' THEN '  ETA '||eta_days||'d' ELSE '' END
        FROM p3_ships WHERE owner='player' ORDER BY name;" \
        2>/dev/null | sed 's/^ *//' | grep -v '^$') || true
    [[ -z "$ships" ]] && { warn "No ships found."; return 1; }
    local chosen
    chosen=$(echo "$ships" | gum filter --placeholder "Select ship…")
    [[ -z "$chosen" ]] && return 1
    echo "${chosen%% *}"
}

p3_pick_good() {
    p3_psql --tuples-only -c "SELECT name FROM p3_goods ORDER BY name;" \
        | sed 's/^ *//' | grep -v '^$' \
        | gum filter --placeholder "Select good…"
}

# ─────────────────────────────────────────────────────────────────────────────
#  STANDALONE HELPERS  (provided by app.sh when sourced; defined here for
#  direct execution of patrician3.sh as a self-contained game)
# ─────────────────────────────────────────────────────────────────────────────
declare -a MENU_BREADCRUMB=("Main")

push_breadcrumb() { MENU_BREADCRUMB+=("$1"); }
pop_breadcrumb()  { [[ ${#MENU_BREADCRUMB[@]} -gt 1 ]] && unset 'MENU_BREADCRUMB[-1]'; }

section_header() {
    local crumb
    crumb=$(IFS=" › "; echo "${MENU_BREADCRUMB[*]}")
    gum style \
        --border normal \
        --margin "1" \
        --padding "1 2" \
        --border-foreground 008F11 \
        --bold "$crumb › $1"
}

info()    { gum style --foreground 244 "info:  $*";    }
success() { gum style --foreground 76  "✓ $*";         }
error()   { gum style --foreground 196 "✗ $*" >&2;     }
warn()    { gum style --foreground 214 "⚠ $*";         }

pause() {
    gum style --foreground 244 "Press ENTER to continue..."
    read -r
}

confirm() {
    gum confirm --default=false --timeout=30s -- "$1" || return 1
}

require() {
    command -v "$1" &>/dev/null || {
        echo "❌ Required command not found: $1" >&2
        exit 1
    }
}

# Dependency check (only when run standalone — sourcing app.sh does its own check)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require gum
    require psql
fi

# ─────────────────────────────────────────────────────────────────────────────
#  §14a  SCHEMA  (p3_create_tables)
# ─────────────────────────────────────────────────────────────────────────────
p3_create_tables() {
    info "Creating Patrician III + IV tables…"
    p3_psql <<'SQL'

-- ── Player ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS p3_player (
    player_id  SERIAL PRIMARY KEY,
    name       TEXT          NOT NULL DEFAULT 'Merchant',
    home_city  TEXT          NOT NULL DEFAULT 'Lübeck',
    gold       NUMERIC(12,2) NOT NULL DEFAULT 2000,
    rank       TEXT          NOT NULL DEFAULT 'Apprentice',
    game_year  INTEGER       NOT NULL DEFAULT 1300,
    game_day   INTEGER       NOT NULL DEFAULT 1 CHECK (game_day BETWEEN 1 AND 360)
);

-- ── Goods catalogue ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS p3_goods (
    good_id          SERIAL PRIMARY KEY,
    name             TEXT          NOT NULL UNIQUE,
    category         TEXT          NOT NULL DEFAULT 'commodity',
    buy_price_min    NUMERIC(10,2),
    sell_price_min   NUMERIC(10,2),
    sell_price_max   NUMERIC(10,2),
    max_satisfaction NUMERIC(10,2),
    base_production  NUMERIC(8,4)  NOT NULL DEFAULT 0.5,  -- units/day
    is_raw_material  BOOLEAN       NOT NULL DEFAULT FALSE,
    notes            TEXT
);

-- ── Cities  (league distinguishes Hanse vs Med for P4) ───────────────────
CREATE TABLE IF NOT EXISTS p3_cities (
    city_id    SERIAL  PRIMARY KEY,
    name       TEXT    NOT NULL UNIQUE,
    region     TEXT    NOT NULL DEFAULT 'Baltic',
    population INTEGER NOT NULL DEFAULT 5000,
    league     TEXT    NOT NULL DEFAULT 'Hanseatic',
    hex_q      INTEGER DEFAULT NULL,  -- pointy-top axial q (≈ east)
    hex_r      INTEGER DEFAULT NULL,  -- pointy-top axial r (≈ south)
    notes      TEXT
);

-- ── City production/demand ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS p3_city_goods (
    city_id    INTEGER NOT NULL REFERENCES p3_cities(city_id) ON DELETE CASCADE,
    good_id    INTEGER NOT NULL REFERENCES p3_goods(good_id)  ON DELETE CASCADE,
    role       TEXT    NOT NULL CHECK (role IN ('produces','demands')),
    efficiency INTEGER NOT NULL DEFAULT 100,
    PRIMARY KEY (city_id, good_id, role)
);

-- ── Live market ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS p3_market (
    market_id    SERIAL  PRIMARY KEY,
    city_id      INTEGER       NOT NULL REFERENCES p3_cities(city_id),
    good_id      INTEGER       NOT NULL REFERENCES p3_goods(good_id),
    current_buy  NUMERIC(10,2) NOT NULL,
    current_sell NUMERIC(10,2) NOT NULL,
    stock        INTEGER       NOT NULL DEFAULT 100,
    UNIQUE (city_id, good_id)
);

-- ── Price history (snapshot every 10 days) ───────────────────────────────
CREATE TABLE IF NOT EXISTS p3_price_history (
    hist_id     SERIAL  PRIMARY KEY,
    city_id     INTEGER       NOT NULL REFERENCES p3_cities(city_id),
    good_id     INTEGER       NOT NULL REFERENCES p3_goods(good_id),
    game_year   INTEGER       NOT NULL,
    game_day    INTEGER       NOT NULL,
    buy_price   NUMERIC(10,2) NOT NULL,
    sell_price  NUMERIC(10,2) NOT NULL,
    stock       INTEGER       NOT NULL,
    recorded_at TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    UNIQUE (city_id, good_id, game_year, game_day)
);

-- ── Ships  (speed_knots drives eta_days calculation) ─────────────────────
-- Types: Snaikka(50,5kn) Crayer(80,7kn) Hulk(160,4kn)
--        Cog(120,6kn) Galley(90,9kn) Carrack(220,5.5kn)
CREATE TABLE IF NOT EXISTS p3_ships (
    ship_id      SERIAL  PRIMARY KEY,
    name         TEXT           NOT NULL,
    owner        TEXT           NOT NULL DEFAULT 'player',
    ship_type    TEXT           NOT NULL DEFAULT 'Snaikka',
    cargo_cap    INTEGER        NOT NULL DEFAULT 50,
    speed_knots  NUMERIC(5,2)   NOT NULL DEFAULT 5.0,
    current_city TEXT           NOT NULL DEFAULT 'Lübeck',
    status       TEXT           NOT NULL DEFAULT 'docked'
                                CHECK (status IN ('docked','sailing','loading','unloading')),
    eta_days     INTEGER        NOT NULL DEFAULT 0,
    destination  TEXT,
    notes        TEXT
);

-- ── Cargo ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS p3_cargo (
    cargo_id SERIAL  PRIMARY KEY,
    ship_id  INTEGER NOT NULL REFERENCES p3_ships(ship_id) ON DELETE CASCADE,
    good_id  INTEGER NOT NULL REFERENCES p3_goods(good_id),
    quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    UNIQUE (ship_id, good_id)
);

-- ── Routes  (travel_days at Snaikka-5kn baseline) ────────────────────────
-- Per-ship ETA = ROUND(distance_nm / (speed_knots * 24))
CREATE TABLE IF NOT EXISTS p3_routes (
    route_id      SERIAL PRIMARY KEY,
    name          TEXT    NOT NULL,
    city_a        TEXT    NOT NULL,
    city_b        TEXT    NOT NULL,
    distance_nm   INTEGER NOT NULL DEFAULT 300,
    travel_days   INTEGER NOT NULL DEFAULT 3,
    notes         TEXT
);

-- ── Route standing orders ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS p3_route_orders (
    order_id  SERIAL  PRIMARY KEY,
    route_id  INTEGER       NOT NULL REFERENCES p3_routes(route_id) ON DELETE CASCADE,
    city      TEXT          NOT NULL,
    good_id   INTEGER       NOT NULL REFERENCES p3_goods(good_id),
    action    TEXT          NOT NULL CHECK (action IN ('buy','sell')),
    quantity  INTEGER       NOT NULL DEFAULT 10,
    max_price NUMERIC(10,2),
    min_price NUMERIC(10,2)
);

-- ── Ship–Route assignments ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS p3_ship_routes (
    ship_id  INTEGER NOT NULL REFERENCES p3_ships(ship_id)   ON DELETE CASCADE,
    route_id INTEGER NOT NULL REFERENCES p3_routes(route_id) ON DELETE CASCADE,
    active   BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (ship_id, route_id)
);

-- ── One-off ship orders ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS p3_ship_orders (
    order_id    SERIAL PRIMARY KEY,
    ship_id     INTEGER       NOT NULL REFERENCES p3_ships(ship_id) ON DELETE CASCADE,
    order_type  TEXT          NOT NULL CHECK (order_type IN ('sail','buy','sell','wait')),
    target_city TEXT,
    good_id     INTEGER       REFERENCES p3_goods(good_id),
    quantity    INTEGER,
    price_limit NUMERIC(10,2),
    executed    BOOLEAN       NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ── Building types  (daily_maintenance replaces monthly_maintenance) ──────
CREATE TABLE IF NOT EXISTS p3_building_types (
    building_type_id       SERIAL        PRIMARY KEY,
    name                   TEXT          NOT NULL UNIQUE,
    output_good_id         INTEGER       NOT NULL REFERENCES p3_goods(good_id),
    input_good_id          INTEGER       REFERENCES p3_goods(good_id),
    input_units_per_output NUMERIC(6,3)  NOT NULL DEFAULT 0,
    base_production        NUMERIC(8,4)  NOT NULL DEFAULT 0.25,  -- units/day
    construction_cost      INTEGER       NOT NULL DEFAULT 5000,
    daily_maintenance      NUMERIC(8,2)  NOT NULL DEFAULT 20,    -- gold/day
    notes                  TEXT
);

-- ── Player-owned buildings ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS p3_player_buildings (
    pb_id            SERIAL PRIMARY KEY,
    city_id          INTEGER NOT NULL REFERENCES p3_cities(city_id),
    building_type_id INTEGER NOT NULL REFERENCES p3_building_types(building_type_id),
    num_buildings    INTEGER NOT NULL DEFAULT 1 CHECK (num_buildings > 0),
    acquired_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ── Hex grid (POINTY-TOP axial, 1 hex ≈ 50 nm) ───────────────────────────
--
--  Pointy-top axial coordinate system (redblobgames §2 Layout):
--    · q-axis points east-northeast  (flat-top had q pointing straight east)
--    · r-axis points south-southeast
--    · s = -q - r  (cube constraint, stored as generated column)
--
--  Neighbour directions (pointy-top):
--    (q+1, r  ) E   (q-1, r  ) W
--    (q  , r-1) NE  (q  , r+1) SW
--    (q+1, r-1) NW  (q-1, r+1) SE
--
--  Distance between hex A and hex B:
--    max( |qa-qb|, |ra-rb|, |sa-sb| )
--
CREATE TABLE IF NOT EXISTS p3_hex_tiles (
    hex_id  SERIAL  PRIMARY KEY,
    q       INTEGER NOT NULL,
    r       INTEGER NOT NULL,
    s       INTEGER GENERATED ALWAYS AS (-q - r) STORED,
    terrain TEXT    NOT NULL DEFAULT 'sea'
                    CHECK (terrain IN ('sea','coast','land','forest','mountain','ice')),
    city_id INTEGER REFERENCES p3_cities(city_id) ON DELETE SET NULL,
    hazard  TEXT,
    notes   TEXT,
    UNIQUE (q, r)
);
CREATE INDEX IF NOT EXISTS idx_p3_hex_tiles_city ON p3_hex_tiles(city_id);

-- ── Hex SQL helpers ───────────────────────────────────────────────────────
--
--  Distance formula (cube / axial — same for pointy-top and flat-top):
--    max(|q1-q2|, |r1-r2|, |(-q1-r1)-(-q2-r2)|)
--
CREATE OR REPLACE FUNCTION p3_hex_distance(q1 INT, r1 INT, q2 INT, r2 INT)
RETURNS INTEGER LANGUAGE sql IMMUTABLE AS $$
    SELECT GREATEST(ABS(q1-q2), ABS(r1-r2), ABS((-q1-r1)-(-q2-r2)));
$$;

--  Pointy-top neighbour directions (6 neighbours):
--    redblobgames hex_directions for pointy-top:
--    (1,0) (1,-1) (0,-1) (-1,0) (-1,1) (0,1)
--
CREATE OR REPLACE FUNCTION p3_hex_neighbors(q INT, r INT)
RETURNS TABLE(nq INT, nr INT) LANGUAGE sql IMMUTABLE AS $$
    VALUES
        (q+1, r  ),   -- E
        (q+1, r-1),   -- NE
        (q  , r-1),   -- NW
        (q-1, r  ),   -- W
        (q-1, r+1),   -- SW
        (q  , r+1);   -- SE
$$;

-- Travel days from hex distance: 1 hex = 50 nm, speed_kn × 24 = nm/day
CREATE OR REPLACE FUNCTION p3_travel_days(
    city_a_id  INT,
    city_b_id  INT,
    speed_kn   NUMERIC DEFAULT 5.0
) RETURNS INTEGER LANGUAGE sql STABLE AS $$
    SELECT GREATEST(1,
        ROUND(
            (p3_hex_distance(ca.hex_q, ca.hex_r, cb.hex_q, cb.hex_r) * 50.0)
            / (speed_kn * 24.0)
        )::INTEGER
    )
    FROM p3_cities ca, p3_cities cb
    WHERE ca.city_id = city_a_id
      AND cb.city_id = city_b_id
      AND ca.hex_q IS NOT NULL
      AND cb.hex_q IS NOT NULL;
$$;

-- ── Marginal pricing elasticity ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS p3_good_elasticity (
    good_id         INTEGER PRIMARY KEY REFERENCES p3_goods(good_id) ON DELETE CASCADE,
    elasticity_buy  NUMERIC(5,3) NOT NULL DEFAULT 0.40,
    elasticity_sell NUMERIC(5,3) NOT NULL DEFAULT 0.30,
    stock_ref       INTEGER      NOT NULL DEFAULT 100,
    price_floor_pct NUMERIC(5,3) NOT NULL DEFAULT 0.30,
    price_ceil_pct  NUMERIC(5,3) NOT NULL DEFAULT 3.00
);

-- ── Enhanced multi-factor marginal price function ────────────────────────
--
--  Factors applied on top of the base stock/elasticity power law:
--    1. SEASONAL  — sine wave over the 360-day year, phase-shifted per
--                   category (food cheap at harvest, luxury peaks year-end)
--    2. PANIC     — extra spike when stock < 20 % of reference (hoarding
--                   premium); symmetric glut discount above 200 %
--    3. CATEGORY  — luxury goods are intrinsically more volatile than staples
--    4. SPREAD    — ASK = midpoint × 1.08, BID = midpoint × 0.92
--    5. CLAMP     — hard floor / ceiling from p3_good_elasticity
--
--  p_qty_offset = units already purchased this session (0 for first unit)
--  so the function returns the *marginal* price of the next unit.
--
CREATE OR REPLACE FUNCTION p3_marginal_price(
    p_city_id    INT,
    p_good_id    INT,
    p_action     TEXT,      -- 'buy'  or  'sell'
    p_qty_offset INT,       -- units already transacted this session
    p_game_day   INT        -- 1..360  for seasonal shift
) RETURNS NUMERIC LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_mid             NUMERIC;
    v_stock           INT;
    v_stock_ref       INT;
    v_elast           NUMERIC;
    v_floor_pct       NUMERIC;
    v_ceil_pct        NUMERIC;
    v_category        TEXT;
    v_effective_stock INT;
    v_season_mod      NUMERIC;
    v_vol_mod         NUMERIC;
    v_scarcity        NUMERIC;
    v_panic_mod       NUMERIC;
    v_price           NUMERIC;
BEGIN
    SELECT
        (m.current_buy / 1.08 + m.current_sell / 0.92) / 2.0,
        m.stock,
        e.stock_ref,
        g.category,
        CASE WHEN p_action = 'buy' THEN e.elasticity_buy
             ELSE e.elasticity_sell END,
        e.price_floor_pct,
        e.price_ceil_pct
    INTO v_mid, v_stock, v_stock_ref, v_category, v_elast, v_floor_pct, v_ceil_pct
    FROM p3_market m
    JOIN p3_goods g           ON g.good_id = m.good_id
    JOIN p3_good_elasticity e ON e.good_id = g.good_id
    WHERE m.city_id = p_city_id AND m.good_id = p_good_id;

    IF NOT FOUND THEN RETURN NULL; END IF;

    -- Effective stock moves in opposite directions for buy vs sell
    v_effective_stock := GREATEST(
        CASE WHEN p_action = 'buy'
             THEN v_stock - p_qty_offset
             ELSE v_stock + p_qty_offset
        END, 1
    );

    -- 1. Seasonal factor  (±10 % amplitude, 360-day period)
    --    Phase offsets: food cheap mid-year (harvest), material peaks in
    --    summer building season, luxury peaks at year-end celebrations.
    v_season_mod := 1.0 + 0.10 * SIN(
        (p_game_day::NUMERIC / 360.0) * 2.0 * PI()
        + CASE v_category
            WHEN 'food'     THEN PI()           -- trough at day 180
            WHEN 'material' THEN PI() / 2.0     -- peak at day  90
            WHEN 'luxury'   THEN -PI() / 2.0    -- peak at day 270
            ELSE PI() / 4.0
          END
    );

    -- 2. Category volatility multiplier
    v_vol_mod := CASE v_category
        WHEN 'luxury'    THEN 1.25   -- exotic goods swing the hardest
        WHEN 'food'      THEN 0.88   -- staple prices are sticky
        WHEN 'material'  THEN 1.05
        ELSE 1.0
    END;

    -- 3. Core power-law scarcity
    v_scarcity := POWER(
        v_stock_ref::NUMERIC / v_effective_stock::NUMERIC,
        v_elast
    );

    -- 4. Panic / glut non-linearity
    --    Below 20 % of reference: price spikes steeply (panic buying premium)
    --    Above 200 % of reference: price further depressed  (glut discount)
    v_panic_mod := CASE
        WHEN v_effective_stock < v_stock_ref * 0.20 THEN
            1.0 + 0.60 * (1.0 - v_effective_stock::NUMERIC
                               / (v_stock_ref::NUMERIC * 0.20))
        WHEN v_effective_stock > v_stock_ref * 2.0 THEN
            1.0 - 0.20 * LEAST(
                (v_effective_stock::NUMERIC / (v_stock_ref::NUMERIC * 2.0)) - 1.0,
                1.0)
        ELSE 1.0
    END;

    v_price := v_mid * v_season_mod * v_vol_mod * v_scarcity * v_panic_mod;

    -- 5. Bid/Ask spread
    IF p_action = 'buy'  THEN v_price := v_price * 1.08; END IF;
    IF p_action = 'sell' THEN v_price := v_price * 0.92; END IF;

    -- 6. Hard floor / ceiling
    RETURN GREATEST(
        v_mid * v_floor_pct,
        LEAST(v_mid * v_ceil_pct, ROUND(v_price, 2))
    );
END;
$$;

-- ── Limit orders ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS p3_limit_orders (
    order_id           SERIAL PRIMARY KEY,
    ship_id            INTEGER NOT NULL REFERENCES p3_ships(ship_id) ON DELETE CASCADE,
    city_id            INTEGER NOT NULL REFERENCES p3_cities(city_id),
    good_id            INTEGER NOT NULL REFERENCES p3_goods(good_id),
    action             TEXT    NOT NULL CHECK (action IN ('buy','sell')),
    total_quantity     INTEGER NOT NULL CHECK (total_quantity > 0),
    remaining_quantity INTEGER NOT NULL CHECK (remaining_quantity >= 0),
    price_limit        NUMERIC(10,2) NOT NULL,
    active             BOOLEAN DEFAULT TRUE,
    created_at         TIMESTAMPTZ DEFAULT NOW()
);

-- ── Trade log ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS p3_trade_log (
    log_id      SERIAL PRIMARY KEY,
    game_year   INTEGER       NOT NULL,
    game_day    INTEGER       NOT NULL,
    ship_id     INTEGER       REFERENCES p3_ships(ship_id),
    ship_name   TEXT,
    city        TEXT,
    good_id     INTEGER       REFERENCES p3_goods(good_id),
    good_name   TEXT,
    action      TEXT          NOT NULL CHECK (action IN ('buy','sell','arrive','depart')),
    quantity    INTEGER,
    price       NUMERIC(10,2),
    total_value NUMERIC(12,2),
    gold_after  NUMERIC(12,2),
    logged_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ── Fleet view ────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW p3_fleet_view AS
SELECT s.ship_id, s.name, s.ship_type, s.speed_knots,
       s.current_city, s.status, s.destination, s.eta_days,
       s.cargo_cap,
       COALESCE(SUM(c.quantity), 0)               AS cargo_used,
       s.cargo_cap - COALESCE(SUM(c.quantity), 0) AS cargo_free
FROM   p3_ships s
LEFT   JOIN p3_cargo c ON c.ship_id = s.ship_id
WHERE  s.owner = 'player'
GROUP  BY s.ship_id, s.name, s.ship_type, s.speed_knots,
          s.current_city, s.status, s.destination, s.eta_days, s.cargo_cap;

-- ── Market view ───────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW p3_market_view AS
SELECT
    ci.name           AS city,
    ci.league,
    g.name            AS good,
    g.category,
    m.current_buy,
    m.current_sell,
    g.buy_price_min   AS ref_buy_max,
    g.sell_price_min  AS ref_sell_min,
    g.sell_price_max  AS ref_sell_max,
    m.stock,
    ROUND(m.current_buy - m.current_sell, 2) AS spread,
    CASE
        WHEN m.current_buy  <= g.buy_price_min  THEN '🟢 GOOD BUY'
        WHEN m.current_sell >= g.sell_price_max THEN '🔥 GREAT SELL'
        WHEN m.current_sell >= g.sell_price_min THEN '💰 GOOD SELL'
        ELSE '—'
    END AS signal
FROM p3_market m
JOIN p3_cities ci ON ci.city_id = m.city_id
JOIN p3_goods  g  ON g.good_id  = m.good_id
ORDER BY ci.name, g.name;

-- ── Arbitrage view ────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW p3_arbitrage_view AS
SELECT
    bm.city          AS buy_city,
    sm.city          AS sell_city,
    bm.good,
    bm.current_buy   AS buy_price,
    sm.current_sell  AS sell_price,
    ROUND(sm.current_sell - bm.current_buy, 2) AS profit_per_unit,
    bm.stock         AS buy_stock,
    sm.stock         AS sell_stock
FROM   p3_market_view bm
JOIN   p3_market_view sm
       ON sm.good = bm.good AND sm.city <> bm.city
WHERE  sm.current_sell > bm.current_buy
ORDER  BY profit_per_unit DESC;

-- ── pg_notify helper ─────────────────────────────────────────────────────
--
--  Called by the bash tick daemon every simulated game day.
--  Any external psql session can receive real-time events with:
--    LISTEN p3_day_tick;
--
--  Payload JSON: { "year": N, "day": N, "gold": N.NN, "rank": "..." }
--
CREATE OR REPLACE FUNCTION p3_notify_tick()
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_payload TEXT;
BEGIN
    SELECT json_build_object(
        'year', game_year,
        'day',  game_day,
        'gold', ROUND(gold, 2),
        'rank', rank
    )::text INTO v_payload FROM p3_player LIMIT 1;
    PERFORM pg_notify('p3_day_tick', COALESCE(v_payload, '{}'));
END;
$$;

SQL
    success "✅  All Patrician III + IV tables and views created."
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14b  SEED DATA
# ─────────────────────────────────────────────────────────────────────────────

# ── Goods (daily base_production — all 28 goods for P3 + P4) ──────────────
p3_seed_goods() {
    info "Seeding goods (daily production rates)…"
    p3_psql <<'SQL'
INSERT INTO p3_goods
    (name, category, buy_price_min, sell_price_min, sell_price_max,
     max_satisfaction, base_production, is_raw_material, notes)
VALUES
-- ── Patrician III goods ───────────────────────────────────────────────────
-- Hanseatic staples — high daily output
    ('Beer',       'food',      38,    44,   60,   40,  1.600, FALSE, 'Big Four staple — Grain→Beer'),
    ('Bricks',     'material',  80,   130,  140, NULL,  0.480, FALSE, 'Building material'),
    ('Fish',       'food',     450,   490,  540,  515,  0.400, FALSE, 'Big Four — preserved with Salt'),
    ('Grain',      'food',      95,   140,  160,  141,  0.800,  TRUE, 'Big Four raw — abundant'),
    ('Hemp',       'material', 400,   500,  600, NULL,  0.320,  TRUE, 'Rope & rigging raw'),
    ('Honey',      'food',     110,   160,  180,  128,  0.260,  TRUE, 'Apiary raw'),
    ('Salt',       'material',  27,    33,   50,   32,  1.120,  TRUE, 'Preservation raw — very high output'),
    ('Timber',     'material',  57,    75,   95,   70,  0.640,  TRUE, 'Shipbuilding raw'),
    ('Pitch',      'material',  60,   100,  120, NULL,  0.380, FALSE, 'Waterproofing — pine resin'),
    ('Whale Oil',  'material',  72,   100,  150,   96,  0.260, FALSE, 'Lamp oil — coastal only'),
    ('Pottery',    'commodity', 185,  230,  250,  200,  0.320, FALSE, 'Low-tier luxury'),
-- Processed goods — require input, lower daily throughput
    ('Cloth',      'luxury',   220,   340,  350,  242,  0.260, FALSE, 'Wool→Cloth — high profit'),
    ('Iron Goods', 'luxury',   320,   430,  450,  300,  0.190, FALSE, 'Pig Iron→Iron Goods — best margins'),
    ('Meat',       'food',     950,  1250, 1500, 1120,  0.160, FALSE, 'Cattle — expensive, low output'),
    ('Leather',    'commodity', 250,  300,  340,  262,  0.320, FALSE, 'By-product of cattle'),
-- Expensive raws
    ('Pig Iron',   'material', 900,  1200, 1300, NULL,  0.270,  TRUE, 'Smelter raw — needs for Iron Goods'),
    ('Skins',      'luxury',   850,   900, 1400,  791,  0.160,  TRUE, 'Fur trade — very high value'),
    ('Wool',       'material', 925,  1300, 1300, 1030,  0.230,  TRUE, 'Sheep raw — needed for Cloth'),
    ('Spices',     'luxury',   280,   350,  400,  327,  0.097, FALSE, 'Mediterranean imports only'),
    ('Wine',       'luxury',   230,   350,  400,  257,  0.160, FALSE, 'Vineyard — Rhine and Med'),
-- ── Patrician IV Mediterranean goods ─────────────────────────────────────
    ('Olive Oil',  'luxury',   180,   240,  320,  210,  0.210, FALSE, 'Med staple — strong demand in North'),
    ('Silk',       'luxury',  1200,  1600, 2200, 1400,  0.065, FALSE, 'Top-tier luxury — Constantinople'),
    ('Glass',      'luxury',   320,   420,  550,  380,  0.120, FALSE, 'Venice specialty'),
    ('Sand',       'material',  10,    12,   18, NULL,  1.400,  TRUE, 'Glassworks raw'),
    ('Cotton',     'material', 180,   240,  290, NULL,  0.320,  TRUE, 'Cloth alternative — warm regions'),
    ('Alum',       'material', 140,   180,  220, NULL,  0.210,  TRUE, 'Cloth dyeing agent'),
    ('Dates',      'food',     160,   210,  260,  190,  0.190, FALSE, 'North African luxury food'),
    ('Ivory',      'luxury',  2400,  3200, 4500, 2800,  0.032, FALSE, 'Rare African trade good')
ON CONFLICT (name) DO UPDATE SET
    buy_price_min    = EXCLUDED.buy_price_min,
    sell_price_min   = EXCLUDED.sell_price_min,
    sell_price_max   = EXCLUDED.sell_price_max,
    max_satisfaction = EXCLUDED.max_satisfaction,
    base_production  = EXCLUDED.base_production,
    notes            = EXCLUDED.notes;
SQL
    success "Goods seeded (28 goods, daily production rates)."
}

# ── Cities ────────────────────────────────────────────────────────────────
p3_seed_cities() {
    info "Seeding Hanseatic cities…"
    p3_psql <<'SQL'
INSERT INTO p3_cities (name, region, population, league) VALUES
    ('Aalborg',     'North Sea',  6000, 'Hanseatic'),
    ('Bergen',      'North Sea',  8000, 'Hanseatic'),
    ('Brugge',      'West',      14000, 'Hanseatic'),
    ('Bremen',      'West',      12000, 'Hanseatic'),
    ('Cologne',     'Rhine',     18000, 'Hanseatic'),
    ('Edinburgh',   'British',    7000, 'Hanseatic'),
    ('Gdansk',      'Baltic',    11000, 'Hanseatic'),
    ('Groningen',   'West',       7000, 'Hanseatic'),
    ('Hamburg',     'West',      13000, 'Hanseatic'),
    ('Ladoga',      'East',       4000, 'Hanseatic'),
    ('London',      'British',   20000, 'Hanseatic'),
    ('Lübeck',      'Baltic',    15000, 'Hanseatic'),
    ('Malmö',       'Baltic',     8000, 'Hanseatic'),
    ('Novgorod',    'East',       9000, 'Hanseatic'),
    ('Oslo',        'North Sea',  6500, 'Hanseatic'),
    ('Reval',       'Baltic',     7000, 'Hanseatic'),
    ('Riga',        'Baltic',     8500, 'Hanseatic'),
    ('Ripen',       'North Sea',  5000, 'Hanseatic'),
    ('Rostock',     'Baltic',     7500, 'Hanseatic'),
    ('Scarborough', 'British',    6000, 'Hanseatic'),
    ('Stettin',     'Baltic',     8000, 'Hanseatic'),
    ('Stockholm',   'Baltic',     9000, 'Hanseatic'),
    ('Torun',       'Baltic',     6500, 'Hanseatic'),
    ('Visby',       'Baltic',     7000, 'Hanseatic')
ON CONFLICT (name) DO NOTHING;
SQL
    success "Hanseatic cities seeded (24)."
}

p3_seed_p4_cities() {
    info "Seeding Mediterranean cities (P4)…"
    p3_psql <<'SQL'
INSERT INTO p3_cities (name, region, population, league) VALUES
    ('Venice',         'Mediterranean', 80000, 'Mediterranean'),
    ('Genoa',          'Mediterranean', 60000, 'Mediterranean'),
    ('Marseille',      'Mediterranean', 25000, 'Mediterranean'),
    ('Barcelona',      'Mediterranean', 30000, 'Mediterranean'),
    ('Lisbon',         'Atlantic',      20000, 'Mediterranean'),
    ('Constantinople', 'Bosphorus',    200000, 'Mediterranean'),
    ('Naples',         'Mediterranean', 40000, 'Mediterranean'),
    ('Palermo',        'Mediterranean', 20000, 'Mediterranean'),
    ('Tunis',          'North Africa',  15000, 'Mediterranean'),
    ('Alexandria',     'North Africa',  50000, 'Mediterranean')
ON CONFLICT (name) DO NOTHING;
SQL
    success "Mediterranean cities seeded (10)."
}

# ── City production/demand (Hanseatic) ────────────────────────────────────
p3_seed_city_goods() {
    info "Seeding Hanseatic city production & demand…"
    p3_psql <<'SQL'
INSERT INTO p3_city_goods (city_id, good_id, role, efficiency)
SELECT ci.city_id, g.good_id, v.role, v.efficiency
FROM (VALUES
    ('Aalborg','Meat','produces',120),    ('Aalborg','Pig Iron','produces',120),
    ('Aalborg','Timber','produces',120),  ('Aalborg','Whale Oil','produces',110),
    ('Aalborg','Beer','demands',100),     ('Aalborg','Iron Goods','demands',100),
    ('Bergen','Whale Oil','produces',120),('Bergen','Pitch','produces',110),
    ('Bergen','Iron Goods','demands',100),('Bergen','Meat','demands',100),
    ('Brugge','Hemp','produces',120),     ('Brugge','Wool','produces',120),
    ('Brugge','Salt','produces',110),     ('Brugge','Pottery','produces',110),
    ('Brugge','Cloth','demands',100),
    ('Bremen','Beer','produces',120),     ('Bremen','Bricks','produces',120),
    ('Bremen','Cloth','produces',110),    ('Bremen','Iron Goods','produces',120),
    ('Bremen','Spices','demands',100),
    ('Cologne','Honey','produces',120),   ('Cologne','Wine','produces',120),
    ('Cologne','Pottery','produces',110), ('Cologne','Spices','demands',100),
    ('Edinburgh','Cloth','produces',110), ('Edinburgh','Fish','produces',120),
    ('Edinburgh','Iron Goods','produces',110),
    ('Gdansk','Beer','produces',120),     ('Gdansk','Grain','produces',120),
    ('Gdansk','Hemp','produces',120),     ('Gdansk','Meat','produces',110),
    ('Gdansk','Pitch','produces',110),
    ('Groningen','Bricks','produces',120),('Groningen','Grain','produces',120),
    ('Groningen','Hemp','produces',110),  ('Groningen','Timber','produces',110),
    ('Hamburg','Beer','produces',120),    ('Hamburg','Fish','produces',120),
    ('Hamburg','Grain','produces',120),   ('Hamburg','Hemp','produces',110),
    ('Hamburg','Salt','demands',100),
    ('Ladoga','Fish','produces',110),     ('Ladoga','Grain','produces',120),
    ('Ladoga','Hemp','produces',110),     ('Ladoga','Pig Iron','produces',120),
    ('Ladoga','Skins','produces',120),
    ('London','Beer','produces',120),     ('London','Cloth','produces',120),
    ('London','Meat','produces',120),     ('London','Pig Iron','produces',110),
    ('London','Wool','produces',120),     ('London','Spices','demands',100),
    ('London','Wine','demands',100),
    ('Lübeck','Bricks','produces',120),   ('Lübeck','Fish','produces',120),
    ('Lübeck','Iron Goods','produces',120),('Lübeck','Pitch','produces',110),
    ('Malmö','Cloth','produces',110),     ('Malmö','Meat','produces',110),
    ('Malmö','Wool','produces',110),
    ('Novgorod','Beer','produces',110),   ('Novgorod','Meat','produces',120),
    ('Novgorod','Pitch','produces',120),  ('Novgorod','Skins','produces',120),
    ('Novgorod','Timber','produces',120),
    ('Oslo','Bricks','produces',110),     ('Oslo','Pig Iron','produces',120),
    ('Oslo','Pitch','produces',120),      ('Oslo','Timber','produces',120),
    ('Oslo','Whale Oil','produces',120),
    ('Reval','Grain','produces',120),     ('Reval','Iron Goods','produces',110),
    ('Reval','Salt','produces',120),      ('Reval','Skins','produces',120),
    ('Riga','Fish','produces',120),       ('Riga','Honey','produces',110),
    ('Riga','Pitch','produces',120),      ('Riga','Salt','produces',120),
    ('Riga','Skins','produces',110),
    ('Ripen','Bricks','produces',120),    ('Ripen','Pig Iron','produces',110),
    ('Ripen','Pottery','produces',110),   ('Ripen','Salt','produces',120),
    ('Ripen','Whale Oil','produces',120),
    ('Rostock','Grain','produces',120),   ('Rostock','Hemp','produces',110),
    ('Rostock','Honey','produces',120),   ('Rostock','Pottery','produces',110),
    ('Rostock','Salt','produces',110),
    ('Scarborough','Beer','produces',110),('Scarborough','Cloth','produces',110),
    ('Scarborough','Iron Goods','produces',110),('Scarborough','Timber','produces',110),
    ('Scarborough','Wool','produces',120),
    ('Stettin','Beer','produces',120),    ('Stettin','Fish','produces',120),
    ('Stettin','Grain','produces',120),   ('Stettin','Hemp','produces',120),
    ('Stettin','Salt','produces',110),
    ('Stockholm','Iron Goods','produces',120),('Stockholm','Pig Iron','produces',120),
    ('Stockholm','Timber','produces',120),('Stockholm','Whale Oil','produces',110),
    ('Torun','Honey','produces',120),     ('Torun','Meat','produces',110),
    ('Torun','Pottery','produces',110),   ('Torun','Timber','produces',110),
    ('Torun','Wool','produces',110),
    ('Visby','Cloth','produces',110),     ('Visby','Honey','produces',110),
    ('Visby','Pottery','produces',110),   ('Visby','Wool','produces',110)
) AS v(city_name, good_name, role, efficiency)
JOIN p3_cities ci ON ci.name = v.city_name
JOIN p3_goods  g  ON g.name  = v.good_name
ON CONFLICT (city_id, good_id, role) DO UPDATE SET efficiency = EXCLUDED.efficiency;
SQL
    success "Hanseatic city production seeded."
}

p3_seed_p4_city_goods() {
    info "Seeding Mediterranean city production & demand (P4)…"
    p3_psql <<'SQL'
INSERT INTO p3_city_goods (city_id, good_id, role, efficiency)
SELECT ci.city_id, g.good_id, v.role, v.efficiency
FROM (VALUES
    ('Venice',         'Glass',     'produces', 130),
    ('Venice',         'Silk',      'produces', 120),
    ('Venice',         'Salt',      'produces', 110),
    ('Venice',         'Spices',    'demands',  100),
    ('Venice',         'Olive Oil', 'demands',  100),
    ('Genoa',          'Olive Oil', 'produces', 120),
    ('Genoa',          'Cloth',     'produces', 110),
    ('Genoa',          'Alum',      'produces', 110),
    ('Genoa',          'Spices',    'demands',  100),
    ('Marseille',      'Wine',      'produces', 130),
    ('Marseille',      'Olive Oil', 'produces', 120),
    ('Marseille',      'Salt',      'produces', 110),
    ('Barcelona',      'Wine',      'produces', 120),
    ('Barcelona',      'Cotton',    'produces', 120),
    ('Barcelona',      'Cloth',     'produces', 110),
    ('Lisbon',         'Salt',      'produces', 120),
    ('Lisbon',         'Fish',      'produces', 120),
    ('Constantinople', 'Silk',      'produces', 130),
    ('Constantinople', 'Spices',    'produces', 120),
    ('Constantinople', 'Alum',      'produces', 120),
    ('Constantinople', 'Glass',     'demands',  100),
    ('Constantinople', 'Cloth',     'demands',  100),
    ('Naples',         'Wine',      'produces', 110),
    ('Naples',         'Olive Oil', 'produces', 110),
    ('Naples',         'Grain',     'produces', 110),
    ('Palermo',        'Grain',     'produces', 130),
    ('Palermo',        'Salt',      'produces', 120),
    ('Palermo',        'Cotton',    'produces', 110),
    ('Tunis',          'Dates',     'produces', 130),
    ('Tunis',          'Ivory',     'produces', 110),
    ('Tunis',          'Leather',   'produces', 120),
    ('Alexandria',     'Cotton',    'produces', 130),
    ('Alexandria',     'Dates',     'produces', 120),
    ('Alexandria',     'Spices',    'produces', 120),
    ('Alexandria',     'Ivory',     'produces', 110)
) AS v(city_name, good_name, role, efficiency)
JOIN p3_cities ci ON ci.name = v.city_name
JOIN p3_goods  g  ON g.name  = v.good_name
ON CONFLICT (city_id, good_id, role) DO UPDATE SET efficiency = EXCLUDED.efficiency;
SQL
    success "Mediterranean city production seeded."
}

# ── Market seed ───────────────────────────────────────────────────────────
p3_seed_market() {
    info "Seeding market prices (bid/ask spread model)…"
    p3_psql <<'SQL'
INSERT INTO p3_market (city_id, good_id, current_buy, current_sell, stock)
SELECT
    ci.city_id,
    g.good_id,
    ROUND(mid_price * 1.08, 2) AS current_buy,
    ROUND(mid_price * 0.92, 2) AS current_sell,
    CASE
        WHEN cg.good_id IS NOT NULL
            THEN LEAST(500, FLOOR(g.base_production * 450)::INTEGER)
        ELSE GREATEST(10, FLOOR(g.base_production * 90)::INTEGER)
    END AS stock
FROM p3_cities ci
CROSS JOIN p3_goods g
LEFT JOIN p3_city_goods cg
       ON cg.city_id = ci.city_id AND cg.good_id = g.good_id AND cg.role = 'produces'
CROSS JOIN LATERAL (
    SELECT ROUND(
        (g.buy_price_min + g.sell_price_min) / 2.0
        * (0.85 + (RANDOM()::NUMERIC) * 0.30)
        * CASE WHEN cg.good_id IS NOT NULL THEN 0.88::NUMERIC ELSE 1.05::NUMERIC END,
    2) AS mid_price
) m
WHERE g.buy_price_min IS NOT NULL
ON CONFLICT (city_id, good_id) DO NOTHING;
SQL
    success "Market seeded."
}

# ── Routes ────────────────────────────────────────────────────────────────
p3_seed_routes() {
    info "Seeding trade routes (travel_days at Snaikka 5kn baseline)…"
    p3_psql <<'SQL'
INSERT INTO p3_routes (name, city_a, city_b, distance_nm, travel_days, notes) VALUES
-- Hanseatic (P3)
    ('Lübeck–Hamburg',      'Lübeck',    'Hamburg',        120,  1, 'Short hop — Grain/Beer/Fish'),
    ('Lübeck–Rostock',      'Lübeck',    'Rostock',        100,  1, 'Grain/Hemp/Honey'),
    ('Lübeck–Gdansk',       'Lübeck',    'Gdansk',         350,  3, 'Grain/Beer/Hemp east'),
    ('Lübeck–Stockholm',    'Lübeck',    'Stockholm',      650,  5, 'Iron Goods/Pig Iron'),
    ('Lübeck–Bergen',       'Lübeck',    'Bergen',         900,  8, 'Whale Oil/Pitch'),
    ('Lübeck–London',       'Lübeck',    'London',        1050,  9, 'Cloth/Wool long route'),
    ('Hamburg–Brugge',      'Hamburg',   'Brugge',         600,  5, 'Cloth/Wool/Salt west'),
    ('Hamburg–Groningen',   'Hamburg',   'Groningen',      250,  2, 'Hemp/Bricks/Grain'),
    ('Gdansk–Riga',         'Gdansk',    'Riga',           280,  2, 'Grain/Salt Baltic'),
    ('Gdansk–Novgorod',     'Gdansk',    'Novgorod',       500,  4, 'Skins/Timber east'),
    ('Stockholm–Ladoga',    'Stockholm', 'Ladoga',         450,  4, 'Pig Iron/Skins'),
    ('Oslo–Aalborg',        'Oslo',      'Aalborg',        300,  3, 'Timber/Whale Oil'),
    ('Riga–Reval',          'Riga',      'Reval',          200,  2, 'Salt/Skins/Grain Baltic'),
    ('Reval–Novgorod',      'Reval',     'Novgorod',       280,  2, 'Skins/Timber east'),
    ('London–Scarborough',  'London',    'Scarborough',    300,  3, 'Cloth/Wool/Beer British'),
    ('Bergen–Scarborough',  'Bergen',    'Scarborough',    600,  5, 'Whale Oil to Britain'),
    ('Visby–Gdansk',        'Visby',     'Gdansk',         220,  2, 'Cloth/Honey/Pottery'),
    ('Visby–Lübeck',        'Visby',     'Lübeck',         420,  4, 'Cloth/Wool loop'),
    ('Brugge–London',       'Brugge',    'London',         280,  2, 'Cloth/Salt/Spices'),
    ('Cologne–Brugge',      'Cologne',   'Brugge',         240,  2, 'Wine/Honey Rhine'),
-- Mediterranean (P4)
    ('Venice–Genoa',        'Venice',    'Genoa',          500,  3, 'Silk/Glass/Wine'),
    ('Genoa–Marseille',     'Genoa',     'Marseille',      280,  2, 'Spices/Olive Oil'),
    ('Marseille–Barcelona', 'Marseille', 'Barcelona',      400,  3, 'Wine/Cloth/Spices'),
    ('Barcelona–Lisbon',    'Barcelona', 'Lisbon',         800,  6, 'Atlantic gateway'),
    ('Venice–Constantinople','Venice',   'Constantinople', 1400,  9, 'Silk/Spices luxury run'),
    ('Genoa–Tunis',         'Genoa',     'Tunis',          600,  4, 'Spices/Leather/Ivory'),
    ('Marseille–Naples',    'Marseille', 'Naples',         600,  4, 'Olive Oil/Wine south'),
    ('Naples–Palermo',      'Naples',    'Palermo',        280,  2, 'Grain/Salt Sicily'),
    ('Genoa–Alexandria',    'Genoa',     'Alexandria',    1800, 12, 'Cotton/Ivory/Dates far east'),
    ('Lisbon–London',       'Lisbon',    'London',        1200,  8, 'Connects Med to Hanse')
ON CONFLICT DO NOTHING;
SQL
    success "Routes seeded (20 Hanseatic + 10 Mediterranean)."
}

# ── Building types ────────────────────────────────────────────────────────
p3_seed_building_types() {
    info "Seeding building types (daily production + daily maintenance)…"
    p3_psql <<'SQL'
INSERT INTO p3_building_types
    (name, output_good_id, input_good_id, input_units_per_output,
     base_production, construction_cost, daily_maintenance, notes)
SELECT bt.name, g_out.good_id, g_in.good_id,
       bt.input_u, bt.prod, bt.cost, bt.maint, bt.notes
FROM (VALUES
-- ── Patrician III buildings ───────────────────────────────────────────────
-- name                       out_good      in_good   input_u   prod    cost    maint/day  notes
 ('Grain Farm',       'Grain',      NULL,         0.000, 0.233,  5000,  25.67, 'Raw — Hamburg/Gdansk/Stettin'),
 ('Hemp Farm',        'Hemp',       NULL,         0.000, 0.058,  4000,  25.67, 'Raw — Brugge/Groningen/Hamburg'),
 ('Sheep Farm',       'Wool',       NULL,         0.000, 0.117,  6000, 112.00, 'Raw — London/Scarborough/Malmö'),
 ('Apiary',           'Honey',      NULL,         0.000, 0.467,  3000,  49.00, 'Raw — Cologne/Rostock/Torun'),
 ('Vineyard',         'Wine',       NULL,         0.000, 0.467,  8000,  98.00, 'Raw — Cologne best; Med even better'),
 ('Sawmill',          'Timber',     NULL,         0.000, 0.467,  2500,  28.00, 'Raw — Oslo/Novgorod/Stockholm'),
 ('Iron Smelter',     'Pig Iron',   NULL,         0.000, 0.117, 10000, 112.00, 'Raw — Oslo/London/Ladoga'),
 ('Saltworks',        'Salt',       NULL,         0.000, 1.167,  4000,  30.33, 'Raw — Ripen/Riga/Reval. Very high output'),
 ('Pottery Workshop', 'Pottery',    NULL,         0.000, 0.467,  5000,  84.00, 'Finished — Cologne/Rostock/Visby'),
 ('Pitchmaker',       'Pitch',      NULL,         0.000, 0.233,  2000,  12.83, 'Finished — Oslo/Bergen/Novgorod'),
 ('Brickworks',       'Bricks',     NULL,         0.000, 0.233,  2000,  12.83, 'Finished — Bremen/Groningen/Lübeck'),
 ('Hunting Lodge',    'Skins',      NULL,         0.000, 0.233,  7000, 168.00, 'Raw — Riga/Reval/Novgorod/Ladoga'),
 ('Cattle Farm',      'Meat',       NULL,         0.000, 0.058, 10000, 114.33, 'Raw — London/Aalborg/Malmö. Slow, high value'),
 ('Fishery',          'Fish',       'Salt',       0.050, 0.233,  6000,  84.00, 'Needs Salt — Hamburg/Edinburgh/Lübeck'),
 ('Whaling Station',  'Whale Oil',  NULL,         0.000, 0.933,  8000, 140.00, 'Finished — Ripen/Bergen/Oslo/Aalborg'),
 ('Brewery',          'Beer',       'Grain',      0.140, 1.633,  8000,  60.67, 'Grain→Beer — Hamburg/Gdansk/Bremen. Highest output'),
 ('Weaving Mill',     'Cloth',      'Wool',       0.100, 0.700,  9000, 102.67, 'Wool→Cloth — London/Scarborough/Malmö'),
 ('Iron Goods Workshop','Iron Goods','Pig Iron',  0.500, 0.700, 12000, 121.33, 'Pig Iron→Iron Goods — Lübeck/Bremen/Reval. Best margin'),
-- ── Patrician IV Mediterranean buildings ─────────────────────────────────
 ('Olive Grove',      'Olive Oil',  NULL,         0.000, 0.350,  6000,  45.00, 'P4 — Venice/Genoa/Marseille/Naples'),
 ('Winery (Med)',     'Wine',       NULL,         0.000, 0.583,  8000,  98.00, 'P4 — higher output than Rhine vineyard'),
 ('Silk Workshop',    'Silk',       NULL,         0.000, 0.117, 15000, 280.00, 'P4 — top-tier luxury; Constantinople best'),
 ('Spice Warehouse',  'Spices',     NULL,         0.000, 0.150, 12000, 200.00, 'P4 — redistributes imported spices'),
 ('Glassworks',       'Glass',      'Sand',       0.200, 0.280,  9000, 120.00, 'P4 — Venice specialty; needs Sand input'),
 ('Cotton Gin',       'Cotton',     NULL,         0.000, 0.400,  5000,  55.00, 'P4 — Barcelona/Alexandria/Palermo'),
 ('Alum Works',       'Alum',       NULL,         0.000, 0.240,  8000,  90.00, 'P4 — Constantinople/Genoa; dyeing agent')
) AS bt(name, out_good, in_good, input_u, prod, cost, maint, notes)
JOIN p3_goods g_out ON g_out.name = bt.out_good
LEFT JOIN p3_goods g_in ON g_in.name = bt.in_good
ON CONFLICT (name) DO UPDATE SET
    base_production   = EXCLUDED.base_production,
    construction_cost = EXCLUDED.construction_cost,
    daily_maintenance = EXCLUDED.daily_maintenance,
    notes             = EXCLUDED.notes;
SQL
    success "Building types seeded (18 P3 + 6 P4 = 24 total)."
}

# ── Elasticity ────────────────────────────────────────────────────────────
p3_seed_elasticity() {
    info "Seeding marginal price elasticity…"
    p3_psql <<'SQL'
INSERT INTO p3_good_elasticity
    (good_id, elasticity_buy, elasticity_sell, stock_ref, price_floor_pct, price_ceil_pct)
SELECT g.good_id,
       CASE g.name
           WHEN 'Ivory'      THEN 0.75
           WHEN 'Silk'       THEN 0.70
           WHEN 'Skins'      THEN 0.65
           WHEN 'Spices'     THEN 0.60
           WHEN 'Wool'       THEN 0.55
           WHEN 'Cloth'      THEN 0.55
           WHEN 'Iron Goods' THEN 0.50
           WHEN 'Meat'       THEN 0.50
           WHEN 'Glass'      THEN 0.48
           WHEN 'Olive Oil'  THEN 0.45
           WHEN 'Whale Oil'  THEN 0.45
           WHEN 'Pig Iron'   THEN 0.45
           WHEN 'Wine'       THEN 0.45
           WHEN 'Alum'       THEN 0.42
           WHEN 'Cotton'     THEN 0.40
           WHEN 'Honey'      THEN 0.40
           WHEN 'Dates'      THEN 0.38
           WHEN 'Pottery'    THEN 0.38
           WHEN 'Hemp'       THEN 0.35
           WHEN 'Leather'    THEN 0.35
           WHEN 'Beer'       THEN 0.30
           WHEN 'Fish'       THEN 0.30
           WHEN 'Grain'      THEN 0.25
           WHEN 'Timber'     THEN 0.25
           WHEN 'Salt'       THEN 0.22
           WHEN 'Bricks'     THEN 0.20
           WHEN 'Pitch'      THEN 0.20
           WHEN 'Sand'       THEN 0.10
           ELSE 0.35
       END AS elasticity_buy,
       CASE g.name
           WHEN 'Ivory'      THEN 0.65
           WHEN 'Silk'       THEN 0.60
           WHEN 'Skins'      THEN 0.55
           WHEN 'Spices'     THEN 0.50
           WHEN 'Wool'       THEN 0.45
           WHEN 'Cloth'      THEN 0.45
           WHEN 'Iron Goods' THEN 0.40
           WHEN 'Meat'       THEN 0.40
           WHEN 'Glass'      THEN 0.38
           WHEN 'Olive Oil'  THEN 0.35
           WHEN 'Wine'       THEN 0.35
           WHEN 'Beer'       THEN 0.22
           WHEN 'Grain'      THEN 0.18
           WHEN 'Salt'       THEN 0.15
           WHEN 'Sand'       THEN 0.08
           ELSE 0.28
       END AS elasticity_sell,
       CASE
           WHEN g.is_raw_material THEN 120
           ELSE 80
       END AS stock_ref,
       0.30 AS price_floor_pct,
       3.50 AS price_ceil_pct
FROM p3_goods g
ON CONFLICT (good_id) DO UPDATE SET
    elasticity_buy  = EXCLUDED.elasticity_buy,
    elasticity_sell = EXCLUDED.elasticity_sell,
    stock_ref       = EXCLUDED.stock_ref;
SQL
    success "Elasticity seeded for all 28 goods."
}

# ── Hex city placement (POINTY-TOP) ──────────────────────────────────────
p3_seed_hex_cities() {
    info "Placing cities on pointy-top hex grid…"
    p3_psql <<'SQL'
-- =============================================================================
--  POINTY-TOP AXIAL COORDINATES  (q, r)
--  Reference: https://www.redblobgames.com/grids/hexagons/implementation.html
--
--  Origin: Lübeck (0, 0)  — 53.8655°N, 10.6866°E
--  Scale:  1 hex ≈ 50 nautical miles
--
--  Conversion from geographic coordinates:
--    At 54°N:  1° lon ≈ 35.38 nm  →  50 nm / 35.38 nm/° = 1.413°/hex (E–W)
--              1° lat ≈ 60.00 nm  →  50 nm / 60.00 nm/° = 0.833°/hex (N–S)
--    q = ROUND( (lon - 10.687) / 1.413 )    — positive q = east
--    r = ROUND( (53.866 - lat) / 0.833 )    — positive r = south
--
--  City coordinates verified against actual lat/lon.
--  Hamburg (53.55°N, 10.00°E) rounds to the same hex as Lübeck at 50nm scale
--  (they are only 65 km / 35 nm apart), so Hamburg is placed at (-1, 0),
--  one hex due west — geographically accurate for a terminal separation.
--
--  Neighbour directions (pointy-top, for reference):
--    (+1, 0)  E    (+1,-1) NE    (0,-1) NW
--    (-1, 0)  W    (-1,+1) SW    (0,+1) SE
-- =============================================================================
WITH city_coords(city_name, q, r) AS (VALUES
    -- ── Hanseatic Baltic ─────────────────────────────────────────────────
    --                         q    r     lat      lon
    ('Lübeck',                 0,   0),  -- 53.87N  10.69E  origin
    ('Hamburg',               -1,   0),  -- 53.55N  10.00E  35nm W of Lübeck; manual offset
    ('Rostock',                1,   0),  -- 54.09N  12.14E
    ('Stettin',                3,   1),  -- 53.43N  14.55E
    ('Gdansk',                 6,  -1),  -- 54.35N  18.65E
    ('Riga',                   9,  -4),  -- 56.95N  24.11E
    ('Reval',                 10,  -7),  -- 59.44N  24.75E  (Tallinn)
    ('Novgorod',              15,  -6),  -- 58.53N  31.28E
    ('Stockholm',              5,  -7),  -- 59.33N  18.07E
    ('Visby',                  5,  -5),  -- 57.63N  18.29E
    ('Malmö',                  2,  -2),  -- 55.61N  13.00E
    -- ── Scandinavia & North Sea ──────────────────────────────────────────
    ('Bergen',                -4,  -8),  -- 60.39N   5.32E
    ('Oslo',                   0,  -7),  -- 59.91N  10.75E
    ('Aalborg',               -1,  -4),  -- 57.05N   9.92E
    ('Ripen',                 -1,  -2),  -- 55.34N   9.79E  (Ribe)
    -- ── British Isles ────────────────────────────────────────────────────
    ('Scarborough',           -8,   0),  -- 54.28N  -0.40E
    ('Edinburgh',            -10,  -3),  -- 55.95N  -3.19E
    ('London',                -8,   3),  -- 51.51N  -0.13E
    -- ── Rhine & Low Countries ────────────────────────────────────────────
    ('Brugge',                -5,   3),  -- 51.21N   3.22E
    ('Groningen',             -3,   1),  -- 53.22N   6.57E
    ('Bremen',                -1,   1),  -- 53.08N   8.80E
    ('Cologne',               -3,   4),  -- 50.93N   6.95E
    -- ── Eastern Baltic ───────────────────────────────────────────────────
    ('Torun',                  6,   1),  -- 53.01N  18.61E
    ('Ladoga',                15,  -7),  -- 60.00N  32.30E
    -- ── Mediterranean (P4) ───────────────────────────────────────────────
    --  These share the same coordinate space as the Hanseatic map,
    --  falling naturally below (positive r = south) and slightly east/west.
    ('Venice',                 1,  10),  -- 45.44N  12.32E
    ('Genoa',                 -1,  11),  -- 44.41N   8.95E
    ('Marseille',             -4,  13),  -- 43.30N   5.37E
    ('Barcelona',             -6,  15),  -- 41.39N   2.17E
    ('Lisbon',               -14,  18),  -- 38.72N  -9.14E
    ('Constantinople',        13,  15),  -- 41.01N  28.98E
    ('Naples',                 3,  16),  -- 40.85N  14.27E
    ('Palermo',                2,  19),  -- 38.12N  13.36E
    ('Tunis',                  0,  20),  -- 36.81N  10.18E
    ('Alexandria',            14,  27)   -- 31.20N  29.92E
)
UPDATE p3_cities ci
SET    hex_q = cc.q,
       hex_r = cc.r
FROM   city_coords cc
WHERE  ci.name = cc.city_name;

-- Create hex tiles for each placed city
INSERT INTO p3_hex_tiles (q, r, terrain, city_id)
SELECT ci.hex_q, ci.hex_r,
       CASE
           WHEN ci.name IN ('Novgorod','Groningen','Bremen','Cologne','Torun','Ladoga',
                            'Constantinople','Alexandria','Tunis')
               THEN 'land'
           ELSE 'coast'
       END,
       ci.city_id
FROM p3_cities ci
WHERE ci.hex_q IS NOT NULL
ON CONFLICT (q, r) DO UPDATE
    SET city_id = EXCLUDED.city_id,
        terrain  = EXCLUDED.terrain;
SQL
    success "Cities placed on pointy-top hex grid (24 Baltic + 10 Mediterranean)."
}

# ── Player + starting ship ────────────────────────────────────────────────
p3_seed_player() {
    local cnt
    cnt=$(p3_psql --tuples-only -c "SELECT COUNT(*) FROM p3_player;" | tr -d ' ')
    if [[ "$cnt" == "0" ]]; then
        p3_psql -c "INSERT INTO p3_player (name, home_city, gold, rank, game_year, game_day)
                    VALUES ('Merchant', 'Lübeck', 2000, 'Apprentice', 1300, 1);"
        success "Player created — 2 000 gold, home city Lübeck, Year 1300 Day 1."
    else
        info "Player already exists."
    fi
}

p3_seed_starting_ship() {
    local cnt
    cnt=$(p3_psql --tuples-only -c "SELECT COUNT(*) FROM p3_ships WHERE owner='player';" | tr -d ' ')
    if [[ "$cnt" == "0" ]]; then
        p3_psql -c "INSERT INTO p3_ships
                        (name, owner, ship_type, cargo_cap, speed_knots, current_city, status)
                    VALUES ('Henrietta', 'player', 'Snaikka', 50, 5.0, 'Lübeck', 'docked');"
        success "Starting ship 'Henrietta' (Snaikka, 50 cargo, 5 kn) created in Lübeck."
    fi
}

# ── Drop all tables / views / functions (hard reset) ─────────────────────
p3_drop_tables() {
    info "Dropping all Patrician III + IV objects…"
    p3_psql <<'SQL'
-- Views first (depend on tables)
DROP VIEW IF EXISTS p3_arbitrage_view CASCADE;
DROP VIEW IF EXISTS p3_market_view    CASCADE;
DROP VIEW IF EXISTS p3_fleet_view     CASCADE;

-- Functions
DROP FUNCTION IF EXISTS p3_marginal_price(INT,INT,TEXT,INT,INT) CASCADE;
DROP FUNCTION IF EXISTS p3_travel_days(INT,INT,NUMERIC)         CASCADE;
DROP FUNCTION IF EXISTS p3_hex_neighbors(INT,INT)               CASCADE;
DROP FUNCTION IF EXISTS p3_hex_distance(INT,INT,INT,INT)        CASCADE;

-- Tables in reverse-FK order (CASCADE handles any stragglers)
DROP TABLE IF EXISTS p3_trade_log        CASCADE;
DROP TABLE IF EXISTS p3_limit_orders     CASCADE;
DROP TABLE IF EXISTS p3_ship_orders      CASCADE;
DROP TABLE IF EXISTS p3_ship_routes      CASCADE;
DROP TABLE IF EXISTS p3_route_orders     CASCADE;
DROP TABLE IF EXISTS p3_routes           CASCADE;
DROP TABLE IF EXISTS p3_cargo            CASCADE;
DROP TABLE IF EXISTS p3_ships            CASCADE;
DROP TABLE IF EXISTS p3_player_buildings CASCADE;
DROP TABLE IF EXISTS p3_building_types   CASCADE;
DROP TABLE IF EXISTS p3_price_history    CASCADE;
DROP TABLE IF EXISTS p3_market           CASCADE;
DROP TABLE IF EXISTS p3_city_goods       CASCADE;
DROP TABLE IF EXISTS p3_hex_tiles        CASCADE;
DROP TABLE IF EXISTS p3_good_elasticity  CASCADE;
DROP TABLE IF EXISTS p3_cities           CASCADE;
DROP TABLE IF EXISTS p3_goods            CASCADE;
DROP TABLE IF EXISTS p3_player           CASCADE;
SQL
    success "All Patrician objects dropped."
}

# ── Full setup ────────────────────────────────────────────────────────────
p3_setup_all() {
    p3_drop_tables
    p3_create_tables
    p3_seed_goods
    p3_seed_cities
    p3_seed_p4_cities
    p3_seed_city_goods
    p3_seed_p4_city_goods
    p3_seed_market
    p3_seed_routes
    p3_seed_building_types
    p3_seed_elasticity
    p3_seed_hex_cities
    p3_seed_player
    p3_seed_starting_ship
    echo
    success "✅  Patrician III + IV fully initialised!"
    info    "    Hanseatic cities: 24  |  Mediterranean cities: 10"
    info    "    Goods: 28 (20 Hanse + 8 Med)  |  Building types: 24"
    info    "    Hex system: pointy-top axial, 1 hex ≈ 50 nm, origin Lübeck (0,0)"
    info    "    Ship types: Snaikka(50,5kn) Crayer(80,7kn) Hulk(160,4kn)"
    info    "                Cog(120,6kn) Galley(90,9kn) Carrack(220,5.5kn)"
    info    "    Starting: 2000 gold, ship 'Henrietta' in Lübeck, Year 1300 Day 1"
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14c  ADVANCE DAY  (replaces p3_advance_month)
# ─────────────────────────────────────────────────────────────────────────────
p3_advance_day() {

    # 1. Tick ships — 1 day per call
    p3_psql -c "
        UPDATE p3_ships SET eta_days = eta_days - 1
        WHERE  status = 'sailing' AND eta_days > 0;

        UPDATE p3_ships
        SET    status = 'docked', current_city = destination,
               destination = NULL, eta_days = 0
        WHERE  status = 'sailing' AND eta_days <= 0;
    " >/dev/null

    # 2. Log arrivals (once per ship per day)
    p3_psql -c "
        INSERT INTO p3_trade_log
            (game_year, game_day, ship_id, ship_name, city, action, logged_at)
        SELECT pl.game_year, pl.game_day, s.ship_id, s.name, s.current_city, 'arrive', NOW()
        FROM   p3_ships s, p3_player pl
        WHERE  s.owner  = 'player' AND s.status = 'docked' AND s.eta_days = 0
          AND  NOT EXISTS (
              SELECT 1 FROM p3_trade_log tl
              WHERE  tl.ship_id   = s.ship_id AND tl.action = 'arrive'
                AND  tl.game_year = pl.game_year AND tl.game_day = pl.game_day
          );
    " >/dev/null 2>&1 || true

    # 3. Daily production
    #    base_production = units/day; efficiency scales it; 0.17% daily consumption
    p3_psql -c "
        UPDATE p3_market m
        SET    stock = LEAST(500,
                   GREATEST(0,
                       m.stock
                       + COALESCE((
                           SELECT FLOOR(g.base_production * cg.efficiency / 100.0)::INTEGER
                           FROM   p3_city_goods cg
                           JOIN   p3_goods      g ON g.good_id = cg.good_id
                           WHERE  cg.city_id = m.city_id AND cg.good_id = m.good_id
                             AND  cg.role = 'produces'
                         ), 0)
                       - GREATEST(1, ROUND((m.stock * 0.0017)::NUMERIC, 0)::INTEGER)
                   ))
        WHERE  m.stock > 0 OR EXISTS (
            SELECT 1 FROM p3_city_goods cg
            WHERE cg.city_id = m.city_id AND cg.good_id = m.good_id AND cg.role = 'produces'
        );
    " >/dev/null

    # 4. Daily price tick — 1/30th of monthly pressure, per-unit elasticity preserved
    p3_psql -c "
        UPDATE p3_market m
        SET current_sell = GREATEST(1::NUMERIC, ROUND(new_mid * 0.92, 2)),
            current_buy  = GREATEST(1::NUMERIC, ROUND(new_mid * 1.08, 2))
        FROM (
            SELECT m2.city_id, m2.good_id,
                ROUND(
                    ((m2.current_buy / 1.08 + m2.current_sell / 0.92) / 2.0)
                    * CASE
                        WHEN m2.stock < 20  THEN 1.0027::NUMERIC
                        WHEN m2.stock < 50  THEN 1.0010::NUMERIC
                        WHEN m2.stock > 200 THEN 0.9990::NUMERIC
                        WHEN m2.stock > 350 THEN 0.9977::NUMERIC
                        ELSE 1.0000::NUMERIC
                      END
                    * (0.9987::NUMERIC + (RANDOM()::NUMERIC) * 0.0026::NUMERIC)
                    * CASE
                        WHEN ((m2.current_buy/1.08 + m2.current_sell/0.92)/2.0)
                             > g.buy_price_min * 1.5 THEN 0.9990::NUMERIC
                        WHEN ((m2.current_buy/1.08 + m2.current_sell/0.92)/2.0)
                             < g.buy_price_min * 0.5 THEN 1.0010::NUMERIC
                        ELSE 1.0000::NUMERIC
                      END,
                2) AS new_mid
            FROM p3_market m2 JOIN p3_goods g ON g.good_id = m2.good_id
        ) e
        WHERE e.city_id = m.city_id AND e.good_id = m.good_id;
    " >/dev/null

    # 5. Snapshot price history every 10 days
    p3_psql -c "
        INSERT INTO p3_price_history
            (city_id, good_id, game_year, game_day, buy_price, sell_price, stock)
        SELECT m.city_id, m.good_id, pl.game_year, pl.game_day,
               m.current_buy, m.current_sell, m.stock
        FROM   p3_market m, p3_player pl
        WHERE  (pl.game_day % 10) = 0
        ON CONFLICT DO NOTHING;
    " >/dev/null 2>&1 || true

    # 6. Route standing orders
    p3_psql -c "
        DO \$\$
        DECLARE r RECORD; v_free INTEGER; v_qty INTEGER; v_total NUMERIC; v_gold NUMERIC;
        BEGIN
            FOR r IN
                SELECT sr.ship_id, ro.good_id, ro.quantity, ro.max_price,
                       m.current_buy, ci.city_id, m.stock AS mstock
                FROM   p3_ship_routes sr
                JOIN   p3_routes rt ON rt.route_id = sr.route_id AND sr.active
                JOIN   p3_route_orders ro ON ro.route_id = rt.route_id AND ro.action = 'buy'
                JOIN   p3_ships s ON s.ship_id = sr.ship_id AND s.status = 'docked'
                                 AND s.current_city = ro.city
                JOIN   p3_cities ci ON ci.name = s.current_city
                JOIN   p3_market m  ON m.city_id = ci.city_id AND m.good_id = ro.good_id
                WHERE (ro.max_price IS NULL OR m.current_buy <= ro.max_price) AND m.stock > 0
            LOOP
                SELECT cargo_free INTO v_free FROM p3_fleet_view WHERE ship_id = r.ship_id;
                v_qty := LEAST(r.quantity, v_free, r.mstock);
                v_total := r.current_buy * v_qty;
                SELECT gold INTO v_gold FROM p3_player;
                CONTINUE WHEN v_qty <= 0 OR v_gold < v_total;
                INSERT INTO p3_cargo (ship_id, good_id, quantity) VALUES (r.ship_id, r.good_id, v_qty)
                    ON CONFLICT (ship_id, good_id)
                    DO UPDATE SET quantity = p3_cargo.quantity + EXCLUDED.quantity;
                UPDATE p3_market SET stock = stock - v_qty
                    WHERE city_id = r.city_id AND good_id = r.good_id;
                UPDATE p3_player SET gold = gold - v_total;
            END LOOP;
        END;
        \$\$;
    " >/dev/null 2>&1 || true

    # 6.5. Buildings + limit orders
    p3_process_production_and_orders_daily

    # 7. Advance calendar
    p3_psql -c "
        UPDATE p3_player
        SET game_day  = CASE WHEN game_day >= 360 THEN 1 ELSE game_day + 1 END,
            game_year = CASE WHEN game_day >= 360 THEN game_year + 1 ELSE game_year END;
    " >/dev/null

    local yd
    yd=$(p3_psql --tuples-only -c \
        "SELECT 'Year '||game_year||'  Day '||LPAD(game_day::text,3,'0') FROM p3_player;" \
        | tr -d ' ')
    success "Day advanced → $yd"
}

# ── Building production + limit orders (daily) ───────────────────────────
p3_process_production_and_orders_daily() {
    p3_psql <<'SQL' >/dev/null 2>&1
DO $$
DECLARE
    rec          RECORD;
    input_avail  NUMERIC;
    input_needed NUMERIC;
    actual_prod  NUMERIC;
BEGIN
    FOR rec IN
        SELECT pb.city_id, bt.output_good_id, bt.input_good_id,
               bt.input_units_per_output,
               (bt.base_production * pb.num_buildings)   AS prod_amt,
               (bt.daily_maintenance * pb.num_buildings) AS maint_cost
        FROM p3_player_buildings pb
        JOIN p3_building_types bt ON bt.building_type_id = pb.building_type_id
    LOOP
        UPDATE p3_player SET gold = GREATEST(0, gold - rec.maint_cost);
        actual_prod := 0;
        IF rec.input_good_id IS NULL THEN
            actual_prod := rec.prod_amt;
        ELSE
            SELECT COALESCE(stock, 0) INTO input_avail
            FROM p3_market WHERE city_id = rec.city_id AND good_id = rec.input_good_id;
            input_needed := rec.prod_amt * rec.input_units_per_output;
            IF input_avail >= input_needed THEN
                UPDATE p3_market SET stock = GREATEST(0, stock - FLOOR(input_needed)::INTEGER)
                WHERE city_id = rec.city_id AND good_id = rec.input_good_id;
                actual_prod := rec.prod_amt;
            ELSIF input_avail > 0 THEN
                actual_prod := input_avail / rec.input_units_per_output;
                UPDATE p3_market SET stock = 0
                WHERE city_id = rec.city_id AND good_id = rec.input_good_id;
            END IF;
        END IF;
        IF actual_prod > 0 THEN
            UPDATE p3_market SET stock = LEAST(500, stock + FLOOR(actual_prod)::INTEGER)
            WHERE city_id = rec.city_id AND good_id = rec.output_good_id;
        END IF;
    END LOOP;
END $$;
SQL
    p3_psql <<'SQL' >/dev/null 2>&1
DO $$
DECLARE
    o RECORD; fulfill INTEGER; v_free INTEGER; v_cargo INTEGER;
BEGIN
    FOR o IN
        SELECT lo.*, s.current_city, s.status, m.current_buy, m.current_sell, m.stock
        FROM p3_limit_orders lo
        JOIN p3_ships  s ON s.ship_id = lo.ship_id
        JOIN p3_market m ON m.city_id = lo.city_id AND m.good_id = lo.good_id
        WHERE lo.active AND lo.remaining_quantity > 0 AND s.status = 'docked'
          AND s.current_city = (SELECT name FROM p3_cities WHERE city_id = lo.city_id)
    LOOP
        IF o.action = 'buy' AND o.current_buy <= o.price_limit THEN
            SELECT cargo_free INTO v_free FROM p3_fleet_view WHERE ship_id = o.ship_id;
            fulfill := LEAST(o.remaining_quantity, COALESCE(v_free, 0), o.stock, 5);
            IF fulfill > 0 THEN
                INSERT INTO p3_cargo (ship_id, good_id, quantity)
                    VALUES (o.ship_id, o.good_id, fulfill)
                    ON CONFLICT (ship_id, good_id)
                    DO UPDATE SET quantity = p3_cargo.quantity + fulfill;
                UPDATE p3_market SET stock = stock - fulfill
                    WHERE city_id = o.city_id AND good_id = o.good_id;
                UPDATE p3_player SET gold = gold - (o.current_buy * fulfill);
                UPDATE p3_limit_orders SET remaining_quantity = remaining_quantity - fulfill
                    WHERE order_id = o.order_id;
            END IF;
        ELSIF o.action = 'sell' AND o.current_sell >= o.price_limit THEN
            SELECT quantity INTO v_cargo FROM p3_cargo
                WHERE ship_id = o.ship_id AND good_id = o.good_id;
            fulfill := LEAST(o.remaining_quantity, COALESCE(v_cargo, 0), 5);
            IF fulfill > 0 THEN
                UPDATE p3_cargo SET quantity = quantity - fulfill
                    WHERE ship_id = o.ship_id AND good_id = o.good_id;
                DELETE FROM p3_cargo
                    WHERE ship_id = o.ship_id AND good_id = o.good_id AND quantity <= 0;
                UPDATE p3_market SET stock = stock + fulfill
                    WHERE city_id = o.city_id AND good_id = o.good_id;
                UPDATE p3_player SET gold = gold + (o.current_sell * fulfill);
                UPDATE p3_limit_orders SET remaining_quantity = remaining_quantity - fulfill
                    WHERE order_id = o.order_id;
            END IF;
        END IF;
        UPDATE p3_limit_orders SET active = FALSE
            WHERE order_id = o.order_id AND remaining_quantity <= 0;
    END LOOP;
END $$;
SQL
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14d  SAIL ORDER  (speed-aware ETA)
# ─────────────────────────────────────────────────────────────────────────────
p3_sail_ship() {
    local sid="$1" dest="$2"
    local scity status spd

    scity=$(p3_psql --tuples-only -c "SELECT current_city FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
    status=$(p3_psql --tuples-only -c "SELECT status       FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
    spd=$(p3_psql --tuples-only -c    "SELECT speed_knots  FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')

    [[ "$status" != "docked" ]] && { error "$scity ship is $status."; return 1; }

    # ETA = distance_nm / (speed_knots * 24)  — faster ships arrive sooner
    local eta
    eta=$(p3_psql --tuples-only -c "
        SELECT GREATEST(1, ROUND(distance_nm::NUMERIC / ($spd * 24.0))::INTEGER)
        FROM p3_routes
        WHERE (city_a = '$scity' AND city_b = '$dest')
           OR (city_b = '$scity' AND city_a = '$dest')
        ORDER BY distance_nm LIMIT 1;" | tr -d ' ')

    # Fallback to hex distance if no route defined
    if [[ -z "$eta" || "$eta" == "0" ]]; then
        eta=$(p3_psql --tuples-only -c "
            SELECT COALESCE(p3_travel_days(
                (SELECT city_id FROM p3_cities WHERE name = '$scity'),
                (SELECT city_id FROM p3_cities WHERE name = '$dest'),
                $spd::NUMERIC
            ), 7);" | tr -d ' ')
    fi
    [[ -z "$eta" || "$eta" == "0" ]] && eta=7

    p3_psql -c "
        UPDATE p3_ships SET status = 'sailing', destination = '$dest', eta_days = $eta
        WHERE ship_id = $sid;" >/dev/null
    p3_psql -c "
        INSERT INTO p3_trade_log (game_year, game_day, ship_id, ship_name, city, action, logged_at)
        SELECT pl.game_year, pl.game_day, $sid,
               (SELECT name FROM p3_ships WHERE ship_id = $sid), '$scity', 'depart', NOW()
        FROM p3_player pl;" >/dev/null
    success "⛵  Sailing to $dest — ETA ${eta} day(s)  (${spd} kn)"
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14e  BUY  (per-unit marginal pricing)
# ─────────────────────────────────────────────────────────────────────────────
p3_do_buy() {
    local sid="$1" good="$2" qty="$3" scity="$4"
    p3_psql -c "
    DO \$\$
    DECLARE
        v_mid NUMERIC; v_stock INTEGER; v_stock_ref INTEGER; v_elast NUMERIC;
        v_floor_pct NUMERIC; v_ceil_pct NUMERIC; v_total NUMERIC; v_avg NUMERIC;
        v_gold NUMERIC; v_gid INTEGER; v_cid INTEGER; v_free INTEGER;
        i INTEGER; unit_price NUMERIC; new_mid NUMERIC; ref_mid NUMERIC;
    BEGIN
        SELECT g.good_id, ci.city_id,
               (m.current_buy/1.08 + m.current_sell/0.92)/2.0,
               m.stock, (g.buy_price_min+g.sell_price_min)/2.0
        INTO   v_gid, v_cid, v_mid, v_stock, ref_mid
        FROM p3_market m
        JOIN p3_cities ci ON ci.city_id = m.city_id AND ci.name = '$scity'
        JOIN p3_goods  g  ON g.good_id  = m.good_id AND g.name  = '$good';

        SELECT COALESCE(e.elasticity_buy,0.40), COALESCE(e.stock_ref,100),
               COALESCE(e.price_floor_pct,0.30), COALESCE(e.price_ceil_pct,3.00)
        INTO   v_elast, v_stock_ref, v_floor_pct, v_ceil_pct
        FROM p3_goods g LEFT JOIN p3_good_elasticity e USING (good_id) WHERE g.good_id = v_gid;

        SELECT cargo_free INTO v_free FROM p3_fleet_view WHERE ship_id = $sid;
        SELECT gold INTO v_gold FROM p3_player;
        IF v_stock < $qty THEN RAISE EXCEPTION 'Not enough stock (have %, need %)', v_stock, $qty; END IF;
        IF v_free  < $qty THEN RAISE EXCEPTION 'Not enough cargo (free %, need %)', v_free,  $qty; END IF;

        -- Per-unit marginal cost loop
        v_total := 0;
        FOR i IN 0..($qty-1) LOOP
            unit_price := p3_marginal_price(v_cid, v_gid, 'buy', i,
                              (SELECT game_day FROM p3_player LIMIT 1));
            v_total := v_total + COALESCE(unit_price, 0);
        END LOOP;
        v_avg := ROUND(v_total/$qty, 2);

        IF v_gold < v_total THEN
            RAISE EXCEPTION 'Need %g total (avg %/unit), have %g', v_total, v_avg, v_gold;
        END IF;

        INSERT INTO p3_cargo (ship_id, good_id, quantity) VALUES ($sid, v_gid, $qty)
            ON CONFLICT (ship_id, good_id) DO UPDATE SET quantity = p3_cargo.quantity + EXCLUDED.quantity;

        new_mid := COALESCE(
            p3_marginal_price(v_cid, v_gid, 'buy', $qty,
                (SELECT game_day FROM p3_player LIMIT 1)) / 1.08,
            ROUND(v_mid * POWER(v_stock_ref::NUMERIC / GREATEST(v_stock - $qty, 1)::NUMERIC, v_elast), 2)
        );

        UPDATE p3_market SET stock = stock - $qty,
            current_buy  = GREATEST(1, ROUND(new_mid * 1.08, 2)),
            current_sell = GREATEST(1, ROUND(new_mid * 0.92, 2))
        WHERE city_id = v_cid AND good_id = v_gid;

        UPDATE p3_player SET gold = gold - v_total;

        INSERT INTO p3_trade_log
            (game_year, game_day, ship_id, ship_name, city, good_id, good_name,
             action, quantity, price, total_value, gold_after)
        SELECT pl.game_year, pl.game_day, $sid,
               (SELECT name FROM p3_ships WHERE ship_id = $sid),
               '$scity', v_gid, '$good', 'buy', $qty, v_avg, v_total, pl.gold - v_total
        FROM p3_player pl;

        RAISE NOTICE 'Bought % × %  avg %g  total %g  (stock % → %)',
                     $qty, '$good', v_avg, v_total, v_stock, v_stock - $qty;
    END; \$\$;
    " 2>&1 | grep -E 'NOTICE|ERROR|error' || true
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14f  SELL  (per-unit marginal pricing)
# ─────────────────────────────────────────────────────────────────────────────
p3_do_sell() {
    local sid="$1" good="$2" qty="$3" scity="$4"
    p3_psql -c "
    DO \$\$
    DECLARE
        v_mid NUMERIC; v_stock INTEGER; v_stock_ref INTEGER; v_elast NUMERIC;
        v_floor_pct NUMERIC; v_ceil_pct NUMERIC; v_total NUMERIC; v_avg NUMERIC;
        v_aboard INTEGER; v_gid INTEGER; v_cid INTEGER;
        i INTEGER; unit_price NUMERIC; new_mid NUMERIC; ref_mid NUMERIC;
    BEGIN
        SELECT g.good_id, ci.city_id,
               (m.current_buy/1.08 + m.current_sell/0.92)/2.0,
               m.stock, (g.buy_price_min+g.sell_price_min)/2.0
        INTO   v_gid, v_cid, v_mid, v_stock, ref_mid
        FROM p3_market m
        JOIN p3_cities ci ON ci.city_id = m.city_id AND ci.name = '$scity'
        JOIN p3_goods  g  ON g.good_id  = m.good_id AND g.name  = '$good';

        SELECT COALESCE(e.elasticity_sell,0.30), COALESCE(e.stock_ref,100),
               COALESCE(e.price_floor_pct,0.30), COALESCE(e.price_ceil_pct,3.00)
        INTO   v_elast, v_stock_ref, v_floor_pct, v_ceil_pct
        FROM p3_goods g LEFT JOIN p3_good_elasticity e USING (good_id) WHERE g.good_id = v_gid;

        SELECT quantity INTO v_aboard FROM p3_cargo WHERE ship_id = $sid AND good_id = v_gid;
        IF COALESCE(v_aboard, 0) < $qty THEN
            RAISE EXCEPTION 'Not enough cargo (have %, need %)', COALESCE(v_aboard, 0), $qty;
        END IF;

        -- Per-unit marginal revenue loop
        v_total := 0;
        FOR i IN 0..($qty-1) LOOP
            unit_price := p3_marginal_price(v_cid, v_gid, 'sell', i,
                              (SELECT game_day FROM p3_player LIMIT 1));
            v_total := v_total + COALESCE(unit_price, 0);
        END LOOP;
        v_avg := ROUND(v_total/$qty, 2);

        UPDATE p3_cargo SET quantity = quantity - $qty WHERE ship_id = $sid AND good_id = v_gid;
        DELETE FROM p3_cargo WHERE ship_id = $sid AND good_id = v_gid AND quantity <= 0;

        new_mid := COALESCE(
            p3_marginal_price(v_cid, v_gid, 'sell', $qty,
                (SELECT game_day FROM p3_player LIMIT 1)) / 0.92,
            ROUND(v_mid * POWER(v_stock_ref::NUMERIC / GREATEST(v_stock + $qty, 1)::NUMERIC, v_elast), 2)
        );

        UPDATE p3_market SET stock = stock + $qty,
            current_buy  = GREATEST(1, ROUND(new_mid * 1.08, 2)),
            current_sell = GREATEST(1, ROUND(new_mid * 0.92, 2))
        WHERE city_id = v_cid AND good_id = v_gid;

        UPDATE p3_player SET gold = gold + v_total;

        INSERT INTO p3_trade_log
            (game_year, game_day, ship_id, ship_name, city, good_id, good_name,
             action, quantity, price, total_value, gold_after)
        SELECT pl.game_year, pl.game_day, $sid,
               (SELECT name FROM p3_ships WHERE ship_id = $sid),
               '$scity', v_gid, '$good', 'sell', $qty, v_avg, v_total, pl.gold + v_total
        FROM p3_player pl;

        RAISE NOTICE 'Sold % × %  avg %g  total %g  (stock % → %)',
                     $qty, '$good', v_avg, v_total, v_stock, v_stock + $qty;
    END; \$\$;
    " 2>&1 | grep -E 'NOTICE|ERROR|error' || true
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14m  REAL-TIME TICK DAEMON  (pg_notify + LISTEN integration)
#
#  Architecture:
#    _p3_tick_loop   — background bash loop; advances one game day every
#                      P3_TICK_INTERVAL seconds, then calls p3_notify_tick()
#                      which fires pg_notify('p3_day_tick', json_payload).
#    _p3_listen_loop — background psql LISTEN session; writes the JSON
#                      payload of each notification to P3_TICK_STATE_FILE
#                      so the dashboard can show the last-tick info without
#                      an extra DB round-trip.
#
#  External monitoring:  psql -c "LISTEN p3_day_tick;"
#                        (receives live JSON every simulated day)
# ─────────────────────────────────────────────────────────────────────────────
P3_TICK_PID_FILE="/tmp/p3_tick_${P3_DB:-traderdude}.pid"
P3_LISTEN_PID_FILE="/tmp/p3_listen_${P3_DB:-traderdude}.pid"
P3_TICK_STATE_FILE="/tmp/p3_tick_${P3_DB:-traderdude}.state"
P3_TICK_INTERVAL="${P3_TICK_INTERVAL:-10}"    # seconds per simulated game day

# ── Internal: background loop that advances the day ──────────────────────
_p3_tick_loop() {
    while true; do
        sleep "${P3_TICK_INTERVAL:-10}"
        # Advance ships, production, prices, calendar — then notify
        p3_psql <<'TKSQL' >/dev/null 2>&1 || true
-- Ship movement
UPDATE p3_ships SET eta_days = eta_days - 1
    WHERE status = 'sailing' AND eta_days > 0;
UPDATE p3_ships
    SET status = 'docked', current_city = destination, destination = NULL, eta_days = 0
    WHERE status = 'sailing' AND eta_days <= 0;
-- Daily stock tick
UPDATE p3_market m SET stock = LEAST(500, GREATEST(0,
    m.stock
    + COALESCE((SELECT FLOOR(g.base_production * cg.efficiency / 100.0)::INTEGER
                FROM p3_city_goods cg JOIN p3_goods g ON g.good_id = cg.good_id
                WHERE cg.city_id = m.city_id AND cg.good_id = m.good_id
                  AND cg.role = 'produces'), 0)
    - GREATEST(1, ROUND((m.stock * 0.0017)::NUMERIC, 0)::INTEGER)))
WHERE m.stock > 0 OR EXISTS (
    SELECT 1 FROM p3_city_goods cg
    WHERE cg.city_id = m.city_id AND cg.good_id = m.good_id AND cg.role = 'produces');
-- Daily price tick
UPDATE p3_market m
    SET current_sell = GREATEST(1, ROUND(e.new_mid * 0.92, 2)),
        current_buy  = GREATEST(1, ROUND(e.new_mid * 1.08, 2))
    FROM (SELECT m2.city_id, m2.good_id,
                 ROUND(((m2.current_buy / 1.08 + m2.current_sell / 0.92) / 2.0)
                 * CASE WHEN m2.stock <  20  THEN 1.0027
                        WHEN m2.stock <  50  THEN 1.0010
                        WHEN m2.stock > 350  THEN 0.9977
                        WHEN m2.stock > 200  THEN 0.9990 ELSE 1.0 END
                 * (0.9987 + RANDOM() * 0.0026), 2) AS new_mid
          FROM p3_market m2) e
    WHERE e.city_id = m.city_id AND e.good_id = m.good_id;
-- Advance calendar
UPDATE p3_player
    SET game_day  = CASE WHEN game_day >= 360 THEN 1      ELSE game_day + 1  END,
        game_year = CASE WHEN game_day >= 360 THEN game_year + 1 ELSE game_year END;
-- Fire pg_notify so any LISTEN client gets the event
SELECT p3_notify_tick();
TKSQL
        # Write last-tick state to file for dashboard (avoids an extra query)
        p3_psql --tuples-only -c "
            SELECT json_build_object(
                'year', game_year, 'day', game_day, 'gold', ROUND(gold, 2)
            )::text FROM p3_player LIMIT 1;" 2>/dev/null \
            | tr -d ' \n' > "$P3_TICK_STATE_FILE" || true
    done
}

# ── Internal: psql LISTEN session — writes each notification to state file
_p3_listen_loop() {
    # pg_sleep(86400) keeps the connection open for up to 24 h; psql prints
    # async notifications as they arrive on stdout, which we parse here.
    printf 'LISTEN p3_day_tick;\nSELECT pg_sleep(86400);\n' \
        | psql -X --username="$P3_USER" --dbname="$P3_DB" --no-readline 2>/dev/null \
        | while IFS= read -r line; do
              if [[ "$line" == *'p3_day_tick'* ]]; then
                  local payload
                  payload=$(grep -oE '\{[^}]+\}' <<< "$line" || true)
                  [[ -n "$payload" ]] && printf '%s' "$payload" > "$P3_TICK_STATE_FILE"
              fi
          done
}

p3_start_tick() {
    if [[ -f "$P3_TICK_PID_FILE" ]] && kill -0 "$(cat "$P3_TICK_PID_FILE")" 2>/dev/null; then
        warn "Tick daemon already running  (PID $(cat "$P3_TICK_PID_FILE"))."
        return
    fi
    _p3_tick_loop &
    echo $! > "$P3_TICK_PID_FILE"
    _p3_listen_loop &
    echo $! > "$P3_LISTEN_PID_FILE"
    success "⏱  Auto-tick STARTED — 1 game day every ${P3_TICK_INTERVAL}s"
    info    "   Tick PID   : $(cat "$P3_TICK_PID_FILE")"
    info    "   pg_notify  : channel p3_day_tick  (payload = JSON)"
    info    "   External   : psql -c \"LISTEN p3_day_tick;\""
}

p3_stop_tick() {
    local stopped=0
    for pidfile in "$P3_TICK_PID_FILE" "$P3_LISTEN_PID_FILE"; do
        if [[ -f "$pidfile" ]]; then
            kill "$(cat "$pidfile")" 2>/dev/null || true
            rm -f "$pidfile"
            (( stopped++ )) || true
        fi
    done
    [[ $stopped -gt 0 ]] && success "⏹  Tick daemon stopped." \
                         || warn    "No tick daemon is running."
}

p3_tick_status() {
    echo
    if [[ -f "$P3_TICK_PID_FILE" ]] && kill -0 "$(cat "$P3_TICK_PID_FILE")" 2>/dev/null; then
        success "⏱  RUNNING — 1 game day every ${P3_TICK_INTERVAL}s  (PID $(cat "$P3_TICK_PID_FILE"))"
        if [[ -f "$P3_TICK_STATE_FILE" ]]; then
            info "   Last tick state : $(cat "$P3_TICK_STATE_FILE")"
        fi
        info    "   pg_notify channel : p3_day_tick"
        info    "   LISTEN externally : psql -U ${P3_USER} ${P3_DB} -c 'LISTEN p3_day_tick;'"
    else
        rm -f "$P3_TICK_PID_FILE" "$P3_LISTEN_PID_FILE" 2>/dev/null || true
        warn "⏹  Stopped — use 'Start Auto-Tick' from the Simulation menu to begin."
    fi
}

p3_set_tick_interval() {
    local v
    v=$(gum input --placeholder "Seconds per game day (current: ${P3_TICK_INTERVAL})" \
                  --value "$P3_TICK_INTERVAL")
    [[ "$v" =~ ^[1-9][0-9]*$ ]] || { error "Enter a positive whole number."; return; }
    P3_TICK_INTERVAL="$v"
    success "Tick interval set to ${P3_TICK_INTERVAL}s/day."
    if [[ -f "$P3_TICK_PID_FILE" ]] && kill -0 "$(cat "$P3_TICK_PID_FILE")" 2>/dev/null; then
        if confirm "Restart daemon now to apply the new interval?"; then
            p3_stop_tick
            p3_start_tick
        fi
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14n  RICH MAIN DASHBOARD
#
#  Displayed at the top of every patrician_menu iteration.
#  Uses full terminal width: left panel = status + fleet,
#  right panel = live arbitrage opportunities.
# ─────────────────────────────────────────────────────────────────────────────
p3_main_dashboard() {
    local cols half ruler
    cols=$(tput cols 2>/dev/null || echo 90)
    half=$(( cols / 2 - 2 ))
    [[ $half -lt 36 ]] && half=36
    [[ $half -gt 64 ]] && half=64
    ruler=$(printf '─%.0s' $(seq 1 $((half - 4))))

    # ── Single DB round-trip: player + fleet counts ──────────────────────────
    local gold rank gyear gday docked sailing
    {
        read -r gold; read -r rank; read -r gyear
        read -r gday; read -r docked; read -r sailing
    } < <(p3_psql --tuples-only -c "
        SELECT pl.gold::text, pl.rank,
               pl.game_year::text, pl.game_day::text,
               (SELECT COUNT(*)::text FROM p3_ships WHERE owner='player' AND status='docked'),
               (SELECT COUNT(*)::text FROM p3_ships WHERE owner='player' AND status='sailing')
        FROM p3_player pl LIMIT 1;" 2>/dev/null \
        | sed 's/|/\n/g; s/^ *//; s/ *$//' \
        || printf '???\nApprentice\n???\n0\n0\n0\n')

    # ── Fleet detail lines ───────────────────────────────────────────────────
    local fleet_lines
    fleet_lines=$(p3_psql --tuples-only -c "
        SELECT '  ' || RPAD(name, 14) ||
               CASE status
                   WHEN 'sailing' THEN '⛵ → ' || COALESCE(destination,'?') ||
                                       '  ETA ' || eta_days || 'd'
                   ELSE           '⚓ ' || current_city
               END || '  [' || cargo_used || '/' || cargo_cap || ']'
        FROM p3_fleet_view ORDER BY status DESC, name LIMIT 6;" 2>/dev/null \
        | grep -v '^\s*$' || echo "  (no ships in fleet)")

    # ── Tick badge ───────────────────────────────────────────────────────────
    local tick_badge
    if [[ -f "$P3_TICK_PID_FILE" ]] && kill -0 "$(cat "$P3_TICK_PID_FILE")" 2>/dev/null; then
        tick_badge="⏱  Auto-tick RUNNING   ${P3_TICK_INTERVAL}s / day"
    else
        tick_badge="⏹  Manual mode  ·  Simulation › Start Auto-Tick"
    fi

    # ── Arbitrage opportunities ──────────────────────────────────────────────
    local arb_lines
    arb_lines=$(p3_psql --tuples-only -c "
        SELECT '  ' || RPAD(good, 12)    ||
                       RPAD(buy_city, 14) ||
               '→  '|| RPAD(sell_city, 14) ||
               '+' || profit_per_unit || '/u'
        FROM p3_arbitrage_view LIMIT 7;" 2>/dev/null \
        | grep -v '^\s*$' || echo "  (run Initialise / Reset Game first)")

    # ── Render left panel: status + fleet ────────────────────────────────────
    local panel_left
    panel_left=$(
    {
        printf '⚓  PATRICIAN  III / IV\n'
        printf '%s\n' "$ruler"
        printf '📅  Year %-6s  ·  Day %03d\n' "${gyear:-???}" "${gday:-0}"
        printf '💰  %-22s  🏅  %s\n' "${gold:-???} gold" "${rank:-Apprentice}"
        printf '%s\n' "$ruler"
        printf '🚢  %s docked   ·   %s at sea\n' "${docked:-0}" "${sailing:-0}"
        printf '%s\n' "$fleet_lines"
        printf '%s\n' "$ruler"
        printf '%s\n' "$tick_badge"
    } | gum style \
            --border rounded \
            --border-foreground 33 \
            --padding "0 2" \
            --width "$half")

    # ── Render right panel: arbitrage ────────────────────────────────────────
    local panel_right
    panel_right=$(
    {
        printf '📊  ARBITRAGE OPPORTUNITIES\n'
        printf '%s\n' "$ruler"
        printf '  %-12s %-14s %-14s %s\n' "GOOD" "BUY AT" "SELL AT" "PROFIT"
        printf '%s\n' "$ruler"
        printf '%s\n' "$arb_lines"
    } | gum style \
            --border rounded \
            --border-foreground 214 \
            --padding "0 2" \
            --width "$half")

    gum join --horizontal --align top "$panel_left" "  " "$panel_right"
    echo
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14g  MAIN PATRICIAN MENU
# ─────────────────────────────────────────────────────────────────────────────
patrician_menu() {
    push_breadcrumb "⚓ Patrician"
    while true; do
        p3_main_dashboard

        choice="$(gum choose --height 40 \
            "── Setup ──" \
            "Initialise / Reset Game" \
            "Reseed Market Prices" \
            "── Fleet ──" \
            "View Fleet" \
            "Buy a Ship" \
            "Rename Ship" \
            "Give Sail Order" \
            "View Ship Cargo" \
            "── Trading ──" \
            "Buy Goods at City" \
            "Sell Goods at City" \
            "── Buildings ──" \
            "🏭 Manage Buildings & Limit Orders" \
            "── Market ──" \
            "View Market at City" \
            "Best Arbitrage Opportunities" \
            "Cross-League Opportunities  (Hanse ↔ Med)" \
            "Price History for Good" \
            "Good Reference Prices" \
            "── Routes ──" \
            "View All Routes" \
            "Create Trade Route" \
            "Add Order to Route" \
            "Assign Ship to Route" \
            "── World ──" \
            "View All Cities" \
            "City Production Details" \
            "🗺 Hex Map & City Distances" \
            "📊 Market Elasticity & Price Curves" \
            "── Time ──" \
            "Advance One Day" \
            "Advance Multiple Days" \
            "── Simulation ──" \
            "Start Auto-Tick" \
            "Stop Auto-Tick" \
            "Tick Status" \
            "Set Tick Interval" \
            "── Log ──" \
            "View Trade Log" \
            "── Mediterranean ──" \
            "🌊 Patrician IV — Mediterranean" \
            "Back")"

        case "$choice" in
            "── Setup ──"|"── Fleet ──"|"── Trading ──"|"── Buildings ──"|\
            "── Market ──"|"── Routes ──"|"── World ──"|"── Time ──"|\
            "── Simulation ──"|"── Log ──"|"── Mediterranean ──")
                continue ;;

            "🗺 Hex Map & City Distances")      p3_hex_menu ;;
            "📊 Market Elasticity & Price Curves") p3_elasticity_menu ;;
            "🏭 Manage Buildings & Limit Orders")  p3_buildings_menu ;;
            "🌊 Patrician IV — Mediterranean")     p3_p4_menu ;;

            # ── SIMULATION ─────────────────────────────────────────────────
            "Start Auto-Tick")    p3_start_tick ;;
            "Stop Auto-Tick")     p3_stop_tick  ;;
            "Tick Status")        p3_tick_status ;;
            "Set Tick Interval")  p3_set_tick_interval ;;

            # ── SETUP ──────────────────────────────────────────────────────
            "Initialise / Reset Game")
                if confirm "Create/reset ALL Patrician tables and seed data?"; then
                    p3_setup_all
                fi ;;

            "Reseed Market Prices")
                if confirm "Re-randomise all market prices (keeps stock levels)?"; then
                    p3_psql -c "
                        UPDATE p3_market m
                        SET current_buy  = ROUND(new_mid * 1.08, 2),
                            current_sell = ROUND(new_mid * 0.92, 2)
                        FROM (
                            SELECT m2.city_id, m2.good_id,
                                   ROUND(
                                       (g.buy_price_min + g.sell_price_min) / 2.0
                                       * (0.85 + (RANDOM()::NUMERIC) * 0.30)
                                       * CASE WHEN cg.good_id IS NOT NULL
                                              THEN 0.88::NUMERIC ELSE 1.05::NUMERIC END,
                                   2) AS new_mid
                            FROM p3_market m2
                            JOIN p3_goods g ON g.good_id = m2.good_id
                            LEFT JOIN p3_city_goods cg
                                ON cg.city_id = m2.city_id AND cg.good_id = m2.good_id
                                AND cg.role = 'produces'
                        ) e WHERE e.city_id = m.city_id AND e.good_id = m.good_id;" >/dev/null
                    success "Market prices re-randomised."
                fi ;;

            # ── FLEET ──────────────────────────────────────────────────────
            "View Fleet")
                p3_psql -c "
                    SELECT ship_id AS id, name, ship_type AS type,
                           speed_knots AS kn,
                           current_city AS city, status,
                           COALESCE(destination, '—') AS dest,
                           CASE WHEN eta_days > 0 THEN eta_days||'d' ELSE '—' END AS eta,
                           cargo_cap AS cap, cargo_used AS used, cargo_free AS free
                    FROM p3_fleet_view ORDER BY name;" ;;

            "Buy a Ship")
                local stype cost cap spd
                stype=$(gum choose \
                    "Snaikka  — cap  50, 5.0 kn — 1 200g  (Baltic coastal workhorse)" \
                    "Crayer   — cap  80, 7.0 kn — 2 500g  (Faster, medium cargo)" \
                    "Hulk     — cap 160, 4.0 kn — 5 000g  (Slow bulk hauler)" \
                    "Cog      — cap 120, 6.0 kn — 3 500g  (P4 — balanced Med trader)" \
                    "Galley   — cap  90, 9.0 kn — 4 200g  (P4 — fastest ship)" \
                    "Carrack  — cap 220, 5.5 kn — 9 000g  (P4 — flagship cargo)")
                case "$stype" in
                    *Snaikka*) cap=50;  cost=1200; spd=5.0; stype="Snaikka" ;;
                    *Crayer*)  cap=80;  cost=2500; spd=7.0; stype="Crayer"  ;;
                    *Hulk*)    cap=160; cost=5000; spd=4.0; stype="Hulk"    ;;
                    *Cog*)     cap=120; cost=3500; spd=6.0; stype="Cog"     ;;
                    *Galley*)  cap=90;  cost=4200; spd=9.0; stype="Galley"  ;;
                    *Carrack*) cap=220; cost=9000; spd=5.5; stype="Carrack" ;;
                    *) pause; continue ;;
                esac
                local gold; gold=$(p3_gold)
                if awk "BEGIN{exit !(${gold}+0 < ${cost}+0)}"; then
                    error "Not enough gold (have ${gold}g, need ${cost}g)."
                else
                    local sname home
                    sname=$(gum input --placeholder "Name your new ship")
                    [[ -z "$sname" ]] && { error "Name required."; pause; continue; }
                    home=$(p3_psql --tuples-only -c "SELECT home_city FROM p3_player;" | tr -d ' ')
                    p3_psql -c "
                        INSERT INTO p3_ships (name, owner, ship_type, cargo_cap, speed_knots, current_city)
                        VALUES ('$sname', 'player', '$stype', $cap, $spd, '$home');
                        UPDATE p3_player SET gold = gold - $cost;" >/dev/null
                    success "Purchased '$sname' ($stype, ${cap} cap, ${spd}kn) for ${cost}g."
                fi ;;

            "Rename Ship")
                local sid; sid=$(p3_pick_ship) || { pause; continue; }
                local newname; newname=$(gum input --placeholder "New ship name")
                [[ -z "$newname" ]] && { pause; continue; }
                p3_psql -c "UPDATE p3_ships SET name = '$newname' WHERE ship_id = $sid;" >/dev/null
                success "Ship renamed to '$newname'." ;;

            "Give Sail Order")
                local sid; sid=$(p3_pick_ship) || { pause; continue; }
                local sname scity status
                sname=$(p3_psql --tuples-only -c "SELECT name         FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
                scity=$(p3_psql --tuples-only -c "SELECT current_city FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
                status=$(p3_psql --tuples-only -c "SELECT status       FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
                if [[ "$status" != "docked" ]]; then
                    local eta; eta=$(p3_psql --tuples-only -c "SELECT eta_days FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
                    warn "$sname is $status (ETA ${eta} day(s))."
                    pause; continue
                fi
                info "Select destination for $sname (currently in $scity):"
                local dest; dest=$(p3_pick_city)
                [[ -z "$dest" || "$dest" == "$scity" ]] && { error "Invalid destination."; pause; continue; }
                p3_sail_ship "$sid" "$dest" ;;

            "View Ship Cargo")
                local sid; sid=$(p3_pick_ship) || { pause; continue; }
                p3_psql -c "
                    SELECT g.name AS good, c.quantity,
                           ROUND(m.current_sell * c.quantity, 2) AS est_sell_value
                    FROM   p3_cargo c
                    JOIN   p3_goods  g  ON g.good_id  = c.good_id
                    JOIN   p3_ships  s  ON s.ship_id  = c.ship_id
                    JOIN   p3_cities ci ON ci.name    = s.current_city
                    JOIN   p3_market m  ON m.good_id  = c.good_id AND m.city_id = ci.city_id
                    WHERE  c.ship_id = $sid AND c.quantity > 0
                    ORDER  BY g.name;" ;;

            # ── TRADING ────────────────────────────────────────────────────
            "Buy Goods at City")
                local sid; sid=$(p3_pick_ship) || { pause; continue; }
                local scity status
                scity=$(p3_psql --tuples-only -c "SELECT current_city FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
                status=$(p3_psql --tuples-only -c "SELECT status FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
                [[ "$status" != "docked" ]] && { warn "Ship must be docked to trade."; pause; continue; }
                p3_psql -c "
                    SELECT g.name AS good, m.current_buy AS ask, m.current_sell AS bid,
                           m.stock, mv.signal
                    FROM   p3_market m
                    JOIN   p3_goods   g  ON g.good_id  = m.good_id
                    JOIN   p3_cities  ci ON ci.city_id = m.city_id AND ci.name = '$scity'
                    JOIN   p3_market_view mv ON mv.city = '$scity' AND mv.good = g.name
                    ORDER  BY g.name;" | cat
                echo
                local good qty
                good=$(p3_pick_good)
                [[ -z "$good" ]] && { pause; continue; }
                qty=$(gum input --placeholder "Quantity to buy")
                [[ -z "$qty" || ! "$qty" =~ ^[0-9]+$ ]] && { error "Invalid quantity."; pause; continue; }
                p3_do_buy "$sid" "$good" "$qty" "$scity" ;;

            "Sell Goods at City")
                local sid; sid=$(p3_pick_ship) || { pause; continue; }
                local scity status
                scity=$(p3_psql --tuples-only -c "SELECT current_city FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
                status=$(p3_psql --tuples-only -c "SELECT status FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
                [[ "$status" != "docked" ]] && { warn "Ship must be docked to trade."; pause; continue; }
                p3_psql -c "
                    SELECT g.name AS good, c.quantity AS aboard,
                           m.current_sell AS bid, m.stock
                    FROM   p3_cargo c
                    JOIN   p3_goods  g  ON g.good_id  = c.good_id
                    JOIN   p3_ships  s  ON s.ship_id  = c.ship_id AND s.ship_id = $sid
                    JOIN   p3_cities ci ON ci.name    = s.current_city
                    JOIN   p3_market m  ON m.good_id  = c.good_id AND m.city_id = ci.city_id
                    WHERE  c.quantity > 0 ORDER BY g.name;" | cat
                echo
                local good qty
                good=$(p3_pick_good)
                [[ -z "$good" ]] && { pause; continue; }
                qty=$(gum input --placeholder "Quantity to sell")
                [[ -z "$qty" || ! "$qty" =~ ^[0-9]+$ ]] && { error "Invalid quantity."; pause; continue; }
                p3_do_sell "$sid" "$good" "$qty" "$scity" ;;

            # ── MARKET ─────────────────────────────────────────────────────
            "View Market at City")
                local city; city=$(p3_pick_city)
                [[ -z "$city" ]] && { pause; continue; }
                p3_psql -c "
                    SELECT good, current_buy AS ask, current_sell AS bid,
                           stock, signal
                    FROM p3_market_view WHERE city = '$city'
                    ORDER BY good;" ;;

            "Best Arbitrage Opportunities")
                p3_psql -c "
                    SELECT buy_city, sell_city, good,
                           buy_price, sell_price, profit_per_unit, buy_stock
                    FROM p3_arbitrage_view
                    LIMIT 20;" ;;

            "Cross-League Opportunities  (Hanse ↔ Med)")
                p3_psql -c "
                    SELECT av.buy_city, av.sell_city, av.good,
                           av.buy_price, av.sell_price, av.profit_per_unit,
                           r.travel_days                                       AS days_snaikka,
                           GREATEST(1, ROUND(r.travel_days*5.0/7.0)::INTEGER) AS days_crayer,
                           GREATEST(1, ROUND(r.travel_days*5.0/9.0)::INTEGER) AS days_galley
                    FROM p3_arbitrage_view av
                    LEFT JOIN p3_routes r ON
                        (r.city_a = av.buy_city AND r.city_b = av.sell_city) OR
                        (r.city_b = av.buy_city AND r.city_a = av.sell_city)
                    WHERE av.profit_per_unit > 0
                      AND (
                        (av.buy_city  IN (SELECT name FROM p3_cities WHERE league = 'Hanseatic')
                         AND av.sell_city IN (SELECT name FROM p3_cities WHERE league = 'Mediterranean'))
                        OR
                        (av.buy_city  IN (SELECT name FROM p3_cities WHERE league = 'Mediterranean')
                         AND av.sell_city IN (SELECT name FROM p3_cities WHERE league = 'Hanseatic'))
                      )
                    ORDER BY av.profit_per_unit DESC LIMIT 15;" ;;

            "Price History for Good")
                local good; good=$(p3_pick_good)
                [[ -z "$good" ]] && { pause; continue; }
                local city; city=$(p3_pick_city)
                [[ -z "$city" ]] && { pause; continue; }
                p3_psql -c "
                    SELECT game_year, game_day, buy_price, sell_price, stock
                    FROM p3_price_history ph
                    JOIN p3_cities ci ON ci.city_id = ph.city_id AND ci.name  = '$city'
                    JOIN p3_goods  g  ON g.good_id  = ph.good_id AND g.name   = '$good'
                    ORDER BY game_year, game_day
                    LIMIT 60;" ;;

            "Good Reference Prices")
                p3_psql -c "
                    SELECT name, category,
                           buy_price_min, sell_price_min, sell_price_max,
                           ROUND(base_production, 4) AS prod_per_day,
                           is_raw_material AS raw
                    FROM p3_goods ORDER BY category, name;" ;;

            # ── ROUTES ─────────────────────────────────────────────────────
            "View All Routes")
                p3_psql -c "
                    SELECT name, city_a, city_b, distance_nm,
                           travel_days AS days_snaikka,
                           GREATEST(1, ROUND(distance_nm::NUMERIC/(7.0*24.0))::INTEGER) AS days_crayer,
                           GREATEST(1, ROUND(distance_nm::NUMERIC/(9.0*24.0))::INTEGER) AS days_galley
                    FROM p3_routes ORDER BY name;" ;;

            "Create Trade Route")
                local rname ca cb dist
                rname=$(gum input --placeholder "Route name (e.g. Lübeck–Gdansk Beer Run)")
                [[ -z "$rname" ]] && { pause; continue; }
                info "Select city A:"; ca=$(p3_pick_city); [[ -z "$ca" ]] && { pause; continue; }
                info "Select city B:"; cb=$(p3_pick_city); [[ -z "$cb" ]] && { pause; continue; }
                dist=$(gum input --placeholder "Distance in nautical miles" --value "300")
                local tdays; tdays=$(awk "BEGIN{printf \"%d\", int(${dist}/120 + 0.5)}")
                [[ -z "$tdays" || "$tdays" == "0" ]] && tdays=3
                p3_psql -c "
                    INSERT INTO p3_routes (name, city_a, city_b, distance_nm, travel_days)
                    VALUES ('$rname', '$ca', '$cb', $dist, $tdays);" >/dev/null
                success "Route '$rname' created (${tdays}d at Snaikka speed)." ;;

            "Add Order to Route")
                local rlist rid rname
                rlist=$(p3_psql --tuples-only -c "SELECT route_id||' – '||name FROM p3_routes ORDER BY name;" \
                    | sed 's/^ *//' | grep -v '^$')
                [[ -z "$rlist" ]] && { warn "No routes."; pause; continue; }
                rname=$(echo "$rlist" | gum filter --placeholder "Select route…")
                rid="${rname%% *}"
                [[ -z "$rid" ]] && { pause; continue; }
                local city; city=$(p3_pick_city)
                [[ -z "$city" ]] && { pause; continue; }
                local action; action=$(gum choose "buy" "sell")
                local good; good=$(p3_pick_good)
                [[ -z "$good" ]] && { pause; continue; }
                local gid; gid=$(p3_psql --tuples-only -c "SELECT good_id FROM p3_goods WHERE name='$good';" | tr -d ' ')
                local qty; qty=$(gum input --placeholder "Quantity" --value "10")
                local maxp; maxp=$(gum input --placeholder "Max/min price (blank = no limit)")
                if [[ "$action" == "buy" ]]; then
                    p3_psql -c "INSERT INTO p3_route_orders (route_id, city, good_id, action, quantity, max_price)
                                VALUES ($rid, '$city', $gid, 'buy', $qty,
                                        $([ -n "$maxp" ] && echo "'$maxp'" || echo 'NULL'));" >/dev/null
                else
                    p3_psql -c "INSERT INTO p3_route_orders (route_id, city, good_id, action, quantity, min_price)
                                VALUES ($rid, '$city', $gid, 'sell', $qty,
                                        $([ -n "$maxp" ] && echo "'$maxp'" || echo 'NULL'));" >/dev/null
                fi
                success "Order added to route." ;;

            "Assign Ship to Route")
                local sid; sid=$(p3_pick_ship) || { pause; continue; }
                local rlist rname rid
                rlist=$(p3_psql --tuples-only -c "SELECT route_id||' – '||name FROM p3_routes ORDER BY name;" \
                    | sed 's/^ *//' | grep -v '^$')
                rname=$(echo "$rlist" | gum filter --placeholder "Select route…")
                rid="${rname%% *}"
                [[ -z "$rid" ]] && { pause; continue; }
                p3_psql -c "INSERT INTO p3_ship_routes (ship_id, route_id, active)
                            VALUES ($sid, $rid, TRUE) ON CONFLICT DO NOTHING;" >/dev/null
                success "Ship assigned to route." ;;

            # ── WORLD ──────────────────────────────────────────────────────
            "View All Cities")
                p3_psql -c "
                    SELECT name, region, league, population,
                           COALESCE(hex_q::text, '?') || ',' || COALESCE(hex_r::text, '?') AS hex_qr
                    FROM p3_cities ORDER BY league, region, name;" ;;

            "City Production Details")
                local city; city=$(p3_pick_city)
                [[ -z "$city" ]] && { pause; continue; }
                p3_psql -c "
                    SELECT g.name AS good, cg.role, cg.efficiency,
                           ROUND(g.base_production * cg.efficiency / 100.0, 4) AS daily_output,
                           ROUND(g.base_production * cg.efficiency / 100.0 * 30, 2) AS est_30d
                    FROM p3_city_goods cg
                    JOIN p3_goods   g  ON g.good_id  = cg.good_id
                    JOIN p3_cities  ci ON ci.city_id = cg.city_id AND ci.name = '$city'
                    ORDER BY cg.role, g.name;" ;;

            # ── TIME ───────────────────────────────────────────────────────
            "Advance One Day")
                p3_advance_day ;;

            "Advance Multiple Days")
                local ndays
                ndays=$(gum input --placeholder "How many days to advance?" --value "10")
                [[ -z "$ndays" || ! "$ndays" =~ ^[0-9]+$ ]] && { error "Enter a number."; pause; continue; }
                local i
                for (( i=1; i<=ndays; i++ )); do
                    p3_advance_day
                done
                success "Advanced $ndays days." ;;

            # ── LOG ────────────────────────────────────────────────────────
            "View Trade Log")
                p3_psql -c "
                    SELECT game_year, game_day, action,
                           COALESCE(good_name, '—') AS good,
                           COALESCE(ship_name, '—') AS ship,
                           COALESCE(city, '—')      AS city,
                           quantity, price, total_value, gold_after
                    FROM p3_trade_log
                    ORDER BY log_id DESC LIMIT 40;" ;;

            "Back" | *)
                pop_breadcrumb
                CURRENT_MENU="main"
                return ;;
        esac
        pause
    done
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14h  PATRICIAN IV MENU
# ─────────────────────────────────────────────────────────────────────────────
p3_p4_menu() {
    push_breadcrumb "🌊 Patrician IV"
    while true; do
        local gold yd
        gold=$(p3_gold 2>/dev/null || echo "?")
        yd=$(p3_psql --tuples-only -c \
            "SELECT 'Year '||game_year||' Day '||LPAD(game_day::text,3,'0') FROM p3_player;" \
            2>/dev/null | tr -d ' ' || echo "??")

        section_header "🌊 Patrician IV — Mediterranean  │  💰 ${gold}g  │  📅 ${yd}"

        choice="$(gum choose \
            "── Mediterranean Market ──" \
            "View Med Market (All Cities)" \
            "Med Arbitrage Opportunities" \
            "Cross-League Opportunities  (Hanse ↔ Med)" \
            "── Mediterranean Cities ──" \
            "View All Med Cities" \
            "Med City Production Details" \
            "── Goods ──" \
            "Mediterranean Goods Reference" \
            "── Ships ──" \
            "Ship Type Comparison" \
            "Back")"

        case "$choice" in
            "── Mediterranean Market ──"|"── Mediterranean Cities ──"|"── Goods ──"|"── Ships ──")
                continue ;;

            "View Med Market (All Cities)")
                p3_psql -c "
                    SELECT city, good, current_buy, current_sell, stock, signal
                    FROM p3_market_view WHERE league = 'Mediterranean'
                    ORDER BY city, good;" ;;

            "Med Arbitrage Opportunities")
                p3_psql -c "
                    SELECT buy_city, sell_city, good, buy_price, sell_price,
                           profit_per_unit, buy_stock
                    FROM p3_arbitrage_view
                    WHERE buy_city  IN (SELECT name FROM p3_cities WHERE league = 'Mediterranean')
                       OR sell_city IN (SELECT name FROM p3_cities WHERE league = 'Mediterranean')
                    ORDER BY profit_per_unit DESC LIMIT 20;" ;;

            "Cross-League Opportunities  (Hanse ↔ Med)")
                p3_psql -c "
                    SELECT av.buy_city, av.sell_city, av.good,
                           av.buy_price, av.sell_price, av.profit_per_unit,
                           r.travel_days                                       AS days_snaikka,
                           GREATEST(1, ROUND(r.travel_days*5.0/7.0)::INTEGER) AS days_crayer,
                           GREATEST(1, ROUND(r.travel_days*5.0/9.0)::INTEGER) AS days_galley
                    FROM p3_arbitrage_view av
                    LEFT JOIN p3_routes r ON
                        (r.city_a = av.buy_city AND r.city_b = av.sell_city) OR
                        (r.city_b = av.buy_city AND r.city_a = av.sell_city)
                    WHERE av.profit_per_unit > 0
                      AND (
                        (av.buy_city  IN (SELECT name FROM p3_cities WHERE league = 'Hanseatic')
                         AND av.sell_city IN (SELECT name FROM p3_cities WHERE league = 'Mediterranean'))
                        OR
                        (av.buy_city  IN (SELECT name FROM p3_cities WHERE league = 'Mediterranean')
                         AND av.sell_city IN (SELECT name FROM p3_cities WHERE league = 'Hanseatic'))
                      )
                    ORDER BY av.profit_per_unit DESC LIMIT 15;" ;;

            "View All Med Cities")
                p3_psql -c "
                    SELECT name, region, population,
                           COALESCE(hex_q::text, '?') || ',' || COALESCE(hex_r::text, '?') AS hex_qr
                    FROM p3_cities WHERE league = 'Mediterranean'
                    ORDER BY region, name;" ;;

            "Med City Production Details")
                local city
                city=$(p3_psql --tuples-only -c \
                    "SELECT name FROM p3_cities WHERE league = 'Mediterranean' ORDER BY name;" \
                    | sed 's/^ *//' | grep -v '^$' | gum filter --placeholder "Select Med city…")
                [[ -z "$city" ]] && { pause; continue; }
                p3_psql -c "
                    SELECT g.name AS good, cg.role, cg.efficiency,
                           ROUND(g.base_production * cg.efficiency / 100.0, 4) AS daily_output
                    FROM p3_city_goods cg
                    JOIN p3_goods   g  ON g.good_id  = cg.good_id
                    JOIN p3_cities  ci ON ci.city_id = cg.city_id AND ci.name = '$city'
                    ORDER BY cg.role, g.name;" ;;

            "Mediterranean Goods Reference")
                p3_psql -c "
                    SELECT name, category, buy_price_min, sell_price_min, sell_price_max,
                           ROUND(base_production, 4) AS prod_day
                    FROM p3_goods
                    WHERE name IN ('Olive Oil','Silk','Glass','Sand','Cotton',
                                   'Alum','Dates','Ivory','Wine','Spices')
                    ORDER BY sell_price_max DESC;" ;;

            "Ship Type Comparison")
                p3_psql -c "
                    SELECT type, cap, kn,
                           GREATEST(1, ROUND(120.0  /(kn*24))::INTEGER) AS lubeck_hamburg_d,
                           GREATEST(1, ROUND(350.0  /(kn*24))::INTEGER) AS lubeck_gdansk_d,
                           GREATEST(1, ROUND(1050.0 /(kn*24))::INTEGER) AS lubeck_london_d,
                           GREATEST(1, ROUND(1400.0 /(kn*24))::INTEGER) AS venice_cpl_d
                    FROM (VALUES
                        ('Snaikka',50,5.0),('Crayer',80,7.0),('Hulk',160,4.0),
                        ('Cog',120,6.0),('Galley',90,9.0),('Carrack',220,5.5)
                    ) AS t(type, cap, kn)
                    ORDER BY kn DESC;" ;;

            "Back" | *) pop_breadcrumb; return ;;
        esac
        pause
    done
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14i  BUILDINGS MENU (daily maintenance display)
# ─────────────────────────────────────────────────────────────────────────────
p3_buildings_menu() {
    push_breadcrumb "🏭 Buildings"
    while true; do
        local gold maint_day
        gold=$(p3_gold 2>/dev/null || echo "?")
        maint_day=$(p3_psql --tuples-only -c "
            SELECT COALESCE(ROUND(SUM(bt.daily_maintenance * pb.num_buildings), 2), 0)
            FROM p3_player_buildings pb
            JOIN p3_building_types bt ON bt.building_type_id = pb.building_type_id;
            " 2>/dev/null | tr -d ' ' || echo "0")

        section_header "🏭 Buildings  │  💰 ${gold}g  │  🔧 ${maint_day}g/day overhead"

        choice="$(gum choose \
            "Build a Building" \
            "Expand Existing Building" \
            "Demolish / Sell Building" \
            "View My Buildings" \
            "Building Production Report" \
            "Building Type Catalogue" \
            "City Building Efficiency" \
            "── Limit Orders ──" \
            "Place Limit Order" \
            "View Active Limit Orders" \
            "Cancel Limit Order" \
            "Back")"

        case "$choice" in
            "── Limit Orders ──") continue ;;

            "Build a Building")
                local city city_id bt_id
                city=$(p3_pick_city); [[ -z "$city" ]] && { pause; continue; }
                city_id=$(p3_psql --tuples-only -c "SELECT city_id FROM p3_cities WHERE name='$city';" | tr -d ' ')

                local types
                types=$(p3_psql --tuples-only -c "
                    SELECT bt.building_type_id || ' – ' || bt.name
                           || '  [' || g_out.name
                           || COALESCE(' ← ' || g_in.name, '')
                           || ']  prod:' || bt.base_production || '/day'
                           || '  cost:' || bt.construction_cost || 'g'
                           || '  maint:' || bt.daily_maintenance || 'g/day'
                    FROM p3_building_types bt
                    JOIN p3_goods g_out ON g_out.good_id = bt.output_good_id
                    LEFT JOIN p3_goods g_in ON g_in.good_id = bt.input_good_id
                    ORDER BY bt.name;" 2>/dev/null | sed 's/^ *//' | grep -v '^$') || true
                [[ -z "$types" ]] && { warn "No building types found."; pause; continue; }
                local chosen; chosen=$(echo "$types" | gum filter --placeholder "Select building type…")
                [[ -z "$chosen" ]] && { pause; continue; }
                bt_id="${chosen%% *}"

                local bt_name bt_cost
                bt_name=$(p3_psql --tuples-only -c "SELECT name FROM p3_building_types WHERE building_type_id=$bt_id;" | tr -d ' ')
                bt_cost=$(p3_psql --tuples-only -c "SELECT construction_cost FROM p3_building_types WHERE building_type_id=$bt_id;" | tr -d ' ')

                local gold_now; gold_now=$(p3_gold)
                if awk "BEGIN{exit !(${gold_now}+0 < ${bt_cost}+0)}"; then
                    error "Not enough gold (have ${gold_now}g, need ${bt_cost}g)."
                    pause; continue
                fi

                if confirm "Build '$bt_name' in $city for ${bt_cost}g?"; then
                    p3_psql -c "
                        INSERT INTO p3_player_buildings (city_id, building_type_id, num_buildings)
                        VALUES ($city_id, $bt_id, 1) ON CONFLICT DO NOTHING;
                        UPDATE p3_player SET gold = gold - $bt_cost;" >/dev/null
                    success "Built '$bt_name' in $city. It will produce each day tick."
                fi ;;

            "View My Buildings")
                p3_psql -c "
                    SELECT pb.pb_id AS id, bt.name AS building, ci.name AS city,
                           pb.num_buildings AS count,
                           ROUND(bt.base_production * pb.num_buildings, 4)   AS prod_per_day,
                           ROUND(bt.daily_maintenance * pb.num_buildings, 2) AS cost_per_day,
                           g_out.name AS output,
                           COALESCE(g_in.name, '—') AS input
                    FROM p3_player_buildings pb
                    JOIN p3_building_types bt ON bt.building_type_id = pb.building_type_id
                    JOIN p3_cities ci ON ci.city_id = pb.city_id
                    JOIN p3_goods g_out ON g_out.good_id = bt.output_good_id
                    LEFT JOIN p3_goods g_in ON g_in.good_id = bt.input_good_id
                    ORDER BY ci.name, bt.name;" ;;

            "Building Type Catalogue")
                p3_psql -c "
                    SELECT bt.name, g_out.name AS output,
                           COALESCE(g_in.name, '—') AS input,
                           bt.input_units_per_output AS in_per_unit,
                           ROUND(bt.base_production, 4) AS prod_day,
                           bt.construction_cost AS cost,
                           bt.daily_maintenance AS maint_day,
                           ROUND(bt.construction_cost::NUMERIC / NULLIF(bt.daily_maintenance, 0), 0) AS payback_days,
                           bt.notes
                    FROM p3_building_types bt
                    JOIN p3_goods g_out ON g_out.good_id = bt.output_good_id
                    LEFT JOIN p3_goods g_in ON g_in.good_id = bt.input_good_id
                    ORDER BY bt.name;" ;;

            "Building Production Report")
                p3_psql -c "
                    SELECT ci.name AS city, g_out.name AS output,
                           SUM(pb.num_buildings) AS buildings,
                           ROUND(SUM(bt.base_production * pb.num_buildings), 4) AS total_prod_day,
                           ROUND(SUM(bt.daily_maintenance * pb.num_buildings), 2) AS total_maint_day
                    FROM p3_player_buildings pb
                    JOIN p3_building_types bt ON bt.building_type_id = pb.building_type_id
                    JOIN p3_cities ci ON ci.city_id = pb.city_id
                    JOIN p3_goods g_out ON g_out.good_id = bt.output_good_id
                    GROUP BY ci.name, g_out.name
                    ORDER BY ci.name, g_out.name;" ;;

            "City Building Efficiency")
                local city; city=$(p3_pick_city)
                [[ -z "$city" ]] && { pause; continue; }
                p3_psql -c "
                    SELECT g.name AS good, cg.efficiency,
                           ROUND(g.base_production * cg.efficiency / 100.0, 4) AS daily_if_built
                    FROM p3_city_goods cg
                    JOIN p3_goods g ON g.good_id = cg.good_id
                    JOIN p3_cities ci ON ci.city_id = cg.city_id AND ci.name = '$city'
                    WHERE cg.role = 'produces'
                    ORDER BY cg.efficiency DESC, g.name;" ;;

            "Expand Existing Building")
                local blist pb_id
                blist=$(p3_psql --tuples-only -c "
                    SELECT pb.pb_id || ' – ' || bt.name || ' in ' || ci.name || ' (×' || pb.num_buildings || ')'
                    FROM p3_player_buildings pb
                    JOIN p3_building_types bt ON bt.building_type_id = pb.building_type_id
                    JOIN p3_cities ci ON ci.city_id = pb.city_id
                    ORDER BY ci.name, bt.name;" 2>/dev/null | sed 's/^ *//' | grep -v '^$') || true
                [[ -z "$blist" ]] && { warn "No buildings owned."; pause; continue; }
                local chosen; chosen=$(echo "$blist" | gum filter --placeholder "Select building…")
                pb_id="${chosen%% *}"
                [[ -z "$pb_id" ]] && { pause; continue; }
                local add_n; add_n=$(gum input --placeholder "How many additional buildings?" --value "1")
                [[ -z "$add_n" || ! "$add_n" =~ ^[0-9]+$ ]] && { pause; continue; }
                local cost_each; cost_each=$(p3_psql --tuples-only -c "
                    SELECT bt.construction_cost FROM p3_player_buildings pb
                    JOIN p3_building_types bt ON bt.building_type_id = pb.building_type_id
                    WHERE pb.pb_id = $pb_id;" | tr -d ' ')
                local total_cost=$(( cost_each * add_n ))
                local gold_now; gold_now=$(p3_gold)
                if awk "BEGIN{exit !(${gold_now}+0 < ${total_cost}+0)}"; then
                    error "Need ${total_cost}g, have ${gold_now}g."
                    pause; continue
                fi
                if confirm "Expand by $add_n for ${total_cost}g?"; then
                    p3_psql -c "
                        UPDATE p3_player_buildings SET num_buildings = num_buildings + $add_n
                        WHERE pb_id = $pb_id;
                        UPDATE p3_player SET gold = gold - $total_cost;" >/dev/null
                    success "Expanded. +$add_n buildings."
                fi ;;

            "Demolish / Sell Building")
                local blist pb_id
                blist=$(p3_psql --tuples-only -c "
                    SELECT pb.pb_id || ' – ' || bt.name || ' in ' || ci.name || ' (×' || pb.num_buildings || ')'
                    FROM p3_player_buildings pb
                    JOIN p3_building_types bt ON bt.building_type_id = pb.building_type_id
                    JOIN p3_cities ci ON ci.city_id = pb.city_id
                    ORDER BY ci.name, bt.name;" 2>/dev/null | sed 's/^ *//' | grep -v '^$') || true
                [[ -z "$blist" ]] && { warn "No buildings owned."; pause; continue; }
                local chosen; chosen=$(echo "$blist" | gum filter --placeholder "Select building to demolish…")
                pb_id="${chosen%% *}"
                [[ -z "$pb_id" ]] && { pause; continue; }
                local refund; refund=$(p3_psql --tuples-only -c "
                    SELECT ROUND(bt.construction_cost * pb.num_buildings * 0.40)
                    FROM p3_player_buildings pb
                    JOIN p3_building_types bt ON bt.building_type_id = pb.building_type_id
                    WHERE pb.pb_id = $pb_id;" | tr -d ' ')
                if confirm "Demolish for ${refund}g refund (40%)?"; then
                    p3_psql -c "
                        UPDATE p3_player SET gold = gold + $refund;
                        DELETE FROM p3_player_buildings WHERE pb_id = $pb_id;" >/dev/null
                    success "Demolished. Received ${refund}g."
                fi ;;

            "Place Limit Order")
                local sid; sid=$(p3_pick_ship) || { pause; continue; }
                local scity; scity=$(p3_psql --tuples-only -c "SELECT current_city FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
                local cid; cid=$(p3_psql --tuples-only -c "SELECT city_id FROM p3_cities WHERE name='$scity';" | tr -d ' ')
                local action; action=$(gum choose "buy" "sell")
                local good; good=$(p3_pick_good); [[ -z "$good" ]] && { pause; continue; }
                local gid; gid=$(p3_psql --tuples-only -c "SELECT good_id FROM p3_goods WHERE name='$good';" | tr -d ' ')
                local qty; qty=$(gum input --placeholder "Total quantity")
                local price; price=$(gum input --placeholder "Price limit (buy: max | sell: min)")
                [[ -z "$qty" || -z "$price" ]] && { error "Qty and price required."; pause; continue; }
                p3_psql -c "
                    INSERT INTO p3_limit_orders
                        (ship_id, city_id, good_id, action, total_quantity, remaining_quantity, price_limit)
                    VALUES ($sid, $cid, $gid, '$action', $qty, $qty, $price);" >/dev/null
                success "Limit order placed: $action $qty $good @ $price in $scity." ;;

            "View Active Limit Orders")
                p3_psql -c "
                    SELECT lo.order_id, lo.action, g.name AS good,
                           ci.name AS city, lo.price_limit,
                           lo.remaining_quantity || '/' || lo.total_quantity AS remaining,
                           m.current_buy AS ask, m.current_sell AS bid
                    FROM p3_limit_orders lo
                    JOIN p3_goods   g  ON g.good_id  = lo.good_id
                    JOIN p3_cities  ci ON ci.city_id = lo.city_id
                    JOIN p3_market  m  ON m.city_id  = lo.city_id AND m.good_id = lo.good_id
                    WHERE lo.active AND lo.remaining_quantity > 0
                    ORDER BY lo.order_id;" ;;

            "Cancel Limit Order")
                local oid
                oid=$(p3_psql --tuples-only -c "
                    SELECT lo.order_id || ' – ' || lo.action || ' '
                           || lo.remaining_quantity || ' ' || g.name
                           || ' @ ' || lo.price_limit || ' (' || ci.name || ')'
                    FROM p3_limit_orders lo
                    JOIN p3_goods g ON g.good_id = lo.good_id
                    JOIN p3_cities ci ON ci.city_id = lo.city_id
                    WHERE lo.active ORDER BY lo.order_id;" 2>/dev/null \
                    | sed 's/^ *//' | grep -v '^$' | gum filter --placeholder "Select order to cancel…")
                oid="${oid%% *}"
                [[ -z "$oid" ]] && { pause; continue; }
                p3_psql -c "UPDATE p3_limit_orders SET active = FALSE WHERE order_id = $oid;" >/dev/null
                success "Limit order $oid cancelled." ;;

            "Back" | *) pop_breadcrumb; return ;;
        esac
        pause
    done
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14j  ELASTICITY MENU  (view/tune marginal pricing)
# ─────────────────────────────────────────────────────────────────────────────
p3_elasticity_menu() {
    push_breadcrumb "📊 Elasticity"
    while true; do
        section_header "📊 Market Elasticity & Price Curves"
        choice="$(gum choose \
            "View Elasticity Table" \
            "Adjust Good Elasticity" \
            "Preview Marginal Price Curve" \
            "Back")"

        case "$choice" in
            "View Elasticity Table")
                p3_psql -c "
                    SELECT g.name AS good, g.category,
                           e.elasticity_buy  AS buy_e,
                           e.elasticity_sell AS sell_e,
                           e.stock_ref, e.price_floor_pct AS floor,
                           e.price_ceil_pct  AS ceil
                    FROM p3_goods g
                    JOIN p3_good_elasticity e ON e.good_id = g.good_id
                    ORDER BY e.elasticity_buy DESC;" ;;

            "Adjust Good Elasticity")
                local good; good=$(p3_pick_good); [[ -z "$good" ]] && { pause; continue; }
                p3_psql -c "
                    SELECT e.elasticity_buy, e.elasticity_sell,
                           e.stock_ref, e.price_floor_pct, e.price_ceil_pct
                    FROM p3_good_elasticity e JOIN p3_goods g USING (good_id)
                    WHERE g.name = '$good';" | cat
                local new_buy new_sell new_ref
                new_buy=$(gum input  --placeholder "elasticity_buy  (blank=keep)")
                new_sell=$(gum input --placeholder "elasticity_sell (blank=keep)")
                new_ref=$(gum input  --placeholder "stock_ref       (blank=keep)")
                p3_psql -c "
                    UPDATE p3_good_elasticity e
                    SET elasticity_buy  = COALESCE(NULLIF('$new_buy','')::NUMERIC,  e.elasticity_buy),
                        elasticity_sell = COALESCE(NULLIF('$new_sell','')::NUMERIC, e.elasticity_sell),
                        stock_ref       = COALESCE(NULLIF('$new_ref','')::INTEGER,  e.stock_ref)
                    FROM p3_goods g WHERE g.good_id = e.good_id AND g.name = '$good';" >/dev/null
                success "Elasticity updated for $good." ;;

            "Preview Marginal Price Curve")
                local good city
                good=$(p3_pick_good); [[ -z "$good" ]] && { pause; continue; }
                city=$(p3_pick_city); [[ -z "$city" ]] && { pause; continue; }
                gum style --bold --foreground 212 "── Marginal Ask for buying 1…20 units of $good in $city ──"
                p3_psql -c "
                    SELECT
                        generate_series(1,20) AS qty,
                        ROUND(
                            ((m.current_buy/1.08 + m.current_sell/0.92)/2.0)
                            * POWER(
                                e.stock_ref::NUMERIC
                                / GREATEST(m.stock - generate_series(1,20) + 1, 1)::NUMERIC,
                                e.elasticity_buy
                            )
                            * 1.08,
                        2) AS marginal_ask
                    FROM p3_market m
                    JOIN p3_cities ci ON ci.city_id = m.city_id AND ci.name = '$city'
                    JOIN p3_goods  g  ON g.good_id  = m.good_id AND g.name  = '$good'
                    JOIN p3_good_elasticity e ON e.good_id = g.good_id;" | cat ;;

            "Back" | *) pop_breadcrumb; return ;;
        esac
        pause
    done
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14k  HEX MAP MENU  (pointy-top system; uses p3_travel_days)
# ─────────────────────────────────────────────────────────────────────────────
p3_hex_menu() {
    push_breadcrumb "🗺 Hex Map"
    while true; do
        section_header "🗺 Hex Map & World"

        choice="$(gum choose \
            "── Overview ──" \
            "Show All City Positions" \
            "ASCII Map (text overview)" \
            "── Distance & Travel ──" \
            "Distance Between Two Cities" \
            "Cities Within Range of City" \
            "Travel Time Between Cities" \
            "── Hex Tile Operations ──" \
            "View Tile at Coordinates" \
            "List All Placed Tiles" \
            "Create / Edit Tile" \
            "Move City to New Hex" \
            "Back")"

        case "$choice" in
            "── Overview ──"|"── Distance & Travel ──"|"── Hex Tile Operations ──")
                continue ;;

            "Show All City Positions")
                p3_psql -c "
                    SELECT ci.name AS city, ci.region, ci.league,
                           ci.hex_q AS q, ci.hex_r AS r,
                           (-ci.hex_q - ci.hex_r) AS s,
                           COALESCE(ht.terrain, 'unmapped') AS terrain,
                           ci.population
                    FROM p3_cities ci
                    LEFT JOIN p3_hex_tiles ht ON ht.city_id = ci.city_id
                    ORDER BY ci.league, ci.name;" ;;

            "ASCII Map (text overview)")
                gum style --foreground 244 \
                    "Pointy-top hex map  |  1 hex ≈ 50 nm  |  q→E  r→S  |  Lübeck = (0,0)"
                echo
                p3_psql -c "
                    SELECT
                        LPAD(ci.hex_q::text, 4) || ',' ||
                        LPAD(ci.hex_r::text, 4) || '  ' ||
                        RPAD(LEFT(ci.name, 18), 18) ||
                        '  hexes_from_Lubeck: ' ||
                        COALESCE(p3_hex_distance(0, 0, ci.hex_q, ci.hex_r)::text, '?')
                    FROM p3_cities ci
                    WHERE ci.hex_q IS NOT NULL
                    ORDER BY ci.hex_r, ci.hex_q;" | cat
                echo
                gum style --foreground 244 \
                    "Snaikka (5 kn): ~120 nm/day ≈ 2.4 hex/day." ;;

            "Distance Between Two Cities")
                info "Select first city:";  local ca; ca=$(p3_pick_city)
                [[ -z "$ca" ]] && { pause; continue; }
                info "Select second city:"; local cb; cb=$(p3_pick_city)
                [[ -z "$cb" ]] && { pause; continue; }
                p3_psql -c "
                    SELECT ca.name AS from_city, cb.name AS to_city,
                           COALESCE(p3_hex_distance(ca.hex_q,ca.hex_r,cb.hex_q,cb.hex_r)::text,'?') AS hex_dist,
                           COALESCE((p3_hex_distance(ca.hex_q,ca.hex_r,cb.hex_q,cb.hex_r)*50)::text,'?') AS approx_nm,
                           COALESCE(p3_travel_days(ca.city_id,cb.city_id,5.0)::text,'no coords') AS days_snaikka_5kn,
                           COALESCE(p3_travel_days(ca.city_id,cb.city_id,7.0)::text,'—')         AS days_crayer_7kn,
                           COALESCE(p3_travel_days(ca.city_id,cb.city_id,9.0)::text,'—')         AS days_galley_9kn
                    FROM p3_cities ca, p3_cities cb
                    WHERE ca.name = '$ca' AND cb.name = '$cb';" ;;

            "Cities Within Range of City")
                local src_city max_days
                src_city=$(p3_pick_city); [[ -z "$src_city" ]] && { pause; continue; }
                max_days=$(gum input --placeholder "Max travel days (e.g. 7)" --value "7")
                [[ -z "$max_days" ]] && { pause; continue; }
                p3_psql -c "
                    SELECT dest.name AS city,
                           COALESCE(p3_hex_distance(src.hex_q,src.hex_r,dest.hex_q,dest.hex_r)::text,'?') AS hexes,
                           COALESCE((p3_hex_distance(src.hex_q,src.hex_r,dest.hex_q,dest.hex_r)*50)::text,'?') AS nm,
                           COALESCE(p3_travel_days(src.city_id,dest.city_id,5.0)::text,'?') AS days_snaikka
                    FROM p3_cities src, p3_cities dest
                    WHERE src.name = '$src_city'
                      AND dest.city_id <> src.city_id
                      AND dest.hex_q IS NOT NULL AND src.hex_q IS NOT NULL
                      AND COALESCE(p3_travel_days(src.city_id,dest.city_id,5.0), 9999) <= $max_days
                    ORDER BY p3_travel_days(src.city_id,dest.city_id,5.0), dest.name;" ;;

            "Travel Time Between Cities")
                info "Snaikka 5kn · Crayer 7kn · Hulk 4kn · Cog 6kn · Galley 9kn · Carrack 5.5kn"
                info "Select origin:";      local ta; ta=$(p3_pick_city); [[ -z "$ta" ]] && { pause; continue; }
                info "Select destination:"; local tb; tb=$(p3_pick_city); [[ -z "$tb" ]] && { pause; continue; }
                p3_psql -c "
                    SELECT ca.name AS origin, cb.name AS destination,
                           COALESCE(p3_hex_distance(ca.hex_q,ca.hex_r,cb.hex_q,cb.hex_r)::text,'?') AS hex_dist,
                           COALESCE(p3_travel_days(ca.city_id,cb.city_id,5.0)::text,'?')   AS snaikka_5kn,
                           COALESCE(p3_travel_days(ca.city_id,cb.city_id,7.0)::text,'?')   AS crayer_7kn,
                           COALESCE(p3_travel_days(ca.city_id,cb.city_id,9.0)::text,'?')   AS galley_9kn,
                           COALESCE(p3_travel_days(ca.city_id,cb.city_id,5.5)::text,'?')   AS carrack_5_5kn
                    FROM p3_cities ca, p3_cities cb
                    WHERE ca.name = '$ta' AND cb.name = '$tb';" ;;

            "View Tile at Coordinates")
                local tq; tq=$(gum input --placeholder "q" --value "0")
                local tr; tr=$(gum input --placeholder "r" --value "0")
                p3_psql -c "
                    SELECT ht.q, ht.r, ht.s, ht.terrain,
                           COALESCE(ci.name, '(no city)') AS city,
                           COALESCE(ht.hazard, 'none') AS hazard, ht.notes
                    FROM p3_hex_tiles ht
                    LEFT JOIN p3_cities ci ON ci.city_id = ht.city_id
                    WHERE ht.q = $tq AND ht.r = $tr;" ;;

            "List All Placed Tiles")
                p3_psql -c "
                    SELECT ht.q, ht.r, ht.s, ht.terrain,
                           COALESCE(ci.name, '—') AS city,
                           COALESCE(ht.hazard, '—') AS hazard
                    FROM p3_hex_tiles ht
                    LEFT JOIN p3_cities ci ON ci.city_id = ht.city_id
                    ORDER BY ht.r, ht.q;" ;;

            "Create / Edit Tile")
                local tq tr terrain hazard tnotes
                tq=$(gum input --placeholder "q coordinate")
                tr=$(gum input --placeholder "r coordinate")
                [[ -z "$tq" || -z "$tr" ]] && { pause; continue; }
                terrain=$(gum choose "sea" "coast" "land" "forest" "mountain" "ice")
                hazard=$(gum input --placeholder "Hazard (blank = none)")
                tnotes=$(gum input --placeholder "Notes  (blank = none)")
                p3_psql -c "
                    INSERT INTO p3_hex_tiles (q, r, terrain, hazard, notes)
                    VALUES ($tq, $tr, '$terrain',
                            NULLIF('$hazard',''), NULLIF('$tnotes',''))
                    ON CONFLICT (q, r) DO UPDATE
                        SET terrain = EXCLUDED.terrain,
                            hazard  = EXCLUDED.hazard,
                            notes   = EXCLUDED.notes;" >/dev/null
                success "Tile ($tq,$tr) saved as $terrain." ;;

            "Move City to New Hex")
                local city nq nr
                city=$(p3_pick_city); [[ -z "$city" ]] && { pause; continue; }
                nq=$(gum input --placeholder "New q coordinate")
                nr=$(gum input --placeholder "New r coordinate")
                [[ -z "$nq" || -z "$nr" ]] && { pause; continue; }
                p3_psql -c "UPDATE p3_cities SET hex_q = $nq, hex_r = $nr WHERE name = '$city';" >/dev/null
                success "$city moved to hex ($nq,$nr)." ;;

            "Back" | *) pop_breadcrumb; return ;;
        esac
        pause
    done
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14l  ENTRY POINT — run standalone as ./patrician3.sh
# ─────────────────────────────────────────────────────────────────────────────
run_app() {
    clear
    gum style \
        --border double \
        --margin "1" \
        --padding "1 4" \
        --border-foreground 33 \
        --bold \
        "⚓  PATRICIAN III / IV" \
        "$(gum style --foreground 244 'Hanseatic Trading Simulation — CLI Edition')"
    patrician_menu
}

# Only auto-run when executed directly (not when sourced into app.sh)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_app
fi
