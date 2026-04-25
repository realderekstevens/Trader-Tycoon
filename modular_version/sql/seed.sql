-- =============================================================================
--  sql/seed.sql  --  Patrician III / IV reference data
--
--  Apply AFTER schema.sql.  All statements are idempotent:
--    ON CONFLICT DO NOTHING  or  ON CONFLICT DO UPDATE
--  Safe to re-run to pick up changes.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
--  1. GOODS  (28 total)
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO p3_goods
    (name, category, buy_price_min, sell_price_min, sell_price_max,
     max_satisfaction, base_production, is_raw_material, notes)
VALUES
    ('Beer',       'food',      38,    44,   60,   40,  1.600, FALSE, 'Big Four staple, Grain->Beer'),
    ('Bricks',     'material',  80,   130,  140, NULL,  0.480, FALSE, 'Building material'),
    ('Fish',       'food',     450,   490,  540,  515,  0.400, FALSE, 'Big Four, preserved with Salt'),
    ('Grain',      'food',      95,   140,  160,  141,  0.800,  TRUE, 'Big Four raw, abundant'),
    ('Hemp',       'material', 400,   500,  600, NULL,  0.320,  TRUE, 'Rope and rigging raw'),
    ('Honey',      'food',     110,   160,  180,  128,  0.260,  TRUE, 'Apiary raw'),
    ('Salt',       'material',  27,    33,   50,   32,  1.120,  TRUE, 'Preservation raw'),
    ('Timber',     'material',  57,    75,   95,   70,  0.640,  TRUE, 'Shipbuilding raw'),
    ('Pitch',      'material',  60,   100,  120, NULL,  0.380, FALSE, 'Waterproofing'),
    ('Whale Oil',  'material',  72,   100,  150,   96,  0.260, FALSE, 'Lamp oil'),
    ('Pottery',    'commodity', 185,  230,  250,  200,  0.320, FALSE, 'Low-tier luxury'),
    ('Cloth',      'luxury',   220,   340,  350,  242,  0.260, FALSE, 'Wool->Cloth'),
    ('Iron Goods', 'luxury',   320,   430,  450,  300,  0.190, FALSE, 'Pig Iron->Iron Goods'),
    ('Meat',       'food',     950,  1250, 1500, 1120,  0.160, FALSE, 'Cattle'),
    ('Leather',    'commodity', 250,  300,  340,  262,  0.320, FALSE, 'By-product of cattle'),
    ('Pig Iron',   'material', 900,  1200, 1300, NULL,  0.270,  TRUE, 'Smelter raw'),
    ('Skins',      'luxury',   850,   900, 1400,  791,  0.160,  TRUE, 'Fur trade'),
    ('Wool',       'material', 925,  1300, 1300, 1030,  0.230,  TRUE, 'Sheep raw'),
    ('Spices',     'luxury',   280,   350,  400,  327,  0.097, FALSE, 'Mediterranean imports'),
    ('Wine',       'luxury',   230,   350,  400,  257,  0.160, FALSE, 'Vineyard'),
    ('Olive Oil',  'luxury',   180,   240,  320,  210,  0.210, FALSE, 'Med staple'),
    ('Silk',       'luxury',  1200,  1600, 2200, 1400,  0.065, FALSE, 'Top-tier luxury'),
    ('Glass',      'luxury',   320,   420,  550,  380,  0.120, FALSE, 'Venice specialty'),
    ('Sand',       'material',  10,    12,   18, NULL,  1.400,  TRUE, 'Glassworks raw'),
    ('Cotton',     'material', 180,   240,  290, NULL,  0.320,  TRUE, 'Cloth alternative'),
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

