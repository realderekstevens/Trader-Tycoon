#!/usr/bin/env bash
# screens/hex.sh  —  Hex map, city distances, tile operations
# DEPENDENCIES: lib/db.sh  lib/ui.sh

p3_hex_menu() {
    push_breadcrumb "🗺 Hex Map"
    while true; do
        section_header "🗺 Hex Map & World"

        choice="$(gum choose \
            "── Overview ──" \
            "Show All City Positions" \
            "ASCII Map (text overview)" \
            "── Distance & Travel ──" \
            "Distance Between Two Cities" \
            "Cities Within Range of City" \
            "Travel Time Between Cities" \
            "── Hex Tile Operations ──" \
            "View Tile at Coordinates" \
            "List All Placed Tiles" \
            "Create / Edit Tile" \
            "Move City to New Hex" \
            "Back")"

        case "$choice" in
            "── Overview ──"|"── Distance & Travel ──"|"── Hex Tile Operations ──")
                continue ;;

            "Show All City Positions")
                p3_psql -c "
                    SELECT ci.name AS city, ci.region, ci.league,
                           ci.hex_q AS q, ci.hex_r AS r,
                           (-ci.hex_q - ci.hex_r) AS s,
                           COALESCE(ht.terrain, 'unmapped') AS terrain,
                           ci.population
                    FROM p3_cities ci
                    LEFT JOIN p3_hex_tiles ht ON ht.city_id = ci.city_id
                    ORDER BY ci.league, ci.name;" ;;

            "ASCII Map (text overview)")
                gum style --foreground 244 \
                    "Pointy-top hex map  |  1 hex ≈ 50 nm  |  q→E  r→S  |  Lübeck = (0,0)"
                echo
                p3_psql -c "
                    SELECT
                        LPAD(ci.hex_q::text, 4) || ',' ||
                        LPAD(ci.hex_r::text, 4) || '  ' ||
                        RPAD(LEFT(ci.name, 18), 18) ||
                        '  hexes_from_Lubeck: ' ||
                        COALESCE(p3_hex_distance(0, 0, ci.hex_q, ci.hex_r)::text, '?')
                    FROM p3_cities ci
                    WHERE ci.hex_q IS NOT NULL
                    ORDER BY ci.hex_r, ci.hex_q;" | cat
                echo
                gum style --foreground 244 "Snaikka (5 kn): ~120 nm/day ≈ 2.4 hex/day." ;;

            "Distance Between Two Cities")
                info "Select first city:";  local ca; ca=$(p3_pick_city)
                [[ -z "$ca" ]] && { pause; continue; }
                info "Select second city:"; local cb; cb=$(p3_pick_city)
                [[ -z "$cb" ]] && { pause; continue; }
                p3_psql -c "
                    SELECT ca.name AS from_city, cb.name AS to_city,
                           COALESCE(p3_hex_distance(ca.hex_q,ca.hex_r,cb.hex_q,cb.hex_r)::text,'?') AS hex_dist,
                           COALESCE((p3_hex_distance(ca.hex_q,ca.hex_r,cb.hex_q,cb.hex_r)*50)::text,'?') AS approx_nm,
                           COALESCE(p3_travel_days(ca.city_id,cb.city_id,5.0)::text,'no coords') AS days_snaikka_5kn,
                           COALESCE(p3_travel_days(ca.city_id,cb.city_id,7.0)::text,'—')         AS days_crayer_7kn,
                           COALESCE(p3_travel_days(ca.city_id,cb.city_id,9.0)::text,'—')         AS days_galley_9kn
                    FROM p3_cities ca, p3_cities cb
                    WHERE ca.name = '$ca' AND cb.name = '$cb';" ;;

            "Cities Within Range of City")
                local src_city max_days
                src_city=$(p3_pick_city); [[ -z "$src_city" ]] && { pause; continue; }
                max_days=$(gum input --placeholder "Max travel days (e.g. 7)" --value "7")
                [[ -z "$max_days" ]] && { pause; continue; }
                p3_psql -c "
                    SELECT dest.name AS city,
                           COALESCE(p3_hex_distance(src.hex_q,src.hex_r,dest.hex_q,dest.hex_r)::text,'?') AS hexes,
                           COALESCE((p3_hex_distance(src.hex_q,src.hex_r,dest.hex_q,dest.hex_r)*50)::text,'?') AS nm,
                           COALESCE(p3_travel_days(src.city_id,dest.city_id,5.0)::text,'?') AS days_snaikka
                    FROM p3_cities src, p3_cities dest
                    WHERE src.name = '$src_city'
                      AND dest.city_id <> src.city_id
                      AND dest.hex_q IS NOT NULL AND src.hex_q IS NOT NULL
                      AND COALESCE(p3_travel_days(src.city_id,dest.city_id,5.0), 9999) <= $max_days
                    ORDER BY p3_travel_days(src.city_id,dest.city_id,5.0), dest.name;" ;;

            "Travel Time Between Cities")
                info "Snaikka 5kn · Crayer 7kn · Hulk 4kn · Cog 6kn · Galley 9kn · Carrack 5.5kn"
                info "Select origin:";      local ta; ta=$(p3_pick_city); [[ -z "$ta" ]] && { pause; continue; }
                info "Select destination:"; local tb; tb=$(p3_pick_city); [[ -z "$tb" ]] && { pause; continue; }
                p3_psql -c "
                    SELECT ca.name AS origin, cb.name AS destination,
                           COALESCE(p3_hex_distance(ca.hex_q,ca.hex_r,cb.hex_q,cb.hex_r)::text,'?') AS hex_dist,
                           COALESCE(p3_travel_days(ca.city_id,cb.city_id,5.0)::text,'?')   AS snaikka_5kn,
                           COALESCE(p3_travel_days(ca.city_id,cb.city_id,7.0)::text,'?')   AS crayer_7kn,
                           COALESCE(p3_travel_days(ca.city_id,cb.city_id,9.0)::text,'?')   AS galley_9kn,
                           COALESCE(p3_travel_days(ca.city_id,cb.city_id,5.5)::text,'?')   AS carrack_5_5kn
                    FROM p3_cities ca, p3_cities cb
                    WHERE ca.name = '$ta' AND cb.name = '$tb';" ;;

            "View Tile at Coordinates")
                local tq; tq=$(gum input --placeholder "q" --value "0")
                local tr; tr=$(gum input --placeholder "r" --value "0")
                p3_psql -c "
                    SELECT ht.q, ht.r, ht.s, ht.terrain,
                           COALESCE(ci.name, '(no city)') AS city,
                           COALESCE(ht.hazard, 'none') AS hazard, ht.notes
                    FROM p3_hex_tiles ht
                    LEFT JOIN p3_cities ci ON ci.city_id = ht.city_id
                    WHERE ht.q = $tq AND ht.r = $tr;" ;;

            "List All Placed Tiles")
                p3_psql -c "
                    SELECT ht.q, ht.r, ht.s, ht.terrain,
                           COALESCE(ci.name, '—') AS city,
                           COALESCE(ht.hazard, '—') AS hazard
                    FROM p3_hex_tiles ht
                    LEFT JOIN p3_cities ci ON ci.city_id = ht.city_id
                    ORDER BY ht.r, ht.q;" ;;

            "Create / Edit Tile")
                local tq tr terrain hazard tnotes
                tq=$(gum input --placeholder "q coordinate")
                tr=$(gum input --placeholder "r coordinate")
                [[ -z "$tq" || -z "$tr" ]] && { pause; continue; }
                terrain=$(gum choose "sea" "coast" "land" "forest" "mountain" "ice")
                hazard=$(gum input --placeholder "Hazard (blank = none)")
                tnotes=$(gum input --placeholder "Notes  (blank = none)")
                p3_psql -c "
                    INSERT INTO p3_hex_tiles (q, r, terrain, hazard, notes)
                    VALUES ($tq, $tr, '$terrain',
                            NULLIF('$hazard',''), NULLIF('$tnotes',''))
                    ON CONFLICT (q, r) DO UPDATE
                        SET terrain = EXCLUDED.terrain,
                            hazard  = EXCLUDED.hazard,
                            notes   = EXCLUDED.notes;" >/dev/null
                success "Tile ($tq,$tr) saved as $terrain." ;;

            "Move City to New Hex")
                local city nq nr
                city=$(p3_pick_city); [[ -z "$city" ]] && { pause; continue; }
                nq=$(gum input --placeholder "New q coordinate")
                nr=$(gum input --placeholder "New r coordinate")
                [[ -z "$nq" || -z "$nr" ]] && { pause; continue; }
                p3_psql -c "UPDATE p3_cities SET hex_q = $nq, hex_r = $nr WHERE name = '$city';" >/dev/null
                success "$city moved to hex ($nq,$nr)." ;;

            "Back" | *) pop_breadcrumb; return ;;
        esac
        pause
    done
}

# ─────────────────────────────────────────────────────────────────────────────
#  ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────
run_app() {
    clear
    gum style \
        --border double \
        --margin "1" \
        --padding "1 4" \
        --border-foreground 33 \
        --bold \
        "⚓  PATRICIAN III / IV" \
        "$(gum style --foreground 244 'Hanseatic Trading Simulation — CLI Edition')"
    patrician_menu
}

