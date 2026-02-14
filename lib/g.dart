import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bible App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const BookSelectionScreen(),
    );
  }
}

/// ---------------------- SCREEN 1 ----------------------
/// Book & Chapter Selection Screen
class BookSelectionScreen extends StatefulWidget {
  const BookSelectionScreen({super.key});

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
    Map<String,int> chapterCounts = {
      "Genesis":50, "Exodus":40, "Leviticus":27, "Numbers":36, "Deuteronomy":34,
      "Joshua":24, "Judges":21, "Ruth":4, "1 Samuel":31, "2 Samuel":24,
      "1 Kings":22, "2 Kings":25, "1 Chronicles":29, "2 Chronicles":36, "Ezra":10,
      "Nehemiah":13, "Esther":10, "Job":42, "Psalms":150, "Proverbs":31, "Ecclesiastes":12,
      "Song of Solomon":8, "Isaiah":66, "Jeremiah":52, "Lamentations":5, "Ezekiel":48,
      "Daniel":12, "Hosea":14, "Joel":3, "Amos":9, "Obadiah":1, "Jonah":4, "Micah":7,
      "Nahum":3, "Habakkuk":3, "Zephaniah":3, "Haggai":2, "Zechariah":14, "Malachi":4,
      "Matthew":28,"Mark":16,"Luke":24,"John":21,"Acts":28,"Romans":16,"1 Corinthians":16,
      "2 Corinthians":13,"Galatians":6,"Ephesians":6,"Philippians":4,"Colossians":4,
      "1 Thessalonians":5,"2 Thessalonians":3,"1 Timothy":6,"2 Timothy":4,"Titus":3,
      "Philemon":1,"Hebrews":13,"James":5,"1 Peter":5,"2 Peter":3,"1 John":5,"2 John":1,
      "3 John":1,"Jude":1,"Revelation":22
    };
    return chapterCounts[book] ?? 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Select Book & Chapter")),
      body: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: books.length,
        itemBuilder: (context, index) {
          final book = books[index];
          final isExpanded = expandedBook == book;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    expandedBook = (expandedBook == book) ? null : book;
                  });
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  color: Colors.grey[300],
                  child: Text(
                    book,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              if (isExpanded)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 6,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                      childAspectRatio: 1.5,
                    ),
                    itemCount: getChapterCount(book),
                    itemBuilder: (context, chapterIndex) {
                      final chapterNum = chapterIndex + 1;
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChapterViewScreen(
                                book: book,
                                chapter: chapterNum,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text("$chapterNum"),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// ---------------------- SCREEN 2 ----------------------
/// Chapter View Screen
class ChapterViewScreen extends StatefulWidget {
  final String book;
  final int chapter;
  const ChapterViewScreen({super.key, required this.book, required this.chapter});

  @override
  State<ChapterViewScreen> createState() => _ChapterViewScreenState();
}

class _ChapterViewScreenState extends State<ChapterViewScreen> {
  List<Map<String, dynamic>> verses = [];

  @override
  void initState() {
    super.initState();
    fetchChapter(widget.book, widget.chapter);
  }

  Future<void> fetchChapter(String book, int chapter) async {
    try {
      final reference = "$book+$chapter";
      final response = await http.get(
        Uri.parse('https://bible-api.com/$reference?translation=kjv'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final apiVerses = data['verses'] as List;

        setState(() {
          verses = apiVerses.map((v) {
            String text = v['text']
                .replaceAll('“', '"')
                .replaceAll('”', '"')
                .replaceAll('‘', "'")
                .replaceAll('’', "'");
            return {
              'verse': v['verse'],
              'text': text.trim(),
              'color': null,
            };
          }).toList();
        });
      } else {
        setState(() {
          verses = [
            {'verse': 0, 'text': 'Error fetching chapter: ${response.statusCode}', 'color': null}
          ];
        });
      }
    } catch (e) {
      setState(() {
        verses = [
          {'verse': 0, 'text': 'Error: $e', 'color': null}
        ];
      });
    }
  }

  Future<void> showHighlightDialog(int index) async {
    Color? selectedColor = await showDialog<Color>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Highlight Verse?"),
          content: Wrap(
            spacing: 10,
            children: [
              _colorOption(Colors.yellow, context),
              _colorOption(Colors.greenAccent, context),
              _colorOption(Colors.orangeAccent, context),
              _colorOption(Colors.cyanAccent, context),
              _colorOption(Colors.pinkAccent, context),
              _colorOption(null, context),
            ],
          ),
        );
      },
    );

    setState(() {
      verses[index]['color'] = selectedColor;
    });
  }

  Widget _colorOption(Color? color, BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, color),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color ?? Colors.transparent,
          border: Border.all(color: Colors.black),
        ),
        child: color == null ? const Icon(Icons.clear, size: 18) : null,
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("${widget.book} ${widget.chapter}")),
      body: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: verses.length,
        itemBuilder: (context, index) {
          final verse = verses[index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: SelectableText.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: "${verse['verse']}. ",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => showHighlightDialog(index),
                  ),
                  TextSpan(
                    text: verse['text'],
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.5,
                      backgroundColor: verse['color'],
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