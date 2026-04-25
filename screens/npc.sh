#!/usr/bin/env bash
# screens/npc.sh  —  NPC fleet management (admin only)
# DEPENDENCIES: lib/db.sh  lib/ui.sh

# ─────────────────────────────────────────────────────────────────────────────
#  §14k  NPC FLEET MENU  (admin)
# ─────────────────────────────────────────────────────────────────────────────
p3_npc_menu() {
    local is_adm
    is_adm=$(p3_psql --tuples-only -c "SELECT is_admin FROM p3_player;" | tr -d ' ')
    if [[ "$is_adm" != "t" ]]; then
        warn "NPC fleet management requires administrator access."
        return
    fi
    push_breadcrumb "🤖 NPC Fleet"
    while true; do
        section_header "🤖 NPC Merchant Fleet"
        choice=$(gum choose \
            "View NPC Fleet Summary" \
            "View NPC Ships Visible in My Cities" \
            "View NPC Trade Log" \
            "Run NPC AI Tick Manually" \
            "Back")

        case "$choice" in
            "View NPC Fleet Summary")
                p3_psql -c "
                    SELECT ship, specialisation, current_city, status,
                           destination, ai_state, trips_completed, total_profit
                    FROM p3_npc_fleet_summary;" ;;

            "View NPC Ships Visible in My Cities")
                p3_psql -c "
                    SELECT name AS ship, ship_type, current_city,
                           status, specialisation
                    FROM p3_visible_npc_ships
                    ORDER BY current_city, name;" ;;

            "View NPC Trade Log")
                p3_psql -c "
                    SELECT game_year, game_day, ship_name, good_name,
                           action, city, quantity, price, profit
                    FROM p3_npc_trade_log
                    ORDER BY log_id DESC LIMIT 40;" ;;

            "Run NPC AI Tick Manually")
                p3_npc_tick
                success "NPC AI tick complete." ;;

            "Back" | *) pop_breadcrumb; return ;;
        esac
        pause
    done
}