-- ─────────────────────────────────────────────────────────────────────────────
--  2. CITIES
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO p3_cities (name, region, population, latitude, longitude, league) VALUES
    ('Aalborg',        'North Sea',      26660, 57.05, 9.916667,         'Hanseatic'),
    ('Bergen',         'North Sea',      12006, 60.3894, 5.3300,         'Hanseatic'),
    ('Brugge',         'West',           93884, 51.2097, 3.2247,         'Hanseatic'),
    ('Bremen',         'West',           17612, 53.0833, 8.8,            'Hanseatic'),
    ('Cologne',        'Rhine',          25084, 50.9364, 6.9528,         'Hanseatic'),
    ('Edinburgh',      'British',        23061, 55.9533, -3.1883,        'Hanseatic'),
    ('Gdansk',         'Baltic',         33318, 54.35205, 18.64637,      'Hanseatic'),
    ('Groningen',      'West',           16558, 53.2167, 6.55,           'Hanseatic'),
    ('Hamburg',        'West',           34771, 53.5511, 9.9937,         'Hanseatic'),
    ('Ladoga',         'East',           10329, 61, 31.5,                'Hanseatic'),
    ('London',         'British',        42914, 51.5074, 0.1278,         'Hanseatic'),
    ('Lubeck',         'Baltic',         18206, 53.866268999, 10.683932, 'Hanseatic'),
    ('Malmo',          'Baltic',         24759, 55.6033, 13.0013,        'Hanseatic'),
    ('Novgorod',       'East',           27462, 58.5215, 31.2722,        'Hanseatic'),
    ('Oslo',           'North Sea',      19206, 59.9139, 10.7522,        'Hanseatic'),
    ('Reval',          'Baltic',          7480, 59.4370, 24.7536,        'Hanseatic'),
    ('Riga',           'Baltic',         17026, 56.9489, 24.10639,       'Hanseatic'),
    ('Ribe',           'North Sea',       8961, 55.3275, 8.7617,         'Hanseatic'),
    ('Rostock',        'Baltic',         20764, 54.0887, 12.14049,       'Hanseatic'),
    ('Scarborough',    'British',        17423, 54.283113, -0.399752,    'Hanseatic'),
    ('Stettin',        'Baltic',         29761, 53.4325, 14.6215,        'Hanseatic'),
    ('Stockholm',      'Baltic',         21820, 59.3340445, 18.0082345,  'Hanseatic'),
    ('Torun',          'Baltic',         15944, 53.0102719, 18.6048094,  'Hanseatic'),
    ('Visby',          'Baltic',          7258, 57.6347, 18.2992,        'Hanseatic'),
    ('Venice',         'Mediterranean', 116000, 45.436, 12.334,          'Mediterranean'),
    ('Genoa',          'Mediterranean', 148000, 44.4070624, 8.9339889,   'Mediterranean'),
    ('Marseille',      'Mediterranean',  46358, 43.2957, 5.4043,         'Mediterranean'),
    ('Barcelona',      'Mediterranean',  60681, 41.3887901, 2.1589899,   'Mediterranean'),
    ('Lisbon',         'Atlantic',       53345, 38.725262, -9.149998,    'Mediterranean'),
    ('Constantinople', 'Bosphorus',     120000, 41.0122, 28.9760,        'Mediterranean'),
    ('Naples',         'Mediterranean', 286000, 40.85631, 14.24641,      'Mediterranean'),
    ('Palermo',        'Mediterranean',  76153, 38.1111, 13.3517,        'Mediterranean'),
    ('Tunis',          'North Africa',   33194, 36.8065, 10.1817,        'Mediterranean'),
    ('Alexandria',     'North Africa',  227000, 31.2001, 29.9187,        'Mediterranean')
ON CONFLICT (name) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
--  3. HEX COORDINATES  (pointy-top axial, Lubeck = 0,0)
-- ─────────────────────────────────────────────────────────────────────────────
WITH city_coords(city_name, q, r) AS (VALUES
    ('Lubeck',           0,   0),  ('Hamburg',         -1,   0),
    ('Rostock',          1,   0),  ('Stettin',          3,   1),
    ('Gdansk',           6,  -1),  ('Riga',             9,  -4),
    ('Reval',           10,  -7),  ('Novgorod',        15,  -6),
    ('Stockholm',        5,  -7),  ('Visby',            5,  -5),
    ('Malmo',            2,  -2),  ('Bergen',          -4,  -8),
    ('Oslo',             0,  -7),  ('Aalborg',         -1,  -4),
    ('Ripen',           -1,  -2),  ('Scarborough',     -8,   0),
    ('Edinburgh',      -10,  -3),  ('London',          -8,   3),
    ('Brugge',          -5,   3),  ('Groningen',       -3,   1),
    ('Bremen',          -1,   1),  ('Cologne',         -3,   4),
    ('Torun',            6,   1),  ('Ladoga',          15,  -7),
    ('Venice',           1,  10),  ('Genoa',           -1,  11),
    ('Marseille',       -4,  13),  ('Barcelona',       -6,  15),
    ('Lisbon',         -14,  18),  ('Constantinople',  13,  15),
    ('Naples',           3,  16),  ('Palermo',          2,  19),
    ('Tunis',            0,  20),  ('Alexandria',      14,  27)
)
UPDATE p3_cities ci SET hex_q = cc.q, hex_r = cc.r
FROM city_coords cc WHERE ci.name = cc.city_name;

