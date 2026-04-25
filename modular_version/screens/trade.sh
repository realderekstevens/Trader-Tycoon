#!/usr/bin/env bash
# screens/trade.sh  —  Interactive buy and sell screens with marginal pricing
# DEPENDENCIES: lib/db.sh  lib/ui.sh

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
p3_interactive_sell() {
    local sid="$1" scity="$2"
    local gold
    gold=$(p3_gold)

    # Build cargo list with current bid prices
    local cargo_list
    cargo_list=$(p3_psql --tuples-only -c "
        SELECT RPAD(g.name, 14) ||
               '  ABOARD:' || RPAD(c.quantity::text, 7) ||
               'SELL:'     || RPAD(m.current_sell::text, 9) ||
               'STK:'      || RPAD(m.stock::text, 6) ||
               'EST:'      || ROUND(m.current_sell * c.quantity, 2) || 'g'
        FROM   p3_cargo c
        JOIN   p3_goods  g  ON g.good_id  = c.good_id
        JOIN   p3_ships  s  ON s.ship_id  = c.ship_id AND s.ship_id = $sid
        JOIN   p3_cities ci ON ci.name    = s.current_city
        JOIN   p3_market m  ON m.good_id  = c.good_id AND m.city_id = ci.city_id
        WHERE  c.quantity > 0 ORDER BY g.name;" 2>/dev/null \
        | sed 's/^ *//' | grep -v '^$' || true)

    if [[ -z "$cargo_list" ]]; then
        warn "No cargo aboard this ship."
        return
    fi

    clear
    gum style --foreground 214 --bold "SELL GOODS — $scity  |  Your gold: ${gold}g"
    echo
    gum style --foreground 244 "  $(printf '%-14s  %-14s %-16s %-10s %s' 'GOOD' 'ABOARD' 'SELLING PRICE' 'STOCK' 'EST.VALUE')"
    echo

    local chosen_line
    chosen_line=$(printf '%s\n' "$cargo_list" \
        | gum filter \
            --placeholder "Type to filter cargo…" \
            --height 20 \
            --prompt "▶ " \
            --indicator "→")
    [[ -z "$chosen_line" ]] && return

    local good
    good=$(echo "$chosen_line" | awk '{print $1}')
    [[ -z "$good" ]] && return

    # Fetch market + cargo + elasticity data in one shot
    local ask bid stock aboard elast_sell stock_ref
    {
        read -r ask; read -r bid; read -r stock; read -r aboard
        read -r elast_sell; read -r stock_ref
    } < <(p3_psql --tuples-only -c "
        SELECT m.current_buy::text,
               m.current_sell::text,
               m.stock::text,
               COALESCE(c.quantity, 0)::text,
               e.elasticity_sell::text,
               e.stock_ref::text
        FROM p3_market m
        JOIN p3_cities        ci ON ci.city_id = m.city_id AND ci.name = '$scity'
        JOIN p3_goods          g ON g.good_id  = m.good_id AND g.name  = '$good'
        JOIN p3_good_elasticity e ON e.good_id = g.good_id
        LEFT JOIN p3_cargo     c ON c.good_id  = m.good_id AND c.ship_id = $sid
        LIMIT 1;" 2>/dev/null | sed 's/|/\n/g; s/^ *//; s/ *$//' \
        || printf '0\n0\n0\n0\n0.5\n80\n')

    # Build marginal sell curve in bash
    # Selling increases city stock → price falls with each unit sold.
    # Anchored so that q=1 yields exactly the current Selling Price (bid).
    # unit_price(q) = bid * (stock / max(stock + q - 1, 1))^elast_sell
    #   q=1  → bid*(stock/stock)^e  = bid  ✓
    #   q=2  → bid*(stock/(stock+1))^e < bid  ✓ (more stock = less rare)
    clear
    gum style --foreground 214 --bold "MARGINAL SELL CURVE — $good in $scity"
    gum style --foreground 244 "    Current Selling Price: ${bid}g  |  Buying Price: ${ask}g  |  City stock: ${stock}  |  Aboard: ${aboard}"
    echo
    printf '  %-6s  %-12s  %s\n' "QTY" "UNIT PRICE" "TOTAL REVENUE"

    local running_total=0
    local i
    for i in $(seq 1 20); do
        local unit_price
        unit_price=$(awk -v bid="$bid" -v stk="$stock" \
                         -v e="$elast_sell" -v q="$i" '
            BEGIN {
                denom = stk + q - 1
                if (denom < 1) denom = 1
                printf "%.2f", bid * (stk / denom)^e
            }')
        running_total=$(awk -v rt="$running_total" -v up="$unit_price" \
            'BEGIN { printf "%.2f", rt + up }')
        printf '  %-6s  %-12s  %s\n' "$i" "${unit_price}g" "${running_total}g"
    done
    echo

    local qty
    qty=$(gum input --placeholder "How many units to sell? (max ${aboard}, 0 to cancel)" --value "")
    [[ -z "$qty" || ! "$qty" =~ ^[0-9]+$ || "$qty" == "0" ]] && { warn "Sale cancelled."; return; }

    # Compute precise total revenue for chosen qty
    local total_revenue=0
    for i in $(seq 1 "$qty"); do
        local up
        up=$(awk -v bid="$bid" -v stk="$stock" \
                 -v e="$elast_sell" -v q="$i" '
            BEGIN {
                denom = stk + q - 1
                if (denom < 1) denom = 1
                printf "%.2f", bid * (stk / denom)^e
            }')
        total_revenue=$(awk -v tr="$total_revenue" -v up="$up" 'BEGIN { printf "%.2f", tr + up }')
    done

    echo
    gum style --foreground 214 --bold "  SUMMARY: Sell $qty x $good in $scity"
    gum style --foreground 244 "  Unit range: ${bid}g (1st unit) → marginal pricing applied"
    gum style --foreground 76  "  Total revenue: ${total_revenue}g  |  Gold after: $(awk "BEGIN{printf \"%.2f\", $gold + $total_revenue}")g"
    echo

    if gum confirm --default=false "Confirm sale: $qty × $good for ${total_revenue}g?"; then
        p3_do_sell "$sid" "$good" "$qty" "$scity"
    else
        warn "Sale cancelled."
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14j  MAIN PATRICIAN MENU
# ─────────────────────────────────────────────────────────────────────────────
