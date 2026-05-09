-- =============================================================================
--  sql/schema.sql  --  Patrician III / IV database schema
--
--  Apply with:  psql -d traderdude -f sql/schema.sql
--  Safe to re-run (all CREATE uses IF NOT EXISTS / CREATE OR REPLACE).
-- =============================================================================

-- ── Player ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS p3_player (
    player_id  SERIAL PRIMARY KEY,
    name       TEXT          NOT NULL DEFAULT 'Merchant',
    home_city  TEXT          NOT NULL DEFAULT 'Lubeck',
    gold       NUMERIC(12,2) NOT NULL DEFAULT 2000,
    rank       TEXT          NOT NULL DEFAULT 'Apprentice',
    game_year  INTEGER       NOT NULL DEFAULT 1337,
    game_day   INTEGER       NOT NULL DEFAULT 121 CHECK (game_day BETWEEN 1 AND 360),
    is_admin   BOOLEAN       NOT NULL DEFAULT TRUE
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
    base_production  NUMERIC(8,4)  NOT NULL DEFAULT 0.5,
    is_raw_material  BOOLEAN       NOT NULL DEFAULT FALSE,
    notes            TEXT
);

-- ── Cities ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS p3_cities (
    city_id    SERIAL  PRIMARY KEY,
    name       TEXT    NOT NULL UNIQUE,
    region     TEXT    NOT NULL DEFAULT 'Baltic',
    population INTEGER NOT NULL DEFAULT 5000,
    league     TEXT    NOT NULL DEFAULT 'Hanseatic',
    latitude   NUMERIC DEFAULT NULL,
    longitude  NUMERIC DEFAULT NULL,
    hex_q      INTEGER DEFAULT NULL,
    hex_r      INTEGER DEFAULT NULL,
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

-- ── Ships ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS p3_ships (
    ship_id      SERIAL  PRIMARY KEY,
    name         TEXT           NOT NULL,
    owner        TEXT           NOT NULL DEFAULT 'player',
    ship_type    TEXT           NOT NULL DEFAULT 'Snaikka',
    cargo_cap    INTEGER        NOT NULL DEFAULT 50,
    speed_knots  NUMERIC(5,2)   NOT NULL DEFAULT 5.0,
    current_city TEXT           NOT NULL DEFAULT 'Lubeck',
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

-- ── Routes ────────────────────────────────────────────────────────────────
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

-- ── Ship-Route assignments ────────────────────────────────────────────────
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

-- ── Building types ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS p3_building_types (
    building_type_id       SERIAL        PRIMARY KEY,
    name                   TEXT          NOT NULL UNIQUE,
    output_good_id         INTEGER       NOT NULL REFERENCES p3_goods(good_id),
    input_good_id          INTEGER       REFERENCES p3_goods(good_id),
    input_units_per_output NUMERIC(6,3)  NOT NULL DEFAULT 0,
    base_production        NUMERIC(8,4)  NOT NULL DEFAULT 0.25,
    construction_cost      INTEGER       NOT NULL DEFAULT 5000,
    daily_maintenance      NUMERIC(8,2)  NOT NULL DEFAULT 20,
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

-- ── Hex grid (pointy-top axial, 1 hex = 50 nm) ───────────────────────────
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

-- ── Marginal pricing elasticity ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS p3_good_elasticity (
    good_id         INTEGER PRIMARY KEY REFERENCES p3_goods(good_id) ON DELETE CASCADE,
    elasticity_buy  NUMERIC(5,3) NOT NULL DEFAULT 0.40,
    elasticity_sell NUMERIC(5,3) NOT NULL DEFAULT 0.30,
    stock_ref       INTEGER      NOT NULL DEFAULT 100,
    price_floor_pct NUMERIC(5,3) NOT NULL DEFAULT 0.30,
    price_ceil_pct  NUMERIC(5,3) NOT NULL DEFAULT 3.00
);

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

-- ── Counting houses ───────────────────────────────────────────────────────
--  Grants permanent market visibility + enables limit orders without a ship.
CREATE TABLE IF NOT EXISTS p3_counting_houses (
    ch_id        SERIAL PRIMARY KEY,
    city_name    TEXT   NOT NULL,
    city_id      INTEGER NOT NULL REFERENCES p3_cities(city_id) ON DELETE CASCADE,
    established  TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (city_id)
);

-- ── NPC factions ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS p3_npc_factions (
    faction_id   SERIAL PRIMARY KEY,
    name         TEXT NOT NULL UNIQUE,
    home_city    TEXT NOT NULL,
    description  TEXT
);

-- ── NPC ship specialisations and AI state ────────────────────────────────
CREATE TABLE IF NOT EXISTS p3_npc_ships (
    npc_ship_id      INTEGER  PRIMARY KEY REFERENCES p3_ships(ship_id) ON DELETE CASCADE,
    good_id          INTEGER  NOT NULL REFERENCES p3_goods(good_id),
    home_city        TEXT     NOT NULL DEFAULT 'Lubeck',
    ai_state         TEXT     NOT NULL DEFAULT 'seeking'
                              CHECK (ai_state IN ('seeking','loading','sailing','unloading','returning')),
    target_buy_city  TEXT,
    target_sell_city TEXT,
    last_profit      NUMERIC(12,2) DEFAULT 0,
    total_profit     NUMERIC(12,2) DEFAULT 0,
    trips_completed  INTEGER  NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_p3_npc_good ON p3_npc_ships(good_id);

-- ── NPC trade log (admin-visible only) ───────────────────────────────────
CREATE TABLE IF NOT EXISTS p3_npc_trade_log (
    log_id      SERIAL PRIMARY KEY,
    game_year   INTEGER,
    game_day    INTEGER,
    ship_id     INTEGER REFERENCES p3_ships(ship_id),
    ship_name   TEXT,
    good_id     INTEGER REFERENCES p3_goods(good_id),
    good_name   TEXT,
    action      TEXT,
    city        TEXT,
    quantity    INTEGER,
    price       NUMERIC(10,2),
    profit      NUMERIC(12,2),
    logged_at   TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
--  FUNCTIONS
-- =============================================================================

-- ── Hex helpers ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION p3_hex_distance(q1 INT, r1 INT, q2 INT, r2 INT)
RETURNS INTEGER LANGUAGE sql IMMUTABLE AS $$
    SELECT GREATEST(ABS(q1-q2), ABS(r1-r2), ABS((-q1-r1)-(-q2-r2)));
$$;

CREATE OR REPLACE FUNCTION p3_hex_neighbors(q INT, r INT)
RETURNS TABLE(nq INT, nr INT) LANGUAGE sql IMMUTABLE AS $$
    VALUES (q+1,r),(q+1,r-1),(q,r-1),(q-1,r),(q-1,r+1),(q,r+1);
$$;

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
    WHERE ca.city_id = city_a_id AND cb.city_id = city_b_id
      AND ca.hex_q IS NOT NULL AND cb.hex_q IS NOT NULL;
$$;

-- ── Counting house cost (scales with population) ──────────────────────────
CREATE OR REPLACE FUNCTION p3_counting_house_cost(p_city_name TEXT)
RETURNS INTEGER LANGUAGE sql STABLE AS $$
    SELECT CASE
        WHEN population >= 50000 THEN 2000
        WHEN population >= 20000 THEN 1500
        WHEN population >= 10000 THEN 1000
        ELSE 500
    END FROM p3_cities WHERE name = p_city_name;
$$;

-- ── Fog of war: cities visible to the player ─────────────────────────────
--  Admins see all. Others see: home city, cities with docked ships,
--  cities with counting houses.
CREATE OR REPLACE FUNCTION p3_player_visible_city_ids()
RETURNS TABLE(city_id INTEGER) LANGUAGE sql STABLE AS $$
    SELECT ci.city_id FROM p3_cities ci
        WHERE (SELECT is_admin FROM p3_player LIMIT 1)
    UNION
    SELECT ci2.city_id FROM p3_ships s
        JOIN p3_cities ci2 ON ci2.name = s.current_city
        WHERE s.owner = 'player' AND s.status = 'docked'
          AND NOT (SELECT is_admin FROM p3_player LIMIT 1)
    UNION
    SELECT ch.city_id FROM p3_counting_houses ch
        WHERE NOT (SELECT is_admin FROM p3_player LIMIT 1)
    UNION
    SELECT ci3.city_id FROM p3_cities ci3
        JOIN p3_player pl ON ci3.name = pl.home_city
        WHERE NOT (SELECT is_admin FROM p3_player LIMIT 1);
$$;

-- ── Marginal pricing ──────────────────────────────────────────────────────
--  Price moves with stock level, seasonality, category volatility,
--  scarcity curve, and panic/glut modifiers.
CREATE OR REPLACE FUNCTION p3_marginal_price(
    p_city_id    INT,
    p_good_id    INT,
    p_action     TEXT,
    p_qty_offset INT,
    p_game_day   INT
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

    v_effective_stock := GREATEST(
        CASE WHEN p_action = 'buy'
             THEN v_stock - p_qty_offset
             ELSE v_stock + p_qty_offset
        END, 1
    );

    v_season_mod := 1.0 + 0.10 * SIN(
        (p_game_day::NUMERIC / 360.0) * 2.0 * PI()
        + CASE v_category
            WHEN 'food'     THEN PI()
            WHEN 'material' THEN PI() / 2.0
            WHEN 'luxury'   THEN -PI() / 2.0
            ELSE PI() / 4.0
          END
    );

    v_vol_mod := CASE v_category
        WHEN 'luxury'   THEN 1.25
        WHEN 'food'     THEN 0.88
        WHEN 'material' THEN 1.05
        ELSE 1.0
    END;

    v_scarcity := POWER(
        v_stock_ref::NUMERIC / v_effective_stock::NUMERIC,
        v_elast
    );

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

    IF p_action = 'buy'  THEN v_price := v_price * 1.08; END IF;
    IF p_action = 'sell' THEN v_price := v_price * 0.92; END IF;

    RETURN GREATEST(
        v_mid * v_floor_pct,
        LEAST(v_mid * v_ceil_pct, ROUND(v_price, 2))
    );
END;
$$;

-- ── pg_notify helper ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION p3_notify_tick()
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_payload TEXT;
BEGIN
    SELECT json_build_object(
        'year', game_year, 'day', game_day,
        'gold', ROUND(gold, 2), 'rank', rank
    )::text INTO v_payload FROM p3_player LIMIT 1;
    PERFORM pg_notify('p3_day_tick', COALESCE(v_payload, '{}'));
END;
$$;

-- =============================================================================
--  VIEWS
-- =============================================================================

-- ── Fleet (player only) ───────────────────────────────────────────────────
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

-- ── Full market view (admin / NPC use only) ───────────────────────────────
CREATE OR REPLACE VIEW p3_market_view AS
SELECT ci.name AS city, ci.league, g.name AS good, g.category,
       m.current_buy, m.current_sell,
       g.buy_price_min AS ref_buy_max, g.sell_price_min AS ref_sell_min,
       g.sell_price_max AS ref_sell_max, m.stock,
       ROUND(m.current_buy - m.current_sell, 2) AS spread,
       CASE
           WHEN m.current_buy  <= g.buy_price_min  THEN 'GOOD BUY'
           WHEN m.current_sell >= g.sell_price_max THEN 'GREAT SELL'
           WHEN m.current_sell >= g.sell_price_min THEN 'GOOD SELL'
           ELSE '--'
       END AS signal
FROM p3_market m
JOIN p3_cities ci ON ci.city_id = m.city_id
JOIN p3_goods  g  ON g.good_id  = m.good_id
ORDER BY ci.name, g.name;

-- ── Player-visible market view (fog of war filtered) ─────────────────────
CREATE OR REPLACE VIEW p3_visible_market_view AS
SELECT ci.name AS city, ci.league, g.name AS good, g.category,
       m.current_buy, m.current_sell,
       g.buy_price_min AS ref_buy_max, g.sell_price_min AS ref_sell_min,
       g.sell_price_max AS ref_sell_max, m.stock,
       ROUND(m.current_buy - m.current_sell, 2) AS spread,
       CASE
           WHEN m.current_buy  <= g.buy_price_min  THEN 'GOOD BUY'
           WHEN m.current_sell >= g.sell_price_max THEN 'GREAT SELL'
           WHEN m.current_sell >= g.sell_price_min THEN 'GOOD SELL'
           ELSE '--'
       END AS signal
FROM   p3_market m
JOIN   p3_cities ci ON ci.city_id = m.city_id
JOIN   p3_goods  g  ON g.good_id  = m.good_id
WHERE  m.city_id IN (SELECT city_id FROM p3_player_visible_city_ids())
ORDER  BY ci.name, g.name;

-- ── Lubeck market view (always visible on dashboard) ─────────────────────
CREATE OR REPLACE VIEW p3_lubeck_market_view AS
SELECT g.name AS good, g.category,
       m.current_buy AS ask, m.current_sell AS bid, m.stock,
       CASE
           WHEN m.current_buy  <= g.buy_price_min  THEN 'BUY'
           WHEN m.current_sell >= g.sell_price_max THEN 'SELL!'
           WHEN m.current_sell >= g.sell_price_min THEN 'SELL'
           ELSE '--'
       END AS signal
FROM   p3_market m
JOIN   p3_cities ci ON ci.city_id = m.city_id AND ci.name = 'Lubeck'
JOIN   p3_goods  g  ON g.good_id  = m.good_id
ORDER  BY g.category, m.current_sell DESC;

-- ── Admin arbitrage view ──────────────────────────────────────────────────
CREATE OR REPLACE VIEW p3_admin_arbitrage_view AS
SELECT bm.city AS buy_city, sm.city AS sell_city, bm.good,
       bm.current_buy AS buy_price, sm.current_sell AS sell_price,
       ROUND(sm.current_sell - bm.current_buy, 2) AS profit_per_unit,
       bm.stock AS buy_stock, sm.stock AS sell_stock,
       COALESCE(
           (SELECT r.travel_days FROM p3_routes r
            WHERE (r.city_a = bm.city AND r.city_b = sm.city)
               OR (r.city_b = bm.city AND r.city_a = sm.city)
            ORDER BY r.travel_days LIMIT 1), NULL
       ) AS route_days_snaikka
FROM   p3_market_view bm
JOIN   p3_market_view sm ON sm.good = bm.good AND sm.city <> bm.city
WHERE  sm.current_sell > bm.current_buy
ORDER  BY profit_per_unit DESC;

-- ── Admin cross-league arbitrage view ────────────────────────────────────
CREATE OR REPLACE VIEW p3_admin_crossleague_view AS
SELECT av.buy_city, av.sell_city, av.good,
       av.buy_price, av.sell_price, av.profit_per_unit,
       av.route_days_snaikka,
       CASE WHEN av.route_days_snaikka IS NOT NULL
            THEN GREATEST(1, ROUND(av.route_days_snaikka * 5.0 / 7.0)::INTEGER)
       END AS days_crayer,
       CASE WHEN av.route_days_snaikka IS NOT NULL
            THEN GREATEST(1, ROUND(av.route_days_snaikka * 5.0 / 9.0)::INTEGER)
       END AS days_galley
FROM   p3_admin_arbitrage_view av
WHERE  av.profit_per_unit > 0 AND (
    (av.buy_city  IN (SELECT name FROM p3_cities WHERE league = 'Hanseatic')
     AND av.sell_city IN (SELECT name FROM p3_cities WHERE league = 'Mediterranean'))
    OR
    (av.buy_city  IN (SELECT name FROM p3_cities WHERE league = 'Mediterranean')
     AND av.sell_city IN (SELECT name FROM p3_cities WHERE league = 'Hanseatic'))
)
ORDER  BY av.profit_per_unit DESC;

-- ── NPC ships visible to player ───────────────────────────────────────────
--  Only visible in cities where the player has a docked ship or counting house.
CREATE OR REPLACE VIEW p3_visible_npc_ships AS
SELECT s.ship_id, s.name, s.ship_type, s.current_city,
       s.status, s.destination, s.eta_days,
       g.name AS specialisation
FROM   p3_ships s
JOIN   p3_npc_ships ns ON ns.npc_ship_id = s.ship_id
JOIN   p3_goods g ON g.good_id = ns.good_id
WHERE  s.owner = 'npc'
  AND  s.current_city IN (
      SELECT current_city FROM p3_ships WHERE owner = 'player' AND status = 'docked'
      UNION
      SELECT city_name FROM p3_counting_houses
  );

-- ── NPC fleet summary (admin only) ───────────────────────────────────────
CREATE OR REPLACE VIEW p3_npc_fleet_summary AS
SELECT s.name AS ship, g.name AS specialisation,
       s.current_city, s.status,
       COALESCE(s.destination, '--') AS destination,
       ns.ai_state, ns.trips_completed,
       ROUND(ns.total_profit, 2) AS total_profit,
       ROUND(ns.last_profit,  2) AS last_trip_profit
FROM   p3_ships s
JOIN   p3_npc_ships ns ON ns.npc_ship_id = s.ship_id
JOIN   p3_goods g ON g.good_id = ns.good_id
ORDER  BY s.name;
