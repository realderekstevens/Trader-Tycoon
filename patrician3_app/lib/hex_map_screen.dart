// =============================================================================
//  hex_map_screen.dart  —  Patrician III Baltic Hex Map
//
//  Drop this file into lib/ alongside main.dart.
//  Add HexMapScreen() as a new tab in MainShell.
//
//  Features:
//    • Flat-top hex grid painted via CustomPainter
//    • All 24 Hanseatic cities from p3_cities (with real q,r coordinates)
//    • Dynamic data loaded from PostgREST p3_cities + p3_market_view
//    • Pinch-to-zoom + pan (InteractiveViewer)
//    • Tap a city → slide-up panel with live market prices
//    • Trade route lines between connected cities
//    • Terrain colour coding: sea / coast / land
//    • Hex distance & estimated travel time display
//    • "My ships" indicator badges on current city hexes
// =============================================================================

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

// Import your existing models / providers
// (GameState, ApiConfig, OTheme, MarketEntry, Ship, City are in main.dart)
// In a real project split these into separate files and import properly.
// Here we redeclare only what we need so the file is self-contained for review.

// ─────────────────────────────────────────────────────────────────────────────
//  HEX MATH  (flat-top, axial storage q,r  →  s = -q-r)
//  Reference: https://www.redblobgames.com/grids/hexagons/
// ─────────────────────────────────────────────────────────────────────────────
class HexCoord {
  final int q, r;
  const HexCoord(this.q, this.r);

  int get s => -q - r;

  int distanceTo(HexCoord other) => (
    (q - other.q).abs() +
    (r - other.r).abs() +
    (s - other.s).abs()
  ) ~/ 2;

  /// Axial → pixel centre for FLAT-TOP hexes.
  /// size = hex radius (centre to vertex).
  Offset toPixel(double size) => Offset(
    size * (3.0 / 2.0 * q),
    size * (sqrt(3) / 2.0 * q + sqrt(3) * r),
  );

  @override
  bool operator ==(Object other) =>
    other is HexCoord && other.q == q && other.r == r;

  @override
  int get hashCode => Object.hash(q, r);
}