INSERT INTO p3_hex_tiles (q, r, terrain, city_id)
SELECT ci.hex_q, ci.hex_r,
       CASE WHEN ci.name IN
           ('Novgorod','Groningen','Bremen','Cologne','Torun','Ladoga',
            'Constantinople','Alexandria','Tunis')
           THEN 'land' ELSE 'coast' END,
       ci.city_id
FROM p3_cities ci WHERE ci.hex_q IS NOT NULL
ON CONFLICT (q, r) DO UPDATE
    SET city_id = EXCLUDED.city_id, terrain = EXCLUDED.terrain;

-- ─────────────────────────────────────────────────────────────────────────────
--  4. CITY PRODUCTION & DEMAND
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO p3_city_goods (city_id, good_id, role, efficiency)
SELECT ci.city_id, g.good_id, v.role, v.efficiency
FROM (VALUES
    ('Aalborg','Meat','produces',120),     ('Aalborg','Pig Iron','produces',120),
    ('Aalborg','Timber','produces',120),   ('Aalborg','Whale Oil','produces',110),
    ('Aalborg','Beer','demands',100),      ('Aalborg','Iron Goods','demands',100),
    ('Bergen','Whale Oil','produces',120), ('Bergen','Pitch','produces',110),
    ('Bergen','Iron Goods','demands',100), ('Bergen','Meat','demands',100),
    ('Brugge','Hemp','produces',120),      ('Brugge','Wool','produces',120),
    ('Brugge','Salt','produces',110),      ('Brugge','Pottery','produces',110),
    ('Brugge','Cloth','demands',100),
    ('Bremen','Beer','produces',120),      ('Bremen','Bricks','produces',120),
    ('Bremen','Cloth','produces',110),     ('Bremen','Iron Goods','produces',120),
    ('Bremen','Spices','demands',100),
    ('Cologne','Honey','produces',120),    ('Cologne','Wine','produces',120),
    ('Cologne','Pottery','produces',110),  ('Cologne','Spices','demands',100),
    ('Edinburgh','Cloth','produces',110),  ('Edinburgh','Fish','produces',120),
    ('Edinburgh','Iron Goods','produces',110),
    ('Gdansk','Beer','produces',120),      ('Gdansk','Grain','produces',120),
    ('Gdansk','Hemp','produces',120),      ('Gdansk','Meat','produces',110),
    ('Gdansk','Pitch','produces',110),
    ('Groningen','Bricks','produces',120), ('Groningen','Grain','produces',120),
    ('Groningen','Hemp','produces',110),   ('Groningen','Timber','produces',110),
    ('Hamburg','Beer','produces',120),     ('Hamburg','Fish','produces',120),
    ('Hamburg','Grain','produces',120),    ('Hamburg','Hemp','produces',110),
    ('Hamburg','Salt','demands',100),
    ('Ladoga','Fish','produces',110),      ('Ladoga','Grain','produces',120),
    ('Ladoga','Hemp','produces',110),      ('Ladoga','Pig Iron','produces',120),
    ('Ladoga','Skins','produces',120),
    ('London','Beer','produces',120),      ('London','Cloth','produces',120),
    ('London','Meat','produces',120),      ('London','Pig Iron','produces',110),
    ('London','Wool','produces',120),      ('London','Spices','demands',100),
    ('London','Wine','demands',100),
    ('Lubeck','Bricks','produces',120),    ('Lubeck','Fish','produces',120),
    ('Lubeck','Iron Goods','produces',120),('Lubeck','Pitch','produces',110),
    ('Malmo','Cloth','produces',110),      ('Malmo','Meat','produces',110),
    ('Malmo','Wool','produces',110),
    ('Novgorod','Beer','produces',110),    ('Novgorod','Meat','produces',120),
    ('Novgorod','Pitch','produces',120),   ('Novgorod','Skins','produces',120),
    ('Novgorod','Timber','produces',120),
    ('Oslo','Bricks','produces',110),      ('Oslo','Pig Iron','produces',120),
    ('Oslo','Pitch','produces',120),       ('Oslo','Timber','produces',120),
    ('Oslo','Whale Oil','produces',120),
    ('Reval','Grain','produces',120),      ('Reval','Iron Goods','produces',110),
    ('Reval','Salt','produces',120),       ('Reval','Skins','produces',120),
    ('Riga','Fish','produces',120),        ('Riga','Honey','produces',110),
    ('Riga','Pitch','produces',120),       ('Riga','Salt','produces',120),
    ('Riga','Skins','produces',110),
    ('Ripen','Bricks','produces',120),     ('Ripen','Pig Iron','produces',110),
    ('Ripen','Pottery','produces',110),    ('Ripen','Salt','produces',120),
    ('Ripen','Whale Oil','produces',120),
    ('Rostock','Grain','produces',120),    ('Rostock','Hemp','produces',110),
    ('Rostock','Honey','produces',120),    ('Rostock','Pottery','produces',110),
    ('Rostock','Salt','produces',110),
    ('Scarborough','Beer','produces',110), ('Scarborough','Cloth','produces',110),
    ('Scarborough','Iron Goods','produces',110),('Scarborough','Timber','produces',110),
    ('Scarborough','Wool','produces',120),
    ('Stettin','Beer','produces',120),     ('Stettin','Fish','produces',120),
    ('Stettin','Grain','produces',120),    ('Stettin','Hemp','produces',120),
    ('Stettin','Salt','produces',110),
    ('Stockholm','Iron Goods','produces',120),('Stockholm','Pig Iron','produces',120),
    ('Stockholm','Timber','produces',120), ('Stockholm','Whale Oil','produces',110),
    ('Torun','Honey','produces',120),      ('Torun','Meat','produces',110),
    ('Torun','Pottery','produces',110),    ('Torun','Timber','produces',110),
    ('Torun','Wool','produces',110),
    ('Visby','Cloth','produces',110),      ('Visby','Honey','produces',110),
    ('Visby','Pottery','produces',110),    ('Visby','Wool','produces',110),
    -- Mediterranean
    ('Venice','Glass','produces',130),     ('Venice','Silk','produces',120),
    ('Venice','Salt','produces',110),      ('Venice','Spices','demands',100),
    ('Venice','Olive Oil','demands',100),
    ('Genoa','Olive Oil','produces',120),  ('Genoa','Cloth','produces',110),
    ('Genoa','Alum','produces',110),       ('Genoa','Spices','demands',100),
    ('Marseille','Wine','produces',130),   ('Marseille','Olive Oil','produces',120),
    ('Marseille','Salt','produces',110),
    ('Barcelona','Wine','produces',120),   ('Barcelona','Cotton','produces',120),
    ('Barcelona','Cloth','produces',110),
    ('Lisbon','Salt','produces',120),      ('Lisbon','Fish','produces',120),
    ('Constantinople','Silk','produces',130),('Constantinople','Spices','produces',120),
    ('Constantinople','Alum','produces',120),('Constantinople','Glass','demands',100),
    ('Constantinople','Cloth','demands',100),
    ('Naples','Wine','produces',110),      ('Naples','Olive Oil','produces',110),
    ('Naples','Grain','produces',110),
    ('Palermo','Grain','produces',130),    ('Palermo','Salt','produces',120),
    ('Palermo','Cotton','produces',110),
    ('Tunis','Dates','produces',130),      ('Tunis','Ivory','produces',110),
    ('Tunis','Leather','produces',120),
    ('Alexandria','Cotton','produces',130),('Alexandria','Dates','produces',120),
    ('Alexandria','Spices','produces',120),('Alexandria','Ivory','produces',110)
) AS v(city_name, good_name, role, efficiency)
JOIN p3_cities ci ON ci.name = v.city_name
JOIN p3_goods  g  ON g.name  = v.good_name
ON CONFLICT (city_id, good_id, role) DO UPDATE SET efficiency = EXCLUDED.efficiency;

