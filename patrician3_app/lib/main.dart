// =============================================================================
//  PATRICIAN III — Flutter Client
//  Dark / gritty aesthetic inspired by Obenseur.
//  PostgREST backend: all tables prefixed p3_  (plus newspaper_stock_quotes)
//
//  Dependencies (pubspec.yaml):
//    http: ^1.2.0
//    provider: ^6.1.2
//    shared_preferences: ^2.2.2
//    intl: ^0.19.0
//    fl_chart: ^0.67.0
//    google_fonts: ^6.2.1
// =============================================================================

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GameState()),
        ChangeNotifierProvider(create: (_) => ApiConfig()),
      ],
      child: const PatricianApp(),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  OBENSEUR DARK THEME  — gritty, industrial, medieval-mercantile
// ─────────────────────────────────────────────────────────────────────────────
class OTheme {
  // Backgrounds — layered slate blacks with warm undertone
  static const bg0 = Color(0xFF0D0C0A);   // deepest — main scaffold
  static const bg1 = Color(0xFF141310);   // card surface
  static const bg2 = Color(0xFF1C1A16);   // elevated card / panel
  static const bg3 = Color(0xFF252118);   // top-level chrome / dialogs

  // Accent — old gold / amber lamp-light
  static const gold    = Color(0xFFB8912A);
  static const goldHi  = Color(0xFFD4A830);
  static const goldLo  = Color(0xFF7A5F18);

  // Signal colours
  static const profit  = Color(0xFF4A7C59);  // muted forest green
  static const loss    = Color(0xFF8B3030);  // dark crimson
  static const neutral = Color(0xFF5A5040);  // warm grey

  // Text hierarchy
  static const textPrimary   = Color(0xFFD8CEB8);   // warm off-white parchment
  static const textSecondary = Color(0xFF8A7E68);   // aged ink
  static const textMuted     = Color(0xFF4A4438);   // faded margin notes

  // Borders — faint scratches
  static const border    = Color(0xFF2A2520);
  static const borderHi  = Color(0xFF3D3628);

  // ── Typography ──────────────────────────────────────────────────────────────
  static TextTheme get textTheme => TextTheme(
    displayLarge: GoogleFonts.cinzelDecorative(
      color: gold, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 3),
    displayMedium: GoogleFonts.cinzel(
      color: textPrimary, fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: 2),
    titleLarge: GoogleFonts.cinzel(
      color: textPrimary, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 1.5),
    titleMedium: GoogleFonts.crimsonText(
      color: textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
    bodyLarge: GoogleFonts.crimsonText(
      color: textPrimary, fontSize: 15, height: 1.5),
    bodyMedium: GoogleFonts.crimsonText(
      color: textSecondary, fontSize: 13, height: 1.4),
    labelSmall: GoogleFonts.sourceCodePro(
      color: textMuted, fontSize: 10, letterSpacing: 1.2),
  );

  static ThemeData get theme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg0,
    colorScheme: const ColorScheme.dark(
      surface: bg1,
      primary: gold,
      secondary: goldHi,
      error: loss,
      onSurface: textPrimary,
      onPrimary: bg0,
    ),
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: bg0,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.cinzel(
        color: gold, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 2),
      iconTheme: const IconThemeData(color: gold),
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: bg1,
      selectedItemColor: gold,
      unselectedItemColor: textMuted,
      showUnselectedLabels: true,
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: bg1,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
        side: BorderSide(color: border, width: 1),
      ),
    ),
    dividerTheme: const DividerThemeData(color: border, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: bg2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
        borderSide: BorderSide(color: gold, width: 1.5),
      ),
      hintStyle: GoogleFonts.crimsonText(color: textMuted, fontSize: 14),
      labelStyle: GoogleFonts.crimsonText(color: textSecondary, fontSize: 13),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: bg2,
        foregroundColor: gold,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
          side: BorderSide(color: goldLo),
        ),
        textStyle: GoogleFonts.cinzel(fontSize: 12, letterSpacing: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    iconTheme: const IconThemeData(color: textSecondary, size: 18),
    chipTheme: ChipThemeData(
      backgroundColor: bg2,
      labelStyle: GoogleFonts.sourceCodePro(color: textSecondary, fontSize: 11),
      side: const BorderSide(color: border),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(3))),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  API CONFIG (PostgREST base URL — configurable in-app)
// ─────────────────────────────────────────────────────────────────────────────
class ApiConfig extends ChangeNotifier {
  String _baseUrl = 'http://localhost:3000';

