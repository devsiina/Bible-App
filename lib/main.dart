// =============================================================================
//  FLUTTER BIBLE APP  ·  Single-file  ·  KJV  ·  SharedPreferences offline
// =============================================================================
//
//  SETUP — pubspec.yaml:
//
//  dependencies:
//    flutter:
//      sdk: flutter
//    shared_preferences: ^2.3.2
//    http: ^1.2.0
//
//  ⚠️  REQUIRED — android/app/src/main/AndroidManifest.xml:
//  Add this line BEFORE the <application> tag:
//
//    <uses-permission android:name="android.permission.INTERNET"/>
//
//  Without it Android blocks all network calls and you get:
//  "Failed host lookup / SocketException errno 7".
// =============================================================================

import 'dart:convert';
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── Entry point ───────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const BibleApp());
}

// ── Palette ───────────────────────────────────────────────────────────────────

const _bg       = Color(0xFF080C14);
const _surface  = Color(0xFF0F1622);
const _card     = Color(0xFF151E2E);
const _gold     = Color(0xFFCEA84A);
const _goldGlow = Color(0x28CEA84A);
const _parch    = Color(0xFFEADFC8);
const _muted    = Color(0xFF52596A);
const _dimLine  = Color(0xFF1C2535);
const _error    = Color(0xFFBF4040);

// ── Bible source URLs (primary + fallback CDN) ────────────────────────────────
//
//  We try each URL in order; first successful response wins.
//  jsdelivr mirrors the same GitHub repo via a global CDN and is
//  more reliable on restricted networks / emulators.

const _kBibleUrls = [
  'https://cdn.jsdelivr.net/gh/thiagobodruk/bible@master/json/en_kjv.json',
  'https://raw.githubusercontent.com/thiagobodruk/bible/master/json/en_kjv.json',
];

// ── SharedPreferences keys ────────────────────────────────────────────────────

const _kRawKey        = 'bible_raw';
const _kDownloadedKey = 'bible_downloaded';

// ── Data model ────────────────────────────────────────────────────────────────

class BibleBook {
  final String abbrev;
  final String name;
  final List<List<String>> chapters;

  const BibleBook({
    required this.abbrev,
    required this.name,
    required this.chapters,
  });

  factory BibleBook.fromJson(Map<String, dynamic> j) => BibleBook(
        // Guard every field — some JSON entries carry null values
        abbrev: (j['abbrev'] as String?)?.trim() ?? '',
        name:   (j['book']   as String?)?.trim() ??
                (j['name']   as String?)?.trim() ?? 'Unknown',
        chapters: ((j['chapters'] as List?) ?? [])
            .map((c) => ((c as List?) ?? [])
                .map((v) => ((v as String?) ?? '').trim())
                .where((v) => v.isNotEmpty)
                .toList())
            .toList(),
      );

  int get chapterCount => chapters.length;
  int get verseCount => chapters.fold(0, (s, c) => s + c.length);
  String get shortTag =>
      abbrev.toUpperCase().substring(0, min(3, abbrev.length));
}

const _otCount = 39;

// ── Repository ────────────────────────────────────────────────────────────────

class BibleRepository {
  static Future<bool> isDownloaded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kDownloadedKey) ?? false;
  }

  static Future<void> store(String rawJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRawKey, rawJson);
    await prefs.setBool(_kDownloadedKey, true);
  }

  static Future<List<BibleBook>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kRawKey) ?? '[]';
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => BibleBook.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRawKey);
    await prefs.setBool(_kDownloadedKey, false);
  }
}

// ── App ───────────────────────────────────────────────────────────────────────

