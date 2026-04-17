# Patrician III — Flutter Client

Dark, gritty Hanseatic trading game UI for your PostgREST backend.

## Aesthetic Direction

Inspired by **Obenseur** — industrial grime, lamplight gold on carbon black.
- Font stack: **Cinzel Decorative** (headers) · **Crimson Text** (body) · **Source Code Pro** (data/labels)
- Color: `#0D0C0A` void-black → `#B8912A` amber gold → `#4A7C59` forest green / `#8B3030` crimson
- Minimalist chrome, maximalist density in data tables

---

## Setup

### 1. Flutter
```bash
cd patrician3_app
flutter pub get
flutter run                   # any device/emulator
```

### 2. PostgREST — your existing backend
Make sure your `app.sh` has been run with:
- **Patrician III initialised** (`⚓ Patrician Trading Game → Initialise Game`)
- **PostgREST running** (`PostgREST Setup → Start Server`)

The default base URL in the app is `http://localhost:3000`.  
Change it live in the **CONFIG** tab.

### 3. CORS
Add to your PostgREST config:
```toml
server-cors-allowed-origins = "*"
```

---

## Database Tables Used

All tables are hit directly via PostgREST REST API (GET/POST/PATCH).

| PostgREST Endpoint      | Purpose                                  |
|------------------------|------------------------------------------|
| `p3_player`            | Gold, rank, game date                    |
| `p3_ships`             | Fleet — type, cargo, status, ETA         |
| `p3_cargo`             | Goods loaded per ship                    |
| `p3_goods`             | Reference prices, categories             |
| `p3_cities`            | Hanseatic cities + regions               |
| `p3_city_goods`        | City production / demand roles           |
| `p3_market_view`       | Live ask/bid prices (SQL VIEW)           |
| `p3_market`            | Raw market table (stock levels)          |
| `p3_arbitrage_view`    | Best cross-city profit opportunities     |
| `p3_trade_log`         | Full action history                      |
| `p3_routes`            | Named trade routes                       |
| `p3_route_orders`      | Standing buy/sell orders per route       |
| `p3_building_types`    | Building catalogue                       |
| `p3_player_buildings`  | Owned buildings                          |
| `p3_limit_orders`      | Active limit orders                      |
| `p3_price_history`     | Monthly price snapshots                  |
| `p3_hex_tiles`         | Hex grid tile map                        |
| `p3_good_elasticity`   | Price elasticity config                  |
| `newspaper_stock_quotes` | Historical NYSE 1929 data (bonus tab)  |

---

## Screens

### 📊 LEDGER (Dashboard)
- Player stats strip: gold, rank, port, date
- Top 5 arbitrage signals (colour-coded profit per unit)
- Recent transaction log (last 8 actions)

### 📈 MARKET
- Searchable / city-filtered market table
- Columns: Good · City · Buy Price · Sell Price · Stock
- Left-border colour signal: green = good sell, dark red = buy opportunity
- Chip filter row for quick city selection

### ⛵ FLEET
- Ship cards: name, type, status badge, cargo cap, current port
- TRADE button → bottom sheet: pick good, enter qty, execute buy
- SAIL button → bottom sheet: pick destination city, issue sail order
- Live status colours: docked=green / sailing=gold

### 📜 LOG
- Full trade history with left accent bar per action type
- Columns: action · good · city · ship · qty · gold after
- Date display as `MMM YYYY` game calendar

### ⚙️ CONFIG
- PostgREST URL editor with live reconnect
- Full endpoint reference list
- Connection status indicator

---

## Extending the App

**Add a Hex Map tab:** use `p3_hex_tiles` + `p3_cities.hex_q/hex_r` and paint
flat-top hexagons on a `CustomPainter`.

**Add a Buildings tab:** read `p3_building_types` and `p3_player_buildings`;
build/expand/demolish via POST/PATCH.

**Add Price History charts:** `p3_price_history` has one row per good per city
per month — pass to `fl_chart` LineChart.

**Add newspaper quotes screen:** `newspaper_stock_quotes` with date range
filters to browse your 1929 NYSE transcriptions.

**Advance Time:** call PostgREST RPC endpoint `/rpc/p3_advance_month`
(expose via `CREATE FUNCTION` + `SECURITY DEFINER`).
