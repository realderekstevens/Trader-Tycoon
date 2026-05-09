#!/usr/bin/env bash
# =============================================================================
#  lib/db.sh  —  Database connection, pickers, and core game transactions
#
#  All functions that touch PostgreSQL live here. Screens call these helpers
#  rather than issuing psql commands directly, which keeps SQL changes
#  localised and makes unit-testing straightforward.
#
#  DEPENDENCIES: psql
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
#  CONNECTION
# ─────────────────────────────────────────────────────────────────────────────
P3_DB="${PSQL_DB:-traderdude}"
P3_USER="${PSQL_USER:-postgres}"

p3_psql() {
    psql -X --username="$P3_USER" --dbname="$P3_DB" --tuples-only "$@"
}

p3_gold() {
    p3_psql --tuples-only -c "SELECT gold FROM p3_player LIMIT 1;" | tr -d ' '
}

# ─────────────────────────────────────────────────────────────────────────────
#  INTERACTIVE PICKERS  (gum filter wrappers)
# ─────────────────────────────────────────────────────────────────────────────
p3_pick_city() {
    p3_psql --tuples-only -c "SELECT name FROM p3_cities ORDER BY name;" \
        | sed 's/^ *//' | grep -v '^$' \
        | gum filter --placeholder "Select city…"
}

