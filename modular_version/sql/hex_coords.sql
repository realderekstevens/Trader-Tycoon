-- =============================================================================
--  sql/hex_coords.sql  —  Hex grid coordinates & tile bootstrap
--  Patrician III / IV  ·  pointy-top axial  ·  Lübeck = (0, 0)  ·  1 hex ≈ 50 nm
--
--  Apply AFTER schema.sql and seed.sql (cities must already exist).
--  Safe to re-run: all statements use ON CONFLICT DO UPDATE.
--
--  Grid orientation
--    q  increases eastward
--    r  increases southward
--    s  = −q − r  (stored, never set manually)
--
--  NOTE: 'Ripen' in the original seed was a typo — corrected to 'Ribe' below
--        to match the p3_cities INSERT.
-- =============================================================================

-- ── Step 1: Write axial coordinates onto cities ───────────────────────────────
WITH city_coords (city_name, q, r) AS (VALUES
-- Hanseatic — Baltic core
    ('Lubeck',        0,   0),
    ('Hamburg',      -1,   0),
    ('Rostock',       1,   0),
    ('Stettin',       3,   1),
    ('Gdansk',        6,  -1),
    ('Riga',          9,  -4),
    ('Reval',        10,  -7),
    ('Novgorod',     15,  -6),
    ('Stockholm',     5,  -7),
    ('Visby',         5,  -5),
    ('Malmo',         2,  -2),
    ('Torun',         6,   1),
-- Hanseatic — North Sea / Scandinavia
    ('Bergen',       -4,  -8),
    ('Oslo',          0,  -7),
    ('Aalborg',      -1,  -4),
    ('Ribe',         -1,  -2),   -- was 'Ripen' in original seed (typo)
-- Hanseatic — British Isles
    ('Scarborough',  -8,   0),
    ('Edinburgh',   -10,  -3),
    ('London',       -8,   3),
-- Hanseatic — Rhine / Low Countries
    ('Brugge',       -5,   3),
    ('Groningen',    -3,   1),
    ('Bremen',       -1,   1),
    ('Cologne',      -3,   4),
-- Hanseatic — East
    ('Ladoga',       15,  -7),
-- Mediterranean
    ('Venice',        1,  10),
    ('Genoa',        -1,  11),
    ('Marseille',    -4,  13),
    ('Barcelona',    -6,  15),
    ('Lisbon',      -14,  18),
    ('Constantinople',13, 15),
    ('Naples',        3,  16),
    ('Palermo',       2,  19),
    ('Tunis',         0,  20),
    ('Alexandria',   14,  27)
)
UPDATE p3_cities ci
   SET hex_q = cc.q,
       hex_r = cc.r
  FROM city_coords cc
 WHERE ci.name = cc.city_name;

-- ── Step 2: Bootstrap p3_hex_tiles for every city hex ─────────────────────────
--  Terrain rules (matching original seed logic):
--    land  — inland cities: Novgorod, Groningen, Bremen, Cologne, Torun, Ladoga,
--            Constantinople, Alexandria, Tunis
--    coast — everything else with a city
INSERT INTO p3_hex_tiles (q, r, terrain, city_id)
SELECT
    ci.hex_q,
    ci.hex_r,
    CASE WHEN ci.name IN (
        'Novgorod', 'Groningen', 'Bremen', 'Cologne', 'Torun', 'Ladoga',
        'Constantinople', 'Alexandria', 'Tunis'
    ) THEN 'land' ELSE 'coast' END,
    ci.city_id
FROM p3_cities ci
WHERE ci.hex_q IS NOT NULL
ON CONFLICT (q, r) DO UPDATE
    SET city_id = EXCLUDED.city_id,
        terrain  = EXCLUDED.terrain;

-- ── Step 3: Sanity check (run manually after applying) ────────────────────────
-- SELECT name, hex_q AS q, hex_r AS r, (-hex_q - hex_r) AS s
--   FROM p3_cities
--  WHERE hex_q IS NOT NULL
--  ORDER BY hex_r, hex_q;
