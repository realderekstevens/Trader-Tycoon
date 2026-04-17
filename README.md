# Patrician III + IV — TraderDude

## Files in this package

| File | Goes into |
|---|---|
| `patrician3.sh` | Your project root (same folder as `app.sh`) |
| `main.dart` | `patrician3_app/lib/main.dart` |
| `hex_map_screen.dart` | `patrician3_app/lib/hex_map_screen.dart` |
| `pubspec.yaml` | `patrician3_app/pubspec.yaml` |

---

## Backend setup (bash)

### Fresh database

```bash
# From your TraderDude project directory:
source ./patrician3.sh

# Initialise everything (tables + all seed data):
p3_setup_all

# Start your game:
# Option A — run patrician_menu() directly:
patrician_menu

# Option B — integrate into app.sh (see below)
```

### Integrating into app.sh

Add one line near the top of `app.sh`, after your config block:

```bash
source "$(dirname "$0")/patrician3.sh"
```

Then in `patrician_menu()` (or wherever your main menu routes):
- Add `"🌊 Patrician IV — Mediterranean"` to the `gum choose` list
- Add `"🌊 Patrician IV — Mediterranean") p3_p4_menu ;;` to the case block
- Replace `p3_advance_month` calls with `p3_advance_day`

---

## What's changed from the old version

### Daily time system
- `game_day` (1–360) replaces `game_month`
- `eta_days` replaces `eta_months` on ships
- `travel_days` on routes (baseline at Snaikka 5 kn)
- ETA formula: `distance_nm ÷ (speed_knots × 24)`
  - Snaikka 5 kn: Lübeck→London = 9 days
  - Galley  9 kn: Lübeck→London = 5 days
  - Hulk    4 kn: Lübeck→London = 11 days

### Per-unit marginal pricing
Every single unit bought or sold adjusts the price — not chunked into batches of 5. Buying 30 Iron Goods depresses 30 individual price points, flooding the market curve realistically.

### Rebalanced production (daily fractions)
All `base_production` values are real daily rates:
- Salt: 1.12 units/day (very abundant)
- Grain: 0.80/day
- Beer: 1.63/day from Grain input (highest output building)
- Silk: 0.065/day (rarest — Constantinople only)
- Ivory: 0.032/day (rarest good overall)

Maintenance is also daily — a Brewery costs 60.67g/day, not 1820g/month.

### Patrician IV Mediterranean
- 10 new cities: Venice, Genoa, Marseille, Barcelona, Lisbon, Constantinople, Naples, Palermo, Tunis, Alexandria
- 8 new goods: Olive Oil, Silk, Glass, Sand, Cotton, Alum, Dates, Ivory
- 6 new building types: Olive Grove, Winery (Med), Silk Workshop, Spice Warehouse, Glassworks, Cotton Gin, Alum Works
- 3 new ship types: Cog (120 cap, 6 kn), Galley (90 cap, 9 kn), Carrack (220 cap, 5.5 kn)
- 10 Mediterranean routes
- Cross-league arbitrage view (Hanse ↔ Med)
- Separate `🌊 Patrician IV` submenu

---

## Flutter app setup

```bash
cd patrician3_app

# If you haven't already:
flutter create .

# Copy the files:
cp /path/to/delivered/main.dart lib/main.dart
cp /path/to/delivered/hex_map_screen.dart lib/hex_map_screen.dart
cp /path/to/delivered/pubspec.yaml pubspec.yaml

# Install deps and run:
flutter pub get
flutter run -d linux
```

Set your PostgREST URL in the **CONFIG** tab (default: `http://localhost:3000`).

### PostgREST CORS
Add to your `postgrest.conf`:
```
server-cors-allowed-origins = "*"
```

---

## Ship type reference

| Type | Cargo | Speed | Lübeck→London | Cost |
|---|---|---|---|---|
| Snaikka | 50 | 5.0 kn | 9 days | 1,200g |
| Crayer | 80 | 7.0 kn | 6 days | 2,500g |
| Hulk | 160 | 4.0 kn | 11 days | 5,000g |
| Cog *(P4)* | 120 | 6.0 kn | 7 days | 3,500g |
| Galley *(P4)* | 90 | 9.0 kn | 5 days | 4,200g |
| Carrack *(P4)* | 220 | 5.5 kn | 8 days | 9,000g |

---

## Database tables

All exposed via PostgREST at `http://localhost:3000/`:

`p3_player` · `p3_goods` · `p3_cities` · `p3_city_goods` · `p3_market` · `p3_market_view` · `p3_arbitrage_view` · `p3_ships` · `p3_fleet_view` · `p3_cargo` · `p3_routes` · `p3_route_orders` · `p3_ship_routes` · `p3_building_types` · `p3_player_buildings` · `p3_good_elasticity` · `p3_limit_orders` · `p3_price_history` · `p3_trade_log` · `p3_hex_tiles`
