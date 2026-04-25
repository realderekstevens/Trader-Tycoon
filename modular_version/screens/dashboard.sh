#!/usr/bin/env bash
# screens/dashboard.sh  —  Main dashboard and city intel panel
# DEPENDENCIES: lib/db.sh  lib/ui.sh

p3_main_dashboard() {
    local cols left_w right_w ruler_l ruler_r
    cols=$(tput cols 2>/dev/null || echo 200)
    # Left panel fixed at 46 chars; right panel gets everything else
    left_w=46
    right_w=$(( cols - left_w - 6 ))   # 6 = border + gap overhead
    [[ $right_w -lt 60  ]] && right_w=60
    [[ $right_w -gt 160 ]] && right_w=160
    ruler_l=$(printf '─%.0s' $(seq 1 $((left_w - 4))))
    ruler_r=$(printf '─%.0s' $(seq 1 $((right_w - 4))))

    # ── Single DB round-trip ───────────────────────────────────────────────
    local gold rank gyear gday docked sailing is_admin counting_houses visible_cities
    {
        read -r gold; read -r rank; read -r gyear; read -r gday
        read -r docked; read -r sailing; read -r is_admin
        read -r counting_houses; read -r visible_cities
    } < <(p3_psql --tuples-only -c "
        SELECT pl.gold::text, pl.rank,
               pl.game_year::text, pl.game_day::text,
               (SELECT COUNT(*)::text FROM p3_ships WHERE owner='player' AND status='docked'),
               (SELECT COUNT(*)::text FROM p3_ships WHERE owner='player' AND status='sailing'),
               pl.is_admin::text,
               (SELECT COUNT(*)::text FROM p3_counting_houses),
               (SELECT COUNT(DISTINCT city_id)::text FROM p3_player_visible_city_ids())
        FROM p3_player pl LIMIT 1;" 2>/dev/null \
        | sed 's/|/\n/g; s/^ *//; s/ *$//' \
        || printf '???\nApprentice\n???\n0\n0\n0\nf\n0\n1\n')

    is_admin="${is_admin:-f}"
    counting_houses="${counting_houses:-0}"
    visible_cities="${visible_cities:-1}"

    # ── Fleet lines ────────────────────────────────────────────────────────
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

    local tick_badge
    if [[ -f "$P3_TICK_PID_FILE" ]] && kill -0 "$(cat "$P3_TICK_PID_FILE")" 2>/dev/null; then
        tick_badge="⏱  Auto-tick RUNNING  ${P3_TICK_INTERVAL}s/day"
    else
        tick_badge="⏹  Manual  ·  Sim › Start Auto-Tick"
    fi

    # ── LEFT panel: player status + fleet ─────────────────────────────────
    local panel_left
    panel_left=$(
    {
        printf '⚓  PATRICIAN  III / IV\n'
        [[ "$is_admin" == "t" ]] && printf '** ADMINISTRATOR MODE **\n'
        printf '%s\n' "$ruler_l"
        printf 'Year %-6s  *  Day %03d\n' "${gyear:-???}" "${gday:-0}"
        printf 'Gold: %-18s  Rank: %s\n' "${gold:-???}" "${rank:-Apprentice}"
        printf '%s\n' "$ruler_l"
        printf 'Ships:  %s docked  *  %s at sea\n' "${docked:-0}" "${sailing:-0}"
        printf '%s\n' "$fleet_lines"
        printf '%s\n' "$ruler_l"
        printf 'Cities: %-4s  *  Counting houses: %s\n' \
            "$visible_cities" "$counting_houses"
        printf '%s\n' "$ruler_l"
        printf '%s\n' "$tick_badge"
    } | gum style \
            --border rounded \
            --border-foreground 33 \
            --padding "0 1" \
            --width "$left_w")

    # ── RIGHT panel data queries ───────────────────────────────────────────
    local rp_color
    local lub_pop lub_region lub_league lub_hex lub_ch_count
    {
        read -r lub_pop; read -r lub_region; read -r lub_league
        read -r lub_hex; read -r lub_ch_count
    } < <(p3_psql --tuples-only -c "
        SELECT ci.population::text, ci.region, ci.league,
               COALESCE(ci.hex_q::text||','||ci.hex_r::text,'unmapped'),
               (SELECT COUNT(*)::text FROM p3_counting_houses)
        FROM p3_cities ci WHERE ci.name='Lübeck' LIMIT 1;" 2>/dev/null \
        | sed 's/|/\n/g; s/^ *//; s/ *$//' \
        || printf '?\nBaltic\nHanseatic\nunmapped\n0\n')

    # Market: fetch as pairs for 2-column layout
    local lub_market_2col
    lub_market_2col=$(p3_psql --tuples-only -c "
        WITH numbered AS (
            SELECT ROW_NUMBER() OVER (ORDER BY good) AS rn,
                   RPAD(good, 12) || RPAD(ask::text, 9) || RPAD(bid::text, 8) ||
                   RPAD(stock::text, 5) || COALESCE(signal,'–') AS entry
            FROM p3_lubeck_market_view
        ),
        odds  AS (SELECT rn, entry FROM numbered WHERE MOD(rn,2)=1),
        evens AS (SELECT rn, entry FROM numbered WHERE MOD(rn,2)=0)
        SELECT '  ' || RPAD(o.entry, 40) || '  |  ' || COALESCE(e.entry,'')
        FROM odds o LEFT JOIN evens e ON e.rn = o.rn + 1
        ORDER BY o.rn;" 2>/dev/null \
        | grep -v '^\s*$' || echo "  (market not seeded)")

    # Production & demand
    local lub_prod_lines
    lub_prod_lines=$(p3_psql --tuples-only -c "
        SELECT '  ' || RPAD(g.name, 13) ||
               RPAD(cg.role, 9) ||
               RPAD(cg.efficiency::text||'%', 5) ||
               ROUND(g.base_production * cg.efficiency / 100.0, 3)::text || '/day'
        FROM p3_city_goods cg
        JOIN p3_goods  g  ON g.good_id  = cg.good_id
        JOIN p3_cities ci ON ci.city_id = cg.city_id AND ci.name = 'Lübeck'
        ORDER BY cg.role DESC, g.name;" 2>/dev/null \
        | grep -v '^\s*$' || echo "  (no production data)")

    # Buildings — compact
    local lub_bldg_lines
    lub_bldg_lines=$(p3_psql --tuples-only -c "
        SELECT '  ' || RPAD(bt.name, 18) || 'x' || pb.num_buildings ||
               '  -> ' || g_out.name || '  (' || bt.daily_maintenance*pb.num_buildings || 'g/day maint)'
        FROM p3_player_buildings pb
        JOIN p3_building_types bt ON bt.building_type_id = pb.building_type_id
        JOIN p3_cities ci ON ci.city_id = pb.city_id AND ci.name = 'Lubeck'
        JOIN p3_goods g_out ON g_out.good_id = bt.output_good_id
        ORDER BY bt.name;" 2>/dev/null \
        | grep -v '^\s*$' || echo "  none")

    # City-owned (NPC) production facilities — visible from a ship/counting house
    local lub_city_prod_lines
    lub_city_prod_lines=$(p3_psql --tuples-only -c "
        SELECT '  ' || RPAD(g.name, 14) ||
               RPAD(cg.role, 9) ||
               RPAD(cg.efficiency::text||'%', 6) ||
               ROUND(g.base_production * cg.efficiency / 100.0, 3)::text || '/day'
        FROM p3_city_goods cg
        JOIN p3_goods  g  ON g.good_id  = cg.good_id
        JOIN p3_cities ci ON ci.city_id = cg.city_id AND ci.name = 'Lubeck'
        ORDER BY cg.role DESC, g.name;" 2>/dev/null \
        | grep -v '^\s*$' || echo "  (no city production data)")

    # Nearest cities — inline pairs, fixed 32-char column
    local lub_nearby_lines
    lub_nearby_lines=$(p3_psql --tuples-only -c "
        WITH n AS (
            SELECT ROW_NUMBER() OVER (ORDER BY p3_hex_distance(0,0,dest.hex_q,dest.hex_r)) AS rn,
                   RPAD(dest.name, 14) ||
                   RPAD(COALESCE(p3_hex_distance(0,0,dest.hex_q,dest.hex_r)::text||'hx','?'), 6) ||
                   COALESCE(p3_travel_days(src.city_id,dest.city_id,5.0)::text,'?')||'d' AS entry
            FROM p3_cities src, p3_cities dest
            WHERE src.name='Lubeck' AND dest.city_id<>src.city_id
              AND dest.hex_q IS NOT NULL AND src.hex_q IS NOT NULL
            ORDER BY p3_hex_distance(0,0,dest.hex_q,dest.hex_r) NULLS LAST
            LIMIT 8
        ),
        odds  AS (SELECT rn,entry FROM n WHERE MOD(rn,2)=1),
        evens AS (SELECT rn,entry FROM n WHERE MOD(rn,2)=0)
        SELECT '  ' || RPAD(o.entry, 32) || '  ' || COALESCE(e.entry,'')
        FROM odds o LEFT JOIN evens e ON e.rn = o.rn+1
        ORDER BY o.rn;" 2>/dev/null \
        | grep -v '^\s*$' || echo "  (no hex data — run Initialise first)")

    # ── RIGHT panel assembly ───────────────────────────────────────────────
    local panel_right
    if [[ "$is_admin" == "t" ]]; then
        rp_color=214
        local arb_lines
        arb_lines=$(p3_psql --tuples-only -c "
            SELECT '  ' || RPAD(good, 13) ||
                           RPAD(buy_city, 15) ||
                   '->  '|| RPAD(sell_city, 15) ||
                   '+' || profit_per_unit || '/u'
            FROM p3_admin_arbitrage_view LIMIT 10;" 2>/dev/null \
            | grep -v '^\s*$' || echo "  (no arbitrage data)")
        panel_right=$(
        {
            printf 'HOME  LUBECK  |  pop:%-7s  |  %s  [hex %s]  |  counting houses: %s\n' \
                "$lub_pop" "$lub_league" "$lub_hex" "$lub_ch_count"
            printf '%s\n' "$ruler_r"
            printf '  %-12s %-9s %-8s %-5s  |  %-12s %-9s %-8s %-5s\n' \
                "GOOD" "ASK" "BID" "STK" "GOOD" "ASK" "BID" "STK"
            printf '%s\n' "$lub_market_2col"
            printf '%s\n' "$ruler_r"
            printf '[ADMIN]  TOP ARBITRAGE\n'
            printf '  %-13s %-15s %-15s %s\n' "GOOD" "BUY AT" "SELL AT" "PROFIT/U"
            printf '%s\n' "$arb_lines"
        } | gum style \
                --border rounded \
                --border-foreground "$rp_color" \
                --padding "0 1" \
                --width "$right_w")
    else
        rp_color=33
        panel_right=$(
        {
            printf 'HOME  LUBECK  |  pop:%-7s  |  %s  |  region: %s  |  hex: %s  |  counting houses: %s\n' \
                "$lub_pop" "$lub_league" "$lub_region" "$lub_hex" "$lub_ch_count"
            printf '%s\n' "$ruler_r"
            printf '  %-12s %-9s %-8s %-5s  |  %-12s %-9s %-8s %-5s\n' \
                "GOOD" "ASK" "BID" "STK" "GOOD" "ASK" "BID" "STK"
            printf '%s\n' "$lub_market_2col"
            printf '%s\n' "$ruler_r"
            printf 'PRODUCTION & DEMAND\n'
            printf '  %-13s %-9s %-5s %s\n' "GOOD" "ROLE" "EFF" "OUTPUT"
            printf '%s\n' "$lub_prod_lines"
            printf '%s\n' "$ruler_r"
            printf 'CITY PRODUCTION FACILITIES  (city-owned)\n'
            printf '  %-14s %-9s %-6s %s\n' "GOOD" "ROLE" "EFF" "OUTPUT/DAY"
            printf '%s\n' "$lub_city_prod_lines"
            printf '%s\n' "$ruler_r"
            printf 'YOUR BUILDINGS IN LUBECK\n'
            printf '%s\n' "$lub_bldg_lines"
            printf '%s\n' "$ruler_r"
            printf 'NEAREST CITIES\n'
            printf '%s\n' "$lub_nearby_lines"
        } | gum style \
                --border rounded \
                --border-foreground "$rp_color" \
                --padding "0 1" \
                --width "$right_w")
    fi

    gum join --horizontal --align top "$panel_left" "  " "$panel_right"
    echo
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14i-A  ADMIN & SETUP SUBMENU
# ─────────────────────────────────────────────────────────────────────────────
p3_admin_menu() {
    push_breadcrumb "⚙ Admin & Setup"
    while true; do
        clear
        section_header "⚙ Admin & Setup — Restricted Access"

        local choice
        choice="$(gum choose \
            "── Game Setup ──" \
            "Initialise / Reset Game" \
            "Reseed Market Prices" \
            "── Simulation Ticker ──" \
            "Start Auto-Tick" \
            "Stop Auto-Tick" \
            "Tick Status" \
            "Set Tick Interval" \
            "── Admin Tools ──" \
            "🤖 NPC Fleet Management" \
            "Best Arbitrage Opportunities" \
            "Cross-League Opportunities  (Hanse ↔ Med)" \
            "Back")"

        case "$choice" in
            "── Game Setup ──"|"── Simulation Ticker ──"|"── Admin Tools ──")
                continue ;;

            "Initialise / Reset Game")
                warn "This will DESTROY and re-create ALL game tables and data."
                warn "All progress, ships, gold, and market history will be LOST."
                echo
                if gum confirm --default=false "Are you absolutely sure you want to reset everything?"; then
                    if gum confirm --default=false "Final confirmation — reset the game now?"; then
                        p3_setup_all
                        success "Game fully reset and re-seeded."
                    else
                        warn "Reset cancelled."
                    fi
                else
                    warn "Reset cancelled."
                fi ;;

            "Reseed Market Prices")
                warn "This will randomise ALL market prices across every city."
                warn "Current price trends and spread data will be overwritten."
                echo
                if gum confirm --default=false "Are you sure you want to re-randomise market prices?"; then
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
                else
                    warn "Reseed cancelled."
                fi ;;

            "Start Auto-Tick")   p3_start_tick ;;
            "Stop Auto-Tick")    p3_stop_tick  ;;
            "Tick Status")       p3_tick_status ;;
            "Set Tick Interval") p3_set_tick_interval ;;

            "🤖 NPC Fleet Management") p3_npc_menu ;;

            "Best Arbitrage Opportunities")
                local is_adm
                is_adm=$(p3_psql --tuples-only -c "SELECT is_admin FROM p3_player;" | tr -d ' ')
                if [[ "$is_adm" != "t" ]]; then
                    warn "Arbitrage data is restricted to administrators."
                    pause; continue
                fi
                p3_psql -c "
                    SELECT buy_city, sell_city, good,
                           buy_price, sell_price, profit_per_unit,
                           buy_stock, route_days_snaikka
                    FROM p3_admin_arbitrage_view
                    LIMIT 20;" ;;

            "Cross-League Opportunities  (Hanse ↔ Med)")
                local is_adm
                is_adm=$(p3_psql --tuples-only -c "SELECT is_admin FROM p3_player;" | tr -d ' ')
                if [[ "$is_adm" != "t" ]]; then
                    warn "Cross-league data requires administrator access."
                    pause; continue
                fi
                p3_psql -c "
                    SELECT buy_city, sell_city, good, buy_price, sell_price,
                           profit_per_unit, route_days_snaikka, days_crayer, days_galley
                    FROM p3_admin_crossleague_view LIMIT 15;" ;;

            "Back" | *) pop_breadcrumb; return ;;
        esac
        pause
    done
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14i-B  INTERACTIVE BUY — city intel panel + scrollable price list + marginal curve
# ─────────────────────────────────────────────────────────────────────────────

