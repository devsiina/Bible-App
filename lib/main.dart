import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  await Hive.openBox('bibleBox'); // single box, no adapters
  runApp(const MyApp());
}

/// ---------------------- APP ROOT ----------------------
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Box box;
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    box = Hive.box('bibleBox');
    _isDarkMode = box.get('darkMode', defaultValue: false);
  }

  void _toggleTheme() {
    setState(() {
      _isDarkMode = !_isDarkMode;
      box.put('darkMode', _isDarkMode);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bible App',
      theme: _isDarkMode ? ThemeData.dark() : ThemeData.light(),
      home: BookSelectionScreen(toggleTheme: _toggleTheme),
    );
  }
}

/// ---------------------- SCREEN 1 ----------------------
class BookSelectionScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  const BookSelectionScreen({super.key, required this.toggleTheme});

  @override
  State<BookSelectionScreen> createState() => _BookSelectionScreenState();
}

class _BookSelectionScreenState extends State<BookSelectionScreen> {
  String? expandedBook;

  static const List<String> books = [
    "Genesis","Exodus","Leviticus","Numbers","Deuteronomy","Joshua","Judges","Ruth",
    "1 Samuel","2 Samuel","1 Kings","2 Kings","1 Chronicles","2 Chronicles","Ezra",
    "Nehemiah","Esther","Job","Psalms","Proverbs","Ecclesiastes","Song of Solomon",
    "Isaiah","Jeremiah","Lamentations","Ezekiel","Daniel","Hosea","Joel","Amos",
    "Obadiah","Jonah","Micah","Nahum","Habakkuk","Zephaniah","Haggai","Zechariah",
    "Malachi","Matthew","Mark","Luke","John","Acts","Romans","1 Corinthians","2 Corinthians",
    "Galatians","Ephesians","Philippians","Colossians","1 Thessalonians","2 Thessalonians",
    "1 Timothy","2 Timothy","Titus","Philemon","Hebrews","James","1 Peter","2 Peter",
    "1 John","2 John","3 John","Jude","Revelation"
  ];

  int getChapterCount(String book) {
    final map = {
      "Genesis":50,"Exodus":40,"Leviticus":27,"Numbers":36,"Deuteronomy":34,
      "Joshua":24,"Judges":21,"Ruth":4,"1 Samuel":31,"2 Samuel":24,
      "1 Kings":22,"2 Kings":25,"1 Chronicles":29,"2 Chronicles":36,
      "Ezra":10,"Nehemiah":13,"Esther":10,"Job":42,"Psalms":150,"Proverbs":31,
      "Ecclesiastes":12,"Song of Solomon":8,"Isaiah":66,"Jeremiah":52,
      "Lamentations":5,"Ezekiel":48,"Daniel":12,"Hosea":14,"Joel":3,"Amos":9,
      "Obadiah":1,"Jonah":4,"Micah":7,"Nahum":3,"Habakkuk":3,"Zephaniah":3,
      "Haggai":2,"Zechariah":14,"Malachi":4,"Matthew":28,"Mark":16,
      "Luke":24,"John":21,"Acts":28,"Romans":16,"1 Corinthians":16,
      "2 Corinthians":13,"Galatians":6,"Ephesians":6,"Philippians":4,
      "Colossians":4,"1 Thessalonians":5,"2 Thessalonians":3,"1 Timothy":6,
      "2 Timothy":4,"Titus":3,"Philemon":1,"Hebrews":13,"James":5,
      "1 Peter":5,"2 Peter":3,"1 John":5,"2 John":1,"3 John":1,
      "Jude":1,"Revelation":22
    };
    return map[book] ?? 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Select Book & Chapter"),
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6),
            onPressed: widget.toggleTheme,
          )
        ],
      ),
      body: ListView.builder(
        itemCount: books.length,
        itemBuilder: (context, index) {
          final book = books[index];
          final expanded = expandedBook == book;

          return Column(
            children: [
              ListTile(
                title: Text(book, style: const TextStyle(fontWeight: FontWeight.bold)),
                onTap: () => setState(() {
                  expandedBook = expanded ? null : book;
                }),
              ),
              if (expanded)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: getChapterCount(book),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    childAspectRatio: 1.5,
                  ),
                  itemBuilder: (context, i) {
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChapterViewScreen(
                              book: book,
                              chapter: i + 1,
                            ),
                          ),
                        );
                      },
                      child: Card(child: Center(child: Text("${i + 1}"))),
                    );
                  },
                )
            ],
          );
        },
      ),
    );
  }
}