-- ─────────────────────────────────────────────────────────────────────────────
--  5. MARKET  (seeded from reference prices + randomised ±15%)
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO p3_market (city_id, good_id, current_buy, current_sell, stock)
SELECT
    ci.city_id, g.good_id,
    ROUND(mid_price * 1.08, 2) AS current_buy,
    ROUND(mid_price * 0.92, 2) AS current_sell,
    CASE WHEN cg.good_id IS NOT NULL
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

-- ─────────────────────────────────────────────────────────────────────────────
--  6. TRADE ROUTES
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO p3_routes (name, city_a, city_b, distance_nm, travel_days, notes) VALUES
    ('Lubeck-Hamburg',       'Lubeck',    'Hamburg',         120,  1, 'Grain/Beer/Fish'),
    ('Lubeck-Rostock',       'Lubeck',    'Rostock',         100,  1, 'Grain/Hemp/Honey'),
    ('Lubeck-Gdansk',        'Lubeck',    'Gdansk',          350,  3, 'Grain/Beer/Hemp east'),
    ('Lubeck-Stockholm',     'Lubeck',    'Stockholm',       650,  5, 'Iron Goods/Pig Iron'),
    ('Lubeck-Bergen',        'Lubeck',    'Bergen',          900,  8, 'Whale Oil/Pitch'),
    ('Lubeck-London',        'Lubeck',    'London',         1050,  9, 'Cloth/Wool long route'),
    ('Hamburg-Brugge',       'Hamburg',   'Brugge',          600,  5, 'Cloth/Wool/Salt west'),
    ('Hamburg-Groningen',    'Hamburg',   'Groningen',       250,  2, 'Hemp/Bricks/Grain'),
    ('Gdansk-Riga',          'Gdansk',    'Riga',            280,  2, 'Grain/Salt Baltic'),
    ('Gdansk-Novgorod',      'Gdansk',    'Novgorod',        500,  4, 'Skins/Timber east'),
    ('Stockholm-Ladoga',     'Stockholm', 'Ladoga',          450,  4, 'Pig Iron/Skins'),
    ('Oslo-Aalborg',         'Oslo',      'Aalborg',         300,  3, 'Timber/Whale Oil'),
    ('Riga-Reval',           'Riga',      'Reval',           200,  2, 'Salt/Skins/Grain Baltic'),
    ('Reval-Novgorod',       'Reval',     'Novgorod',        280,  2, 'Skins/Timber east'),
    ('London-Scarborough',   'London',    'Scarborough',     300,  3, 'Cloth/Wool/Beer British'),
    ('Bergen-Scarborough',   'Bergen',    'Scarborough',     600,  5, 'Whale Oil to Britain'),
    ('Visby-Gdansk',         'Visby',     'Gdansk',          220,  2, 'Cloth/Honey/Pottery'),
    ('Visby-Lubeck',         'Visby',     'Lubeck',          420,  4, 'Cloth/Wool loop'),
    ('Brugge-London',        'Brugge',    'London',          280,  2, 'Cloth/Salt/Spices'),
    ('Cologne-Brugge',       'Cologne',   'Brugge',          240,  2, 'Wine/Honey Rhine'),
    ('Venice-Genoa',         'Venice',    'Genoa',           500,  3, 'Silk/Glass/Wine'),
    ('Genoa-Marseille',      'Genoa',     'Marseille',       280,  2, 'Spices/Olive Oil'),
    ('Marseille-Barcelona',  'Marseille', 'Barcelona',       400,  3, 'Wine/Cloth/Spices'),
    ('Barcelona-Lisbon',     'Barcelona', 'Lisbon',          800,  6, 'Atlantic gateway'),
    ('Venice-Constantinople','Venice',    'Constantinople', 1400,  9, 'Silk/Spices luxury run'),
    ('Genoa-Tunis',          'Genoa',     'Tunis',           600,  4, 'Spices/Leather/Ivory'),
    ('Marseille-Naples',     'Marseille', 'Naples',          600,  4, 'Olive Oil/Wine south'),
    ('Naples-Palermo',       'Naples',    'Palermo',         280,  2, 'Grain/Salt Sicily'),
    ('Genoa-Alexandria',     'Genoa',     'Alexandria',     1800, 12, 'Cotton/Ivory/Dates far east'),
    ('Lisbon-London',        'Lisbon',    'London',         1200,  8, 'Connects Med to Hanse')
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
--  7. BUILDING TYPES  (18 Hanseatic + 7 Mediterranean = 25 total)
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO p3_building_types
    (name, output_good_id, input_good_id, input_units_per_output,
     base_production, construction_cost, daily_maintenance, notes)