# ── Helper: render a city intel panel (mirrors the Lübeck dashboard) ─────────
p3_city_intel_panel() {
    local city="$1"
    local ruler
    ruler=$(printf '─%.0s' $(seq 1 74))

    # ── City basics ──────────────────────────────────────────────────────────
    local ci_pop ci_region ci_league ci_hex ci_ch
    {
        read -r ci_pop; read -r ci_region; read -r ci_league
        read -r ci_hex; read -r ci_ch
    } < <(p3_psql --tuples-only -c "
        SELECT ci.population::text, ci.region, ci.league,
               COALESCE(ci.hex_q::text||','||ci.hex_r::text,'unmapped'),
               (SELECT COUNT(*)::text FROM p3_counting_houses
                WHERE city_id = ci.city_id)
        FROM p3_cities ci WHERE ci.name='$city' LIMIT 1;" 2>/dev/null \
        | sed 's/|/\n/g; s/^ *//; s/ *$//' \
        || printf '?\nBaltic\nHanseatic\nunmapped\n0\n')

    # ── City-owned (NPC) production buildings ───────────────────────────────
    local city_prod_lines
    city_prod_lines=$(p3_psql --tuples-only -c "
        SELECT '  ' || RPAD(g.name, 14) ||
               RPAD(cg.role, 9) ||
               RPAD(cg.efficiency::text||'%', 6) ||
               ROUND(g.base_production * cg.efficiency / 100.0, 3)::text || '/day'
        FROM p3_city_goods cg
        JOIN p3_goods  g  ON g.good_id  = cg.good_id
        JOIN p3_cities ci ON ci.city_id = cg.city_id AND ci.name = '$city'
        ORDER BY cg.role DESC, g.name;" 2>/dev/null \
        | grep -v '^\s*$' || echo "  (no production data)")

    # ── Ships in port (player + NPC, docked) ────────────────────────────────
    local ships_in_port
    ships_in_port=$(p3_psql --tuples-only -c "
        SELECT '  ' ||
               RPAD(CASE s.owner WHEN 'player' THEN '[YOU] ' ELSE '[NPC]  ' END || s.name, 22) ||
               RPAD(s.ship_type, 10) ||
               RPAD(s.speed_knots::text||'kn', 7) ||
               'cap:' || s.cargo_cap
        FROM p3_ships s
        WHERE s.current_city = '$city' AND s.status = 'docked'
        ORDER BY s.owner DESC, s.name;" 2>/dev/null \
        | grep -v '^\s*$' || echo "  (no ships in port)")

    # ── Nearest cities ───────────────────────────────────────────────────────
    local nearby_lines
    nearby_lines=$(p3_psql --tuples-only -c "
        WITH n AS (
            SELECT ROW_NUMBER() OVER (ORDER BY p3_hex_distance(src.hex_q,src.hex_r,dest.hex_q,dest.hex_r)) AS rn,
                   RPAD(dest.name, 14) ||
                   RPAD(COALESCE(p3_hex_distance(src.hex_q,src.hex_r,dest.hex_q,dest.hex_r)::text||'hx','?'), 6) ||
                   COALESCE(p3_travel_days(src.city_id,dest.city_id,5.0)::text,'?')||'d' AS entry
            FROM p3_cities src, p3_cities dest
            WHERE src.name='$city' AND dest.city_id<>src.city_id
              AND dest.hex_q IS NOT NULL AND src.hex_q IS NOT NULL
            ORDER BY p3_hex_distance(src.hex_q,src.hex_r,dest.hex_q,dest.hex_r) NULLS LAST
            LIMIT 8
        ),
        odds  AS (SELECT rn,entry FROM n WHERE MOD(rn,2)=1),
        evens AS (SELECT rn,entry FROM n WHERE MOD(rn,2)=0)
        SELECT '  ' || RPAD(o.entry, 32) || '  ' || COALESCE(e.entry,'')
        FROM odds o LEFT JOIN evens e ON e.rn = o.rn+1
        ORDER BY o.rn;" 2>/dev/null \
        | grep -v '^\s*$' || echo "  (no hex data)")

    # ── Render ────────────────────────────────────────────────────────────────
    printf '%s  |  pop:%-7s  |  %s  |  region: %s  |  hex: %s  |  counting houses: %s\n' \
        "${city^^}" "$ci_pop" "$ci_league" "$ci_region" "$ci_hex" "$ci_ch"
    printf '%s\n' "$ruler"
    printf 'PRODUCTION & DEMAND\n'
    printf '  %-14s %-9s %-6s %s\n' "GOOD" "ROLE" "EFF" "OUTPUT/DAY"
    printf '%s\n' "$city_prod_lines"
    printf '%s\n' "$ruler"
    printf 'SHIPS IN PORT\n'
    printf '  %-22s %-10s %-7s %s\n' "NAME" "TYPE" "SPEED" "CAPACITY"
    printf '%s\n' "$ships_in_port"
    printf '%s\n' "$ruler"
    printf 'NEAREST CITIES  (Snaikka 5kn travel time)\n'
    printf '%s\n' "$nearby_lines"
    printf '%s\n' "$ruler"
}

p3_interactive_buy() {
    local sid="$1" scity="$2"
    local gold cargo_free
    gold=$(p3_gold)
    cargo_free=$(p3_psql --tuples-only -c "SELECT cargo_free FROM p3_fleet_view WHERE ship_id=$sid;" | tr -d ' ')

    # Build the goods list with price info as display lines
    local goods_list
    goods_list=$(p3_psql --tuples-only -c "
        SELECT RPAD(g.name, 14) ||
               '  BUY:'  || RPAD(m.current_buy::text, 9) ||
               'SELL:'   || RPAD(m.current_sell::text, 9) ||
               'STK:'    || RPAD(m.stock::text, 6) ||
               COALESCE(mv.signal,'–')
        FROM   p3_market m
        JOIN   p3_goods   g  ON g.good_id  = m.good_id
        JOIN   p3_cities  ci ON ci.city_id = m.city_id AND ci.name = '$scity'
        LEFT JOIN p3_market_view mv ON mv.city = '$scity' AND mv.good = g.name
        ORDER  BY g.name;" 2>/dev/null | sed 's/^ *//' | grep -v '^$' || true)

    [[ -z "$goods_list" ]] && { warn "No market data for $scity."; return; }

    # Show city intel panel above the goods list
    clear
    p3_city_intel_panel "$scity"
    echo
    gum style --foreground 33 --bold "BUY GOODS — $scity  |  Gold: ${gold}g  |  Free cargo: ${cargo_free}"
    echo
    gum style --foreground 244 "  $(printf '%-14s  %-16s %-16s %-10s %s' 'GOOD' 'BUYING PRICE' 'SELLING PRICE' 'STOCK' 'SIG')"
    echo

    local chosen_line
    chosen_line=$(printf '%s\n' "$goods_list" \
        | gum filter \
            --placeholder "Type to filter goods…" \
            --height 20 \
            --prompt "▶ " \
            --indicator "→")
    [[ -z "$chosen_line" ]] && return

    # Extract good name (first word)
    local good
    good=$(echo "$chosen_line" | awk '{print $1}')
    [[ -z "$good" ]] && return

    # Fetch market data for this good
    local ask bid stock elast_buy stock_ref
    {
        read -r ask; read -r bid; read -r stock; read -r elast_buy; read -r stock_ref
    } < <(p3_psql --tuples-only -c "
        SELECT m.current_buy::text,
               m.current_sell::text,
               m.stock::text,
               e.elasticity_buy::text,
               e.stock_ref::text
        FROM p3_market m
        JOIN p3_cities        ci ON ci.city_id = m.city_id AND ci.name = '$scity'
        JOIN p3_goods          g ON g.good_id  = m.good_id AND g.name  = '$good'
        JOIN p3_good_elasticity e ON e.good_id = g.good_id
        LIMIT 1;" 2>/dev/null | sed 's/|/\n/g; s/^ *//; s/ *$//' \
        || printf '0\n0\n0\n0.5\n80\n')

    # Compute marginal buy curve in bash — one row per unit qty 1..20
    # Anchored so that q=1 costs exactly the current Buying Price (ask).
    # unit_price(q) = ask * (stock / max(stock - q + 1, 1))^elast_buy
    #   q=1  → ask*(stock/stock)^e  = ask  ✓
    #   q=2  → ask*(stock/(stock-1))^e > ask  ✓ (less stock = more expensive)
    clear
    gum style --foreground 212 --bold "MARGINAL PRICE CURVE — $good in $scity"
    gum style --foreground 244 "    Current Buying Price: ${ask}g  |  Selling Price: ${bid}g  |  Stock: ${stock}  |  Your gold: ${gold}g"
    echo
    printf '  %-6s  %-12s  %-14s  %s\n' "QTY" "UNIT PRICE" "TOTAL COST" "AFFORDABLE?"

    local running_total=0
    local i
    for i in $(seq 1 20); do
        local unit_price total_now affordable
        unit_price=$(awk -v ask="$ask" -v stk="$stock" \
                         -v e="$elast_buy" -v q="$i" '
            BEGIN {
                denom = stk - q + 1
                if (denom < 1) denom = 1
                printf "%.2f", ask * (stk / denom)^e
            }')
        running_total=$(awk -v rt="$running_total" -v up="$unit_price" \
            'BEGIN { printf "%.2f", rt + up }')
        affordable=$(awk -v gold="$gold" -v tot="$running_total" \
            'BEGIN { print (gold+0 >= tot+0) ? "✓" : "✗ over budget" }')
        printf '  %-6s  %-12s  %-14s  %s\n' "$i" "${unit_price}g" "${running_total}g" "$affordable"
    done
    echo

    # Ask quantity
    local qty
    qty=$(gum input --placeholder "How many units to buy? (0 to cancel)" --value "")
    [[ -z "$qty" || ! "$qty" =~ ^[0-9]+$ || "$qty" == "0" ]] && { warn "Purchase cancelled."; return; }

    # Compute precise total cost for the chosen qty
    local total_cost=0
    for i in $(seq 1 "$qty"); do
        local up
        up=$(awk -v ask="$ask" -v stk="$stock" \
                 -v e="$elast_buy" -v q="$i" '
            BEGIN {
                denom = stk - q + 1
                if (denom < 1) denom = 1
                printf "%.2f", ask * (stk / denom)^e
            }')
        total_cost=$(awk -v tc="$total_cost" -v up="$up" 'BEGIN { printf "%.2f", tc + up }')
    done

    echo
    gum style --foreground 33 --bold "  SUMMARY: Buy $qty x $good in $scity"
    gum style --foreground 244 "  Unit range: ${ask}g (1st unit) → marginal pricing applied"
    gum style --foreground 76  "  Total cost: ${total_cost}g  |  Your gold: ${gold}g"
    echo

    if gum confirm --default=false "Confirm purchase: $qty × $good for ${total_cost}g?"; then
        p3_do_buy "$sid" "$good" "$qty" "$scity"
    else
        warn "Purchase cancelled."
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14i-C  INTERACTIVE SELL — cargo list + marginal curve
# ─────────────────────────────────────────────────────────────────────────────
