#!/usr/bin/env bash
# =============================================================================
#  lib/tick.sh  —  Game time: manual day-advance and real-time daemon
#
#  p3_advance_day      : advance one game day (ships, production, prices,
#                        routes, buildings, NPC AI, calendar)
#  p3_start_tick / p3_stop_tick / p3_tick_status : daemon management
#  p3_set_tick_interval : change the daemon interval at runtime
#
#  The daemon posts pg_notify on channel p3_day_tick after every advance,
#  so external listeners (websockets, log tailers) can react in real time.
#
#  DEPENDENCIES: lib/db.sh  lib/ui.sh
# =============================================================================

P3_TICK_PID_FILE="/tmp/p3_tick_${P3_DB:-traderdude}.pid"
P3_LISTEN_PID_FILE="/tmp/p3_listen_${P3_DB:-traderdude}.pid"
P3_TICK_STATE_FILE="/tmp/p3_tick_${P3_DB:-traderdude}.state"
P3_TICK_INTERVAL="${P3_TICK_INTERVAL:-10}"

# ─────────────────────────────────────────────────────────────────────────────
#  §14c  ADVANCE ONE DAY
# ─────────────────────────────────────────────────────────────────────────────
p3_advance_day() {

    # 1. Tick ships
    p3_psql -c "
        UPDATE p3_ships SET eta_days = eta_days - 1
        WHERE  status = 'sailing' AND eta_days > 0;

        UPDATE p3_ships
        SET    status = 'docked', current_city = destination,
               destination = NULL, eta_days = 0
        WHERE  status = 'sailing' AND eta_days <= 0;
    " >/dev/null

    # 2. Log arrivals
    p3_psql -c "
        INSERT INTO p3_trade_log
            (game_year, game_day, ship_id, ship_name, city, action, logged_at)
        SELECT pl.game_year, pl.game_day, s.ship_id, s.name, s.current_city, 'arrive', NOW()
        FROM   p3_ships s, p3_player pl
        WHERE  s.owner  = 'player' AND s.status = 'docked' AND s.eta_days = 0
          AND  NOT EXISTS (
              SELECT 1 FROM p3_trade_log tl
              WHERE  tl.ship_id   = s.ship_id AND tl.action = 'arrive'
                AND  tl.game_year = pl.game_year AND tl.game_day = pl.game_day
          );
    " >/dev/null 2>&1 || true

    # 3. Daily production
    p3_psql -c "
        UPDATE p3_market m
        SET    stock = LEAST(500,
                   GREATEST(0,
                       m.stock
                       + COALESCE((
                           SELECT FLOOR(g.base_production * cg.efficiency / 100.0)::INTEGER
                           FROM   p3_city_goods cg
                           JOIN   p3_goods      g ON g.good_id = cg.good_id
                           WHERE  cg.city_id = m.city_id AND cg.good_id = m.good_id
                             AND  cg.role = 'produces'
                         ), 0)
                       - GREATEST(1, ROUND((m.stock * 0.0017)::NUMERIC, 0)::INTEGER)
                   ))
        WHERE  m.stock > 0 OR EXISTS (
            SELECT 1 FROM p3_city_goods cg
            WHERE cg.city_id = m.city_id AND cg.good_id = m.good_id AND cg.role = 'produces'
        );
    " >/dev/null

    # 4. Daily price tick
    p3_psql -c "
        UPDATE p3_market m
        SET current_sell = GREATEST(1::NUMERIC, ROUND(new_mid * 0.92, 2)),
            current_buy  = GREATEST(1::NUMERIC, ROUND(new_mid * 1.08, 2))
        FROM (
            SELECT m2.city_id, m2.good_id,
                ROUND(
                    ((m2.current_buy / 1.08 + m2.current_sell / 0.92) / 2.0)
                    * CASE
                        WHEN m2.stock < 20  THEN 1.0027::NUMERIC
                        WHEN m2.stock < 50  THEN 1.0010::NUMERIC
                        WHEN m2.stock > 200 THEN 0.9990::NUMERIC
                        WHEN m2.stock > 350 THEN 0.9977::NUMERIC
                        ELSE 1.0000::NUMERIC
                      END
                    * (0.9987::NUMERIC + (RANDOM()::NUMERIC) * 0.0026::NUMERIC)
                    * CASE
                        WHEN ((m2.current_buy/1.08 + m2.current_sell/0.92)/2.0)
                             > g.buy_price_min * 1.5 THEN 0.9990::NUMERIC
                        WHEN ((m2.current_buy/1.08 + m2.current_sell/0.92)/2.0)
                             < g.buy_price_min * 0.5 THEN 1.0010::NUMERIC
                        ELSE 1.0000::NUMERIC
                      END,
                2) AS new_mid
            FROM p3_market m2 JOIN p3_goods g ON g.good_id = m2.good_id
        ) e
        WHERE e.city_id = m.city_id AND e.good_id = m.good_id;
    " >/dev/null

    # 5. Snapshot price history every 10 days
    p3_psql -c "
        INSERT INTO p3_price_history
            (city_id, good_id, game_year, game_day, buy_price, sell_price, stock)
        SELECT m.city_id, m.good_id, pl.game_year, pl.game_day,
               m.current_buy, m.current_sell, m.stock
        FROM   p3_market m, p3_player pl
        WHERE  (pl.game_day % 10) = 0
        ON CONFLICT DO NOTHING;
    " >/dev/null 2>&1 || true

    # 6. Route standing orders
    p3_psql -c "
        DO \$\$
        DECLARE r RECORD; v_free INTEGER; v_qty INTEGER; v_total NUMERIC; v_gold NUMERIC;
        BEGIN
            FOR r IN
                SELECT sr.ship_id, ro.good_id, ro.quantity, ro.max_price,
                       m.current_buy, ci.city_id, m.stock AS mstock
                FROM   p3_ship_routes sr
                JOIN   p3_routes rt ON rt.route_id = sr.route_id AND sr.active
                JOIN   p3_route_orders ro ON ro.route_id = rt.route_id AND ro.action = 'buy'
                JOIN   p3_ships s ON s.ship_id = sr.ship_id AND s.status = 'docked'
                                 AND s.current_city = ro.city
                JOIN   p3_cities ci ON ci.name = s.current_city
                JOIN   p3_market m  ON m.city_id = ci.city_id AND m.good_id = ro.good_id
                WHERE (ro.max_price IS NULL OR m.current_buy <= ro.max_price) AND m.stock > 0
            LOOP
                SELECT cargo_free INTO v_free FROM p3_fleet_view WHERE ship_id = r.ship_id;
                v_qty := LEAST(r.quantity, v_free, r.mstock);
                v_total := r.current_buy * v_qty;
                SELECT gold INTO v_gold FROM p3_player;
                CONTINUE WHEN v_qty <= 0 OR v_gold < v_total;
                INSERT INTO p3_cargo (ship_id, good_id, quantity) VALUES (r.ship_id, r.good_id, v_qty)
                    ON CONFLICT (ship_id, good_id)
                    DO UPDATE SET quantity = p3_cargo.quantity + EXCLUDED.quantity;
                UPDATE p3_market SET stock = stock - v_qty
                    WHERE city_id = r.city_id AND good_id = r.good_id;
                UPDATE p3_player SET gold = gold - v_total;
            END LOOP;
        END;
        \$\$;
    " >/dev/null 2>&1 || true

    # 6.5. Buildings + limit orders
    p3_process_production_and_orders_daily

    # 6.6. NPC ship AI
    p3_npc_tick

    # 7. Advance calendar
    p3_psql -c "
        UPDATE p3_player
        SET game_day  = CASE WHEN game_day >= 360 THEN 1 ELSE game_day + 1 END,
            game_year = CASE WHEN game_day >= 360 THEN game_year + 1 ELSE game_year END;
    " >/dev/null

    local yd
    yd=$(p3_psql --tuples-only -c \
        "SELECT 'Year '||game_year||'  Day '||LPAD(game_day::text,3,'0') FROM p3_player;" \
        | tr -d ' ')
    success "Day advanced -> $yd"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Building production + limit order fills (called each day advance)
# ─────────────────────────────────────────────────────────────────────────────
p3_process_production_and_orders_daily() {
    p3_psql <<'SQL' >/dev/null 2>&1
DO $$
DECLARE
    rec          RECORD;
    input_avail  NUMERIC;
    input_needed NUMERIC;
    actual_prod  NUMERIC;
BEGIN
    FOR rec IN
        SELECT pb.city_id, bt.output_good_id, bt.input_good_id,
               bt.input_units_per_output,
               (bt.base_production * pb.num_buildings)   AS prod_amt,
               (bt.daily_maintenance * pb.num_buildings) AS maint_cost
        FROM p3_player_buildings pb
        JOIN p3_building_types bt ON bt.building_type_id = pb.building_type_id
    LOOP
        UPDATE p3_player SET gold = GREATEST(0, gold - rec.maint_cost);
        actual_prod := 0;
        IF rec.input_good_id IS NULL THEN
            actual_prod := rec.prod_amt;
        ELSE
            SELECT COALESCE(stock, 0) INTO input_avail
            FROM p3_market WHERE city_id = rec.city_id AND good_id = rec.input_good_id;
            input_needed := rec.prod_amt * rec.input_units_per_output;
            IF input_avail >= input_needed THEN
                UPDATE p3_market SET stock = GREATEST(0, stock - FLOOR(input_needed)::INTEGER)
                WHERE city_id = rec.city_id AND good_id = rec.input_good_id;
                actual_prod := rec.prod_amt;
            ELSIF input_avail > 0 THEN
                actual_prod := input_avail / rec.input_units_per_output;
                UPDATE p3_market SET stock = 0
                WHERE city_id = rec.city_id AND good_id = rec.input_good_id;
            END IF;
        END IF;
        IF actual_prod > 0 THEN
            UPDATE p3_market SET stock = LEAST(500, stock + FLOOR(actual_prod)::INTEGER)
            WHERE city_id = rec.city_id AND good_id = rec.output_good_id;
        END IF;
    END LOOP;
END $$;
SQL
    p3_psql <<'SQL' >/dev/null 2>&1
DO $$
DECLARE
    o RECORD; fulfill INTEGER; v_free INTEGER; v_cargo INTEGER;
BEGIN
    FOR o IN
        SELECT lo.*, s.current_city, s.status, m.current_buy, m.current_sell, m.stock
        FROM p3_limit_orders lo
        JOIN p3_ships  s ON s.ship_id = lo.ship_id
        JOIN p3_market m ON m.city_id = lo.city_id AND m.good_id = lo.good_id
        WHERE lo.active AND lo.remaining_quantity > 0 AND s.status = 'docked'
          AND s.current_city = (SELECT name FROM p3_cities WHERE city_id = lo.city_id)
    LOOP
        IF o.action = 'buy' AND o.current_buy <= o.price_limit THEN
            SELECT cargo_free INTO v_free FROM p3_fleet_view WHERE ship_id = o.ship_id;
            fulfill := LEAST(o.remaining_quantity, COALESCE(v_free, 0), o.stock, 5);
            IF fulfill > 0 THEN
                INSERT INTO p3_cargo (ship_id, good_id, quantity)
                    VALUES (o.ship_id, o.good_id, fulfill)
                    ON CONFLICT (ship_id, good_id)
                    DO UPDATE SET quantity = p3_cargo.quantity + fulfill;
                UPDATE p3_market SET stock = stock - fulfill
                    WHERE city_id = o.city_id AND good_id = o.good_id;
                UPDATE p3_player SET gold = gold - (o.current_buy * fulfill);
                UPDATE p3_limit_orders SET remaining_quantity = remaining_quantity - fulfill
                    WHERE order_id = o.order_id;
            END IF;
        ELSIF o.action = 'sell' AND o.current_sell >= o.price_limit THEN
            SELECT quantity INTO v_cargo FROM p3_cargo
                WHERE ship_id = o.ship_id AND good_id = o.good_id;
            fulfill := LEAST(o.remaining_quantity, COALESCE(v_cargo, 0), 5);
            IF fulfill > 0 THEN
                UPDATE p3_cargo SET quantity = quantity - fulfill
                    WHERE ship_id = o.ship_id AND good_id = o.good_id;
                DELETE FROM p3_cargo
                    WHERE ship_id = o.ship_id AND good_id = o.good_id AND quantity <= 0;
                UPDATE p3_market SET stock = stock + fulfill
                    WHERE city_id = o.city_id AND good_id = o.good_id;
                UPDATE p3_player SET gold = gold + (o.current_sell * fulfill);
                UPDATE p3_limit_orders SET remaining_quantity = remaining_quantity - fulfill
                    WHERE order_id = o.order_id;
            END IF;
        END IF;
        UPDATE p3_limit_orders SET active = FALSE
            WHERE order_id = o.order_id AND remaining_quantity <= 0;
    END LOOP;
END $$;
SQL
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14h  REAL-TIME TICK DAEMON
# ─────────────────────────────────────────────────────────────────────────────
_p3_tick_loop() {
    while true; do
        sleep "${P3_TICK_INTERVAL:-10}"
        p3_psql <<'TKSQL' >/dev/null 2>&1 || true
UPDATE p3_ships SET eta_days = eta_days - 1
    WHERE status = 'sailing' AND eta_days > 0;
UPDATE p3_ships
    SET status = 'docked', current_city = destination, destination = NULL, eta_days = 0
    WHERE status = 'sailing' AND eta_days <= 0;
UPDATE p3_market m SET stock = LEAST(500, GREATEST(0,
    m.stock
    + COALESCE((SELECT FLOOR(g.base_production * cg.efficiency / 100.0)::INTEGER
                FROM p3_city_goods cg JOIN p3_goods g ON g.good_id = cg.good_id
                WHERE cg.city_id = m.city_id AND cg.good_id = m.good_id
                  AND cg.role = 'produces'), 0)
    - GREATEST(1, ROUND((m.stock * 0.0017)::NUMERIC, 0)::INTEGER)))
WHERE m.stock > 0 OR EXISTS (
    SELECT 1 FROM p3_city_goods cg
    WHERE cg.city_id = m.city_id AND cg.good_id = m.good_id AND cg.role = 'produces'
);
UPDATE p3_player
    SET game_day  = CASE WHEN game_day >= 360 THEN 1 ELSE game_day + 1 END,
        game_year = CASE WHEN game_day >= 360 THEN game_year + 1 ELSE game_year END;
SELECT p3_notify_tick();
TKSQL
    done
}

_p3_listen_loop() {
    p3_psql -c "LISTEN p3_day_tick;" 2>/dev/null || true
    while IFS= read -r line; do
        [[ "$line" == *"p3_day_tick"* ]] && \
            printf '[%s] tick: %s\n' "$(date +%H:%M:%S)" "$line" \
            >> "$P3_TICK_STATE_FILE" 2>/dev/null || true
    done < <(psql -X --username="$P3_USER" --dbname="$P3_DB" \
        -c "LISTEN p3_day_tick;" 2>/dev/null || true)
}

p3_start_tick() {
    if [[ -f "$P3_TICK_PID_FILE" ]] && kill -0 "$(cat "$P3_TICK_PID_FILE")" 2>/dev/null; then
        warn "Tick daemon already running  (PID $(cat "$P3_TICK_PID_FILE"))."
        return
    fi
    _p3_tick_loop &
    echo $! > "$P3_TICK_PID_FILE"
    _p3_listen_loop &
    echo $! > "$P3_LISTEN_PID_FILE"
    success "Auto-tick STARTED — 1 game day every ${P3_TICK_INTERVAL}s"
    info    "   Tick PID   : $(cat "$P3_TICK_PID_FILE")"
    info    "   pg_notify  : channel p3_day_tick  (payload = JSON)"
}

p3_stop_tick() {
    local stopped=0
    for pidfile in "$P3_TICK_PID_FILE" "$P3_LISTEN_PID_FILE"; do
        if [[ -f "$pidfile" ]]; then
            kill "$(cat "$pidfile")" 2>/dev/null || true
            rm -f "$pidfile"
            (( stopped++ )) || true
        fi
    done
    [[ $stopped -gt 0 ]] && success "Tick daemon stopped." \
                         || warn    "No tick daemon is running."
}

p3_tick_status() {
    echo
    if [[ -f "$P3_TICK_PID_FILE" ]] && kill -0 "$(cat "$P3_TICK_PID_FILE")" 2>/dev/null; then
        success "RUNNING — 1 game day every ${P3_TICK_INTERVAL}s  (PID $(cat "$P3_TICK_PID_FILE"))"
        if [[ -f "$P3_TICK_STATE_FILE" ]]; then
            info "   Last tick state : $(cat "$P3_TICK_STATE_FILE")"
        fi
    else
        rm -f "$P3_TICK_PID_FILE" "$P3_LISTEN_PID_FILE" 2>/dev/null || true
        warn "Stopped — use 'Start Auto-Tick' from the Simulation menu to begin."
    fi
}

p3_set_tick_interval() {
    local v
    v=$(gum input --placeholder "Seconds per game day (current: ${P3_TICK_INTERVAL})" \
                  --value "$P3_TICK_INTERVAL")
    [[ "$v" =~ ^[1-9][0-9]*$ ]] || { error "Enter a positive whole number."; return; }
    P3_TICK_INTERVAL="$v"
    success "Tick interval set to ${P3_TICK_INTERVAL}s/day."
    if [[ -f "$P3_TICK_PID_FILE" ]] && kill -0 "$(cat "$P3_TICK_PID_FILE")" 2>/dev/null; then
        if confirm "Restart daemon now to apply the new interval?"; then
            p3_stop_tick; p3_start_tick
        fi
    fi
}