SELECT bt.name, g_out.good_id, g_in.good_id,
       bt.input_u, bt.prod, bt.cost, bt.maint, bt.notes
FROM (VALUES
    ('Grain Farm',          'Grain',      NULL,        0.000, 0.233,  5000,  25.67, 'Raw'),
    ('Hemp Farm',           'Hemp',       NULL,        0.000, 0.058,  4000,  25.67, 'Raw'),
    ('Sheep Farm',          'Wool',       NULL,        0.000, 0.117,  6000, 112.00, 'Raw'),
    ('Apiary',              'Honey',      NULL,        0.000, 0.467,  3000,  49.00, 'Raw'),
    ('Vineyard',            'Wine',       NULL,        0.000, 0.467,  8000,  98.00, 'Raw'),
    ('Sawmill',             'Timber',     NULL,        0.000, 0.467,  2500,  28.00, 'Raw'),
    ('Iron Smelter',        'Pig Iron',   NULL,        0.000, 0.117, 10000, 112.00, 'Raw'),
    ('Saltworks',           'Salt',       NULL,        0.000, 1.167,  4000,  30.33, 'Raw, high output'),
    ('Pottery Workshop',    'Pottery',    NULL,        0.000, 0.467,  5000,  84.00, 'Finished'),
    ('Pitchmaker',          'Pitch',      NULL,        0.000, 0.233,  2000,  12.83, 'Finished'),
    ('Brickworks',          'Bricks',     NULL,        0.000, 0.233,  2000,  12.83, 'Finished'),
    ('Hunting Lodge',       'Skins',      NULL,        0.000, 0.233,  7000, 168.00, 'Raw'),
    ('Cattle Farm',         'Meat',       NULL,        0.000, 0.058, 10000, 114.33, 'Raw, slow high value'),
    ('Fishery',             'Fish',       'Salt',      0.050, 0.233,  6000,  84.00, 'Needs Salt'),
    ('Whaling Station',     'Whale Oil',  NULL,        0.000, 0.933,  8000, 140.00, 'Finished'),
    ('Brewery',             'Beer',       'Grain',     0.140, 1.633,  8000,  60.67, 'Grain->Beer, highest output'),
    ('Weaving Mill',        'Cloth',      'Wool',      0.100, 0.700,  9000, 102.67, 'Wool->Cloth'),
    ('Iron Goods Workshop', 'Iron Goods', 'Pig Iron',  0.500, 0.700, 12000, 121.33, 'Best margin'),
    ('Olive Grove',         'Olive Oil',  NULL,        0.000, 0.350,  6000,  45.00, 'P4 Med'),
    ('Winery (Med)',        'Wine',       NULL,        0.000, 0.583,  8000,  98.00, 'P4 Med'),
    ('Silk Workshop',       'Silk',       NULL,        0.000, 0.117, 15000, 280.00, 'P4 top-tier luxury'),
    ('Spice Warehouse',     'Spices',     NULL,        0.000, 0.150, 12000, 200.00, 'P4 redistribution'),
    ('Glassworks',          'Glass',      'Sand',      0.200, 0.280,  9000, 120.00, 'P4 Venice specialty'),
    ('Cotton Gin',          'Cotton',     NULL,        0.000, 0.400,  5000,  55.00, 'P4'),
    ('Alum Works',          'Alum',       NULL,        0.000, 0.240,  8000,  90.00, 'P4 dyeing agent')
) AS bt(name, out_good, in_good, input_u, prod, cost, maint, notes)
JOIN p3_goods g_out ON g_out.name = bt.out_good
LEFT JOIN p3_goods g_in ON g_in.name = bt.in_good
ON CONFLICT (name) DO UPDATE SET
    base_production   = EXCLUDED.base_production,
    construction_cost = EXCLUDED.construction_cost,
    daily_maintenance = EXCLUDED.daily_maintenance,
    notes             = EXCLUDED.notes;

