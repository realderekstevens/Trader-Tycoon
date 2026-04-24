# ⚓ Patrician III / IV — Hanseatic Trading Simulation

> A historically grounded medieval trade simulation set in the Hanseatic League, c. 1300.  
> Play as a Lübeck merchant, build a fleet, establish counting houses, and dominate Baltic trade.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue.svg)](https://flutter.dev)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-14+-336791.svg)](https://postgresql.org)
[![Shell](https://img.shields.io/badge/Shell-bash-green.svg)]()

---

## 📖 Overview

Patrician III/IV simulates the economics of the medieval Hanseatic League across **34 cities**
(24 Baltic + 10 Mediterranean), **28 goods**, and a fully dynamic market model with per-unit
marginal pricing, seasonal price swings, panic/glut mechanics, and a live auto-tick simulation
engine. A Flutter frontend provides a cross-platform UI; the CLI edition runs entirely in bash
with a PostgreSQL backend.

### Key Features

- **Dynamic market pricing** — marginal elasticity, seasonal curves, panic spikes, bid/ask spread
- **Pointy-top hex grid** — 1 hex ≈ 50 nm, speed-aware ETA, `p3_travel_days()` SQL function
- **Fleet management** — 6 ship types (Snaikka → Carrack), standing route orders, limit orders
- **Buildings** — 24 building types with daily production, input consumption, and maintenance costs
- **NPC ship AI** — automated merchant fleets that move goods between production cities
- **Fog of war** — players only see market prices in cities where they have ships or counting houses
- **Admin / player roles** — arbitrage data and global market views are admin-only
- **Patrician IV expansion** — Mediterranean cities, goods (Silk, Ivory, Glass…), and ships
- **Real-time simulation** — `pg_notify` tick daemon; Flutter UI updates live via WebSocket

---

## 🗂️ Project Structure

```
patrician3/
├── app.sh                  # Main CLI entry point (sources patrician3.sh)
├── patrician3.sh           # Core game engine — schema, seed, menus, tick daemon
├── npc_ships.sh            # NPC ship AI — automated inter-city trade fleets
├── patrician3_app/         # Flutter cross-platform frontend
│   ├── lib/
│   │   ├── main.dart           # App root, navigation, PostgREST client
│   │   └── hex_map_screen.dart # Interactive hex map widget
│   ├── pubspec.yaml
│   └── setup.sh            # One-time Flutter project wiring script
├── sql/
│   ├── schema.sql          # Standalone schema (mirrors patrician3.sh §14a)
│   ├── seed.sql            # Standalone seed data
│   └── visibility.sql      # Player visibility & admin privilege system
├── docs/
│   ├── GAME_MECHANICS.md   # Pricing model, production rates, elasticity
│   ├── HEX_SYSTEM.md       # Pointy-top coordinate system reference
│   └── SHIP_TYPES.md       # Ship comparison & route economics
├── CHANGELOG.md
├── CONTRIBUTING.md
└── README.md               # This file
```

---

## 🚀 Quick Start

### Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| PostgreSQL | 14+ | `generated columns` required for `p3_hex_tiles.s` |
| [gum](https://github.com/charmbracelet/gum) | any | TUI prompts (`brew install gum`) |
| Flutter SDK | 3.x | For the Flutter frontend |
| bash | 4+ | macOS ships bash 3; use `brew install bash` |

### CLI Edition

```bash
# 1. Clone and configure
git clone https://github.com/yourname/patrician3.git
cd patrician3

# 2. Set your database connection (or export before running)
export PSQL_DB=traderdude
export PSQL_USER=postgres

# 3. Run — first-time setup is in the Initialise / Reset Game menu
./app.sh

# 4. In the game: Setup → Initialise / Reset Game → confirm
#    Then: Simulation → Start Auto-Tick to begin the live economy
```

### Flutter Frontend

```bash
cd patrician3_app

# One-time wiring (run after flutter create . or first clone)
bash setup.sh

# Start a PostgREST server pointing at your PostgreSQL database, then:
flutter run -d linux       # Linux desktop
flutter run -d android     # Android
flutter run -d chrome      # Web (requires Flutter web support)

# First launch: open CONFIG tab, set PostgREST URL (default: http://localhost:3000)
```

---

## 🎮 Gameplay

### Starting Out

You begin as an **Apprentice** merchant in **Lübeck** with:
- **2,000 gold**  
- One **Snaikka** (50 cargo, 5 knots) named *Henrietta*

You can only see market prices in cities where you have **a ship docked** or a **counting house**.
The Lübeck home market is always visible on your dashboard.

### Player Visibility (Fog of War)

| Location | Can See |
|----------|---------|
| City with your docked ship | Full market prices + stock |
| City with your counting house | Full market prices + stock |
| All other cities | City name only |
| Lübeck (home city) | Always visible on dashboard |

Arbitrage opportunities, cross-league data, and global market views are **admin-only**.
To enable admin mode: `UPDATE p3_player SET is_admin = TRUE;`

### Ranks

| Rank | Unlock |
|------|--------|
| Apprentice | Start |
| Merchant | 5,000 gold |
| Senior Merchant | 20,000 gold |
| Alderman | 50,000 gold |
| Mayor | 100,000 gold |

### Market Pricing Model

Prices are driven by a multi-factor marginal model:

```
price = base_mid × seasonal_factor × volatility × scarcity_power_law × panic_mod × spread
```

- **Seasonal** — ±10% sine wave over the 360-day year (food cheap at harvest, luxuries peak at year-end)  
- **Scarcity** — power-law with per-good elasticity (Ivory: 0.75, Salt: 0.22)  
- **Panic** — stock < 20% reference → sharp spike; stock > 200% → glut discount  
- **Spread** — ask = mid × 1.08, bid = mid × 0.92

---

## 🤖 NPC Ship AI

NPC merchant fleets run automatically every game tick. Each NPC ship:

1. Picks a **source city** that produces its assigned good (with surplus stock)
2. Sails to a **destination city** that demands that good (with low stock)
3. Buys at source, sells at destination, then returns — affecting market prices just as the player would

NPC ships are visible to the player only when **in the same city** as a player ship or counting house.

To configure NPC fleets, see `npc_ships.sh` and the `p3_npc_ships` / `p3_npc_routes` tables.

---

## 🏗️ Schema Overview

```sql
-- Core tables
p3_player           -- One row; gold, rank, game_year, game_day, is_admin
p3_cities           -- 34 cities with hex_q / hex_r coordinates
p3_goods            -- 28 goods with base_production, elasticity config
p3_market           -- Live prices and stock (city × good)
p3_ships            -- Player fleet: type, speed, cargo, status, eta_days
p3_cargo            -- Ship × good inventory
p3_counting_houses  -- Player presence in a city (enables price visibility)

-- Economy
p3_city_goods       -- Production/demand roles per city
p3_building_types   -- 24 building types with daily output & maintenance
p3_player_buildings -- Player-owned buildings
p3_good_elasticity  -- Per-good marginal pricing parameters

-- Routing & orders
p3_routes           -- Named trade routes (distance_nm → travel_days)
p3_route_orders     -- Standing buy/sell orders per route stop
p3_ship_routes      -- Ship ↔ route assignment
p3_limit_orders     -- One-off conditional orders
p3_trade_log        -- Full transaction history

-- NPC
p3_npc_ships        -- Automated merchant ships (owner = 'npc')
p3_npc_routes       -- NPC ship route assignments

-- Spatial
p3_hex_tiles        -- Pointy-top axial (q, r, s) grid tiles

-- Views (player-safe)
p3_fleet_view           -- Player ships with cargo totals
p3_visible_market_view  -- Market data filtered to player's visible cities
p3_lubeck_market_view   -- Lübeck prices (always visible)

-- Views (admin-only)
p3_market_view      -- Full market across all cities
p3_arbitrage_view   -- Global cross-city profit opportunities
```

---

## 🗺️ Hex Coordinate System

The game uses a **pointy-top axial** hex grid (Red Blob Games reference implementation).

- **Origin**: Lübeck (0, 0)
- **Scale**: 1 hex ≈ 50 nautical miles
- **q-axis**: east (+q) / west (−q)
- **r-axis**: south (+r) / north (−r)
- **Distance**: `max(|Δq|, |Δr|, |Δs|)` where `s = −q − r`

```
Conversion from geographic coordinates (at ~54°N):
  q = ROUND( (lon − 10.687) / 1.413 )
  r = ROUND( (53.866 − lat) / 0.833 )
```

SQL helpers: `p3_hex_distance(q1,r1,q2,r2)`, `p3_travel_days(city_a_id, city_b_id, speed_kn)`.

---

## 🛠️ Development

### Running Tests

```bash
# Schema smoke-test (requires a running PostgreSQL)
psql -U postgres -d traderdude -f sql/schema_test.sql

# Flutter widget tests
cd patrician3_app && flutter test
```

### Adding a New City

1. Add to `p3_seed_cities()` in `patrician3.sh`
2. Add hex coordinates to `p3_seed_hex_cities()`
3. Add production/demand rows to `p3_seed_city_goods()`
4. Re-run `Initialise / Reset Game` from the menu

### Adding a New Good

1. Add to `p3_seed_goods()` — set `base_production`, price bounds, `category`
2. Add elasticity row to `p3_seed_elasticity()`
3. Assign to cities in `p3_seed_city_goods()`
4. Optionally add a building type to `p3_seed_building_types()`

---

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Pull requests welcome for:

- New city/good historical accuracy fixes
- NPC ship route improvements
- Flutter UI enhancements (hex map renderer, price charts)
- Additional ship types or building types
- Balance tuning (elasticity, production rates)

---

## 📄 License

MIT — see [LICENSE](LICENSE).

---

## 📚 References

- [Red Blob Games — Hex Grids](https://www.redblobgames.com/grids/hexagons/) — coordinate system
- [Hanseatic League — Wikipedia](https://en.wikipedia.org/wiki/Hanseatic_League) — historical context
- [Patrician III (2003, Ascaron)](https://en.wikipedia.org/wiki/Patrician_III) — gameplay inspiration