/// Flat-top hex corners (0° = right, going clockwise).
List<Offset> hexCorners(Offset center, double size) {
  return List.generate(6, (i) {
    final angle = pi / 3 * i; // 0, 60, 120, 180, 240, 300
    return Offset(
      center.dx + size * cos(angle),
      center.dy + size * sin(angle),
    );
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  CITY DATA  (hardcoded from p3_seed_hex_cities — truth is in the DB,
//  but we embed it so the map renders even before the API responds)
// ─────────────────────────────────────────────────────────────────────────────
enum Terrain { sea, coast, land }

class HexCity {
  final String name;
  final int q, r;
  final Terrain terrain;
  final String region;

  const HexCity(this.name, this.q, this.r, this.terrain, this.region);

  HexCoord get coord => HexCoord(q, r);
}

const _fallbackCities = [
  HexCity('Lübeck',      14, 90, Terrain.coast, 'Baltic'),
  HexCity('Hamburg',     14, 89, Terrain.coast, 'West'),
  HexCity('Rostock',     16, 90, Terrain.coast, 'Baltic'),
  HexCity('Stettin',     21, 89, Terrain.coast, 'Baltic'),
  HexCity('Gdansk',      25, 91, Terrain.coast, 'Baltic'),
  HexCity('Riga',        31, 95, Terrain.coast, 'Baltic'),
  HexCity('Reval',       30, 99, Terrain.coast, 'Baltic'),
  HexCity('Novgorod',    40, 98, Terrain.land,  'East'),
  HexCity('Stockholm',   21, 99, Terrain.coast, 'Baltic'),
  HexCity('Visby',       22, 96, Terrain.coast, 'Baltic'),
  HexCity('Malmö',       16, 93, Terrain.coast, 'Baltic'),
  HexCity('Bergen',       1,101, Terrain.coast, 'North Sea'),
  HexCity('Oslo',         9,100, Terrain.coast, 'North Sea'),
  HexCity('Aalborg',     11, 95, Terrain.coast, 'North Sea'),
  HexCity('Scarborough',  0, 90, Terrain.coast, 'British'),
  HexCity('Edinburgh',    2, 93, Terrain.coast, 'British'),
  HexCity('London',       1, 86, Terrain.coast, 'British'),
  HexCity('Brugge',       6, 85, Terrain.coast, 'West'),
  HexCity('Groningen',    9, 89, Terrain.land,  'West'),
  HexCity('Bremen',      12, 89, Terrain.land,  'West'),
  HexCity('Cologne',     11, 85, Terrain.land,  'Rhine'),
  HexCity('Torun',        3, 88, Terrain.land,  'Baltic'),
  HexCity('Ripen',       11, 92, Terrain.coast, 'North Sea'),
  HexCity('Ladoga',      41,100, Terrain.land,  'East'),
];

/// Key trade routes (city name pairs) — drawn as lines on the map
const _tradeRoutes = [
  ('Lübeck',    'Hamburg'),
  ('Lübeck',    'Rostock'),
  ('Lübeck',    'Gdansk'),
  ('Lübeck',    'Malmö'),
  ('Hamburg',   'Bremen'),
  ('Hamburg',   'Groningen'),
  ('Brugge',    'London'),
  ('Brugge',    'Hamburg'),
  ('Gdansk',    'Riga'),
  ('Riga',      'Reval'),
  ('Reval',     'Novgorod'),
  ('Novgorod',  'Ladoga'),
  ('Stockholm', 'Visby'),
  ('Visby',     'Gdansk'),
  ('Visby',     'Lübeck'),
  ('Bergen',    'Oslo'),
  ('Bergen',    'Scarborough'),
  ('Oslo',      'Aalborg'),
  ('Aalborg',   'Hamburg'),
  ('Scarborough','London'),
  ('Edinburgh', 'Scarborough'),
  ('Edinburgh', 'London'),
  ('London',    'Brugge'),
  ('Cologne',   'Brugge'),
  ('Cologne',   'Bremen'),
];

// ─────────────────────────────────────────────────────────────────────────────
//  STATE
// ─────────────────────────────────────────────────────────────────────────────
class HexMapState extends ChangeNotifier {
  List<HexCity> cities = List.from(_fallbackCities);
  Map<String, List<_MarketRow>> marketByCity = {};
  bool loading = false;
  String? error;

  // DB-loaded city coordinates override fallbacks when available
  Future<void> loadFromApi(String baseUrl) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      // Load cities (with hex coords)
      final cRes = await http.get(Uri.parse('$baseUrl/p3_cities?select=name,region,hex_q,hex_r&order=name'));
      if (cRes.statusCode == 200) {
        final list = jsonDecode(cRes.body) as List;
        final mapped = <HexCity>[];
        for (final j in list) {
          final q = j['hex_q'] as int?;
          final r = j['hex_r'] as int?;
          if (q == null || r == null) continue;
          final name = j['name'] as String;
          // Keep terrain from fallback if known, else coast
          final fallback = _fallbackCities.where((c) => c.name == name).firstOrNull;
          mapped.add(HexCity(name, q, r,
            fallback?.terrain ?? Terrain.coast,
            j['region'] as String? ?? ''));
        }
        if (mapped.isNotEmpty) cities = mapped;
      }
      // Load market view
      final mRes = await http.get(Uri.parse(
        '$baseUrl/p3_market_view?order=city.asc,good.asc&limit=500'));
      if (mRes.statusCode == 200) {
        final list = jsonDecode(mRes.body) as List;
        final grouped = <String, List<_MarketRow>>{};
        for (final j in list) {
          final city = j['city'] as String;
          grouped.putIfAbsent(city, () => []).add(_MarketRow(
            good: j['good'] as String,
            buy: double.tryParse(j['current_buy'].toString()) ?? 0,
            sell: double.tryParse(j['current_sell'].toString()) ?? 0,
            stock: j['stock'] as int? ?? 0,
            signal: j['signal'] as String? ?? '—',
          ));
        }
        marketByCity = grouped;
      }
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
  }
}

class _MarketRow {
  final String good;
  final double buy, sell;
  final int stock;
  final String signal;
  const _MarketRow({required this.good, required this.buy,
    required this.sell, required this.stock, required this.signal});
}

// ─────────────────────────────────────────────────────────────────────────────
//  HEX MAP SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class HexMapScreen extends StatefulWidget {
  const HexMapScreen({super.key});
  @override State<HexMapScreen> createState() => _HexMapScreenState();
}

class _HexMapScreenState extends State<HexMapScreen>
    with SingleTickerProviderStateMixin {
  final _mapState = HexMapState();
  HexCity? _selected;
  late AnimationController _panelCtrl;
  late Animation<Offset> _panelSlide;

  // hexSize controls zoom level — user can change with +/- buttons
  double _hexSize = 28.0;
  static const double _minHex = 14.0;
  static const double _maxHex = 60.0;

  @override
  void initState() {
    super.initState();
    _panelCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 260));
    _panelSlide = Tween<Offset>(
      begin: const Offset(0, 1), end: Offset.zero,
    ).animate(CurvedAnimation(parent: _panelCtrl, curve: Curves.easeOut));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Try to load from API — gracefully degrades to embedded fallback
      try {
        final api = context.read<_ApiConfigShim>();
        _mapState.loadFromApi(api.baseUrl);
      } catch (_) {
        // provider not available in standalone mode — use fallback data
      }
    });

    _mapState.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _panelCtrl.dispose();
    _mapState.dispose();
    super.dispose();
  }

  void _selectCity(HexCity city) {
    setState(() => _selected = city);
    _panelCtrl.forward(from: 0);
  }

  void _deselect() {
    _panelCtrl.reverse().then((_) {
      if (mounted) setState(() => _selected = null);
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Try to get ships from parent GameState for port indicators
    List<_ShipShim> ships = [];
    try {
      ships = context.read<_GameStateShim>().ships;
    } catch (_) {}

    return Scaffold(
      backgroundColor: _seaColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0C0A),
        title: Text('HEX MAP', style: GoogleFonts.cinzel(
          color: const Color(0xFFD4A830), fontSize: 15, letterSpacing: 2)),
        actions: [
          // Zoom controls
          IconButton(
            icon: const Icon(Icons.remove, color: Color(0xFFB8912A)),
            onPressed: () => setState(() => _hexSize = max(_minHex, _hexSize - 4)),
          ),
          Text('${_hexSize.round()}', style: GoogleFonts.sourceCodePro(
            color: const Color(0xFF8A7E68), fontSize: 11)),
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFFB8912A)),
            onPressed: () => setState(() => _hexSize = min(_maxHex, _hexSize + 4)),
          ),
          if (_mapState.loading)
            const Padding(
              padding: EdgeInsets.only(right: 14),
              child: SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: Color(0xFFB8912A))),
            ),
        ],
      ),
      body: GestureDetector(
        onTap: _selected != null ? _deselect : null,
        child: Stack(children: [
          // ── INTERACTIVE MAP ──────────────────────────────────────────────
          InteractiveViewer(
            constrained: false,
            minScale: 0.3,
            maxScale: 4.0,
            boundaryMargin: const EdgeInsets.all(200),
            child: _HexMapCanvas(
              cities: _mapState.cities,
              ships: ships,
              hexSize: _hexSize,
              selected: _selected,
              onCityTap: _selectCity,
              marketByCity: _mapState.marketByCity,
            ),
          ),

          // ── LEGEND ──────────────────────────────────────────────────────
          Positioned(
            left: 12, bottom: _selected != null ? 260 : 12,
            child: _Legend(),
          ),

          // ── CITY DETAIL PANEL ─────────────────────────────────────────────
          if (_selected != null)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: SlideTransition(
                position: _panelSlide,
                child: _CityPanel(
                  city: _selected!,
                  ships: ships,
                  market: _mapState.marketByCity[_selected!.name] ?? [],
                  allCities: _mapState.cities,
                  onClose: _deselect,
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  HEX CANVAS  (the CustomPainter widget)
// ─────────────────────────────────────────────────────────────────────────────

// Terrain palette — Obenseur dark
const _seaColor   = Color(0xFF0A1018);   // deep Baltic midnight
const _coastColor = Color(0xFF101820);   // shallows tint
const _landColor  = Color(0xFF1A1810);   // dark earth
const _goldColor  = Color(0xFFB8912A);
const _goldHiColor= Color(0xFFD4A830);
const _txtColor   = Color(0xFFD8CEB8);
const _txt2Color  = Color(0xFF8A7E68);
const _txt3Color  = Color(0xFF4A4438);
const _borderColor= Color(0xFF2A2520);
const _profitColor= Color(0xFF4A7C59);

class _HexMapCanvas extends StatelessWidget {
  final List<HexCity> cities;
  final List<_ShipShim> ships;
  final double hexSize;
  final HexCity? selected;
  final void Function(HexCity) onCityTap;
  final Map<String, List<_MarketRow>> marketByCity;

  const _HexMapCanvas({
    required this.cities, required this.ships, required this.hexSize,
    required this.selected, required this.onCityTap,
    required this.marketByCity,
  });

  @override
  Widget build(BuildContext context) {
    // Compute canvas bounds from all city positions
    final pixels = cities.map((c) => c.coord.toPixel(hexSize)).toList();
    final minX = pixels.fold(double.infinity,  (a, p) => min(a, p.dx)) - hexSize * 4;
    final minY = pixels.fold(double.infinity,  (a, p) => min(a, p.dy)) - hexSize * 4;
    final maxX = pixels.fold(-double.infinity, (a, p) => max(a, p.dx)) + hexSize * 4;
    final maxY = pixels.fold(-double.infinity, (a, p) => max(a, p.dy)) + hexSize * 4;
    final origin = Offset(-minX, -minY);
    final size = Size(maxX - minX, maxY - minY);

    return GestureDetector(
      onTapUp: (details) => _handleTap(details.localPosition, origin),
      child: CustomPaint(
        size: size,
        painter: _HexPainter(
          cities: cities,
          ships: ships,
          hexSize: hexSize,
          origin: origin,
          selected: selected,
          marketByCity: marketByCity,
        ),
      ),
    );
  }

  void _handleTap(Offset localPos, Offset origin) {
    // Find closest city to tap
    HexCity? closest;
    double bestDist = hexSize * 1.2; // tap radius
    for (final city in cities) {
      final cPx = city.coord.toPixel(hexSize).translate(origin.dx, origin.dy);
      final d = (localPos - cPx).distance;
      if (d < bestDist) { bestDist = d; closest = city; }
    }
    if (closest != null) onCityTap(closest);
  }
}

class _HexPainter extends CustomPainter {
  final List<HexCity> cities;
  final List<_ShipShim> ships;
  final double hexSize;
  final Offset origin;
  final HexCity? selected;
  final Map<String, List<_MarketRow>> marketByCity;

  _HexPainter({
    required this.cities, required this.ships, required this.hexSize,
    required this.origin, required this.selected, required this.marketByCity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawRoutes(canvas);
    _drawCities(canvas);
    _drawShipIndicators(canvas);
  }

  void _drawBackground(Canvas canvas, Size size) {
    // Sea fill
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = _seaColor,
    );
    // Subtle hex grid lines across the whole visible area (very faint)
    _drawGridLines(canvas, size);
  }

  void _drawGridLines(Canvas canvas, Size size) {
    // Draw a sparse background hex grid for navigational feel
    final gridPaint = Paint()
      ..color = const Color(0xFF141210)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.4;

    // Determine q,r range from cities
    if (cities.isEmpty) return;
    final minQ = cities.map((c) => c.q).reduce(min) - 4;
    final maxQ = cities.map((c) => c.q).reduce(max) + 4;
    final minR = cities.map((c) => c.r).reduce(min) - 4;
    final maxR = cities.map((c) => c.r).reduce(max) + 4;

    for (int q = minQ; q <= maxQ; q++) {
      for (int r = minR; r <= maxR; r++) {
        final center = HexCoord(q, r).toPixel(hexSize).translate(origin.dx, origin.dy);
        _drawHexOutline(canvas, center, hexSize, gridPaint);
      }
    }
  }

  void _drawHexOutline(Canvas canvas, Offset center, double size, Paint paint) {
    final corners = hexCorners(center, size);
    final path = Path()..moveTo(corners[0].dx, corners[0].dy);
    for (int i = 1; i < 6; i++) path.lineTo(corners[i].dx, corners[i].dy);
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawHexFilled(Canvas canvas, Offset center, double size, Color fillColor, Color strokeColor) {
    final corners = hexCorners(center, size);
    final path = Path()..moveTo(corners[0].dx, corners[0].dy);
    for (int i = 1; i < 6; i++) path.lineTo(corners[i].dx, corners[i].dy);
    path.close();
    canvas.drawPath(path, Paint()..color = fillColor..style = PaintingStyle.fill);
    canvas.drawPath(path, Paint()..color = strokeColor..style = PaintingStyle.stroke..strokeWidth = 0.8);
  }

  void _drawRoutes(Canvas canvas) {
    final routePaint = Paint()
      ..color = const Color(0xFF2A2820)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final cityMap = {for (final c in cities) c.name: c};

    for (final route in _tradeRoutes) {
      final a = cityMap[route.$1];
      final b = cityMap[route.$2];
      if (a == null || b == null) continue;
      final pa = a.coord.toPixel(hexSize).translate(origin.dx, origin.dy);
      final pb = b.coord.toPixel(hexSize).translate(origin.dx, origin.dy);
      canvas.drawLine(pa, pb, routePaint);
    }
  }

  void _drawCities(Canvas canvas) {
    for (final city in cities) {
      final center = city.coord.toPixel(hexSize).translate(origin.dx, origin.dy);
      final isSel = selected?.name == city.name;

      // Terrain fill
      final fillColor = switch (city.terrain) {
        Terrain.coast => const Color(0xFF101C28),
        Terrain.land  => const Color(0xFF1E1A0E),
        Terrain.sea   => _seaColor,
      };
      final borderColor = isSel
          ? _goldHiColor
          : switch (city.terrain) {
              Terrain.coast => const Color(0xFF203040),
              Terrain.land  => const Color(0xFF302A14),
              Terrain.sea   => _borderColor,
            };

      _drawHexFilled(canvas, center, hexSize - 1,
        isSel ? const Color(0xFF1A1810) : fillColor,
        isSel ? _goldColor : borderColor,
      );

      // Selection glow ring
      if (isSel) {
        _drawHexOutline(canvas, center, hexSize + 2,
          Paint()..color = _goldColor.withOpacity(0.25)
                 ..style = PaintingStyle.stroke..strokeWidth = 2.5);
      }

      // City dot
      final hasMarket = marketByCity.containsKey(city.name);
      final dotColor = isSel ? _goldHiColor :
        (hasMarket ? _goldColor : _txt3Color);
      canvas.drawCircle(center, isSel ? 4.5 : 3.0, Paint()..color = dotColor);

      // City label
      if (hexSize >= 20) {
        _drawLabel(canvas, center, city.name, hexSize);
      }
    }
  }

  void _drawLabel(Canvas canvas, Offset center, String name, double hexSize) {
    final fontSize = hexSize < 30 ? 7.5 : (hexSize < 45 ? 9.0 : 11.0);
    final tp = TextPainter(
      text: TextSpan(
        text: name,
        style: TextStyle(
          color: _txtColor.withOpacity(0.85),
          fontSize: fontSize,
          fontFamily: 'serif',
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Draw below the hex centre
    tp.paint(canvas, Offset(
      center.dx - tp.width / 2,
      center.dy + hexSize * 0.62,
    ));
  }

  void _drawShipIndicators(Canvas canvas) {
    final dockedPorts = <String>{};
    for (final s in ships) {
      if (s.status == 'docked') dockedPorts.add(s.currentCity);
    }

    for (final city in cities) {
      if (!dockedPorts.contains(city.name)) continue;
      final center = city.coord.toPixel(hexSize).translate(origin.dx, origin.dy);
      // Anchor badge — top-right of hex
      final badgeOffset = Offset(center.dx + hexSize * 0.55, center.dy - hexSize * 0.7);
      canvas.drawCircle(badgeOffset, 5, Paint()..color = _profitColor);
      // ⚓ mini text
      final tp = TextPainter(
        text: const TextSpan(text: '⚓', style: TextStyle(fontSize: 7)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, badgeOffset.translate(-tp.width / 2, -tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_HexPainter old) =>
    old.selected != selected ||
    old.hexSize != hexSize ||
    old.cities != cities;
}

// ─────────────────────────────────────────────────────────────────────────────
//  CITY DETAIL PANEL
// ─────────────────────────────────────────────────────────────────────────────
class _CityPanel extends StatelessWidget {
  final HexCity city;
  final List<_ShipShim> ships;
  final List<_MarketRow> market;
  final List<HexCity> allCities;
  final VoidCallback onClose;

  const _CityPanel({
    required this.city, required this.ships, required this.market,
    required this.allCities, required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final dockedHere = ships.where((s) =>
      s.currentCity == city.name && s.status == 'docked').toList();
    final sailingHere = ships.where((s) => s.destination == city.name).toList();

    // Nearby cities within 6 hexes
    final nearby = allCities
      .where((c) => c.name != city.name)
      .map((c) => (c, city.coord.distanceTo(c.coord)))
      .where((t) => t.$2 <= 8)
      .toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141310),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        border: Border(top: BorderSide(color: Color(0xFF2A2520))),
      ),
      constraints: const BoxConstraints(maxHeight: 320),
      child: Column(children: [
        // Handle + header
        const SizedBox(height: 8),
        Center(child: Container(
          width: 36, height: 3,
          decoration: BoxDecoration(
            color: const Color(0xFF2A2520),
            borderRadius: BorderRadius.circular(2)),
        )),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(city.name, style: GoogleFonts.cinzel(
                color: const Color(0xFFD4A830), fontSize: 18, letterSpacing: 1.5)),
              Text('${city.region}  ·  ${city.terrain.name}  ·  (${city.q}, ${city.r})',
                style: GoogleFonts.sourceCodePro(
                  color: const Color(0xFF4A4438), fontSize: 9, letterSpacing: 1)),
            ])),
            // Ship badges
            if (dockedHere.isNotEmpty)
              _badge('⚓ ${dockedHere.length}', _profitColor),
            if (sailingHere.isNotEmpty) ...[
              const SizedBox(width: 6),
              _badge('⛵ inbound', const Color(0xFFB8912A)),
            ],
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onClose,
              child: const Icon(Icons.close, color: Color(0xFF4A4438), size: 18)),
          ]),
        ),
        const Divider(color: Color(0xFF2A2520), height: 16),

        Expanded(child: DefaultTabController(
          length: 2,
          child: Column(children: [
            TabBar(
              isScrollable: false,
              indicatorColor: const Color(0xFFB8912A),
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: GoogleFonts.sourceCodePro(fontSize: 10, letterSpacing: 1.5),
              labelColor: const Color(0xFFD4A830),
              unselectedLabelColor: const Color(0xFF4A4438),
              tabs: const [Tab(text: 'MARKET'), Tab(text: 'DISTANCES')],
            ),
            Expanded(child: TabBarView(children: [
              _MarketPanel(market: market, cityName: city.name),
              _DistancePanel(city: city, nearby: nearby),
            ])),
          ]),
        )),
      ]),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(.15),
      border: Border.all(color: color.withOpacity(.5)),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(text, style: GoogleFonts.sourceCodePro(
      color: color, fontSize: 9, letterSpacing: .5)),
  );
}

class _MarketPanel extends StatelessWidget {
  final List<_MarketRow> market;
  final String cityName;
  const _MarketPanel({required this.market, required this.cityName});

  @override
  Widget build(BuildContext context) {
    if (market.isEmpty) return Center(
      child: Text('No market data for $cityName',
        style: GoogleFonts.crimsonText(color: const Color(0xFF4A4438), fontSize: 13)));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: market.length,
      itemBuilder: (_, i) {
        final m = market[i];
        final hasSig = m.signal != '—';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            if (hasSig)
              Container(width: 3, height: 20, color: _profitColor,
                margin: const EdgeInsets.only(right: 8))
            else
              const SizedBox(width: 11),
            Expanded(child: Text(m.good, style: GoogleFonts.crimsonText(
              color: const Color(0xFFD8CEB8), fontSize: 14))),
            Text('${m.buy.toStringAsFixed(0)}',
              style: GoogleFonts.sourceCodePro(
                color: const Color(0xFF8B3030), fontSize: 11)),
            Text('  /  ', style: GoogleFonts.sourceCodePro(
              color: const Color(0xFF4A4438), fontSize: 11)),
            Text('${m.sell.toStringAsFixed(0)}',
              style: GoogleFonts.sourceCodePro(
                color: _profitColor, fontSize: 11)),
            const SizedBox(width: 12),
            Text('${m.stock}u', style: GoogleFonts.sourceCodePro(
              color: const Color(0xFF4A4438), fontSize: 9)),
          ]),
        );
      },
    );
  }
}

class _DistancePanel extends StatelessWidget {
  final HexCity city;
  final List<(HexCity, int)> nearby;
  const _DistancePanel({required this.city, required this.nearby});

  String _eta(int hexes) {
    // Snaikka: ~6 hex/month  ·  Crayer: ~8  ·  Hulk: ~9
    final snaikka = max(1, (hexes / 6.0).ceil());
    final crayer  = max(1, (hexes / 8.0).ceil());
    return '$snaikka mo (Snaikka)  ·  $crayer mo (Crayer)';
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
    itemCount: nearby.length,
    itemBuilder: (_, i) {
      final (dest, dist) = nearby[i];
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 28, child: Text('$dist', style: GoogleFonts.sourceCodePro(
            color: const Color(0xFFB8912A), fontSize: 11,
            fontWeight: FontWeight.bold))),
          const SizedBox(width: 4),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(dest.name, style: GoogleFonts.crimsonText(
              color: const Color(0xFFD8CEB8), fontSize: 14)),
            Text(_eta(dist), style: GoogleFonts.sourceCodePro(
              color: const Color(0xFF4A4438), fontSize: 9, letterSpacing: .5)),
          ])),
          Text(dest.region, style: GoogleFonts.sourceCodePro(
            color: const Color(0xFF4A4438), fontSize: 9)),
        ]),
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  LEGEND
// ─────────────────────────────────────────────────────────────────────────────
class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFF141310).withOpacity(.92),
      border: Border.all(color: const Color(0xFF2A2520)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _legendRow(const Color(0xFF101C28), 'Coast city'),
      const SizedBox(height: 5),
      _legendRow(const Color(0xFF1E1A0E), 'Inland city'),
      const SizedBox(height: 5),
      _legendRow(_profitColor, '⚓ Ship docked'),
      const SizedBox(height: 5),
      _legendRow(const Color(0xFF2A2820), '── Trade route'),
    ]),
  );

  Widget _legendRow(Color color, String label) => Row(children: [
    Container(width: 12, height: 12, decoration: BoxDecoration(
      color: color, borderRadius: BorderRadius.circular(2),
      border: Border.all(color: const Color(0xFF3A3830), width: .5))),
    const SizedBox(width: 8),
    Text(label, style: GoogleFonts.sourceCodePro(
      color: const Color(0xFF8A7E68), fontSize: 9, letterSpacing: .5)),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
//  SHIM TYPES  (replace with real imports from main.dart in your project)
//  These allow the file to compile standalone for review.
// ─────────────────────────────────────────────────────────────────────────────

/// Shim — replace with: import from main.dart's ApiConfig
class _ApiConfigShim {
  String get baseUrl => 'http://localhost:3000';
}

/// Shim — replace with Ship from main.dart
class _ShipShim {
  final String name, shipType, currentCity, status;
  final String? destination;
  const _ShipShim({
    required this.name, required this.shipType, required this.currentCity,
    required this.status, this.destination,
  });
}

/// Shim — replace with GameState from main.dart
class _GameStateShim {
  List<_ShipShim> get ships => [];
}

// ─────────────────────────────────────────────────────────────────────────────
//  HOW TO WIRE INTO MainShell (main.dart changes)
// ─────────────────────────────────────────────────────────────────────────────
//
//  1. Remove the shim classes above and import your real types instead.
//
//  2. In _MainShellState._tabs, add HexMapScreen():
//       final _tabs = const [
//         _DashboardTab(),
//         _MarketTab(),
//         _FleetTab(),
//         HexMapScreen(),      // ← add here
//         _TradelogTab(),
//         _SettingsTab(),
//       ];
//
//  3. In _MainShellState._labels and _icons, add the new entry:
//       final _labels = const ['LEDGER', 'MARKET', 'FLEET', 'MAP', 'LOG', 'CONFIG'];
//       final _icons  = const [
//         Icons.account_balance_outlined,
//         Icons.store_outlined,
//         Icons.sailing_outlined,
//         Icons.map_outlined,          // ← add here
//         Icons.history_outlined,
//         Icons.settings_outlined,
//       ];
//
//  4. In HexMapScreen.initState, replace _ApiConfigShim / _GameStateShim with:
//       final api = context.read<ApiConfig>();
//       _mapState.loadFromApi(api.baseUrl);
//     and cast ships as List<Ship>.
//
//  5. In _HexMapCanvas / _CityPanel, replace _ShipShim with Ship
//     and access ship.currentCity / ship.status / ship.destination directly.
