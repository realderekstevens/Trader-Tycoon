# Patrician III / IV — Hanseatic Trading Simulation (CLI Edition)

A PostgreSQL-backed medieval trading game playable entirely from the terminal,
built on `psql` and `gum`.

---

## Quick Start

```bash
# 1. Create the database
createdb traderdude

# 2. Apply schema and seed data
psql -d traderdude -f sql/schema.sql
psql -d traderdude -f sql/seed.sql

# 3. Run the game
bash app.sh
```

To reset everything from inside the game: **Admin & Setup → Initialise / Reset Game**

---

## Dependencies

| Tool | Purpose | Install |
|------|---------|---------|
| `psql` | PostgreSQL client | `apt install postgresql-client` |
| `gum` | TUI menus and filters | https://github.com/charmbracelet/gum |

---

## Directory Layout

```
patrician/
├── app.sh                  ← Entrypoint — sources all modules, calls run_app()
│
├── lib/                    ← Pure logic, no menus
│   ├── ui.sh               ← gum wrappers, breadcrumbs, info/warn/error/success
│   ├── db.sh               ← psql(), pickers, sail, buy, sell, NPC AI tick
│   └── tick.sh             ← Day-advance, real-time daemon, building production
│
├── screens/                ← One file per menu / screen
│   ├── dashboard.sh        ← p3_main_dashboard, p3_city_intel_panel
│   ├── trade.sh            ← p3_interactive_buy, p3_interactive_sell
│   ├── main_menu.sh        ← patrician_menu (top-level action dispatcher)
│   ├── admin.sh            ← Admin & Setup menu
│   ├── npc.sh              ← NPC fleet management (admin only)
│   ├── med.sh              ← Patrician IV Mediterranean expansion
│   ├── buildings.sh        ← Buildings, limit orders
│   ├── elasticity.sh       ← Market elasticity and price curves
│   └── hex.sh              ← Hex map, city distances, tile editor
│
└── sql/
    ├── schema.sql          ← All CREATE TABLE / VIEW / FUNCTION statements
    └── seed.sql            ← All INSERT reference data (idempotent)
```

Source load order in `app.sh`: `ui.sh` → `db.sh` → `tick.sh` → screens (any order).
`ui.sh` must be first because `db.sh` calls `warn` and `error`.

---

## Hex Grid Reference

Pointy-top axial coordinates. Lübeck is the origin `(0, 0)`.

```
q increases east  |  r increases south  |  s = -q - r (derived)
Distance = max(|Δq|, |Δr|, |Δs|)
1 hex ≈ 50 nautical miles
```

Conversion from geographic coordinates (~54°N):
```
q = round((lon - 10.687) / 1.413)
r = round((53.866 - lat) / 0.833)
```

---

## Game Systems

| System | Location |
|--------|----------|
| Fog of war | `p3_player_visible_city_ids()` in schema.sql |
| Marginal pricing | `p3_marginal_price()` in schema.sql |
| Seasonal price curves | Inside `p3_marginal_price()` |
| NPC ship AI | `lib/db.sh` → `p3_npc_tick()` |
| Real-time tick daemon | `lib/tick.sh` → `p3_start_tick()` |
| Building production | `lib/tick.sh` → `p3_process_production_and_orders_daily()` |

---

## Environment Variables

```bash
PSQL_DB=traderdude     # Database name   (default: traderdude)
PSQL_USER=postgres     # Database user   (default: postgres)
P3_TICK_INTERVAL=10    # Seconds per game day in auto-tick mode (default: 10)
```

---

## Enable Admin Mode

```sql
UPDATE p3_player SET is_admin = TRUE;
```

Admin mode unlocks: global arbitrage view, NPC fleet management,
cross-league price analysis, and the full market view (bypasses fog of war).

---

## Adding a New Screen

1. Create `screens/my_feature.sh` with a single function `p3_my_feature_menu()`.
2. Add `source "$SCRIPT_DIR/screens/my_feature.sh"` to `app.sh`.
3. Add a menu item and case branch in `screens/main_menu.sh`.
4. No other files need to change.

---

## Adding a New Good or City

Edit `sql/seed.sql` — the INSERT blocks are plain SQL with `ON CONFLICT DO UPDATE`,
so re-running the file after changes is safe. Then run:

```bash
psql -d traderdude -f sql/seed.sql
```

---

## Ship Types

| Type | Cargo | Speed | Cost | Notes |
|------|-------|-------|------|-------|
| Snaikka | 50 | 5.0 kn | 1 200g | Baltic coastal workhorse |
| Crayer | 80 | 7.0 kn | 2 500g | Fast medium hauler |
| Hulk | 160 | 4.0 kn | 5 000g | Slow bulk carrier |
| Cog | 120 | 6.0 kn | 3 500g | P4 — balanced Med trader |
| Galley | 90 | 9.0 kn | 4 200g | P4 — fastest ship |
| Carrack | 220 | 5.5 kn | 9 000g | P4 — flagship cargo |