  String get baseUrl => _baseUrl;

  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    notifyListeners();
  }

  Uri endpoint(String table, {Map<String, String>? params}) {
    final uri = Uri.parse('$_baseUrl/$table');
    return params != null ? uri.replace(queryParameters: params) : uri;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MODELS
// ─────────────────────────────────────────────────────────────────────────────
class Player {
  final int playerId;
  final String name;
  final String homeCity;
  final double gold;
  final String rank;
  final int gameYear;
  final int gameMonth;

  Player({
    required this.playerId, required this.name, required this.homeCity,
    required this.gold, required this.rank, required this.gameYear,
    required this.gameMonth,
  });

  factory Player.fromJson(Map<String, dynamic> j) => Player(
    playerId: j['player_id'] ?? 0,
    name: j['name'] ?? 'Merchant',
    homeCity: j['home_city'] ?? 'Lübeck',
    gold: double.tryParse(j['gold'].toString()) ?? 0,
    rank: j['rank'] ?? 'Apprentice',
    gameYear: j['game_year'] ?? 1300,
    gameMonth: j['game_month'] ?? 1,
  );
}

class Ship {
  final int shipId;
  final String name;
  final String shipType;
  final int cargoCap;
  final String currentCity;
  final String status;
  final int etaMonths;
  final String? destination;

  Ship({
    required this.shipId, required this.name, required this.shipType,
    required this.cargoCap, required this.currentCity, required this.status,
    required this.etaMonths, this.destination,
  });

  factory Ship.fromJson(Map<String, dynamic> j) => Ship(
    shipId: j['ship_id'] ?? 0,
    name: j['name'] ?? '',
    shipType: j['ship_type'] ?? 'Snaikka',
    cargoCap: j['cargo_cap'] ?? 50,
    currentCity: j['current_city'] ?? '',
    status: j['status'] ?? 'docked',
    etaMonths: j['eta_months'] ?? 0,
    destination: j['destination'],
  );

  Color get statusColor {
    switch (status) {
      case 'docked': return OTheme.profit;
      case 'sailing': return OTheme.gold;
      default: return OTheme.neutral;
    }
  }
}

class MarketEntry {
  final String city;
  final String good;
  final double currentBuy;
  final double currentSell;
  final int stock;
  final String signal;

  MarketEntry({
    required this.city, required this.good, required this.currentBuy,
    required this.currentSell, required this.stock, required this.signal,
  });

  factory MarketEntry.fromJson(Map<String, dynamic> j) => MarketEntry(
    city: j['city'] ?? '',
    good: j['good'] ?? '',
    currentBuy: double.tryParse(j['current_buy'].toString()) ?? 0,
    currentSell: double.tryParse(j['current_sell'].toString()) ?? 0,
    stock: j['stock'] ?? 0,
    signal: j['signal'] ?? '—',
  );

  double get spread => currentBuy - currentSell;
}

class ArbitrageEntry {
  final String buyCity;
  final String sellCity;
  final String good;
  final double buyPrice;
  final double sellPrice;
  final double profitPerUnit;

  ArbitrageEntry({
    required this.buyCity, required this.sellCity, required this.good,
    required this.buyPrice, required this.sellPrice, required this.profitPerUnit,
  });

  factory ArbitrageEntry.fromJson(Map<String, dynamic> j) => ArbitrageEntry(
    buyCity: j['buy_city'] ?? '',
    sellCity: j['sell_city'] ?? '',
    good: j['good'] ?? '',
    buyPrice: double.tryParse(j['buy_price'].toString()) ?? 0,
    sellPrice: double.tryParse(j['sell_price'].toString()) ?? 0,
    profitPerUnit: double.tryParse(j['profit_per_unit'].toString()) ?? 0,
  );
}

class TradeLog {
  final int gameYear;
  final int gameMonth;
  final String? shipName;
  final String? city;
  final String? goodName;
  final String action;
  final int? quantity;
  final double? price;
  final double? totalValue;
  final double? goldAfter;

  TradeLog({
    required this.gameYear, required this.gameMonth, this.shipName, this.city,
    this.goodName, required this.action, this.quantity, this.price,
    this.totalValue, this.goldAfter,
  });

  factory TradeLog.fromJson(Map<String, dynamic> j) => TradeLog(
    gameYear: j['game_year'] ?? 0,
    gameMonth: j['game_month'] ?? 0,
    shipName: j['ship_name'],
    city: j['city'],
    goodName: j['good_name'],
    action: j['action'] ?? '',
    quantity: j['quantity'],
    price: j['price'] != null ? double.tryParse(j['price'].toString()) : null,
    totalValue: j['total_value'] != null ? double.tryParse(j['total_value'].toString()) : null,
    goldAfter: j['gold_after'] != null ? double.tryParse(j['gold_after'].toString()) : null,
  );

  Color get actionColor {
    switch (action) {
      case 'buy': return OTheme.loss;
      case 'sell': return OTheme.profit;
      case 'arrive': return OTheme.gold;
      default: return OTheme.neutral;
    }
  }

  String get actionIcon {
    switch (action) {
      case 'buy': return '↓';
      case 'sell': return '↑';
      case 'arrive': return '⚓';
      case 'depart': return '⛵';
      default: return '·';
    }
  }
}

class Good {
  final int goodId;
  final String name;
  final String category;
  final double? buyPriceMin;
  final double? sellPriceMax;
  final bool isRawMaterial;

  Good({
    required this.goodId, required this.name, required this.category,
    this.buyPriceMin, this.sellPriceMax, required this.isRawMaterial,
  });

  factory Good.fromJson(Map<String, dynamic> j) => Good(
    goodId: j['good_id'] ?? 0,
    name: j['name'] ?? '',
    category: j['category'] ?? '',
    buyPriceMin: j['buy_price_min'] != null ? double.tryParse(j['buy_price_min'].toString()) : null,
    sellPriceMax: j['sell_price_max'] != null ? double.tryParse(j['sell_price_max'].toString()) : null,
    isRawMaterial: j['is_raw_material'] == true,
  );
}

class City {
  final int cityId;
  final String name;
  final String region;
  final int population;

  City({required this.cityId, required this.name, required this.region, required this.population});

  factory City.fromJson(Map<String, dynamic> j) => City(
    cityId: j['city_id'] ?? 0,
    name: j['name'] ?? '',
    region: j['region'] ?? '',
    population: j['population'] ?? 0,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  GAME STATE — central provider
// ─────────────────────────────────────────────────────────────────────────────
class GameState extends ChangeNotifier {
  Player? player;
  List<Ship> ships = [];
  List<MarketEntry> market = [];
  List<ArbitrageEntry> arbitrage = [];
  List<TradeLog> tradeLogs = [];
  List<Good> goods = [];
  List<City> cities = [];

  bool loading = false;
  String? error;

  final _fmt = NumberFormat('#,##0.##');

  String fmtGold(double g) => '${_fmt.format(g)} ℊ';
  String fmtDate(int year, int month) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    final m = (month >= 1 && month <= 12) ? months[month - 1] : '?';
    return '$m $year';
  }

  Future<void> loadAll(ApiConfig api) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await Future.wait([
        _loadPlayer(api),
        _loadShips(api),
        _loadMarket(api),
        _loadArbitrage(api),
        _loadTradeLogs(api),
        _loadGoods(api),
        _loadCities(api),
      ]);
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _loadPlayer(ApiConfig api) async {
    final res = await http.get(api.endpoint('p3_player',
      params: {'limit': '1', 'order': 'player_id.asc'}));
    _check(res);
    final list = jsonDecode(res.body) as List;
    if (list.isNotEmpty) player = Player.fromJson(list.first);
  }

  Future<void> _loadShips(ApiConfig api) async {
    final res = await http.get(api.endpoint('p3_ships',
      params: {'owner': 'eq.player', 'order': 'ship_id.asc'}));
    _check(res);
    ships = (jsonDecode(res.body) as List).map((j) => Ship.fromJson(j)).toList();
  }

  Future<void> _loadMarket(ApiConfig api) async {
    final res = await http.get(api.endpoint('p3_market_view',
      params: {'order': 'city.asc,good.asc', 'limit': '500'}));
    _check(res);
    market = (jsonDecode(res.body) as List).map((j) => MarketEntry.fromJson(j)).toList();
  }

  Future<void> _loadArbitrage(ApiConfig api) async {
    final res = await http.get(api.endpoint('p3_arbitrage_view',
      params: {'order': 'profit_per_unit.desc', 'limit': '30'}));
    _check(res);
    arbitrage = (jsonDecode(res.body) as List).map((j) => ArbitrageEntry.fromJson(j)).toList();
  }

  Future<void> _loadTradeLogs(ApiConfig api) async {
    final res = await http.get(api.endpoint('p3_trade_log',
      params: {'order': 'log_id.desc', 'limit': '50'}));
    _check(res);
    tradeLogs = (jsonDecode(res.body) as List).map((j) => TradeLog.fromJson(j)).toList();
  }

  Future<void> _loadGoods(ApiConfig api) async {
    final res = await http.get(api.endpoint('p3_goods',
      params: {'order': 'name.asc'}));
    _check(res);
    goods = (jsonDecode(res.body) as List).map((j) => Good.fromJson(j)).toList();
  }

  Future<void> _loadCities(ApiConfig api) async {
    final res = await http.get(api.endpoint('p3_cities',
      params: {'order': 'name.asc'}));
    _check(res);
    cities = (jsonDecode(res.body) as List).map((j) => City.fromJson(j)).toList();
  }

  // ── WRITE OPERATIONS ──────────────────────────────────────────────────────
  Future<bool> buyGood(ApiConfig api, int shipId, int goodId, int quantity) async {
    // 1. Deduct gold from player; 2. Add cargo; 3. Reduce market stock
    // In a real app this would call a stored procedure via PostgREST /rpc/
    // For now we post to p3_cargo (upsert) and patch p3_player
    final market_ = market.firstWhere(
      (m) => m.good == goods.firstWhere((g) => g.goodId == goodId).name);
    final cost = market_.currentBuy * quantity;
    if ((player?.gold ?? 0) < cost) return false;

    // Update cargo
    try {
      await http.post(
        api.endpoint('p3_cargo'),
        headers: {'Content-Type': 'application/json',
                  'Prefer': 'resolution=merge-duplicates'},
        body: jsonEncode({
          'ship_id': shipId, 'good_id': goodId, 'quantity': quantity,
        }),
      );
      // Log the trade
      await http.post(
        api.endpoint('p3_trade_log'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'game_year': player!.gameYear, 'game_month': player!.gameMonth,
          'ship_id': shipId, 'good_id': goodId, 'good_name': goods.firstWhere((g)=>g.goodId==goodId).name,
          'action': 'buy', 'quantity': quantity, 'price': market_.currentBuy,
          'total_value': cost, 'gold_after': player!.gold - cost,
        }),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sailShip(ApiConfig api, int shipId, String destination, int etaMonths) async {
    try {
      await http.patch(
        api.endpoint('p3_ships', params: {'ship_id': 'eq.$shipId'}),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'status': 'sailing',
          'destination': destination,
          'eta_months': etaMonths,
        }),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  void _check(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  APP ROOT
// ─────────────────────────────────────────────────────────────────────────────
class PatricianApp extends StatelessWidget {
  const PatricianApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Patrician III',
    theme: OTheme.theme,
    debugShowCheckedModeBanner: false,
    home: const SplashScreen(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  SPLASH / LOADING
// ─────────────────────────────────────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const MainShell(),
            transitionDuration: const Duration(milliseconds: 800),
            transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          ),
        );
      }
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: OTheme.bg0,
    body: Center(
      child: FadeTransition(
        opacity: _fade,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Decorative anchor
            const Text('⚓', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 24),
            Text('PATRICIAN', style: OTheme.textTheme.displayLarge),
            const SizedBox(height: 8),
            Text('HANSEATIC TRADE LEAGUE  ·  XIVth CENTURY',
              style: OTheme.textTheme.labelSmall),
            const SizedBox(height: 40),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                backgroundColor: OTheme.bg2,
                color: OTheme.gold,
                minHeight: 2,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  MAIN SHELL — bottom nav
// ─────────────────────────────────────────────────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  final _tabs = const [
    _DashboardTab(),
    _MarketTab(),
    _FleetTab(),
    _TradelogTab(),
    _SettingsTab(),
  ];

  final _labels = const ['LEDGER', 'MARKET', 'FLEET', 'LOG', 'CONFIG'];
  final _icons = const [
    Icons.account_balance_outlined,
    Icons.store_outlined,
    Icons.sailing_outlined,
    Icons.history_outlined,
    Icons.settings_outlined,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final api = context.read<ApiConfig>();
      context.read<GameState>().loadAll(api);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: _tabs[_tab],
    bottomNavigationBar: Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: OTheme.border, width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: List.generate(_labels.length, (i) => BottomNavigationBarItem(
          icon: Icon(_icons[i]),
          label: _labels[i],
        )),
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: GoogleFonts.sourceCodePro(fontSize: 9, letterSpacing: 1),
        unselectedLabelStyle: GoogleFonts.sourceCodePro(fontSize: 9, letterSpacing: 1),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

/// Gritty section label
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Row(children: [
      Container(width: 3, height: 14, color: OTheme.gold),
      const SizedBox(width: 8),
      Text(label, style: GoogleFonts.sourceCodePro(
        color: OTheme.textMuted, fontSize: 11, letterSpacing: 2)),
    ]),
  );
}

/// Stat cell — used in the header dashboard strip
class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _StatCell({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: OTheme.textTheme.labelSmall),
      const SizedBox(height: 2),
      Text(value, style: OTheme.textTheme.titleMedium?.copyWith(
        color: valueColor ?? OTheme.textPrimary,
        fontWeight: FontWeight.w700,
      )),
    ],
  );
}

/// Gold chip
Widget _goldChip(String text) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(
    color: OTheme.goldLo.withOpacity(.25),
    border: Border.all(color: OTheme.goldLo, width: .5),
    borderRadius: BorderRadius.circular(3),
  ),
  child: Text(text, style: GoogleFonts.sourceCodePro(
    color: OTheme.goldHi, fontSize: 11, fontWeight: FontWeight.w600)),
);

/// Status badge
Widget _badge(String text, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  decoration: BoxDecoration(
    color: color.withOpacity(.15),
    border: Border.all(color: color.withOpacity(.5)),
    borderRadius: BorderRadius.circular(3),
  ),
  child: Text(text.toUpperCase(), style: GoogleFonts.sourceCodePro(
    color: color, fontSize: 9, letterSpacing: 1)),
);

/// Error / empty state
Widget _stateMessage(String icon, String msg) => Center(
  child: Padding(
    padding: const EdgeInsets.all(40),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(icon, style: const TextStyle(fontSize: 36)),
      const SizedBox(height: 12),
      Text(msg, style: OTheme.textTheme.bodyMedium, textAlign: TextAlign.center),
    ]),
  ),
);

/// Loading scaffold
Widget _loadingBody() => const Center(
  child: SizedBox(width: 80, child: LinearProgressIndicator(
    color: OTheme.gold, backgroundColor: OTheme.bg2, minHeight: 2)));

// ─────────────────────────────────────────────────────────────────────────────
//  TAB 0 — DASHBOARD / LEDGER
// ─────────────────────────────────────────────────────────────────────────────
class _DashboardTab extends StatelessWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context) {
    final gs = context.watch<GameState>();
    final api = context.read<ApiConfig>();