class BibleApp extends StatelessWidget {
  const BibleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Holy Bible',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _bg,
          colorScheme: const ColorScheme.dark(
              primary: _gold, surface: _surface),
          appBarTheme: const AppBarTheme(
            backgroundColor: _bg,
            elevation: 0,
            iconTheme: IconThemeData(color: _gold),
            titleTextStyle: TextStyle(
              color: _parch,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'Georgia',
            ),
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  HOME SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 'loading' | 'welcome' | 'downloading' | 'error' | 'list'
  String _view = 'loading';

  List<BibleBook> _books      = [];
  double          _dlProgress = 0;
  String          _dlStatus   = '';
  String          _dlError    = '';
  String          _search     = '';
  final           _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkStorage();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Storage check ───────────────────────────────────────────────────────────

  Future<void> _checkStorage() async {
    final downloaded = await BibleRepository.isDownloaded();
    if (downloaded) {
      final books = await BibleRepository.loadAll();
      setState(() { _books = books; _view = 'list'; });
    } else {
      setState(() => _view = 'welcome');
    }
  }

  // ── Download with multi-URL fallback ───────────────────────────────────────

  Future<void> _download() async {
    setState(() {
      _view       = 'downloading';
      _dlProgress = 0.05;
      _dlStatus   = 'Connecting…';
      _dlError    = '';
    });

    String? body;
    String? lastError;

    for (int i = 0; i < _kBibleUrls.length; i++) {
      final url   = _kBibleUrls[i];
      final label = i == 0 ? 'primary source' : 'fallback CDN';

      try {
        setState(() {
          _dlStatus   = 'Trying $label…';
          _dlProgress = 0.10 + i * 0.05;
        });

        final resp = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 60));

        if (resp.statusCode == 200) {
          body = resp.body;
          setState(() {
            _dlStatus   = 'Downloaded ${(resp.bodyBytes.length / 1024).toStringAsFixed(0)} KB from $label';
            _dlProgress = 0.60;
          });
          break; // success — stop trying
        } else {
          lastError = 'HTTP ${resp.statusCode} from $label';
        }
      } catch (e) {
        lastError = e.toString();
        // Try next URL
      }
    }

    if (body == null) {
      // All URLs failed
      setState(() {
        _view    = 'error';
        _dlError = lastError ?? 'Unknown network error';
      });
      return;
    }

    try {
      setState(() {
        _dlStatus   = 'Parsing scriptures…';
        _dlProgress = 0.72;
      });
      await Future.delayed(const Duration(milliseconds: 150));

      final list = jsonDecode(body!) as List;

      setState(() {
        _dlStatus   = 'Saving ${list.length} books to device…';
        _dlProgress = 0.88;
      });
      await Future.delayed(const Duration(milliseconds: 150));

      await BibleRepository.store(body!);

      setState(() { _dlStatus = 'Complete!'; _dlProgress = 1.0; });
      await Future.delayed(const Duration(milliseconds: 700));

      final books = await BibleRepository.loadAll();
      setState(() { _books = books; _view = 'list'; });
    } catch (e) {
      setState(() {
        _view    = 'error';
        _dlError = 'Parse/save error: $e';
      });
    }
  }

  // ── Filter ──────────────────────────────────────────────────────────────────

  List<BibleBook> get _ot =>
      _books.take(_otCount).where(_matches).toList();
  List<BibleBook> get _nt =>
      _books.skip(_otCount).where(_matches).toList();

  bool _matches(BibleBook b) =>
      _search.isEmpty ||
      b.name.toLowerCase().contains(_search.toLowerCase());

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => switch (_view) {
        'loading'     => const _LoadingView(),
        'downloading' => _DownloadingView(
            progress: _dlProgress, status: _dlStatus),
        'error'       => _ErrorView(
            error: _dlError, onRetry: _download),
        'list'        => _buildList(),
        _             => _WelcomeView(onDownload: _download),
      };

  // ── Book list ───────────────────────────────────────────────────────────────

  Widget _buildList() {
    final ot    = _ot;
    final nt    = _nt;
    final empty = ot.isEmpty && nt.isEmpty;

    return Scaffold(
      backgroundColor: _bg,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Holy Bible',
                              style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w700,
                                  color: _parch,
                                  fontFamily: 'Georgia',
                                  letterSpacing: 0.5)),
                          const SizedBox(height: 2),
                          Text(
                              'King James Version · ${_books.length} Books',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: _gold,
                                  letterSpacing: 1.5)),
                        ],
                      ),
                      const Spacer(),
                      _GoldCircle(
                          child: const Icon(
                              Icons.auto_stories_rounded,
                              color: _gold,
                              size: 22)),
                    ]),
                    const SizedBox(height: 18),
                    // Search
                    Container(
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _dimLine),
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (v) =>
                            setState(() => _search = v),
                        style: const TextStyle(
                            color: _parch, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Search books…',
                          hintStyle:
                              const TextStyle(color: _muted),
                          prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: _muted,
                              size: 20),
                          suffixIcon: _search.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                      Icons.close_rounded,
                                      color: _muted,
                                      size: 18),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(
                                        () => _search = '');
                                  })
                              : null,
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(
                                  vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
          children: [
            if (empty) ...[
              const SizedBox(height: 60),
              const Center(
                  child: Text('No books match your search.',
                      style: TextStyle(
                          color: _muted, fontSize: 15))),
            ],
            if (ot.isNotEmpty) ...[
              _TestamentHeader(
                  title: 'Old Testament', count: ot.length),
              const SizedBox(height: 10),
              ...ot.map((b) =>
                  _BookRow(book: b, onTap: () => _openBook(b))),
              const SizedBox(height: 18),
            ],
            if (nt.isNotEmpty) ...[
              _TestamentHeader(
                  title: 'New Testament', count: nt.length),
              const SizedBox(height: 10),
              ...nt.map((b) =>
                  _BookRow(book: b, onTap: () => _openBook(b))),
            ],
          ],
        ),
      ),
    );
  }

  void _openBook(BibleBook b) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChapterScreen(book: b)),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  LOADING VIEW
