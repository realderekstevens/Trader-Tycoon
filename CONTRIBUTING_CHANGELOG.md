# Changelog

All notable changes to Patrician III/IV are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Added
- **NPC ship AI** (`npc_ships.sh`) — 13 automated merchant ships across Hanseatic + Mediterranean routes, each specialised in one good; buys from surplus cities, sells to deficit cities, moves market prices just as player trades do
- **Player visibility / fog of war** (`visibility.sql`) — market prices now only visible in cities where the player has a docked ship or counting house; Lübeck home city always visible
- **Counting houses** (`p3_counting_houses` table) — establish permanent market presence in a city
- **Admin privilege system** — `p3_player.is_admin` flag; arbitrage views and NPC logs gated behind admin check; global market view restricted to admins
- **`p3_visible_market_view`** — player-filtered market view (replaces raw `p3_market_view` for player-facing queries)
- **`p3_lubeck_market_view`** — always-available Lübeck market snapshot for dashboard display
- **`p3_admin_arbitrage_view`** — renamed from `p3_arbitrage_view`; explicit admin-only intent
- **`p3_admin_crossleague_view`** — cross-league arbitrage, admin-only
- **Flutter frontend refactor** (`main.dart`) — Riverpod state management, Hanseatic dark theme, proper error handling, visibility-aware market tab, admin-only arbitrage panel, responsive rail + bottom nav layout
- `p3_counting_house_cost()` SQL function — cost scales with city population
- `p3_player_visible_city_ids()` SQL function — returns set of cities player can see

### Changed
- Dashboard now shows **Lübeck market prices** for non-admin players instead of arbitrage table
- Arbitrage opportunities hidden from players; shown only to admins in a clearly labelled admin card
- Flutter app now uses a centralised `PostgRestService` class instead of scattered fetch calls

---

## [0.1.0] — Initial Release

### Added
- Full Hanseatic + Mediterranean schema (§14a): 15 tables, 5 views, 4 SQL functions
- 28 goods with per-unit marginal elasticity pricing model
- 24 Hanseatic cities + 10 Mediterranean cities on pointy-top hex grid
- 6 ship types: Snaikka, Crayer, Hulk, Cog, Galley, Carrack
- 24 building types with daily production and maintenance costs
- Real-time tick daemon with `pg_notify` and `LISTEN p3_day_tick`
- Route system with standing orders and limit orders
- Seasonal price curves, panic/glut non-linearity, bid/ask spread
- Flutter app: PostgREST integration, hex map screen, basic market view

---

# Contributing

Contributions are welcome. Please read the guidelines below before opening a pull request.

## Development Setup

```bash
git clone https://github.com/yourname/patrician3.git
cd patrician3

# Create a local PostgreSQL database
createdb traderdude

# Run the game once to initialise the schema
PSQL_DB=traderdude ./app.sh
# → Setup → Initialise / Reset Game
```

## What to Contribute

**High-value areas:**

| Area | Examples |
|------|---------|
| Historical accuracy | Fix city coordinates, population, production roles |
| Balance tuning | Elasticity values, daily production rates, building costs |
| NPC AI | Smarter route selection, NPC factions with personalities |
| Flutter UI | Hex map renderer, price history charts, trade log view |
| New content | Additional ship types, building types, goods (historical sources required) |
| Testing | PostgreSQL function tests, Flutter widget tests |

## Pull Request Guidelines

1. **One feature / fix per PR** — keep diffs small and reviewable
2. **SQL changes** — include both forward migration and rollback in `sql/`
3. **Historical citations** — if adding or changing game data (prices, production, city populations), link a source
4. **Flutter** — run `flutter analyze` and `flutter test` before submitting
5. **Shell** — run `shellcheck app.sh patrician3.sh npc_ships.sh` (warnings are acceptable; errors are not)
6. **Commit messages** — use present tense imperative: `Add counting house UI`, `Fix NPC ETA calculation`

## Reporting Bugs

Open a GitHub Issue with:
- Steps to reproduce
- Expected vs actual behaviour
- PostgreSQL version (`psql --version`)
- Flutter version if relevant (`flutter --version`)

## Game Balance Philosophy

- Prices should create **meaningful trade decisions** — not trivially obvious routes
- NPC ships should **stabilise markets**, not dominate them
- Player buildings should **pay for themselves in 30–90 days** at normal trade rates
- The Hanseatic economy should feel **tighter and denser** than the Mediterranean expansion

## Code Style

**Bash:**
- 4-space indentation
- Local variables declared with `local`
- Heredocs for SQL blocks (`<<'SQL' … SQL`)
- `set -e` in all standalone scripts

**SQL:**
- UPPER CASE keywords
- Table aliases: `ci` = cities, `g` = goods, `m` = market, `s` = ships
- All new tables: `p3_` prefix
- All new views: `p3_` prefix; admin views: `p3_admin_` prefix

**Dart/Flutter:**
- Follow `flutter analyze` rules
- Riverpod for all async state (no raw `setState` for server data)
- `PatricianTheme` constants for all colours — no raw `Color(0x...)` in widgets

## License

By contributing you agree that your contributions will be licensed under the MIT License.