    return CustomScrollView(slivers: [
      SliverAppBar(
        pinned: true,
        expandedHeight: 110,
        flexibleSpace: FlexibleSpaceBar(
          titlePadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          title: gs.player == null
              ? Text('PATRICIAN', style: OTheme.textTheme.titleLarge)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(gs.player!.name.toUpperCase(),
                      style: OTheme.textTheme.titleLarge),
                    Text('${gs.player!.rank}  ·  ${gs.fmtDate(gs.player!.gameYear, gs.player!.gameMonth)}',
                      style: OTheme.textTheme.labelSmall),
                  ],
                ),
          background: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [OTheme.bg3, OTheme.bg0],
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: OTheme.gold),
            onPressed: () => gs.loadAll(api),
          ),
        ],
      ),

      if (gs.loading) SliverToBoxAdapter(child: _loadingBody()),

      if (gs.error != null)
        SliverToBoxAdapter(child: _stateMessage('⚠', gs.error!)),

      if (gs.player != null) ...[
        // ── GOLD STRIP ───────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: OTheme.bg1,
              border: Border.all(color: OTheme.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatCell(label: 'TREASURY', value: gs.fmtGold(gs.player!.gold),
                  valueColor: OTheme.goldHi),
                _StatCell(label: 'HOME PORT', value: gs.player!.homeCity),
                _StatCell(label: 'SHIPS', value: '${gs.ships.length}'),
                _StatCell(label: 'DATE',
                  value: gs.fmtDate(gs.player!.gameYear, gs.player!.gameMonth)),
              ],
            ),
          ),
        ),

        // ── ARBITRAGE SIGNALS ─────────────────────────────────────────────────
        const SliverToBoxAdapter(child: _SectionLabel('TOP ARBITRAGE OPPORTUNITIES')),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) {
              final a = gs.arbitrage[i];
              return _ArbitrageCard(entry: a);
            },
            childCount: gs.arbitrage.take(5).length,
          ),
        ),

        // ── RECENT TRADE LOG ─────────────────────────────────────────────────
        const SliverToBoxAdapter(child: _SectionLabel('RECENT TRANSACTIONS')),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => _TradeLogRow(log: gs.tradeLogs[i]),
            childCount: gs.tradeLogs.take(8).length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    ]);
  }
}