-- ─────────────────────────────────────────────────────────────────────────────
--  8. MARGINAL PRICE ELASTICITY  (all 28 goods)
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO p3_good_elasticity
    (good_id, elasticity_buy, elasticity_sell, stock_ref, price_floor_pct, price_ceil_pct)
SELECT g.good_id,
       CASE g.name
           WHEN 'Ivory'      THEN 0.75  WHEN 'Silk'       THEN 0.70
           WHEN 'Skins'      THEN 0.65  WHEN 'Spices'     THEN 0.60
           WHEN 'Wool'       THEN 0.55  WHEN 'Cloth'      THEN 0.55
           WHEN 'Iron Goods' THEN 0.50  WHEN 'Meat'       THEN 0.50
           WHEN 'Glass'      THEN 0.48  WHEN 'Olive Oil'  THEN 0.45
           WHEN 'Whale Oil'  THEN 0.45  WHEN 'Pig Iron'   THEN 0.45
           WHEN 'Wine'       THEN 0.45  WHEN 'Alum'       THEN 0.42
           WHEN 'Cotton'     THEN 0.40  WHEN 'Honey'      THEN 0.40
           WHEN 'Dates'      THEN 0.38  WHEN 'Pottery'    THEN 0.38
           WHEN 'Hemp'       THEN 0.35  WHEN 'Leather'    THEN 0.35
           WHEN 'Beer'       THEN 0.30  WHEN 'Fish'       THEN 0.30
           WHEN 'Grain'      THEN 0.25  WHEN 'Timber'     THEN 0.25
           WHEN 'Salt'       THEN 0.22  WHEN 'Bricks'     THEN 0.20
           WHEN 'Pitch'      THEN 0.20  WHEN 'Sand'       THEN 0.10
           ELSE 0.35
       END AS elasticity_buy,
       CASE g.name
           WHEN 'Ivory'      THEN 0.65  WHEN 'Silk'       THEN 0.60
           WHEN 'Skins'      THEN 0.55  WHEN 'Spices'     THEN 0.50
           WHEN 'Wool'       THEN 0.45  WHEN 'Cloth'      THEN 0.45
           WHEN 'Iron Goods' THEN 0.40  WHEN 'Meat'       THEN 0.40
           WHEN 'Glass'      THEN 0.38  WHEN 'Olive Oil'  THEN 0.35
           WHEN 'Wine'       THEN 0.35  WHEN 'Beer'       THEN 0.22
           WHEN 'Grain'      THEN 0.18  WHEN 'Salt'       THEN 0.15
           WHEN 'Sand'       THEN 0.08  ELSE 0.28
       END AS elasticity_sell,
       CASE WHEN g.is_raw_material THEN 120 ELSE 80 END AS stock_ref,
       0.30 AS price_floor_pct,
       3.50 AS price_ceil_pct
