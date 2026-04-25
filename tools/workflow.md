# First-time setup
psql -d traderdude -f sql/schema.sql
psql -d traderdude -f sql/seed.sql
bash scripts/latlon_to_hex.sh        # computes q,r from lat/lon → writes to DB

# Render the map
python3 tools/hex_map.py             # display on screen
python3 tools/hex_map.py --save map.png