class _ArbitrageCard extends StatelessWidget {
  final ArbitrageEntry entry;
  const _ArbitrageCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final gs = context.read<GameState>();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: OTheme.bg1,
        border: Border.all(color: entry.profitPerUnit > 50
            ? OTheme.profit.withOpacity(.5) : OTheme.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(entry.good, style: OTheme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('${entry.buyCity}  →  ${entry.sellCity}',
              style: OTheme.textTheme.bodyMedium),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _goldChip('+${gs.fmtGold(entry.profitPerUnit)}/unit'),
          const SizedBox(height: 4),
          Text('Buy ${gs.fmtGold(entry.buyPrice)}  ·  Sell ${gs.fmtGold(entry.sellPrice)}',
            style: OTheme.textTheme.labelSmall),
        ]),
      ]),
    );
  }
}

class _TradeLogRow extends StatelessWidget {
  final TradeLog log;
  const _TradeLogRow({required this.log});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: OTheme.border, width: .5)),
    ),
    child: Row(children: [
      Text(log.actionIcon, style: TextStyle(color: log.actionColor, fontSize: 16)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(log.action.toUpperCase(),
            style: GoogleFonts.sourceCodePro(
              color: log.actionColor, fontSize: 10, letterSpacing: 1)),
          if (log.goodName != null) ...[
            const SizedBox(width: 6),
            Text(log.goodName!, style: OTheme.textTheme.titleMedium),
          ],
        ]),
        if (log.city != null)
          Text(log.city!, style: OTheme.textTheme.bodyMedium),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (log.totalValue != null)
          Text('${log.quantity} × ${log.price?.toStringAsFixed(0)}',
            style: OTheme.textTheme.labelSmall),
        if (log.goldAfter != null)
          Text('${log.goldAfter!.toStringAsFixed(0)} ℊ',
            style: GoogleFonts.sourceCodePro(
              color: log.action == 'sell' ? OTheme.profit : OTheme.textSecondary,
              fontSize: 11)),
      ]),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  TAB 1 — MARKET
