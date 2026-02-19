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

/// ---------------------- SCREEN 1: BOOK SELECTION ----------------------
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
            icon: const Icon(Icons.bookmark),
            tooltip: 'Saved Verses',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedVersesScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.notes),
            tooltip: 'All Notes',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AllNotesScreen())),
          ),
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

/// ---------------------- SCREEN 2: CHAPTER VIEW ----------------------
class ChapterViewScreen extends StatefulWidget {
  final String book;
  final int chapter;
  const ChapterViewScreen({super.key, required this.book, required this.chapter});

  @override
  State<ChapterViewScreen> createState() => _ChapterViewScreenState();
}

class _ChapterViewScreenState extends State<ChapterViewScreen> {
  List<Map<String, dynamic>> verses = [];
  Set<String> selectedVerses = {};
  late Box box;

  @override
  void initState() {
    super.initState();
    box = Hive.box('bibleBox');
    fetchChapter(widget.book, widget.chapter);
  }

  String keyFor(int verse) => "${widget.book}_${widget.chapter}_$verse";

  Future<void> fetchChapter(String book, int chapter) async {
    final res = await http.get(Uri.parse('https://bible-api.com/$book+$chapter?translation=kjv'));
    final data = jsonDecode(res.body);

    setState(() {
      verses = (data['verses'] as List).map((v) {
        return {
          'verse': v['verse'],
          // Removing unnecessary line breaks
          'text': v['text'].toString().replaceAll(RegExp(r'\n+'), ' ').trim(),
        };
      }).toList();
    });
    updateVersesFromBox();
  }

  void updateVersesFromBox() {
    final highlights = box.get('highlights', defaultValue: <String, int>{});
    final savedMap = box.get('saved_verses_map', defaultValue: <String, dynamic>{});
    
    setState(() {
      for (var v in verses) {
        final key = keyFor(v['verse']);
        v['saved'] = savedMap.containsKey(key);
        v['color'] = highlights[key] != null ? Color(highlights[key]) : null;
      }
    });
  }

  void clearSelection() {
    setState(() {
      selectedVerses.clear();
    });
  }

  void showVerseActionDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Actions (${selectedVerses.length} selected)"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Highlight Color:", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
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
                      final map = Map<String, int>.from(box.get('highlights', defaultValue: {}));
                      for (var key in selectedVerses) {
                        if (c == null) {
                          map.remove(key);
                        } else {
                          map[key] = c.value;
                        }
                      }
                      box.put('highlights', map);
                      updateVersesFromBox();
                      Navigator.pop(context);
                      clearSelection();
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c ?? Colors.transparent,
                        border: Border.all(
                            color: c == null ? Colors.grey : Colors.transparent,
                            width: 2),
                      ),
                      child: c == null ? const Icon(Icons.format_color_reset, size: 20, color: Colors.grey) : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.edit_note),
                label: const Text("Add/Edit Verse Note"),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => AddNoteScreen(keys: selectedVerses.toList())),
                  ).then((_) => updateVersesFromBox());
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.notes),
                label: const Text("View Notes"),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ViewNoteScreen(keys: selectedVerses.toList())),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.bookmark_add),
                label: const Text("Save / Unsave Verse(s)"),
                onPressed: () {
                  final savedMap = Map<String, String>.from(box.get('saved_verses_map', defaultValue: {}));
                  bool allSaved = selectedVerses.every((k) => savedMap.containsKey(k));

                  for (var key in selectedVerses) {
                    if (allSaved) {
                      savedMap.remove(key);
                    } else {
                      final verseData = verses.firstWhere((v) => keyFor(v['verse']) == key);
                      savedMap[key] = verseData['text'];
                    }
                  }
                  box.put('saved_verses_map', savedMap);
                  updateVersesFromBox();
                  Navigator.pop(context);
                  clearSelection();
                },
              ),
            ),
          ],
        ),
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
          final key = keyFor(v['verse']);
          final isSelected = selectedVerses.contains(key);

          return Container(
            color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: SelectableText.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: "${v['verse']}. ",
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        setState(() {
                          if (isSelected) {
                            selectedVerses.remove(key);
                          } else {
                            selectedVerses.add(key);
                          }
                        });
                      },
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
      floatingActionButton: selectedVerses.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: showVerseActionDialog,
              icon: const Icon(Icons.edit),
              label: Text("Actions (${selectedVerses.length})"),
            )
          : null,
    );
  }
}