// ══════════════════════════════════════════════════════════════════════════════

class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.menu_book_rounded, color: _gold, size: 52),
            SizedBox(height: 24),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(_gold),
              ),
            ),
          ]),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  WELCOME VIEW
// ══════════════════════════════════════════════════════════════════════════════

class _WelcomeView extends StatelessWidget {
  final VoidCallback onDownload;
  const _WelcomeView({required this.onDownload});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _goldGlow,
                      border: Border.all(
                          color: _gold.withOpacity(0.25),
                          width: 1.5),
                    ),
                    child: const Icon(Icons.menu_book_rounded,
                        color: _gold, size: 50),
                  ),
                  const SizedBox(height: 30),
                  const Text('Holy Bible',
                      style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w700,
                          color: _parch,
                          fontFamily: 'Georgia',
                          letterSpacing: 2)),
                  const SizedBox(height: 6),
                  const Text('KING JAMES VERSION',
                      style: TextStyle(
                          fontSize: 11,
                          color: _gold,
                          letterSpacing: 4,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                            width: 40,
                            height: 1,
                            color: _gold.withOpacity(0.35)),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10),
                          child: Icon(Icons.brightness_1,
                              size: 5,
                              color: _gold.withOpacity(0.6)),
                        ),
                        Container(
                            width: 40,
                            height: 1,
                            color: _gold.withOpacity(0.35)),
                      ]),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 18),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _dimLine),
                    ),
                    child: const Text(
                      '"Thy word is a lamp unto my feet,\n'
                      'and a light unto my path."\n\n'
                      '— Psalm 119:105',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: _parch,
                        fontFamily: 'Georgia',
                        fontStyle: FontStyle.italic,
                        height: 1.75,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton.icon(
                      onPressed: onDownload,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(18)),
                        elevation: 10,
                        shadowColor: _gold.withOpacity(0.35),
                      ),
                      icon: const Icon(Icons.download_rounded,
                          size: 22),
                      label: const Text('Download Complete Bible',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                      'One-time download · Reads offline forever',
                      style: TextStyle(fontSize: 12, color: _muted)),
                  const SizedBox(height: 4),
                  const Text(
                      '66 Books · 31,102 Verses · Auto-fallback CDN',
                      style: TextStyle(fontSize: 11, color: _muted)),
                ],
              ),
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  DOWNLOADING VIEW
// ══════════════════════════════════════════════════════════════════════════════