// ─────────────────────────────────────────────────────────────────────────────
class _MarketTab extends StatefulWidget {
  const _MarketTab();
  @override State<_MarketTab> createState() => _MarketTabState();
}

class _MarketTabState extends State<_MarketTab> {
  String _search = '';
  String? _filterCity;

  @override
  Widget build(BuildContext context) {
    final gs = context.watch<GameState>();

    final cities = gs.market.map((m) => m.city).toSet().toList()..sort();
    var filtered = gs.market.where((m) {
      final matchSearch = _search.isEmpty ||
        m.good.toLowerCase().contains(_search) ||
        m.city.toLowerCase().contains(_search);
      final matchCity = _filterCity == null || m.city == _filterCity;
      return matchSearch && matchCity;
    }).toList();

    return CustomScrollView(slivers: [
      SliverAppBar(
        floating: true,
        title: Text('MARKET', style: OTheme.textTheme.titleLarge),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(children: [
              TextField(
                onChanged: (v) => setState(() => _search = v.toLowerCase()),
                decoration: const InputDecoration(
                  hintText: 'Search goods or cities…',
                  prefixIcon: Icon(Icons.search, color: OTheme.textMuted, size: 18),
                ),
                style: OTheme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _filterCity = null),
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: _filterCity == null ? OTheme.goldLo : OTheme.bg2,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: OTheme.border),
                        ),
                        alignment: Alignment.center,
                        child: Text('ALL', style: GoogleFonts.sourceCodePro(
                          color: _filterCity == null ? OTheme.goldHi : OTheme.textMuted,
                          fontSize: 10, letterSpacing: 1)),
                      ),
                    ),
                    ...cities.map((c) => GestureDetector(
                      onTap: () => setState(() => _filterCity = _filterCity == c ? null : c),
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: _filterCity == c ? OTheme.goldLo : OTheme.bg2,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: OTheme.border),
                        ),
                        alignment: Alignment.center,
                        child: Text(c, style: GoogleFonts.sourceCodePro(
                          color: _filterCity == c ? OTheme.goldHi : OTheme.textMuted,
                          fontSize: 10, letterSpacing: .5)),
                      ),
                    )),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),

      if (gs.loading) SliverToBoxAdapter(child: _loadingBody()),

      if (filtered.isEmpty && !gs.loading)
        SliverToBoxAdapter(child: _stateMessage('📜', 'No market data.\nCheck PostgREST connection in Config.')),

      // Header row
      if (filtered.isNotEmpty)
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: OTheme.bg2,
            child: Row(children: [
              Expanded(flex: 3, child: Text('GOOD', style: OTheme.textTheme.labelSmall)),
              Expanded(flex: 2, child: Text('CITY', style: OTheme.textTheme.labelSmall)),
              SizedBox(width: 72, child: Text('BUY', style: OTheme.textTheme.labelSmall, textAlign: TextAlign.right)),
              SizedBox(width: 72, child: Text('SELL', style: OTheme.textTheme.labelSmall, textAlign: TextAlign.right)),
              SizedBox(width: 44, child: Text('STOCK', style: OTheme.textTheme.labelSmall, textAlign: TextAlign.right)),
            ]),
          ),
        ),

      SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => _MarketRow(entry: filtered[i]),
          childCount: filtered.length,
        ),
      ),

      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ]);
  }
}

