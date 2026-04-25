#!/usr/bin/env bash
# screens/buildings.sh  —  Buildings management and limit orders
# DEPENDENCIES: lib/db.sh  lib/ui.sh

p3_buildings_menu() {
    push_breadcrumb "🏭 Buildings"
    while true; do
        local gold maint_day
        gold=$(p3_gold 2>/dev/null || echo "?")
        maint_day=$(p3_psql --tuples-only -c "
            SELECT COALESCE(ROUND(SUM(bt.daily_maintenance * pb.num_buildings), 2), 0)
            FROM p3_player_buildings pb
            JOIN p3_building_types bt ON bt.building_type_id = pb.building_type_id;
            " 2>/dev/null | tr -d ' ' || echo "0")

        section_header "🏭 Buildings  │  💰 ${gold}g  │  🔧 ${maint_day}g/day overhead"

        choice="$(gum choose \
            "Build a Building" \
            "Expand Existing Building" \
            "Demolish / Sell Building" \
            "View My Buildings" \
            "Building Production Report" \
            "Building Type Catalogue" \
            "City Building Efficiency" \
            "── Limit Orders ──" \
            "Place Limit Order" \
            "View Active Limit Orders" \
            "Cancel Limit Order" \
            "Back")"

        case "$choice" in
            "── Limit Orders ──") continue ;;

            "Build a Building")
                local city city_id bt_id
                city=$(p3_pick_city); [[ -z "$city" ]] && { pause; continue; }
                city_id=$(p3_psql --tuples-only -c "SELECT city_id FROM p3_cities WHERE name='$city';" | tr -d ' ')

                local types
                types=$(p3_psql --tuples-only -c "
                    SELECT bt.building_type_id || ' – ' || bt.name
                           || '  [' || g_out.name
                           || COALESCE(' ← ' || g_in.name, '')
                           || ']  prod:' || bt.base_production || '/day'
                           || '  cost:' || bt.construction_cost || 'g'
                           || '  maint:' || bt.daily_maintenance || 'g/day'
                    FROM p3_building_types bt
                    JOIN p3_goods g_out ON g_out.good_id = bt.output_good_id
                    LEFT JOIN p3_goods g_in ON g_in.good_id = bt.input_good_id
                    ORDER BY bt.name;" 2>/dev/null | sed 's/^ *//' | grep -v '^$') || true
                [[ -z "$types" ]] && { warn "No building types found."; pause; continue; }
                local chosen; chosen=$(echo "$types" | gum filter --placeholder "Select building type…")
                [[ -z "$chosen" ]] && { pause; continue; }
                bt_id="${chosen%% *}"

                local bt_name bt_cost
                bt_name=$(p3_psql --tuples-only -c "SELECT name FROM p3_building_types WHERE building_type_id=$bt_id;" | tr -d ' ')
                bt_cost=$(p3_psql --tuples-only -c "SELECT construction_cost FROM p3_building_types WHERE building_type_id=$bt_id;" | tr -d ' ')

                local gold_now; gold_now=$(p3_gold)
                if awk "BEGIN{exit !(${gold_now}+0 < ${bt_cost}+0)}"; then
                    error "Not enough gold (have ${gold_now}g, need ${bt_cost}g)."
                    pause; continue
                fi

                if confirm "Build '$bt_name' in $city for ${bt_cost}g?"; then
                    p3_psql -c "
                        INSERT INTO p3_player_buildings (city_id, building_type_id, num_buildings)
                        VALUES ($city_id, $bt_id, 1) ON CONFLICT DO NOTHING;
                        UPDATE p3_player SET gold = gold - $bt_cost;" >/dev/null
                    success "Built '$bt_name' in $city. Produces each day tick."
                fi ;;

            "View My Buildings")
                p3_psql -c "
                    SELECT pb.pb_id AS id, bt.name AS building, ci.name AS city,
                           pb.num_buildings AS count,
                           ROUND(bt.base_production * pb.num_buildings, 4)   AS prod_per_day,
                           ROUND(bt.daily_maintenance * pb.num_buildings, 2) AS cost_per_day,
                           g_out.name AS output,
                           COALESCE(g_in.name, '—') AS input
                    FROM p3_player_buildings pb
                    JOIN p3_building_types bt ON bt.building_type_id = pb.building_type_id
                    JOIN p3_cities ci ON ci.city_id = pb.city_id
                    JOIN p3_goods g_out ON g_out.good_id = bt.output_good_id
                    LEFT JOIN p3_goods g_in ON g_in.good_id = bt.input_good_id
                    ORDER BY ci.name, bt.name;" ;;

            "Building Type Catalogue")
                p3_psql -c "
                    SELECT bt.name, g_out.name AS output,
                           COALESCE(g_in.name, '—') AS input,
                           bt.input_units_per_output AS in_per_unit,
                           ROUND(bt.base_production, 4) AS prod_day,
                           bt.construction_cost AS cost,
                           bt.daily_maintenance AS maint_day,
                           ROUND(bt.construction_cost::NUMERIC / NULLIF(bt.daily_maintenance, 0), 0) AS payback_days,
                           bt.notes
                    FROM p3_building_types bt
                    JOIN p3_goods g_out ON g_out.good_id = bt.output_good_id
                    LEFT JOIN p3_goods g_in ON g_in.good_id = bt.input_good_id
                    ORDER BY bt.name;" ;;

            "Building Production Report")
                p3_psql -c "
                    SELECT ci.name AS city, g_out.name AS output,
                           SUM(pb.num_buildings) AS buildings,
                           ROUND(SUM(bt.base_production * pb.num_buildings), 4) AS total_prod_day,
                           ROUND(SUM(bt.daily_maintenance * pb.num_buildings), 2) AS total_maint_day
                    FROM p3_player_buildings pb
                    JOIN p3_building_types bt ON bt.building_type_id = pb.building_type_id
                    JOIN p3_cities ci ON ci.city_id = pb.city_id
                    JOIN p3_goods g_out ON g_out.good_id = bt.output_good_id
                    GROUP BY ci.name, g_out.name
                    ORDER BY ci.name, g_out.name;" ;;

            "City Building Efficiency")
                local city; city=$(p3_pick_city)
                [[ -z "$city" ]] && { pause; continue; }
                p3_psql -c "
                    SELECT g.name AS good, cg.efficiency,
                           ROUND(g.base_production * cg.efficiency / 100.0, 4) AS daily_if_built
                    FROM p3_city_goods cg
                    JOIN p3_goods g ON g.good_id = cg.good_id
                    JOIN p3_cities ci ON ci.city_id = cg.city_id AND ci.name = '$city'
                    WHERE cg.role = 'produces'
                    ORDER BY cg.efficiency DESC, g.name;" ;;

            "Expand Existing Building")
                local blist pb_id
                blist=$(p3_psql --tuples-only -c "
                    SELECT pb.pb_id || ' – ' || bt.name || ' in ' || ci.name || ' (×' || pb.num_buildings || ')'
                    FROM p3_player_buildings pb
                    JOIN p3_building_types bt ON bt.building_type_id = pb.building_type_id
                    JOIN p3_cities ci ON ci.city_id = pb.city_id
                    ORDER BY ci.name, bt.name;" 2>/dev/null | sed 's/^ *//' | grep -v '^$') || true
                [[ -z "$blist" ]] && { warn "No buildings owned."; pause; continue; }
                local chosen; chosen=$(echo "$blist" | gum filter --placeholder "Select building…")
                pb_id="${chosen%% *}"
                [[ -z "$pb_id" ]] && { pause; continue; }
                local add_n; add_n=$(gum input --placeholder "How many additional buildings?" --value "1")
                [[ -z "$add_n" || ! "$add_n" =~ ^[0-9]+$ ]] && { pause; continue; }
                local cost_each; cost_each=$(p3_psql --tuples-only -c "
                    SELECT bt.construction_cost FROM p3_player_buildings pb
                    JOIN p3_building_types bt ON bt.building_type_id = pb.building_type_id
                    WHERE pb.pb_id = $pb_id;" | tr -d ' ')
                local total_cost=$(( cost_each * add_n ))
                local gold_now; gold_now=$(p3_gold)
                if awk "BEGIN{exit !(${gold_now}+0 < ${total_cost}+0)}"; then
                    error "Need ${total_cost}g, have ${gold_now}g."
                    pause; continue
                fi
                if confirm "Expand by $add_n for ${total_cost}g?"; then
                    p3_psql -c "
                        UPDATE p3_player_buildings SET num_buildings = num_buildings + $add_n
                        WHERE pb_id = $pb_id;
                        UPDATE p3_player SET gold = gold - $total_cost;" >/dev/null
                    success "Expanded. +$add_n buildings."
                fi ;;

            "Demolish / Sell Building")
                local blist pb_id
                blist=$(p3_psql --tuples-only -c "
                    SELECT pb.pb_id || ' – ' || bt.name || ' in ' || ci.name || ' (×' || pb.num_buildings || ')'
                    FROM p3_player_buildings pb
                    JOIN p3_building_types bt ON bt.building_type_id = pb.building_type_id
                    JOIN p3_cities ci ON ci.city_id = pb.city_id
                    ORDER BY ci.name, bt.name;" 2>/dev/null | sed 's/^ *//' | grep -v '^$') || true
                [[ -z "$blist" ]] && { warn "No buildings owned."; pause; continue; }
                local chosen; chosen=$(echo "$blist" | gum filter --placeholder "Select building to demolish…")
                pb_id="${chosen%% *}"
                [[ -z "$pb_id" ]] && { pause; continue; }
                local refund; refund=$(p3_psql --tuples-only -c "
                    SELECT ROUND(bt.construction_cost * pb.num_buildings * 0.40)
                    FROM p3_player_buildings pb
                    JOIN p3_building_types bt ON bt.building_type_id = pb.building_type_id
                    WHERE pb.pb_id = $pb_id;" | tr -d ' ')
                if confirm "Demolish for ${refund}g refund (40%)?"; then
                    p3_psql -c "
                        UPDATE p3_player SET gold = gold + $refund;
                        DELETE FROM p3_player_buildings WHERE pb_id = $pb_id;" >/dev/null
                    success "Demolished. Received ${refund}g."
                fi ;;

            "Place Limit Order")
                local sid; sid=$(p3_pick_ship) || { pause; continue; }
                local scity; scity=$(p3_psql --tuples-only -c "SELECT current_city FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
                local cid; cid=$(p3_psql --tuples-only -c "SELECT city_id FROM p3_cities WHERE name='$scity';" | tr -d ' ')
                local action; action=$(gum choose "buy" "sell")
                local good; good=$(p3_pick_good); [[ -z "$good" ]] && { pause; continue; }
                local gid; gid=$(p3_psql --tuples-only -c "SELECT good_id FROM p3_goods WHERE name='$good';" | tr -d ' ')
                local qty; qty=$(gum input --placeholder "Total quantity")
                local price; price=$(gum input --placeholder "Price limit (buy: max | sell: min)")
                [[ -z "$qty" || -z "$price" ]] && { error "Qty and price required."; pause; continue; }
                p3_psql -c "
                    INSERT INTO p3_limit_orders
                        (ship_id, city_id, good_id, action, total_quantity, remaining_quantity, price_limit)
                    VALUES ($sid, $cid, $gid, '$action', $qty, $qty, $price);" >/dev/null
                success "Limit order placed: $action $qty $good @ $price in $scity." ;;

            "View Active Limit Orders")
                p3_psql -c "
                    SELECT lo.order_id, lo.action, g.name AS good,
                           ci.name AS city, lo.price_limit,
                           lo.remaining_quantity || '/' || lo.total_quantity AS remaining,
                           m.current_buy AS ask, m.current_sell AS bid
                    FROM p3_limit_orders lo
                    JOIN p3_goods   g  ON g.good_id  = lo.good_id
                    JOIN p3_cities  ci ON ci.city_id = lo.city_id
                    JOIN p3_market  m  ON m.city_id  = lo.city_id AND m.good_id = lo.good_id
                    WHERE lo.active AND lo.remaining_quantity > 0
                    ORDER BY lo.order_id;" ;;

            "Cancel Limit Order")
                local oid
                oid=$(p3_psql --tuples-only -c "
                    SELECT lo.order_id || ' – ' || lo.action || ' '
                           || lo.remaining_quantity || ' ' || g.name
                           || ' @ ' || lo.price_limit || ' (' || ci.name || ')'
                    FROM p3_limit_orders lo
                    JOIN p3_goods g ON g.good_id = lo.good_id
                    JOIN p3_cities ci ON ci.city_id = lo.city_id
                    WHERE lo.active ORDER BY lo.order_id;" 2>/dev/null \
                    | sed 's/^ *//' | grep -v '^$' | gum filter --placeholder "Select order to cancel…")
                oid="${oid%% *}"
                [[ -z "$oid" ]] && { pause; continue; }
                p3_psql -c "UPDATE p3_limit_orders SET active = FALSE WHERE order_id = $oid;" >/dev/null
                success "Limit order $oid cancelled." ;;

            "Back" | *) pop_breadcrumb; return ;;
        esac
        pause
    done
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14n  ELASTICITY MENU
# ─────────────────────────────────────────────────────────────────────────────