class _DownloadingView extends StatelessWidget {
  final double progress;
  final String status;
  const _DownloadingView(
      {required this.progress, required this.status});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.elasticOut,
                    builder: (_, v, child) =>
                        Transform.scale(scale: v, child: child),
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _goldGlow,
                        border: Border.all(
                            color: _gold.withOpacity(0.3),
                            width: 1.5),
                      ),
                      child: const Icon(
                          Icons.cloud_download_rounded,
                          color: _gold,
                          size: 50),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text('Downloading Bible',
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: _parch,
                          fontFamily: 'Georgia')),
                  const SizedBox(height: 8),
                  Text(status,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13,
                          color: _muted,
                          height: 1.5)),
                  const SizedBox(height: 36),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: progress),
                      duration: const Duration(milliseconds: 400),
                      builder: (_, v, __) =>
                          LinearProgressIndicator(
                        value: v,
                        minHeight: 10,
                        backgroundColor: _surface,
                        valueColor:
                            const AlwaysStoppedAnimation(_gold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 400),
                    builder: (_, v, __) => Text(
                      '${(v * 100).toInt()}%',
                      style: const TextStyle(
                          color: _gold,
                          fontSize: 18,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  ERROR VIEW  — shown when all URLs fail
// ══════════════════════════════════════════════════════════════════════════════

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _error.withOpacity(0.12),
                      border: Border.all(
                          color: _error.withOpacity(0.3),
                          width: 1.5),
                    ),
                    child: const Icon(Icons.wifi_off_rounded,
                        color: _error, size: 40),
                  ),
                  const SizedBox(height: 24),
                  const Text('Download Failed',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: _parch,
                          fontFamily: 'Georgia')),
                  const SizedBox(height: 16),

                  // Checklist
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _dimLine),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Text('Check the following:',
                            style: TextStyle(
                                color: _gold,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5)),
                        const SizedBox(height: 12),
                        _CheckItem(
                          icon: Icons.wifi_rounded,
                          text:
                              'Device is connected to the internet',
                        ),
                        _CheckItem(
                          icon: Icons.code_rounded,
                          text:
                              'INTERNET permission added to AndroidManifest.xml',
                        ),
                        _CheckItem(
                          icon: Icons.phonelink_off_rounded,
                          text:
                              'If using an emulator, check its network settings',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Error detail
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _error.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: _error.withOpacity(0.2)),
                    ),
                    child: Text(
                      error,
                      style: const TextStyle(
                          color: _error,
                          fontSize: 11,
                          fontFamily: 'monospace',
                          height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Retry button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: onRetry,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(16)),
                        elevation: 6,
                        shadowColor: _gold.withOpacity(0.3),
                      ),
                      icon: const Icon(Icons.refresh_rounded,
                          size: 20),
                      label: const Text('Try Again',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _CheckItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _CheckItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: _gold, size: 16),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: _parch, fontSize: 13, height: 1.4))),
        ]),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  CHAPTER SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class ChapterScreen extends StatelessWidget {
  final BibleBook book;
  const ChapterScreen({super.key, required this.book});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        body: CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: _bg,
            leading: IconButton(
              icon:
                  const Icon(Icons.arrow_back_ios_rounded, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(book.name,
                    style: const TextStyle(
                        color: _parch,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Georgia')),
                Text(
                    '${book.chapterCount} chapters · ${book.verseCount} verses',
                    style:
                        const TextStyle(color: _muted, fontSize: 11)),
              ],
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: _dimLine),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
            sliver: SliverGrid(
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _ChapterCell(
                  number: i + 1,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          VerseScreen(book: book, startChapter: i),
                    ),
                  ),
                ),
                childCount: book.chapters.length,
              ),
            ),
          ),
        ]),
      );
}

class _ChapterCell extends StatelessWidget {
  final int number;
  final VoidCallback onTap;
  const _ChapterCell({required this.number, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          splashColor: _goldGlow,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _dimLine),
            ),
            child: Center(
              child: Text('$number',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _parch,
                      fontFamily: 'Georgia')),
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  VERSE SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class VerseScreen extends StatefulWidget {
  final BibleBook book;
  final int startChapter;
  const VerseScreen(
      {super.key, required this.book, required this.startChapter});

  @override
  State<VerseScreen> createState() => _VerseScreenState();
}

class _VerseScreenState extends State<VerseScreen> {
  late PageController _pc;
  late int _chapter;
  double _fontSize = 17;

