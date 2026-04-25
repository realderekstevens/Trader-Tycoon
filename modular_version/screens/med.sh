#!/usr/bin/env bash
# screens/med.sh  —  Patrician IV Mediterranean expansion menu
# DEPENDENCIES: lib/db.sh  lib/ui.sh

# ─────────────────────────────────────────────────────────────────────────────
#  §14l  PATRICIAN IV MENU
# ─────────────────────────────────────────────────────────────────────────────
p3_p4_menu() {
    push_breadcrumb "🌊 Patrician IV"
    while true; do
        local gold yd
        gold=$(p3_gold 2>/dev/null || echo "?")
        yd=$(p3_psql --tuples-only -c \
            "SELECT 'Year '||game_year||' Day '||LPAD(game_day::text,3,'0') FROM p3_player;" \
            2>/dev/null | tr -d ' ' || echo "??")

        section_header "🌊 Patrician IV — Mediterranean  │  💰 ${gold}g  │  📅 ${yd}"

        choice="$(gum choose \
            "── Mediterranean Market ──" \
            "View Med Market (All Cities)" \
            "Med Arbitrage Opportunities" \
            "Cross-League Opportunities  (Hanse ↔ Med)" \
            "── Mediterranean Cities ──" \
            "View All Med Cities" \
            "Med City Production Details" \
            "── Goods ──" \
            "Mediterranean Goods Reference" \
            "── Ships ──" \
            "Ship Type Comparison" \
            "Back")"

        case "$choice" in
            "── Mediterranean Market ──"|"── Mediterranean Cities ──"|\
            "── Goods ──"|"── Ships ──")
                continue ;;

            "View Med Market (All Cities)")
                local is_adm
                is_adm=$(p3_psql --tuples-only -c "SELECT is_admin FROM p3_player;" | tr -d ' ')
                if [[ "$is_adm" == "t" ]]; then
                    p3_psql -c "
                        SELECT city, good, current_buy, current_sell, stock, signal
                        FROM p3_market_view WHERE league = 'Mediterranean'
                        ORDER BY city, good;"
                else
                    p3_psql -c "
                        SELECT city, good, current_buy, current_sell, stock, signal
                        FROM p3_visible_market_view WHERE league = 'Mediterranean'
                        ORDER BY city, good;"
                fi ;;

            "Med Arbitrage Opportunities")
                local is_adm
                is_adm=$(p3_psql --tuples-only -c "SELECT is_admin FROM p3_player;" | tr -d ' ')
                if [[ "$is_adm" != "t" ]]; then
                    warn "Arbitrage data is restricted to administrators."
                    pause; continue
                fi
                p3_psql -c "
                    SELECT buy_city, sell_city, good, buy_price, sell_price,
                           profit_per_unit, buy_stock
                    FROM p3_admin_arbitrage_view
                    WHERE buy_city  IN (SELECT name FROM p3_cities WHERE league = 'Mediterranean')
                       OR sell_city IN (SELECT name FROM p3_cities WHERE league = 'Mediterranean')
                    ORDER BY profit_per_unit DESC LIMIT 20;" ;;

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

            "View All Med Cities")
                p3_psql -c "
                    SELECT name, region, population,
                           COALESCE(hex_q::text, '?') || ',' || COALESCE(hex_r::text, '?') AS hex_qr
                    FROM p3_cities WHERE league = 'Mediterranean'
                    ORDER BY region, name;" ;;

            "Med City Production Details")
                local city
                city=$(p3_psql --tuples-only -c \
                    "SELECT name FROM p3_cities WHERE league = 'Mediterranean' ORDER BY name;" \
                    | sed 's/^ *//' | grep -v '^$' | gum filter --placeholder "Select Med city…")
                [[ -z "$city" ]] && { pause; continue; }
                p3_psql -c "
                    SELECT g.name AS good, cg.role, cg.efficiency,
                           ROUND(g.base_production * cg.efficiency / 100.0, 4) AS daily_output
                    FROM p3_city_goods cg
                    JOIN p3_goods   g  ON g.good_id  = cg.good_id
                    JOIN p3_cities  ci ON ci.city_id = cg.city_id AND ci.name = '$city'
                    ORDER BY cg.role, g.name;" ;;

            "Mediterranean Goods Reference")
                p3_psql -c "
                    SELECT name, category, buy_price_min, sell_price_min, sell_price_max,
                           ROUND(base_production, 4) AS prod_day
                    FROM p3_goods
                    WHERE name IN ('Olive Oil','Silk','Glass','Sand','Cotton',
                                   'Alum','Dates','Ivory','Wine','Spices')
                    ORDER BY sell_price_max DESC;" ;;

            "Ship Type Comparison")
                p3_psql -c "
                    SELECT type, cap, kn,
                           GREATEST(1, ROUND(120.0  /(kn*24))::INTEGER) AS lubeck_hamburg_d,
                           GREATEST(1, ROUND(350.0  /(kn*24))::INTEGER) AS lubeck_gdansk_d,
                           GREATEST(1, ROUND(1050.0 /(kn*24))::INTEGER) AS lubeck_london_d,
                           GREATEST(1, ROUND(1400.0 /(kn*24))::INTEGER) AS venice_cpl_d
                    FROM (VALUES
                        ('Snaikka',50,5.0),('Crayer',80,7.0),('Hulk',160,4.0),
                        ('Cog',120,6.0),('Galley',90,9.0),('Carrack',220,5.5)
                    ) AS t(type, cap, kn)
                    ORDER BY kn DESC;" ;;

            "Back" | *) pop_breadcrumb; return ;;
        esac
        pause
    done
}
