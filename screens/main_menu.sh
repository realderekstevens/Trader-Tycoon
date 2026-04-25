#!/usr/bin/env bash
# screens/main_menu.sh  —  Top-level action dispatcher (patrician_menu)
# DEPENDENCIES: lib/db.sh  lib/ui.sh  lib/tick.sh  screens/*

patrician_menu() {
    push_breadcrumb "⚓ Patrician"
    while true; do
        clear
        p3_main_dashboard

        # ── Menu items (shown as preview, filtered with gum filter) ────────
        local _all_items
        _all_items="$(printf '%s\n' \
            "[Trade]  Buy Goods at City" \
            "[Trade]  Sell Goods at City" \
            "[Fleet]  View Fleet" \
            "[Fleet]  Buy a Ship" \
            "[Fleet]  Rename Ship" \
            "[Fleet]  Give Sail Order" \
            "[Fleet]  View Ship Cargo" \
            "[Presence]  Establish Counting House" \
            "[Presence]  View My Counting Houses" \
            "[Buildings]  🏭 Manage Buildings & Limit Orders" \
            "[Market]  View Market at City" \
            "[Market]  Price History for Good" \
            "[Market]  Good Reference Prices" \
            "[Routes]  View All Routes" \
            "[Routes]  Create Trade Route" \
            "[Routes]  Add Order to Route" \
            "[Routes]  Assign Ship to Route" \
            "[World]  View All Cities" \
            "[World]  City Production Details" \
            "[World]  🗺 Hex Map & City Distances" \
            "[World]  📊 Market Elasticity & Price Curves" \
            "[Time]  Advance One Day" \
            "[Time]  Advance Multiple Days" \
            "[Log]  View Trade Log" \
            "[Med]  🌊 Patrician IV — Mediterranean" \
            "[Admin]  ⚙ Admin & Setup" \
            "Back")"

        local _raw_choice
        _raw_choice="$(printf '%s\n' "$_all_items" \
            | gum filter \
                --placeholder "Type to search actions…" \
                --height 20 \
                --prompt "▶ " \
                --indicator "→")"
        # Strip the [Category] prefix to get the canonical choice
        choice="${_raw_choice#*\]  }"
        [[ -z "$choice" ]] && continue

        case "$choice" in

            "🗺 Hex Map & City Distances")         p3_hex_menu ;;
            "📊 Market Elasticity & Price Curves") p3_elasticity_menu ;;
            "🏭 Manage Buildings & Limit Orders")  p3_buildings_menu ;;
            "🌊 Patrician IV — Mediterranean")     p3_p4_menu ;;
            "⚙ Admin & Setup")                     p3_admin_menu ;;

            # ── FLEET ─────────────────────────────────────────────────────
            "View Fleet")
                p3_psql -c "
                    SELECT ship_id AS id, name, ship_type AS type,
                           speed_knots AS kn,
                           current_city AS city, status,
                           COALESCE(destination, '—') AS dest,
                           CASE WHEN eta_days > 0 THEN eta_days||'d' ELSE '—' END AS eta,
                           cargo_cap AS cap, cargo_used AS used, cargo_free AS free
                    FROM p3_fleet_view ORDER BY name;" ;;

            "Buy a Ship")
                local stype cost cap spd
                stype=$(gum choose \
                    "Snaikka  — cap  50, 5.0 kn — 1 200g  (Baltic coastal workhorse)" \
                    "Crayer   — cap  80, 7.0 kn — 2 500g  (Faster, medium cargo)" \
                    "Hulk     — cap 160, 4.0 kn — 5 000g  (Slow bulk hauler)" \
                    "Cog      — cap 120, 6.0 kn — 3 500g  (P4 — balanced Med trader)" \
                    "Galley   — cap  90, 9.0 kn — 4 200g  (P4 — fastest ship)" \
                    "Carrack  — cap 220, 5.5 kn — 9 000g  (P4 — flagship cargo)")
                case "$stype" in
                    *Snaikka*) cap=50;  cost=1200; spd=5.0; stype="Snaikka" ;;
                    *Crayer*)  cap=80;  cost=2500; spd=7.0; stype="Crayer"  ;;
                    *Hulk*)    cap=160; cost=5000; spd=4.0; stype="Hulk"    ;;
                    *Cog*)     cap=120; cost=3500; spd=6.0; stype="Cog"     ;;
                    *Galley*)  cap=90;  cost=4200; spd=9.0; stype="Galley"  ;;
                    *Carrack*) cap=220; cost=9000; spd=5.5; stype="Carrack" ;;
                    *) pause; continue ;;
                esac
                local gold_now; gold_now=$(p3_gold)
                if awk "BEGIN{exit !(${gold_now}+0 < ${cost}+0)}"; then
                    error "Not enough gold (have ${gold_now}g, need ${cost}g)."
                else
                    local sname home
                    sname=$(gum input --placeholder "Name your new ship")
                    [[ -z "$sname" ]] && { error "Name required."; pause; continue; }
                    home=$(p3_psql --tuples-only -c "SELECT home_city FROM p3_player;" | tr -d ' ')
                    p3_psql -c "
                        INSERT INTO p3_ships (name, owner, ship_type, cargo_cap, speed_knots, current_city)
                        VALUES ('$sname', 'player', '$stype', $cap, $spd, '$home');
                        UPDATE p3_player SET gold = gold - $cost;" >/dev/null
                    success "Purchased '$sname' ($stype, ${cap} cap, ${spd}kn) for ${cost}g."
                fi ;;

            "Rename Ship")
                local sid; sid=$(p3_pick_ship) || { pause; continue; }
                local newname; newname=$(gum input --placeholder "New ship name")
                [[ -z "$newname" ]] && { pause; continue; }
                p3_psql -c "UPDATE p3_ships SET name = '$newname' WHERE ship_id = $sid;" >/dev/null
                success "Ship renamed to '$newname'." ;;

            "Give Sail Order")
                local sid; sid=$(p3_pick_ship) || { pause; continue; }
                local sname scity sstatus
                sname=$(p3_psql --tuples-only -c "SELECT name         FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
                scity=$(p3_psql --tuples-only -c "SELECT current_city FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
                sstatus=$(p3_psql --tuples-only -c "SELECT status      FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
                if [[ "$sstatus" != "docked" ]]; then
                    local eta; eta=$(p3_psql --tuples-only -c "SELECT eta_days FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
                    warn "$sname is $sstatus (ETA ${eta} day(s))."
                    pause; continue
                fi
                info "Select destination for $sname (currently in $scity):"
                local dest; dest=$(p3_pick_city)
                [[ -z "$dest" || "$dest" == "$scity" ]] && { error "Invalid destination."; pause; continue; }
                p3_sail_ship "$sid" "$dest" ;;

            "View Ship Cargo")
                local sid; sid=$(p3_pick_ship) || { pause; continue; }
                p3_psql -c "
                    SELECT g.name AS good, c.quantity,
                           ROUND(m.current_sell * c.quantity, 2) AS est_sell_value
                    FROM   p3_cargo c
                    JOIN   p3_goods  g  ON g.good_id  = c.good_id
                    JOIN   p3_ships  s  ON s.ship_id  = c.ship_id
                    JOIN   p3_cities ci ON ci.name    = s.current_city
                    JOIN   p3_market m  ON m.good_id  = c.good_id AND m.city_id = ci.city_id
                    WHERE  c.ship_id = $sid AND c.quantity > 0
                    ORDER  BY g.name;" ;;

            # ── TRADING ───────────────────────────────────────────────────
            "Buy Goods at City")
                local sid; sid=$(p3_pick_ship) || { pause; continue; }
                local scity sstatus
                scity=$(p3_psql --tuples-only -c "SELECT current_city FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
                sstatus=$(p3_psql --tuples-only -c "SELECT status FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
                [[ "$sstatus" != "docked" ]] && { warn "Ship must be docked to trade."; pause; continue; }
                p3_interactive_buy "$sid" "$scity" ;;

            "Sell Goods at City")
                local sid; sid=$(p3_pick_ship) || { pause; continue; }
                local scity sstatus
                scity=$(p3_psql --tuples-only -c "SELECT current_city FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
                sstatus=$(p3_psql --tuples-only -c "SELECT status FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
                [[ "$sstatus" != "docked" ]] && { warn "Ship must be docked to trade."; pause; continue; }
                p3_interactive_sell "$sid" "$scity" ;;

            # ── PRESENCE (COUNTING HOUSES) ────────────────────────────────
            "Establish Counting House")
                local city city_id cost gold_now
                city=$(p3_pick_city)
                [[ -z "$city" ]] && { pause; continue; }
                city_id=$(p3_psql --tuples-only -c \
                    "SELECT city_id FROM p3_cities WHERE name='$city';" | tr -d ' ')

                local exists
                exists=$(p3_psql --tuples-only -c \
                    "SELECT COUNT(*) FROM p3_counting_houses WHERE city_id=$city_id;" | tr -d ' ')
                if [[ "${exists:-0}" -gt 0 ]]; then
                    warn "You already have a counting house in $city."
                    pause; continue
                fi

                cost=$(p3_psql --tuples-only -c \
                    "SELECT p3_counting_house_cost('$city');" | tr -d ' ')
                gold_now=$(p3_gold)
                info "Counting house in $city costs ${cost}g."
                info "Grants permanent market visibility and enables orders there."

                if awk "BEGIN{exit !(${gold_now}+0 < ${cost}+0)}"; then
                    error "Not enough gold (have ${gold_now}g, need ${cost}g)."
                    pause; continue
                fi

                if confirm "Establish counting house in $city for ${cost}g?"; then
                    p3_psql -c "
                        INSERT INTO p3_counting_houses (city_name, city_id)
                        VALUES ('$city', $city_id);
                        UPDATE p3_player SET gold = gold - $cost;" >/dev/null
                    success "Counting house established in $city."
                fi ;;

            "View My Counting Houses")
                p3_psql -c "
                    SELECT ch.city_name AS city, ci.region, ci.population,
                           ci.league, ch.established::date AS since,
                           p3_counting_house_cost(ch.city_name) AS build_cost_ref
                    FROM p3_counting_houses ch
                    JOIN p3_cities ci ON ci.city_id = ch.city_id
                    ORDER BY ch.city_name;" ;;

            # ── MARKET ────────────────────────────────────────────────────
            "View Market at City")
                local city; city=$(p3_pick_city)
                [[ -z "$city" ]] && { pause; continue; }
                local can_see
                can_see=$(p3_psql --tuples-only -c "
                    SELECT COUNT(*) FROM p3_player_visible_city_ids() vid
                    JOIN p3_cities ci ON ci.city_id = vid.city_id
                    WHERE ci.name = '$city';" | tr -d ' ')
                if [[ "${can_see:-0}" -eq 0 ]]; then
                    warn "You have no presence in $city."
                    info  "Sail a ship there or establish a counting house to see prices."
                    pause; continue
                fi
                p3_psql -c "
                    SELECT good, current_buy AS buying_price, current_sell AS selling_price,
                           stock, signal
                    FROM p3_visible_market_view WHERE city = '$city'
                    ORDER BY good;" ;;

            "Best Arbitrage Opportunities")
                local is_adm
                is_adm=$(p3_psql --tuples-only -c "SELECT is_admin FROM p3_player;" | tr -d ' ')
                if [[ "$is_adm" != "t" ]]; then
                    warn "Arbitrage data is restricted to administrators."
                    info  "Only senior merchants with city council access can view this."
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

            "Price History for Good")
                local good; good=$(p3_pick_good)
                [[ -z "$good" ]] && { pause; continue; }
                local city; city=$(p3_pick_city)
                [[ -z "$city" ]] && { pause; continue; }
                # Check visibility
                local can_see
                can_see=$(p3_psql --tuples-only -c "
                    SELECT COUNT(*) FROM p3_player_visible_city_ids() vid
                    JOIN p3_cities ci ON ci.city_id = vid.city_id
                    WHERE ci.name = '$city';" | tr -d ' ')
                if [[ "${can_see:-0}" -eq 0 ]]; then
                    warn "No price data available — you have no presence in $city."
                    pause; continue
                fi
                p3_psql -c "
                    SELECT game_year, game_day, buy_price, sell_price, stock
                    FROM p3_price_history ph
                    JOIN p3_cities ci ON ci.city_id = ph.city_id AND ci.name  = '$city'
                    JOIN p3_goods  g  ON g.good_id  = ph.good_id AND g.name   = '$good'
                    ORDER BY game_year, game_day
                    LIMIT 60;" ;;

            "Good Reference Prices")
                p3_psql -c "
                    SELECT name, category,
                           buy_price_min, sell_price_min, sell_price_max,
                           ROUND(base_production, 4) AS prod_per_day,
                           is_raw_material AS raw
                    FROM p3_goods ORDER BY category, name;" ;;

            # ── ROUTES ────────────────────────────────────────────────────
            "View All Routes")
                p3_psql -c "
                    SELECT name, city_a, city_b, distance_nm,
                           travel_days AS days_snaikka,
                           GREATEST(1, ROUND(distance_nm::NUMERIC/(7.0*24.0))::INTEGER) AS days_crayer,
                           GREATEST(1, ROUND(distance_nm::NUMERIC/(9.0*24.0))::INTEGER) AS days_galley
                    FROM p3_routes ORDER BY name;" ;;

            "Create Trade Route")
                local rname ca cb dist
                rname=$(gum input --placeholder "Route name (e.g. Lübeck–Gdansk Beer Run)")
                [[ -z "$rname" ]] && { pause; continue; }
                info "Select city A:"; ca=$(p3_pick_city); [[ -z "$ca" ]] && { pause; continue; }
                info "Select city B:"; cb=$(p3_pick_city); [[ -z "$cb" ]] && { pause; continue; }
                dist=$(gum input --placeholder "Distance in nautical miles" --value "300")
                local tdays; tdays=$(awk "BEGIN{printf \"%d\", int(${dist}/120 + 0.5)}")
                [[ -z "$tdays" || "$tdays" == "0" ]] && tdays=3
                p3_psql -c "
                    INSERT INTO p3_routes (name, city_a, city_b, distance_nm, travel_days)
                    VALUES ('$rname', '$ca', '$cb', $dist, $tdays);" >/dev/null
                success "Route '$rname' created (${tdays}d at Snaikka speed)." ;;

            "Add Order to Route")
                local rlist rid rname
                rlist=$(p3_psql --tuples-only -c "SELECT route_id||' – '||name FROM p3_routes ORDER BY name;" \
                    | sed 's/^ *//' | grep -v '^$')
                [[ -z "$rlist" ]] && { warn "No routes."; pause; continue; }
                rname=$(echo "$rlist" | gum filter --placeholder "Select route…")
                rid="${rname%% *}"
                [[ -z "$rid" ]] && { pause; continue; }
                local city; city=$(p3_pick_city); [[ -z "$city" ]] && { pause; continue; }
                local action; action=$(gum choose "buy" "sell")
                local good; good=$(p3_pick_good); [[ -z "$good" ]] && { pause; continue; }
                local gid; gid=$(p3_psql --tuples-only -c "SELECT good_id FROM p3_goods WHERE name='$good';" | tr -d ' ')
                local qty; qty=$(gum input --placeholder "Quantity" --value "10")
                local maxp; maxp=$(gum input --placeholder "Max/min price (blank = no limit)")
                if [[ "$action" == "buy" ]]; then
                    p3_psql -c "INSERT INTO p3_route_orders (route_id, city, good_id, action, quantity, max_price)
                                VALUES ($rid, '$city', $gid, 'buy', $qty,
                                        $([ -n "$maxp" ] && echo "'$maxp'" || echo 'NULL'));" >/dev/null
                else
                    p3_psql -c "INSERT INTO p3_route_orders (route_id, city, good_id, action, quantity, min_price)
                                VALUES ($rid, '$city', $gid, 'sell', $qty,
                                        $([ -n "$maxp" ] && echo "'$maxp'" || echo 'NULL'));" >/dev/null
                fi
                success "Order added to route." ;;

            "Assign Ship to Route")
                local sid; sid=$(p3_pick_ship) || { pause; continue; }
                local rlist rname rid
                rlist=$(p3_psql --tuples-only -c "SELECT route_id||' – '||name FROM p3_routes ORDER BY name;" \
                    | sed 's/^ *//' | grep -v '^$')
                rname=$(echo "$rlist" | gum filter --placeholder "Select route…")
                rid="${rname%% *}"
                [[ -z "$rid" ]] && { pause; continue; }
                p3_psql -c "INSERT INTO p3_ship_routes (ship_id, route_id, active)
                            VALUES ($sid, $rid, TRUE) ON CONFLICT DO NOTHING;" >/dev/null
                success "Ship assigned to route." ;;

            # ── WORLD ─────────────────────────────────────────────────────
            "View All Cities")
                p3_psql -c "
                    SELECT name, region, league, population,
                           COALESCE(hex_q::text, '?') || ',' || COALESCE(hex_r::text, '?') AS hex_qr
                    FROM p3_cities ORDER BY league, region, name;" ;;

            "City Production Details")
                local city; city=$(p3_pick_city)
                [[ -z "$city" ]] && { pause; continue; }
                p3_psql -c "
                    SELECT g.name AS good, cg.role, cg.efficiency,
                           ROUND(g.base_production * cg.efficiency / 100.0, 4) AS daily_output,
                           ROUND(g.base_production * cg.efficiency / 100.0 * 30, 2) AS est_30d
                    FROM p3_city_goods cg
                    JOIN p3_goods   g  ON g.good_id  = cg.good_id
                    JOIN p3_cities  ci ON ci.city_id = cg.city_id AND ci.name = '$city'
                    ORDER BY cg.role, g.name;" ;;

            # ── TIME ──────────────────────────────────────────────────────
            "Advance One Day")
                p3_advance_day ;;

            "Advance Multiple Days")
                local ndays
                ndays=$(gum input --placeholder "How many days to advance?" --value "10")
                [[ -z "$ndays" || ! "$ndays" =~ ^[0-9]+$ ]] && { error "Enter a number."; pause; continue; }
                local i
                for (( i=1; i<=ndays; i++ )); do
                    p3_advance_day
                done
                success "Advanced $ndays days." ;;

            # ── LOG ───────────────────────────────────────────────────────
            "View Trade Log")
                p3_psql -c "
                    SELECT game_year, game_day, action,
                           COALESCE(good_name, '—') AS good,
                           COALESCE(ship_name, '—') AS ship,
                           COALESCE(city, '—')      AS city,
                           quantity, price, total_value, gold_after
                    FROM p3_trade_log
                    ORDER BY log_id DESC LIMIT 40;" ;;

            "Back" | *)
                pop_breadcrumb
                CURRENT_MENU="main"
                return ;;
        esac
        pause
    done
}

