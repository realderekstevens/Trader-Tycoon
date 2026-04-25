#!/usr/bin/env bash
# =============================================================================
#  scripts/latlon_to_hex.sh  —  Hex coordinate tool for Patrician III / IV
#
#  The VERIFIED array holds every city's manually-placed hex coordinate from
#  seed.sql — those values are the ground truth and are output exactly as-is.
#
#  The NEW_CITIES array is where you add fresh cities.  Each entry is computed
#  from real-world lat/lon using the same pointy-top axial projection as the
#  rest of the grid (Lübeck anchor, 1 hex ≈ 50 nm).  After running --new,
#  eyeball the output against neighbouring known cities and tweak q by hand
#  if needed — the r (latitude) value will be accurate; q (longitude) may be
#  off by 1-3 hexes for Atlantic/Mediterranean cities due to the map's
#  intentional east-west stretching.
#
#  Usage
#  ──────
#    ./latlon_to_hex.sh                # SQL UPDATE for ALL verified cities
#    ./latlon_to_hex.sh --new          # SQL UPDATE for NEW_CITIES only (computed)
#    ./latlon_to_hex.sh --all          # SQL UPDATE for verified + new combined
#    ./latlon_to_hex.sh --csv          # CSV dump of all verified coordinates
#    ./latlon_to_hex.sh --check        # Print verified table (no DB needed)
# =============================================================================

# ── PROJECTION CONFIG ─────────────────────────────────────────────────────────
# These constants are reverse-engineered from the manually-placed seed values.
# Do not change them unless you're rebuilding the whole grid from scratch.
readonly ANCHOR_LAT=53.8655   # Lübeck — hex (0,0)
readonly ANCHOR_LON=10.6866
readonly HEX_SIZE=0.55        # degrees latitude per hex (≈ 50 nm)
readonly COS_LAT_DEG=53.0     # central latitude for E/W cosine correction

# ── VERIFIED COORDINATES  (exact values from seed.sql) ───────────────────────
# Format: "City Name|q|r"
# These are output verbatim — the formula is NOT applied to them.
VERIFIED=(
# Hanseatic — Baltic core
    "Lubeck|0|0"
    "Hamburg|-1|0"
    "Rostock|1|0"
    "Stettin|3|1"
    "Gdansk|6|-1"
    "Riga|9|-4"
    "Reval|10|-7"
    "Novgorod|15|-6"
    "Stockholm|5|-7"
    "Visby|5|-5"
    "Malmo|2|-2"
    "Torun|6|1"
# Hanseatic — North Sea / Scandinavia
    "Bergen|-4|-8"
    "Oslo|0|-7"
    "Aalborg|-1|-4"
    "Ribe|-1|-2"
# Hanseatic — British Isles
    "Scarborough|-8|0"
    "Edinburgh|-10|-3"
    "London|-8|3"
# Hanseatic — Rhine / Low Countries
    "Brugge|-5|3"
    "Groningen|-3|1"
    "Bremen|-1|1"
    "Cologne|-3|4"
# Hanseatic — East
    "Ladoga|15|-7"
# Mediterranean
    "Venice|1|10"
    "Genoa|-1|11"
    "Marseille|-4|13"
    "Barcelona|-6|15"
    "Lisbon|-14|18"
    "Constantinople|13|15"
    "Naples|3|16"
    "Palermo|2|19"
    "Tunis|0|20"
    "Alexandria|14|27"
)

# ── NEW CITIES  (add here — formula will compute q, r from lat/lon) ───────────
# Format: "City Name|lat|lon"
# After running --new, check output visually and hand-correct q if needed.
NEW_CITIES=(
# Example (uncomment to use):
# "Danzig|54.35|18.65"
# "Bruges|51.21|3.22"
)

# ── FORMULA ───────────────────────────────────────────────────────────────────

COS_LAT=$(awk -v d="$COS_LAT_DEG" \
    'BEGIN{printf "%.10f", cos(d*3.141592653589793/180)}')