/// ---------------------- SCREEN 2 ----------------------
class ChapterViewScreen extends StatefulWidget {
  final String book;
  final int chapter;
  const ChapterViewScreen({super.key, required this.book, required this.chapter});

  @override
  State<ChapterViewScreen> createState() => _ChapterViewScreenState();
}

class _ChapterViewScreenState extends State<ChapterViewScreen> {
  List<Map<String, dynamic>> verses = [];
  late Box box;

  @override
  void initState() {
    super.initState();
    box = Hive.box('bibleBox');
    fetchChapter(widget.book, widget.chapter);
  }

  String keyFor(int verse) => "${widget.book}_${widget.chapter}_$verse";

  Future<void> fetchChapter(String book, int chapter) async {
    final res = await http.get(Uri.parse(
        'https://bible-api.com/$book+$chapter?translation=kjv'));
    final data = jsonDecode(res.body);

    setState(() {
      verses = (data['verses'] as List).map((v) {
        final key = keyFor(v['verse']);
        final saved = box.get('savedVerses', defaultValue: <String>[]);
        final highlights = box.get('highlights', defaultValue: <String, int>{});
        return {
          'verse': v['verse'],
          'text': v['text'].trim(),
          'saved': saved.contains(key),
          'color': highlights[key] != null
              ? Color(highlights[key])
              : null,
        };
      }).toList();
    });
  }

  void showVerseDialog(int index) {
    final verse = verses[index];
    final key = keyFor(verse['verse']);
    final noteController = TextEditingController(
        text: (box.get('notes', defaultValue: {})[key] ?? ""));

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Verse ${verse['verse']}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final c in [
                  Colors.yellow,
                  Colors.greenAccent,
                  Colors.orangeAccent,
                  Colors.cyanAccent,
                  Colors.pinkAccent,
                  null
                ])
                  GestureDetector(
                    onTap: () {
                      final map =
                          Map<String, int>.from(box.get('highlights', defaultValue: {}));
                      if (c == null) {
                        map.remove(key);
                      } else {
                        map[key] = c.value;
                      }
                      box.put('highlights', map);
                      setState(() {});
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: c,
                        border: Border.all(),
                      ),
                      child: c == null ? const Icon(Icons.clear, size: 16) : null,
                    ),
                  ),
              ],
            ),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(labelText: "Verse note"),
            )
          ],
        ),
        actions: [
          TextButton(
            child: const Text("Save Note"),
            onPressed: () {
              final notes = Map<String, String>.from(
                  box.get('notes', defaultValue: {}));
              if (noteController.text.isNotEmpty) {
                notes[key] = noteController.text;
              } else {
                notes.remove(key);
              }
              box.put('notes', notes);
              Navigator.pop(context);
            },
          ),
          TextButton(
            child: Text(verse['saved'] ? "Unsave" : "Save Verse"),
            onPressed: () {
              final saved =
                  List<String>.from(box.get('savedVerses', defaultValue: []));
              verse['saved'] ? saved.remove(key) : saved.add(key);
              box.put('savedVerses', saved);
              setState(() {});
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("${widget.book} ${widget.chapter}")),
      body: ListView.builder(
        itemCount: verses.length,
        itemBuilder: (context, i) {
          final v = verses[i];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SelectableText.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: "${v['verse']}. ",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.blue),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => showVerseDialog(i),
                  ),
                  TextSpan(
                    text: v['text'],
                    style: TextStyle(
                      backgroundColor: v['color'],
                      height: 1.4,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