/// ---------------------- SCREEN 3: ADD VERSE NOTE ----------------------
class AddNoteScreen extends StatefulWidget {
  final List<String> keys;
  const AddNoteScreen({super.key, required this.keys});

  @override
  State<AddNoteScreen> createState() => _AddNoteScreenState();
}

class _AddNoteScreenState extends State<AddNoteScreen> {
  final TextEditingController _controller = TextEditingController();
  late Box box;

  @override
  void initState() {
    super.initState();
    box = Hive.box('bibleBox');
    if (widget.keys.length == 1) {
      final notes = Map<String, String>.from(box.get('notes', defaultValue: {}));
      _controller.text = notes[widget.keys.first] ?? "";
    }
  }

  void saveNote() {
    final notes = Map<String, String>.from(box.get('notes', defaultValue: {}));
    final text = _controller.text.trim();
    for (var key in widget.keys) {
      if (text.isEmpty) {
        notes.remove(key);
      } else {
        notes[key] = text;
      }
    }
    box.put('notes', notes);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Verse Note")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Adding note to ${widget.keys.length} verse(s)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: "Write your thoughts on this verse...",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: saveNote,
                child: const Text("Save Note"),
              ),
            )
          ],
        ),
      ),
    );
  }
}

/// ---------------------- SCREEN 4: VIEW SPECIFIC NOTES ----------------------
class ViewNoteScreen extends StatelessWidget {
  final List<String> keys;
  const ViewNoteScreen({super.key, required this.keys});

  @override
  Widget build(BuildContext context) {
    final box = Hive.box('bibleBox');
    final notes = Map<String, String>.from(box.get('notes', defaultValue: {}));
    
    final relevantNotes = keys.where((k) => notes.containsKey(k)).map((k) {
      final parts = k.split('_');
      return {"ref": "${parts[0]} ${parts[1]}:${parts[2]}", "note": notes[k]};
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text("View Notes")),
      body: relevantNotes.isEmpty
          ? const Center(child: Text("No notes saved for the selected verse(s)."))
          : ListView.builder(
              itemCount: relevantNotes.length,
              itemBuilder: (context, index) {
                final item = relevantNotes[index];
                return ListTile(
                  title: Text(item['ref']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  subtitle: Text(item['note']!),
                );
              },
            ),
    );
  }
}

/// ---------------------- SCREEN 5: SAVED VERSES LIST ----------------------
class SavedVersesScreen extends StatelessWidget {
  const SavedVersesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final box = Hive.box('bibleBox');
    final savedMap = Map<String, String>.from(box.get('saved_verses_map', defaultValue: {}));
    final keys = savedMap.keys.toList();

    return Scaffold(
      appBar: AppBar(title: const Text("Saved Verses")),
      body: keys.isEmpty
          ? const Center(child: Text("No saved verses yet."))
          : ListView.builder(
              itemCount: keys.length,
              itemBuilder: (context, index) {
                final key = keys[index];
                final text = savedMap[key]!;
                final parts = key.split('_');
                final ref = "${parts[0]} ${parts[1]}:${parts[2]}";
                return ListTile(
                  title: Text(ref, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  subtitle: Text(text),
                );
              },
            ),
    );
  }
}

/// ---------------------- SCREEN 6: ALL NOTES LIST ----------------------
class AllNotesScreen extends StatelessWidget {
  const AllNotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final box = Hive.box('bibleBox');
    final notes = Map<String, String>.from(box.get('notes', defaultValue: {}));
    final keys = notes.keys.toList();

    return Scaffold(
      appBar: AppBar(title: const Text("All Verse Notes")),
      body: keys.isEmpty
          ? const Center(child: Text("You haven't added any notes yet."))
          : ListView.builder(
              itemCount: keys.length,
              itemBuilder: (context, index) {
                final key = keys[index];
                final note = notes[key]!;
                final parts = key.split('_');
                final ref = "${parts[0]} ${parts[1]}:${parts[2]}";
                return ListTile(
                  title: Text(ref, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  subtitle: Text(note),
                );
              },
            ),
    );
  }
}