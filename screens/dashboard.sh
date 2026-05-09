#!/usr/bin/env bash
# screens/dashboard.sh  —  Main dashboard and city intel panel
# DEPENDENCIES: lib/db.sh  lib/ui.sh

p3_main_dashboard() {
    local cols left_w right_w ruler_l ruler_r
    cols=$(tput cols 2>/dev/null || echo 200)
    left_w=46
    right_w=$(( cols - left_w - 6 ))   # 6 = border + gap overhead
    [[ $right_w -lt 60  ]] && right_w=60
    [[ $right_w -gt 160 ]] && right_w=160
    ruler_l=$(printf '─%.0s' $(seq 1 $((left_w - 4))))
    ruler_r=$(printf '─%.0s' $(seq 1 $((right_w - 4))))

    # ── Single DB round-trip ───────────────────────────────────────────────
    local gold rank gyear gday docked sailing is_admin counting_houses visible_cities home_city
    {
        read -r gold; read -r rank; read -r gyear; read -r gday
        read -r docked; read -r sailing; read -r is_admin
        read -r counting_houses; read -r visible_cities; read -r home_city
    } < <(p3_psql --tuples-only -c "
        SELECT pl.gold::text, pl.rank,
               pl.game_year::text, pl.game_day::text,
               (SELECT COUNT(*)::text FROM p3_ships WHERE owner='player' AND status='docked'),
               (SELECT COUNT(*)::text FROM p3_ships WHERE owner='player' AND status='sailing'),
               pl.is_admin::text,
               (SELECT COUNT(*)::text FROM p3_counting_houses),
               (SELECT COUNT(DISTINCT city_id)::text FROM p3_player_visible_city_ids()),
               pl.home_city
        FROM p3_player pl LIMIT 1;" 2>/dev/null \
        | sed 's/|/\n/g; s/^ *//; s/ *$//' \
        || printf '???\nApprentice\n???\n0\n0\n0\nf\n0\n1\nLubeck\n')

    is_admin="${is_admin:-f}"
    counting_houses="${counting_houses:-0}"
    visible_cities="${visible_cities:-1}"
    home_city="${home_city:-Lubeck}"

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
        FROM p3_cities ci WHERE ci.name='$home_city' LIMIT 1;" 2>/dev/null \
        | sed 's/|/\n/g; s/^ *//; s/ *$//' \
        || printf '?\nBaltic\nHanseatic\nunmapped\n0\n')

    # Improved market table — better alignment
    local lub_market_2col
    lub_market_2col=$(p3_psql --tuples-only -c "
        WITH src AS (
            SELECT g.name AS good, 
                   m.current_buy AS ask, 
                   m.current_sell AS bid,
                   m.stock,
                   CASE
                       WHEN m.current_buy  <= g.buy_price_min  THEN 'BUY'
                       WHEN m.current_sell >= g.sell_price_max THEN 'SELL!'
                       WHEN m.current_sell >= g.sell_price_min THEN 'SELL'
                       ELSE '--'
                   END AS signal
            FROM p3_market m
            JOIN p3_cities ci ON ci.city_id = m.city_id AND ci.name = '$home_city'
            JOIN p3_goods  g  ON g.good_id  = m.good_id
            ORDER BY g.name
        ),
        numbered AS (
            SELECT ROW_NUMBER() OVER () AS rn,
                   RPAD(good, 14) || 
                   LPAD(ask::text, 9) || 
                   LPAD(bid::text, 9) || 
                   LPAD(stock::text, 5) || '   ' || signal AS entry
            FROM src
        ),
        odds AS (SELECT rn, entry FROM numbered WHERE MOD(rn,2)=1),
        evens AS (SELECT rn, entry FROM numbered WHERE MOD(rn,2)=0)
        SELECT '  ' || RPAD(o.entry, 48) || ' | ' || COALESCE(e.entry, '')
        FROM odds o LEFT JOIN evens e ON e.rn = o.rn + 1
        ORDER BY o.rn;" 2>/dev/null \
        | grep -v '^\s*$' || echo "  (market not seeded)")

    # Production lines (improved padding)
    local lub_prod_lines
    lub_prod_lines=$(p3_psql --tuples-only -c "
        SELECT '  ' || RPAD(g.name, 14) ||
               RPAD(cg.role, 10) ||
               LPAD(cg.efficiency::text||'%', 6) ||
               '   ' || ROUND(g.base_production * cg.efficiency / 100.0, 3)::text || '/day'
        FROM p3_city_goods cg
        JOIN p3_goods  g  ON g.good_id  = cg.good_id
        JOIN p3_cities ci ON ci.city_id = cg.city_id AND ci.name = '$home_city'
        ORDER BY cg.role DESC, g.name;" 2>/dev/null \
        | grep -v '^\s*$' || echo "  (no production data)")

    local lub_bldg_lines
    lub_bldg_lines=$(p3_psql --tuples-only -c "
        SELECT '  ' || RPAD(bt.name, 20) || ' ×' || pb.num_buildings ||
               ' → ' || g_out.name || '  (' || bt.daily_maintenance*pb.num_buildings || 'g/day)'
        FROM p3_player_buildings pb
        JOIN p3_building_types bt ON bt.building_type_id = pb.building_type_id
        JOIN p3_cities ci ON ci.city_id = pb.city_id AND ci.name = '$home_city'
        JOIN p3_goods g_out ON g_out.good_id = bt.output_good_id
        ORDER BY bt.name;" 2>/dev/null \
        | grep -v '^\s*$' || echo "  none")

    local lub_city_prod_lines
    lub_city_prod_lines=$(p3_psql --tuples-only -c "
        SELECT '  ' || RPAD(g.name, 14) ||
               RPAD(cg.role, 10) ||
               LPAD(cg.efficiency::text||'%', 6) ||
               '   ' || ROUND(g.base_production * cg.efficiency / 100.0, 3)::text || '/day'
        FROM p3_city_goods cg
        JOIN p3_goods  g  ON g.good_id  = cg.good_id
        JOIN p3_cities ci ON ci.city_id = cg.city_id AND ci.name = '$home_city'
        ORDER BY cg.role DESC, g.name;" 2>/dev/null \
        | grep -v '^\s*$' || echo "  (no city production)")

    local lub_nearby_lines
    lub_nearby_lines=$(p3_psql --tuples-only -c "
        WITH n AS (
            SELECT ROW_NUMBER() OVER (ORDER BY p3_hex_distance(0,0,dest.hex_q,dest.hex_r)) AS rn,
                   RPAD(dest.name, 15) ||
                   LPAD(COALESCE(p3_hex_distance(0,0,dest.hex_q,dest.hex_r)::text||'hx','?'), 7) ||
                   '  ' || COALESCE(p3_travel_days(src.city_id,dest.city_id,5.0)::text,'?')||'d' AS entry
            FROM p3_cities src, p3_cities dest
            WHERE src.name='$home_city' AND dest.city_id<>src.city_id
              AND dest.hex_q IS NOT NULL AND src.hex_q IS NOT NULL
            ORDER BY p3_hex_distance(0,0,dest.hex_q,dest.hex_r) NULLS LAST
            LIMIT 8
        ),
        odds  AS (SELECT rn,entry FROM n WHERE MOD(rn,2)=1),
        evens AS (SELECT rn,entry FROM n WHERE MOD(rn,2)=0)
        SELECT '  ' || RPAD(o.entry, 36) || '   ' || COALESCE(e.entry,'')
        FROM odds o LEFT JOIN evens e ON e.rn = o.rn+1
        ORDER BY o.rn;" 2>/dev/null \
        | grep -v '^\s*$' || echo "  (no hex data — run Initialise first)")

    # ── RIGHT panel assembly — cleaner sections ─────────────────────────────
    local panel_right
    if [[ "$is_admin" == "t" ]]; then
        # ... (admin panel unchanged for now)
        rp_color=214
        panel_right=$(
        {
            printf 'HOME  %s  |  pop:%-7s  |  %s  [hex %s]  |  counting houses: %s\n' \
                "${home_city^^}" "$lub_pop" "$lub_league" "$lub_hex" "$lub_ch_count"
            printf '%s\n' "$ruler_r"
            printf '  %-14s %-9s %-9s %-5s  |  %-14s %-9s %-9s %-5s\n' \
                "GOOD" "ASK" "BID" "STK" "GOOD" "ASK" "BID" "STK"
            printf '%s\n' "$lub_market_2col"
        } | gum style \
                --border rounded \
                --border-foreground "$rp_color" \
                --padding "0 1" \
                --width "$right_w")
    else
        rp_color=33
        panel_right=$(
        {
            printf 'HOME  %s  |  pop:%-7s  |  %s  |  region: %s  |  hex: %s  |  counting houses: %s\n' \
                "${home_city^^}" "$lub_pop" "$lub_league" "$lub_region" "$lub_hex" "$lub_ch_count"
            printf '%s\n' "$ruler_r"
            printf '  %-14s %-9s %-9s %-5s  |  %-14s %-9s %-9s %-5s\n' \
                "GOOD" "ASK" "BID" "STK" "GOOD" "ASK" "BID" "STK"
            printf '%s\n' "$lub_market_2col"
            printf '%s\n' "$ruler_r"
            printf 'PRODUCTION & DEMAND\n'
            printf '  %-14s %-10s %-6s %s\n' "GOOD" "ROLE" "EFF" "OUTPUT/DAY"
            printf '%s\n' "$lub_prod_lines"
            printf '%s\n' "$ruler_r"
            printf 'CITY PRODUCTION FACILITIES (city-owned)\n'
            printf '  %-14s %-10s %-6s %s\n' "GOOD" "ROLE" "EFF" "OUTPUT/DAY"
            printf '%s\n' "$lub_city_prod_lines"
            printf '%s\n' "$ruler_r"
            printf 'YOUR BUILDINGS IN %s\n' "${home_city^^}"
            printf '%s\n' "$lub_bldg_lines"
            printf '%s\n' "$ruler_r"
            printf 'NEAREST CITIES (travel @ ~5kn)\n'
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

# (rest of the file — interactive buy/sell etc. unchanged)
