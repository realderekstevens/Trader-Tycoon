#!/usr/bin/env bash
# screens/admin.sh  —  Admin & Setup menu (init, reseed, tick, arbitrage)
# DEPENDENCIES: lib/db.sh  lib/ui.sh  lib/tick.sh  screens/npc.sh

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