_latlon_to_hex() {
    # args: name lat lon
    # prints: name|q|r
    awk -v name="$1" -v lat="$2" -v lon="$3" \
        -v alat="$ANCHOR_LAT" -v alon="$ANCHOR_LON" \
        -v coslat="$COS_LAT"  -v size="$HEX_SIZE" '
    BEGIN {
        y = alat - lat                    # positive = south
        x = (lon - alon) * coslat        # cosine-corrected E/W

        # flat x,y → fractional axial (pointy-top)
        fq = (sqrt(3)/3 * x - 1/3 * y) / size
        fr = (2/3 * y) / size

        # axial → cube
        cx = fq; cz = fr; cy = -cx - cz

        # cube rounding (Red Blob Games)
        rx = int(cx + (cx>=0 ? 0.5 : -0.5))
        ry = int(cy + (cy>=0 ? 0.5 : -0.5))
        rz = int(cz + (cz>=0 ? 0.5 : -0.5))
        dx = (rx-cx); if(dx<0) dx=-dx
        dy = (ry-cy); if(dy<0) dy=-dy
        dz = (rz-cz); if(dz<0) dz=-dz
        if      (dx>dy && dx>dz) rx = -ry-rz
        else if (dy>dz)          ry = -rx-rz
        else                     rz = -rx-ry

        printf "%s|%d|%d\n", name, rx, rz
    }'
}

_sql_block() {
    # args: array of "name|q|r" entries, optional comment header
    local -n _arr="$1"
    local header="${2:-}"
    [[ -n "$header" ]] && echo "-- $header"
    echo "WITH city_coords (city_name, q, r) AS (VALUES"
    local first=1
    for entry in "${_arr[@]}"; do
        IFS="|" read -r name q r <<< "$entry"
        if [[ $first -eq 1 ]]; then
            printf "    ('%s', %d, %d)\n" "$name" "$q" "$r"
            first=0
        else
            printf "   ,('%s', %d, %d)\n" "$name" "$q" "$r"
        fi
    done
    echo ")"
    echo "UPDATE p3_cities ci"
    echo "    SET hex_q = cc.q, hex_r = cc.r"
    echo "    FROM city_coords cc"
    echo "    WHERE ci.name = cc.city_name;"
}

# ── OUTPUT MODES ──────────────────────────────────────────────────────────────

MODE="${1:---sql}"

case "$MODE" in

    --csv)
        echo "name,q,r"
        for entry in "${VERIFIED[@]}"; do
            IFS="|" read -r name q r <<< "$entry"
            echo "$name,$q,$r"
        done
        ;;

    --check)
        printf "%-18s  %6s  %6s  %6s\n" "City" "q" "r" "s"
        printf "%-18s  %6s  %6s  %6s\n" "──────────────────" "──────" "──────" "──────"
        for entry in "${VERIFIED[@]}"; do
            IFS="|" read -r name q r <<< "$entry"
            s=$(( -q - r ))
            printf "%-18s  %6d  %6d  %6d\n" "$name" "$q" "$r" "$s"
        done
        echo ""
        echo "${#VERIFIED[@]} verified cities"
        ;;

    --new)
        if [[ ${#NEW_CITIES[@]} -eq 0 ]]; then
            echo "-- No entries in NEW_CITIES array."
            exit 0
        fi
        computed=()
        for entry in "${NEW_CITIES[@]}"; do
            IFS="|" read -r name lat lon <<< "$entry"
            computed+=("$(_latlon_to_hex "$name" "$lat" "$lon")")
        done
        echo "-- Computed from lat/lon — verify q visually before committing"
        _sql_block computed "New cities (formula-placed)"
        ;;

    --all)
        # Compute new cities
        computed=()
        for entry in "${NEW_CITIES[@]}"; do
            IFS="|" read -r name lat lon <<< "$entry"
            computed+=("$(_latlon_to_hex "$name" "$lat" "$lon")")
        done
        combined=("${VERIFIED[@]}" "${computed[@]}")
        echo "-- hex_coords: verified seed values + formula-placed new cities"
        _sql_block combined "All cities"
        ;;

    --sql | *)
        echo "-- hex_coords: verified seed values (manually placed)"
        _sql_block VERIFIED "Verified coordinates from seed.sql"
        ;;
esac