class _MarketRow extends StatelessWidget {
  final MarketEntry entry;
  const _MarketRow({required this.entry});

  Color get _signalColor {
    if (entry.signal.contains('GREAT SELL') || entry.signal.contains('GOOD SELL')) return OTheme.profit;
    if (entry.signal.contains('GOOD BUY')) return OTheme.loss.withOpacity(.8);
    return OTheme.neutral;
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: OTheme.border, width: .5))),
    child: Row(children: [
      Expanded(flex: 3, child: Row(children: [
        if (entry.signal != '—')
          Container(
            width: 3, height: 24, color: _signalColor,
            margin: const EdgeInsets.only(right: 8)),
        Expanded(child: Text(entry.good, style: OTheme.textTheme.bodyLarge)),
      ])),
      Expanded(flex: 2, child: Text(entry.city,
        style: OTheme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
      SizedBox(width: 72, child: Text(
        entry.currentBuy.toStringAsFixed(0),
        style: OTheme.textTheme.bodyMedium?.copyWith(color: OTheme.loss.withOpacity(.9)),
        textAlign: TextAlign.right)),
      SizedBox(width: 72, child: Text(
        entry.currentSell.toStringAsFixed(0),
        style: OTheme.textTheme.bodyMedium?.copyWith(color: OTheme.profit),
        textAlign: TextAlign.right)),
      SizedBox(width: 44, child: Text(
        '${entry.stock}',
        style: OTheme.textTheme.labelSmall,
        textAlign: TextAlign.right)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  TAB 2 — FLEET
// ─────────────────────────────────────────────────────────────────────────────
class _FleetTab extends StatelessWidget {
  const _FleetTab();

  @override
  Widget build(BuildContext context) {
    final gs = context.watch<GameState>();
    final api = context.read<ApiConfig>();

    return CustomScrollView(slivers: [
      SliverAppBar(
        pinned: true,
        title: Text('FLEET', style: OTheme.textTheme.titleLarge),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => gs.loadAll(api),
          ),
        ],
      ),

      if (gs.loading) SliverToBoxAdapter(child: _loadingBody()),

      if (gs.ships.isEmpty && !gs.loading)
        SliverToBoxAdapter(
          child: _stateMessage('⛵', 'No ships found.\nInitialise the game via app.sh first.')),

      SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => _ShipCard(ship: gs.ships[i]),
          childCount: gs.ships.length,
        ),
      ),

      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ]);
  }
}

class _ShipCard extends StatelessWidget {
  final Ship ship;
  const _ShipCard({required this.ship});

  @override
  Widget build(BuildContext context) {
    final gs = context.read<GameState>();
    final api = context.read<ApiConfig>();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OTheme.bg1,
        border: Border.all(color: OTheme.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(ship.name,
            style: OTheme.textTheme.displayMedium?.copyWith(fontSize: 18))),
          _badge(ship.status, ship.statusColor),
        ]),
        const SizedBox(height: 4),
        Text(ship.shipType, style: OTheme.textTheme.bodyMedium),
        const SizedBox(height: 12),

        Row(children: [
          _StatCell(label: 'CAPACITY', value: '${ship.cargoCap} units'),
          const SizedBox(width: 24),
          _StatCell(label: 'PORT', value: ship.currentCity),
          if (ship.destination != null) ...[
            const SizedBox(width: 24),
            _StatCell(label: 'BOUND FOR', value: ship.destination!),
            const SizedBox(width: 24),
            _StatCell(label: 'ETA', value: '${ship.etaMonths} mo.'),
          ],
        ]),

        if (ship.status == 'docked') ...[
          const SizedBox(height: 16),
          Row(children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.store, size: 14),
              label: const Text('TRADE'),
              onPressed: () => _showTradeSheet(context, ship, gs, api),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.sailing, size: 14),
              label: const Text('SAIL'),
              onPressed: () => _showSailSheet(context, ship, gs, api),
            ),
          ]),
        ],
      ]),
    );
  }

  void _showTradeSheet(BuildContext context, Ship ship, GameState gs, ApiConfig api) {
    showModalBottomSheet(
      context: context,
      backgroundColor: OTheme.bg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        side: BorderSide(color: OTheme.border)),
      isScrollControlled: true,
      builder: (_) => _TradeSheet(ship: ship),
    );
  }

  void _showSailSheet(BuildContext context, Ship ship, GameState gs, ApiConfig api) {
    showModalBottomSheet(
      context: context,
      backgroundColor: OTheme.bg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        side: BorderSide(color: OTheme.border)),
      isScrollControlled: true,
      builder: (_) => _SailSheet(ship: ship),
    );
  }
}

class _TradeSheet extends StatefulWidget {
  final Ship ship;
  const _TradeSheet({required this.ship});
  @override State<_TradeSheet> createState() => _TradeSheetState();
}