FROM p3_goods g
ON CONFLICT (good_id) DO UPDATE SET
    elasticity_buy  = EXCLUDED.elasticity_buy,
    elasticity_sell = EXCLUDED.elasticity_sell,
    stock_ref       = EXCLUDED.stock_ref;

-- ─────────────────────────────────────────────────────────────────────────────
--  9. PLAYER + STARTING SHIP
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO p3_player (name, home_city, gold, rank, game_year, game_day, is_admin)
VALUES ('Merchant', 'Lubeck', 2000, 'Apprentice', 1300, 1, FALSE)
ON CONFLICT DO NOTHING;

INSERT INTO p3_ships (name, owner, ship_type, cargo_cap, speed_knots, current_city, status)
SELECT 'Henrietta', 'player', 'Snaikka', 50, 5.0, 'Lubeck', 'docked'
WHERE NOT EXISTS (SELECT 1 FROM p3_ships WHERE owner = 'player');

-- ─────────────────────────────────────────────────────────────────────────────
--  10. NPC FACTIONS + FLEET  (13 ships)
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO p3_npc_factions (name, home_city, description) VALUES
    ('Stralsund Brotherhood',  'Rostock',   'Baltic grain and timber traders'),
    ('Bergen Cod Company',     'Bergen',    'North Sea fish and whale oil merchants'),
    ('Rhine Vintners Guild',   'Cologne',   'Wine and honey specialists'),
    ('London Wool Staple',     'London',    'Wool and cloth exporters'),
    ('Novgorod Fur Company',   'Novgorod',  'Eastern fur and skins traders'),
    ('Venice Silk House',      'Venice',    'Mediterranean luxury good merchants')
