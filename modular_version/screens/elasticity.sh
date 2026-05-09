#!/usr/bin/env bash
# screens/elasticity.sh  —  Market elasticity and price curve explorer
# DEPENDENCIES: lib/db.sh  lib/ui.sh

p3_elasticity_menu() {
    push_breadcrumb "📊 Elasticity"
    while true; do
        section_header "📊 Market Elasticity & Price Curves"
        choice="$(gum choose \
            "── Info ──" \
            "Elasticity Reference Table" \
            "Preview Marginal Price Curve" \
            "── Admin ──" \
            "Adjust Good Elasticity" \
            "Back")"

        case "$choice" in
            "── Info ──"|"── Admin ──") continue ;;

            "Elasticity Reference Table")
                gum style --foreground 33 --bold \
                    "  $(printf '%-14s %-11s %-7s %-8s %-10s %-7s %s' \
                        'GOOD' 'CATEGORY' 'BUY_E' 'SELL_E' 'STOCK_REF' 'FLOOR' 'CEIL')"
                p3_psql --tuples-only -c "
                    SELECT '  ' ||
                           RPAD(g.name, 14) ||
                           RPAD(g.category, 11) ||
                           RPAD(e.elasticity_buy::text, 7) ||
                           RPAD(e.elasticity_sell::text, 8) ||
                           RPAD(e.stock_ref::text, 10) ||
                           RPAD(e.price_floor_pct::text, 7) ||
                           e.price_ceil_pct::text
                    FROM p3_goods g
                    JOIN p3_good_elasticity e ON e.good_id = g.good_id
                    ORDER BY e.elasticity_buy DESC;" 2>/dev/null | grep -v '^\s*$' | cat ;;

            "Adjust Good Elasticity")
                local good; good=$(p3_pick_good); [[ -z "$good" ]] && { pause; continue; }
                p3_psql -c "
                    SELECT e.elasticity_buy, e.elasticity_sell,
                           e.stock_ref, e.price_floor_pct, e.price_ceil_pct
                    FROM p3_good_elasticity e JOIN p3_goods g USING (good_id)
                    WHERE g.name = '$good';" | cat
                local new_buy new_sell new_ref
                new_buy=$(gum input  --placeholder "elasticity_buy  (blank=keep)")
                new_sell=$(gum input --placeholder "elasticity_sell (blank=keep)")
                new_ref=$(gum input  --placeholder "stock_ref       (blank=keep)")
                p3_psql -c "
                    UPDATE p3_good_elasticity e
                    SET elasticity_buy  = COALESCE(NULLIF('$new_buy','')::NUMERIC,  e.elasticity_buy),
                        elasticity_sell = COALESCE(NULLIF('$new_sell','')::NUMERIC, e.elasticity_sell),
                        stock_ref       = COALESCE(NULLIF('$new_ref','')::INTEGER,  e.stock_ref)
                    FROM p3_goods g WHERE g.good_id = e.good_id AND g.name = '$good';" >/dev/null
                success "Elasticity updated for $good." ;;

            "Preview Marginal Price Curve")
                local good city
                good=$(p3_pick_good); [[ -z "$good" ]] && { pause; continue; }
                city=$(p3_pick_city); [[ -z "$city" ]] && { pause; continue; }
                gum style --bold --foreground 212 "── Marginal Ask for buying 1…20 units of $good in $city ──"
                p3_psql -c "
                    SELECT
                        generate_series(1,20) AS qty,
                        ROUND(
                            ((m.current_buy/1.08 + m.current_sell/0.92)/2.0)
                            * POWER(
                                e.stock_ref::NUMERIC
                                / GREATEST(m.stock - generate_series(1,20) + 1, 1)::NUMERIC,
                                e.elasticity_buy
                            )
                            * 1.08,
                        2) AS marginal_ask
                    FROM p3_market m
                    JOIN p3_cities ci ON ci.city_id = m.city_id AND ci.name = '$city'
                    JOIN p3_goods  g  ON g.good_id  = m.good_id AND g.name  = '$good'
                    JOIN p3_good_elasticity e ON e.good_id = g.good_id;" | cat ;;

            "Back" | *) pop_breadcrumb; return ;;
        esac
        pause
    done
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14o  HEX MAP MENU
# ─────────────────────────────────────────────────────────────────────────────