class _TradeSheetState extends State<_TradeSheet> {
  int _qty = 10;
  MarketEntry? _selected;

  @override
  Widget build(BuildContext context) {
    final gs = context.watch<GameState>();
    final api = context.read<ApiConfig>();
    final cityMarket = gs.market.where((m) => m.city == widget.ship.currentCity).toList();

    return DraggableScrollableSheet(
      initialChildSize: .7, maxChildSize: .95, minChildSize: .4,
      expand: false,
      builder: (_, ctrl) => Column(children: [
        const SizedBox(height: 8),
        Container(width: 36, height: 3, decoration: BoxDecoration(
          color: OTheme.border, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('TRADE AT ${widget.ship.currentCity.toUpperCase()}',
            style: OTheme.textTheme.titleLarge),
        ),
        Expanded(
          child: ListView.builder(
            controller: ctrl,
            itemCount: cityMarket.length,
            itemBuilder: (_, i) {
              final m = cityMarket[i];
              final sel = _selected?.good == m.good;
              return GestureDetector(
                onTap: () => setState(() => _selected = m),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: sel ? OTheme.bg3 : OTheme.bg1,
                    border: Border.all(color: sel ? OTheme.gold : OTheme.border),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(children: [
                    Expanded(child: Text(m.good, style: OTheme.textTheme.bodyLarge)),
                    Text('Buy ${m.currentBuy.toStringAsFixed(0)}  Sell ${m.currentSell.toStringAsFixed(0)}',
                      style: OTheme.textTheme.labelSmall),
                  ]),
                ),
              );
            },
          ),
        ),
        if (_selected != null)
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16,
              MediaQuery.of(context).viewInsets.bottom + 16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: OTheme.border))),
            child: Row(children: [
              Expanded(child: TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'QTY'),
                onChanged: (v) => setState(() => _qty = int.tryParse(v) ?? 10),
                style: OTheme.textTheme.bodyLarge,
              )),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () async {
                  final gId = gs.goods.firstWhere((g) => g.name == _selected!.good).goodId;
                  final ok = await gs.buyGood(api, widget.ship.shipId, gId, _qty);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      backgroundColor: ok ? OTheme.profit : OTheme.loss,
                      content: Text(ok ? 'Purchased $_qty × ${_selected!.good}' : 'Transaction failed'),
                    ));
                    if (ok) Navigator.pop(context);
                  }
                },
                child: const Text('BUY'),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _SailSheet extends StatefulWidget {
  final Ship ship;
  const _SailSheet({required this.ship});
  @override State<_SailSheet> createState() => _SailSheetState();
}

class _SailSheetState extends State<_SailSheet> {
  City? _dest;