ON CONFLICT (name) DO NOTHING;

WITH inserted AS (
    INSERT INTO p3_ships (name, owner, ship_type, cargo_cap, speed_knots, current_city, status)
    VALUES
        ('Greifswald Star',    'npc', 'Crayer',  80, 7.0, 'Gdansk',        'docked'),
        ('Wismar Bell',        'npc', 'Hulk',   160, 4.0, 'Hamburg',       'docked'),
        ('Rostock Hawk',       'npc', 'Crayer',  80, 7.0, 'Lubeck',        'docked'),
        ('Aalborg Fisher',     'npc', 'Crayer',  80, 7.0, 'Bergen',        'docked'),
        ('Novgorod Bear',      'npc', 'Hulk',   160, 4.0, 'Novgorod',      'docked'),
        ('Scarborough Fleece', 'npc', 'Crayer',  80, 7.0, 'London',        'docked'),
        ('Rhine Eagle',        'npc', 'Crayer',  80, 7.0, 'Cologne',       'docked'),
        ('Ladoga Trapper',     'npc', 'Snaikka', 50, 5.0, 'Ladoga',        'docked'),
        ('Riga Salt Runner',   'npc', 'Crayer',  80, 7.0, 'Riga',          'docked'),
        ('Stockholm Smith',    'npc', 'Crayer',  80, 7.0, 'Stockholm',     'docked'),
        ('Serenissima',        'npc', 'Carrack',220, 5.5, 'Venice',        'docked'),
        ('Genoa Merchant',     'npc', 'Cog',    120, 6.0, 'Genoa',         'docked'),
        ('Golden Horn',        'npc', 'Galley',  90, 9.0, 'Constantinople','docked')
    ON CONFLICT DO NOTHING
    RETURNING ship_id, name, current_city
)
INSERT INTO p3_npc_ships (npc_ship_id, good_id, home_city)
SELECT i.ship_id, g.good_id, i.current_city
FROM inserted i
JOIN p3_goods g ON g.name = CASE i.name
    WHEN 'Greifswald Star'    THEN 'Grain'
    WHEN 'Wismar Bell'        THEN 'Timber'
    WHEN 'Rostock Hawk'       THEN 'Beer'
    WHEN 'Aalborg Fisher'     THEN 'Fish'
    WHEN 'Novgorod Bear'      THEN 'Skins'
    WHEN 'Scarborough Fleece' THEN 'Wool'
    WHEN 'Rhine Eagle'        THEN 'Wine'
    WHEN 'Ladoga Trapper'     THEN 'Pig Iron'
    WHEN 'Riga Salt Runner'   THEN 'Salt'
    WHEN 'Stockholm Smith'    THEN 'Iron Goods'
    WHEN 'Serenissima'        THEN 'Silk'
    WHEN 'Genoa Merchant'     THEN 'Olive Oil'
    WHEN 'Golden Horn'        THEN 'Spices'
END
ON CONFLICT (npc_ship_id) DO NOTHING;