  @override
  void initState() {
    super.initState();
    _chapter = widget.startChapter;
    _pc = PageController(initialPage: widget.startChapter);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _prev() {
    if (_chapter > 0)
      _pc.previousPage(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOut);
  }

  void _next() {
    if (_chapter < widget.book.chapterCount - 1)
      _pc.nextPage(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_ios_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(book.name,
                style: const TextStyle(
                    color: _parch,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Georgia')),
            Text(
                'Chapter ${_chapter + 1} of ${book.chapterCount}',
                style:
                    const TextStyle(color: _muted, fontSize: 11)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Smaller text',
            icon: const Icon(Icons.text_decrease_rounded,
                size: 20),
            onPressed: _fontSize > 12
                ? () => setState(() => _fontSize -= 1)
                : null,
          ),
          IconButton(
            tooltip: 'Larger text',
            icon: const Icon(Icons.text_increase_rounded,
                size: 20),
            onPressed: _fontSize < 26
                ? () => setState(() => _fontSize += 1)
                : null,
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _dimLine),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: PageView.builder(
            controller: _pc,
            onPageChanged: (i) => setState(() => _chapter = i),
            itemCount: book.chapterCount,
            itemBuilder: (_, ci) {
              final verses = book.chapters[ci];
              return ListView.builder(
                padding:
                    const EdgeInsets.fromLTRB(24, 28, 24, 32),
                itemCount: verses.length + 1,
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 28),
                      child: Column(children: [
                        Text('Chapter ${ci + 1}',
                            style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: _gold,
                                fontFamily: 'Georgia',
                                letterSpacing: 1.5)),
                        const SizedBox(height: 8),
                        Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Container(
                                  width: 32,
                                  height: 1,
                                  color: _gold.withOpacity(0.4)),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 8),
                                child: Icon(Icons.brightness_1,
                                    size: 4,
                                    color:
                                        _gold.withOpacity(0.6)),
                              ),
                              Container(
                                  width: 32,
                                  height: 1,
                                  color: _gold.withOpacity(0.4)),
                            ]),
                      ]),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: RichText(
                      text: TextSpan(children: [
                        TextSpan(
                          text: '$i  ',
                          style: TextStyle(
                              fontSize: _fontSize - 4,
                              fontWeight: FontWeight.w800,
                              color: _gold,
                              fontFamily: 'Georgia'),
                        ),
                        TextSpan(
                          text: verses[i - 1],
                          style: TextStyle(
                              fontSize: _fontSize,
                              color: _parch,
                              fontFamily: 'Georgia',
                              height: 1.75),
                        ),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),

        // Chapter nav bar
        Container(
          decoration: BoxDecoration(
            color: _surface,
            border: Border(top: BorderSide(color: _dimLine)),
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 12),
          child: Row(children: [
            _NavButton(
                icon: Icons.arrow_back_ios_rounded,
                enabled: _chapter > 0,
                onTap: _prev),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Chapter ${_chapter + 1}',
                      style: const TextStyle(
                          color: _parch,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Georgia')),
                  Text(
                      '${book.chapters[_chapter].length} verses',
                      style: const TextStyle(
                          color: _muted, fontSize: 11)),
                ],
              ),
            ),
            _NavButton(
                icon: Icons.arrow_forward_ios_rounded,
                enabled: _chapter < book.chapterCount - 1,
                onTap: _next),
          ]),
        ),
      ]),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _NavButton(
      {required this.icon,
      required this.enabled,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: enabled ? _goldGlow : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon,
                color: enabled ? _gold : _muted, size: 18),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _GoldCircle extends StatelessWidget {
  final Widget child;
  const _GoldCircle({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _goldGlow,
          border: Border.all(color: _gold.withOpacity(0.25)),
        ),
        child: child,
      );
}

class _TestamentHeader extends StatelessWidget {
  final String title;
  final int count;
  const _TestamentHeader(
      {required this.title, required this.count});

  @override
  Widget build(BuildContext context) =>
      Row(children: [
        Container(
            width: 3,
            height: 18,
            color: _gold,
            margin: const EdgeInsets.only(right: 10)),
        Text(title,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _gold,
                letterSpacing: 2)),
        const SizedBox(width: 8),
        Text('$count books',
            style:
                const TextStyle(fontSize: 11, color: _muted)),
        const Spacer(),
        Container(
            width: 80,
            height: 1,
            color: _gold.withOpacity(0.18)),
      ]);
}

class _BookRow extends StatelessWidget {
  final BibleBook book;
  final VoidCallback onTap;
  const _BookRow({required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            splashColor: _goldGlow,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _dimLine),
              ),
              child: Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      color: _goldGlow,
                      borderRadius:
                          BorderRadius.circular(10)),
                  child: Center(
                    child: Text(book.shortTag,
                        style: const TextStyle(
                            color: _gold,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: 0.5)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                    Text(book.name,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _parch,
                            fontFamily: 'Georgia')),
                    const SizedBox(height: 2),
                    Text(
                        '${book.chapterCount} ch · ${book.verseCount} verses',
                        style: const TextStyle(
                            fontSize: 11, color: _muted)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: _muted, size: 18),
              ]),
            ),
          ),
        ),
      );
}