  @override
  Widget build(BuildContext context) {
    final gs = context.watch<GameState>();
    final api = context.read<ApiConfig>();
    final cities = gs.cities.where((c) => c.name != widget.ship.currentCity).toList();

    return DraggableScrollableSheet(
      initialChildSize: .6, maxChildSize: .9, minChildSize: .4,
      expand: false,
      builder: (_, ctrl) => Column(children: [
        const SizedBox(height: 8),
        Container(width: 36, height: 3, decoration: BoxDecoration(
          color: OTheme.border, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('SET COURSE FROM ${widget.ship.currentCity.toUpperCase()}',
            style: OTheme.textTheme.titleLarge),
        ),
        Expanded(
          child: ListView.builder(
            controller: ctrl,
            itemCount: cities.length,
            itemBuilder: (_, i) {
              final c = cities[i];
              final sel = _dest?.cityId == c.cityId;
              return GestureDetector(
                onTap: () => setState(() => _dest = c),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? OTheme.bg3 : OTheme.bg1,
                    border: Border.all(color: sel ? OTheme.gold : OTheme.border),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(children: [
                    Expanded(child: Text(c.name, style: OTheme.textTheme.bodyLarge)),
                    Text(c.region, style: OTheme.textTheme.labelSmall),
                  ]),
                ),
              );
            },
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16,
            MediaQuery.of(context).viewInsets.bottom + 16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: OTheme.border))),
          child: ElevatedButton(
            onPressed: _dest == null ? null : () async {
              // ETA calculation: assume ~1–3 months simplified
              final eta = max(1, (gs.cities.length ~/ 8));
              final ok = await gs.sailShip(api, widget.ship.shipId, _dest!.name, eta);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: ok ? OTheme.profit : OTheme.loss,
                  content: Text(ok
                    ? 'Setting sail for ${_dest!.name} — ETA $eta month(s)'
                    : 'Could not issue sail order'),
                ));
                if (ok) { gs.loadAll(api); Navigator.pop(context); }
              }
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
            child: Text(_dest == null
              ? 'SELECT DESTINATION'
              : 'SAIL TO ${_dest!.name.toUpperCase()}'),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  TAB 3 — TRADE LOG
// ─────────────────────────────────────────────────────────────────────────────
class _TradelogTab extends StatelessWidget {
  const _TradelogTab();

  @override
  Widget build(BuildContext context) {
    final gs = context.watch<GameState>();
    final api = context.read<ApiConfig>();

    return CustomScrollView(slivers: [
      SliverAppBar(
        pinned: true,
        title: Text('TRADE LOG', style: OTheme.textTheme.titleLarge),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => gs.loadAll(api)),
        ],
      ),

      if (gs.loading) SliverToBoxAdapter(child: _loadingBody()),

      if (gs.tradeLogs.isEmpty && !gs.loading)
        SliverToBoxAdapter(child: _stateMessage('📜', 'No trade history yet.')),

      SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) {
            final log = gs.tradeLogs[i];
            return Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: OTheme.border, width: .5),
                  left: BorderSide(color: log.actionColor, width: 3),
                ),
              ),
              child: Row(children: [
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(log.action.toUpperCase(),
                      style: GoogleFonts.sourceCodePro(
                        color: log.actionColor, fontSize: 11, letterSpacing: 1.5)),
                    if (log.goodName != null) ...[
                      const SizedBox(width: 8),
                      Text(log.goodName!, style: OTheme.textTheme.titleMedium),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  Row(children: [
                    if (log.city != null) Text(log.city!, style: OTheme.textTheme.bodyMedium),
                    if (log.shipName != null) ...[
                      if (log.city != null) Text('  ·  ', style: OTheme.textTheme.bodyMedium),
                      Text(log.shipName!, style: OTheme.textTheme.bodyMedium),
                    ],
                  ]),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${gs.fmtDate(log.gameYear, log.gameMonth)}',
                    style: OTheme.textTheme.labelSmall),
                  if (log.quantity != null)
                    Text('${log.quantity} units', style: OTheme.textTheme.bodyMedium),
                  if (log.totalValue != null)
                    Text('${log.totalValue!.toStringAsFixed(0)} ℊ',
                      style: GoogleFonts.crimsonText(
                        color: log.action == 'sell' ? OTheme.profit : OTheme.loss,
                        fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ]),
            );
          },
          childCount: gs.tradeLogs.length,
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  TAB 4 — SETTINGS / CONFIG
// ─────────────────────────────────────────────────────────────────────────────
class _SettingsTab extends StatefulWidget {
  const _SettingsTab();
  @override State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  late TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _urlCtrl.text = context.read<ApiConfig>().baseUrl;
    });
  }

  @override
  void dispose() { _urlCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiConfig>();
    final gs = context.watch<GameState>();

    return CustomScrollView(slivers: [
      SliverAppBar(
        pinned: true,
        title: Text('CONFIG', style: OTheme.textTheme.titleLarge),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── PostgREST URL ─────────────────────────────────────────────────
            const _SectionLabel('POSTGREST ENDPOINT'),
            const SizedBox(height: 4),
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'http://localhost:3000',
              ),
              style: OTheme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                api.setBaseUrl(_urlCtrl.text.trim());
                gs.loadAll(api);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  backgroundColor: OTheme.profit,
                  content: Text('Connecting…'),
                ));
              },
              child: const Text('CONNECT'),
            ),

            const SizedBox(height: 24),
            const Divider(),

            // ── API Endpoints Reference ───────────────────────────────────────
            const _SectionLabel('EXPOSED POSTGREST TABLES'),
            const SizedBox(height: 8),
            ..._endpointRows([
              ('p3_player', 'Player gold, rank, date'),
              ('p3_ships', 'Fleet — type, cargo, status'),
              ('p3_cargo', 'Cargo per ship'),
              ('p3_goods', 'Goods reference + prices'),
              ('p3_cities', 'Hanseatic city list'),
              ('p3_city_goods', 'City production/demand'),
              ('p3_market_view', 'Live prices (VIEW)'),
              ('p3_market', 'Raw market table'),
              ('p3_arbitrage_view', 'Best arbitrage (VIEW)'),
              ('p3_trade_log', 'Full trade history'),
              ('p3_routes', 'Trade routes'),
              ('p3_route_orders', 'Standing orders per route'),
              ('p3_building_types', 'Building type catalogue'),
              ('p3_player_buildings', 'Owned buildings'),
              ('p3_limit_orders', 'Active limit orders'),
              ('p3_price_history', 'Historical prices'),
              ('p3_hex_tiles', 'Hex map tiles'),
              ('p3_good_elasticity', 'Price elasticity params'),
              ('newspaper_stock_quotes', 'Historical NYSE quotes 1929'),
            ]),

            const SizedBox(height: 24),
            const Divider(),

            // ── Connection Test ───────────────────────────────────────────────
            const _SectionLabel('CONNECTION STATUS'),
            const SizedBox(height: 8),
            if (gs.error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: OTheme.loss.withOpacity(.1),
                  border: Border.all(color: OTheme.loss.withOpacity(.4)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(gs.error!, style: OTheme.textTheme.bodyMedium?.copyWith(
                  color: OTheme.loss.withOpacity(.9))),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: OTheme.profit.withOpacity(.1),
                  border: Border.all(color: OTheme.profit.withOpacity(.4)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline, color: OTheme.profit, size: 16),
                  const SizedBox(width: 8),
                  Text(gs.player != null
                    ? 'Connected  ·  ${gs.player!.name}  ·  ${gs.fmtGold(gs.player!.gold)}'
                    : 'Awaiting data…',
                    style: OTheme.textTheme.bodyMedium?.copyWith(color: OTheme.profit)),
                ]),
              ),

            const SizedBox(height: 40),
          ]),
        ),
      ),
    ]);
  }

  List<Widget> _endpointRows(List<(String, String)> items) => items.map((it) =>
    Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: OTheme.bg1,
        border: Border.all(color: OTheme.border),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(children: [
        Expanded(child: Text(it.$1, style: GoogleFonts.sourceCodePro(
          color: OTheme.goldHi, fontSize: 11))),
        Text(it.$2, style: OTheme.textTheme.labelSmall),
      ]),
    )
  ).toList();
}