p3_pick_ship() {
    local ships
    ships=$(p3_psql --tuples-only -c "
        SELECT ship_id || ' - ' || name || ' (' || ship_type || ')  '
               || current_city || '  ' || status
               || CASE WHEN status='sailing' THEN '  ETA '||eta_days||'d' ELSE '' END
        FROM p3_ships WHERE owner='player' ORDER BY name;" \
        2>/dev/null | sed 's/^ *//' | grep -v '^$') || true
    [[ -z "$ships" ]] && { warn "No ships found."; return 1; }
    local chosen
    chosen=$(echo "$ships" | gum filter --placeholder "Select ship…")
    [[ -z "$chosen" ]] && return 1
    echo "${chosen%% *}"
}

p3_pick_good() {
    p3_psql --tuples-only -c "SELECT name FROM p3_goods ORDER BY name;" \
        | sed 's/^ *//' | grep -v '^$' \
        | gum filter --placeholder "Select good…"
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14d  SAIL ORDER
# ─────────────────────────────────────────────────────────────────────────────
p3_sail_ship() {
    local sid="$1" dest="$2"
    local scity status spd

    scity=$(p3_psql --tuples-only -c "SELECT current_city FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
    status=$(p3_psql --tuples-only -c "SELECT status       FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')
    spd=$(p3_psql --tuples-only -c    "SELECT speed_knots  FROM p3_ships WHERE ship_id=$sid;" | tr -d ' ')

    [[ "$status" != "docked" ]] && { error "$scity ship is $status."; return 1; }

    local eta
    eta=$(p3_psql --tuples-only -c "
        SELECT GREATEST(1, ROUND(distance_nm::NUMERIC / ($spd * 24.0))::INTEGER)
        FROM p3_routes
        WHERE (city_a = '$scity' AND city_b = '$dest')
           OR (city_b = '$scity' AND city_a = '$dest')
        ORDER BY distance_nm LIMIT 1;" | tr -d ' ')

    if [[ -z "$eta" || "$eta" == "0" ]]; then
        eta=$(p3_psql --tuples-only -c "
            SELECT COALESCE(p3_travel_days(
                (SELECT city_id FROM p3_cities WHERE name = '$scity'),
                (SELECT city_id FROM p3_cities WHERE name = '$dest'),
                $spd
            ), 5);" | tr -d ' ')
    fi

    [[ -z "$eta" || "$eta" == "0" ]] && eta=5

    p3_psql -c "
        UPDATE p3_ships SET status='sailing', destination='$dest', eta_days=$eta
        WHERE ship_id=$sid;
        INSERT INTO p3_trade_log
            (game_year, game_day, ship_id, ship_name, city, action, logged_at)
        SELECT pl.game_year, pl.game_day, $sid,
               (SELECT name FROM p3_ships WHERE ship_id = $sid), '$scity', 'depart', NOW()
        FROM p3_player pl;" >/dev/null
    success "Sailing to $dest — ETA ${eta} day(s)  (${spd} kn)"
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14e  BUY  (marginal pricing, full trade log)
# ─────────────────────────────────────────────────────────────────────────────
p3_do_buy() {
    local sid="$1" good="$2" qty="$3" scity="$4"
    p3_psql -c "
    DO \$\$
    DECLARE
        v_mid NUMERIC; v_stock INTEGER; v_stock_ref INTEGER; v_elast NUMERIC;
        v_floor_pct NUMERIC; v_ceil_pct NUMERIC; v_total NUMERIC; v_avg NUMERIC;
        v_gold NUMERIC; v_gid INTEGER; v_cid INTEGER; v_free INTEGER;
        i INTEGER; unit_price NUMERIC; new_mid NUMERIC; ref_mid NUMERIC;
    BEGIN
        SELECT g.good_id, ci.city_id,
               (m.current_buy/1.08 + m.current_sell/0.92)/2.0,
               m.stock, (g.buy_price_min+g.sell_price_min)/2.0
        INTO   v_gid, v_cid, v_mid, v_stock, ref_mid
        FROM p3_market m
        JOIN p3_cities ci ON ci.city_id = m.city_id AND ci.name = '$scity'
        JOIN p3_goods  g  ON g.good_id  = m.good_id AND g.name  = '$good';

        SELECT COALESCE(e.elasticity_buy,0.40), COALESCE(e.stock_ref,100),
               COALESCE(e.price_floor_pct,0.30), COALESCE(e.price_ceil_pct,3.00)
        INTO   v_elast, v_stock_ref, v_floor_pct, v_ceil_pct
        FROM p3_goods g LEFT JOIN p3_good_elasticity e USING (good_id) WHERE g.good_id = v_gid;

        SELECT cargo_free INTO v_free FROM p3_fleet_view WHERE ship_id = $sid;
        SELECT gold INTO v_gold FROM p3_player;
        IF v_stock < $qty THEN RAISE EXCEPTION 'Not enough stock (have %, need %)', v_stock, $qty; END IF;
        IF v_free  < $qty THEN RAISE EXCEPTION 'Not enough cargo (free %, need %)', v_free,  $qty; END IF;

        v_total := 0;
        FOR i IN 0..($qty-1) LOOP
            unit_price := p3_marginal_price(v_cid, v_gid, 'buy', i,
                              (SELECT game_day FROM p3_player LIMIT 1));
            v_total := v_total + COALESCE(unit_price, 0);
        END LOOP;
        v_avg := ROUND(v_total/$qty, 2);

        IF v_gold < v_total THEN
            RAISE EXCEPTION 'Need %g total (avg %/unit), have %g', v_total, v_avg, v_gold;
        END IF;

        INSERT INTO p3_cargo (ship_id, good_id, quantity) VALUES ($sid, v_gid, $qty)
            ON CONFLICT (ship_id, good_id) DO UPDATE SET quantity = p3_cargo.quantity + EXCLUDED.quantity;

        new_mid := COALESCE(
            p3_marginal_price(v_cid, v_gid, 'buy', $qty,
                (SELECT game_day FROM p3_player LIMIT 1)) / 1.08,
            ROUND(v_mid * POWER(v_stock_ref::NUMERIC / GREATEST(v_stock - $qty, 1)::NUMERIC, v_elast), 2)
        );

        UPDATE p3_market SET stock = stock - $qty,
            current_buy  = GREATEST(1, ROUND(new_mid * 1.08, 2)),
            current_sell = GREATEST(1, ROUND(new_mid * 0.92, 2))
        WHERE city_id = v_cid AND good_id = v_gid;

        UPDATE p3_player SET gold = gold - v_total;

        INSERT INTO p3_trade_log
            (game_year, game_day, ship_id, ship_name, city, good_id, good_name,
             action, quantity, price, total_value, gold_after)
        SELECT pl.game_year, pl.game_day, $sid,
               (SELECT name FROM p3_ships WHERE ship_id = $sid),
               '$scity', v_gid, '$good', 'buy', $qty, v_avg, v_total, pl.gold - v_total
        FROM p3_player pl;

        RAISE NOTICE 'Bought % x %  avg %g  total %g  (stock % -> %)',
                     $qty, '$good', v_avg, v_total, v_stock, v_stock - $qty;
    END; \$\$;
    " 2>&1 | grep -E 'NOTICE|ERROR|error' || true
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14f  SELL  (marginal pricing, full trade log)
# ─────────────────────────────────────────────────────────────────────────────
p3_do_sell() {
    local sid="$1" good="$2" qty="$3" scity="$4"
    p3_psql -c "
    DO \$\$
    DECLARE
        v_mid NUMERIC; v_stock INTEGER; v_stock_ref INTEGER; v_elast NUMERIC;
        v_floor_pct NUMERIC; v_ceil_pct NUMERIC; v_total NUMERIC; v_avg NUMERIC;
        v_aboard INTEGER; v_gid INTEGER; v_cid INTEGER;
        i INTEGER; unit_price NUMERIC; new_mid NUMERIC; ref_mid NUMERIC;
    BEGIN
        SELECT g.good_id, ci.city_id,
               (m.current_buy/1.08 + m.current_sell/0.92)/2.0,
               m.stock, (g.buy_price_min+g.sell_price_min)/2.0
        INTO   v_gid, v_cid, v_mid, v_stock, ref_mid
        FROM p3_market m
        JOIN p3_cities ci ON ci.city_id = m.city_id AND ci.name = '$scity'
        JOIN p3_goods  g  ON g.good_id  = m.good_id AND g.name  = '$good';

        SELECT COALESCE(e.elasticity_sell,0.30), COALESCE(e.stock_ref,100),
               COALESCE(e.price_floor_pct,0.30), COALESCE(e.price_ceil_pct,3.00)
        INTO   v_elast, v_stock_ref, v_floor_pct, v_ceil_pct
        FROM p3_goods g LEFT JOIN p3_good_elasticity e USING (good_id) WHERE g.good_id = v_gid;

        SELECT quantity INTO v_aboard FROM p3_cargo WHERE ship_id = $sid AND good_id = v_gid;
        IF COALESCE(v_aboard, 0) < $qty THEN
            RAISE EXCEPTION 'Not enough cargo (have %, need %)', COALESCE(v_aboard, 0), $qty;
        END IF;

        v_total := 0;
        FOR i IN 0..($qty-1) LOOP
            unit_price := p3_marginal_price(v_cid, v_gid, 'sell', i,
                              (SELECT game_day FROM p3_player LIMIT 1));
            v_total := v_total + COALESCE(unit_price, 0);
        END LOOP;
        v_avg := ROUND(v_total/$qty, 2);

        UPDATE p3_cargo SET quantity = quantity - $qty WHERE ship_id = $sid AND good_id = v_gid;
        DELETE FROM p3_cargo WHERE ship_id = $sid AND good_id = v_gid AND quantity <= 0;

        new_mid := COALESCE(
            p3_marginal_price(v_cid, v_gid, 'sell', $qty,
                (SELECT game_day FROM p3_player LIMIT 1)) / 0.92,
            ROUND(v_mid * POWER(v_stock_ref::NUMERIC / GREATEST(v_stock + $qty, 1)::NUMERIC, v_elast), 2)
        );

        UPDATE p3_market SET stock = stock + $qty,
            current_buy  = GREATEST(1, ROUND(new_mid * 1.08, 2)),
            current_sell = GREATEST(1, ROUND(new_mid * 0.92, 2))
        WHERE city_id = v_cid AND good_id = v_gid;

        UPDATE p3_player SET gold = gold + v_total;

        INSERT INTO p3_trade_log
            (game_year, game_day, ship_id, ship_name, city, good_id, good_name,
             action, quantity, price, total_value, gold_after)
        SELECT pl.game_year, pl.game_day, $sid,
               (SELECT name FROM p3_ships WHERE ship_id = $sid),
               '$scity', v_gid, '$good', 'sell', $qty, v_avg, v_total, pl.gold + v_total
        FROM p3_player pl;

        RAISE NOTICE 'Sold % x %  avg %g  total %g  (stock % -> %)',
                     $qty, '$good', v_avg, v_total, v_stock, v_stock + $qty;
    END; \$\$;
    " 2>&1 | grep -E 'NOTICE|ERROR|error' || true
}

# ─────────────────────────────────────────────────────────────────────────────
#  §14g  NPC SHIP AI TICK
# ─────────────────────────────────────────────────────────────────────────────
p3_npc_tick() {
    p3_psql <<'NSQL' >/dev/null 2>&1
DO $$
DECLARE
    npc         RECORD;
    v_cargo     INTEGER;
    v_best_buy  TEXT;
    v_best_sell TEXT;
    v_stock     INTEGER;
    v_price_b   NUMERIC;
    v_price_s   NUMERIC;
    v_qty       INTEGER;
    v_profit    NUMERIC;
    v_eta       INTEGER;
    v_cid_src   INTEGER;
    v_cid_dst   INTEGER;
    v_gday      INTEGER;
    v_gyear     INTEGER;
BEGIN
    SELECT game_day, game_year INTO v_gday, v_gyear FROM p3_player LIMIT 1;

    FOR npc IN
        SELECT s.ship_id, s.name AS ship_name, s.current_city, s.status,
               s.eta_days, s.cargo_cap, s.speed_knots, s.destination,
               ns.good_id, ns.home_city, ns.ai_state,
               ns.target_buy_city, ns.target_sell_city,
               g.name AS good_name
        FROM   p3_npc_ships ns
        JOIN   p3_ships s ON s.ship_id = ns.npc_ship_id
        JOIN   p3_goods g ON g.good_id = ns.good_id
        WHERE  s.owner = 'npc'
    LOOP
        SELECT COALESCE(quantity, 0) INTO v_cargo
        FROM   p3_cargo
        WHERE  ship_id = npc.ship_id AND good_id = npc.good_id;
        v_cargo := COALESCE(v_cargo, 0);

        IF npc.status = 'docked' AND v_cargo = 0 THEN
            SELECT ci.city_id, ci.name, m.stock, m.current_buy
            INTO   v_cid_src, v_best_buy, v_stock, v_price_b
            FROM   p3_market m
            JOIN   p3_cities ci ON ci.city_id = m.city_id
            JOIN   p3_city_goods cg ON cg.city_id = m.city_id
                                    AND cg.good_id = npc.good_id
                                    AND cg.role = 'produces'
            WHERE  m.good_id = npc.good_id
              AND  m.stock   > 20
              AND  ci.name  <> npc.current_city
            ORDER  BY m.stock DESC, m.current_buy ASC
            LIMIT  1;

            IF v_best_buy IS NOT NULL THEN
                v_qty := LEAST(npc.cargo_cap, v_stock - 10);
                IF v_qty > 0 THEN
                    INSERT INTO p3_cargo (ship_id, good_id, quantity)
                    VALUES (npc.ship_id, npc.good_id, v_qty)
                    ON CONFLICT (ship_id, good_id)
                    DO UPDATE SET quantity = p3_cargo.quantity + EXCLUDED.quantity;

                    UPDATE p3_market
                    SET    stock        = GREATEST(0, stock - v_qty),
                           current_buy  = GREATEST(1, ROUND(current_buy  * (1.0 + (v_qty::NUMERIC / GREATEST(stock, 1)) * 0.05), 2)),
                           current_sell = GREATEST(1, ROUND(current_sell * (1.0 + (v_qty::NUMERIC / GREATEST(stock, 1)) * 0.05), 2))
                    WHERE  city_id = v_cid_src AND good_id = npc.good_id;

                    UPDATE p3_npc_ships
                    SET    ai_state = 'seeking', target_buy_city = v_best_buy
                    WHERE  npc_ship_id = npc.ship_id;

                    INSERT INTO p3_npc_trade_log
                        (game_year, game_day, ship_id, ship_name, good_id, good_name,
                         action, city, quantity, price)
                    VALUES (v_gyear, v_gday, npc.ship_id, npc.ship_name, npc.good_id,
                            npc.good_name, 'buy', npc.current_city, v_qty, v_price_b);
                END IF;
            END IF;

        ELSIF npc.status = 'docked' AND v_cargo > 0
              AND (npc.target_sell_city IS NULL OR npc.current_city <> npc.target_sell_city) THEN

            SELECT m.city_id, ci.name, m.current_sell
            INTO   v_cid_dst, v_best_sell, v_price_s
            FROM   p3_market m
            JOIN   p3_cities ci ON ci.city_id = m.city_id
            WHERE  m.good_id = npc.good_id
              AND  ci.name  <> npc.current_city
              AND  m.stock   < 150
            ORDER  BY m.current_sell DESC, m.stock ASC
            LIMIT  1;

            IF v_best_sell IS NOT NULL THEN
                v_eta := GREATEST(1, ROUND(
                    COALESCE(p3_travel_days(
                        (SELECT city_id FROM p3_cities WHERE name = npc.current_city LIMIT 1),
                        v_cid_dst,
                        npc.speed_knots
                    ), 5)
                )::INTEGER);

                UPDATE p3_ships
                SET    status      = 'sailing',
                       destination = v_best_sell,
                       eta_days    = v_eta
                WHERE  ship_id = npc.ship_id;

                UPDATE p3_npc_ships
                SET    ai_state = 'sailing', target_sell_city = v_best_sell
                WHERE  npc_ship_id = npc.ship_id;

                INSERT INTO p3_npc_trade_log
                    (game_year, game_day, ship_id, ship_name, good_id, good_name,
                     action, city, quantity)
                VALUES (v_gyear, v_gday, npc.ship_id, npc.ship_name, npc.good_id,
                        npc.good_name, 'depart', npc.current_city, v_cargo);
            END IF;

        ELSIF npc.status = 'docked' AND v_cargo > 0
              AND npc.target_sell_city IS NOT NULL
              AND npc.current_city = npc.target_sell_city THEN

            SELECT m.city_id, m.current_sell, m.stock
            INTO   v_cid_dst, v_price_s, v_stock
            FROM   p3_market m
            JOIN   p3_cities ci ON ci.city_id = m.city_id AND ci.name = npc.current_city
            WHERE  m.good_id = npc.good_id;

            IF v_cid_dst IS NOT NULL THEN
                UPDATE p3_market
                SET    stock        = LEAST(500, stock + v_cargo),
                       current_sell = GREATEST(1, ROUND(current_sell * (1.0 - (v_cargo::NUMERIC / GREATEST(stock + v_cargo, 1)) * 0.04), 2)),
                       current_buy  = GREATEST(1, ROUND(current_buy  * (1.0 - (v_cargo::NUMERIC / GREATEST(stock + v_cargo, 1)) * 0.04), 2))
                WHERE  city_id = v_cid_dst AND good_id = npc.good_id;

                v_profit := v_price_s * v_cargo;

                DELETE FROM p3_cargo
                WHERE  ship_id = npc.ship_id AND good_id = npc.good_id;

                UPDATE p3_npc_ships
                SET    ai_state         = 'seeking',
                       last_profit      = v_profit,
                       total_profit     = total_profit + v_profit,
                       trips_completed  = trips_completed + 1,
                       target_sell_city = NULL
                WHERE  npc_ship_id = npc.ship_id;

                INSERT INTO p3_npc_trade_log
                    (game_year, game_day, ship_id, ship_name, good_id, good_name,
                     action, city, quantity, price, profit)
                VALUES (v_gyear, v_gday, npc.ship_id, npc.ship_name, npc.good_id,
                        npc.good_name, 'sell', npc.current_city, v_cargo, v_price_s, v_profit);
            END IF;
        END IF;

    END LOOP;
END $$;
NSQL
}
