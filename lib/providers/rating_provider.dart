import 'package:flutter/foundation.dart';
import '../core/rating_scale.dart';
import '../data/models/checklist_template.dart';

class RatingProvider extends ChangeNotifier {
  Map<String, String> answers = {};
  Map<String, String> itemNotes = {};

  /// The right-hand column of the Sanitary Order: what the establishment is
  /// ordered to do about each defect. Keyed and cleared exactly like
  /// [itemNotes] — the two are the two halves of one table row, and a row with
  /// only one half filled is not an order anyone can comply with.
  Map<String, String> itemCorrections = {};

  /// The item's extra inputs ([ChecklistField]), keyed by item id then field
  /// label. Optional on every item and independent of the verdict, so unlike
  /// the two maps above these survive an answer change.
  Map<String, Map<String, dynamic>> itemValues = {};

  final Map<String, int> _weights = {};

  /// Atomically resets all state and initializes weights from [templates],
  /// so there is no partially-initialized state window during rapid navigation.
  void init(List<ChecklistTemplate> templates) {
    answers.clear();
    itemNotes.clear();
    itemCorrections.clear();
    itemValues.clear();
    _weights.clear();
    for (var t in templates) {
      _weights[t.id] = t.weight;
    }
    // Single notify after the state is fully valid
    notifyListeners();
  }

  void reset() {
    answers.clear();
    itemNotes.clear();
    itemCorrections.clear();
    itemValues.clear();
    _weights.clear();
    notifyListeners();
  }

  // [REF: ANSWER_CLEARS_DEFECT_TEXT]
  /// Anything other than 'Fail' withdraws the deficiency, so its text goes
  /// with it.
  ///
  /// This used to clear only on 'Pass'. A Fail flipped to N/A kept its note,
  /// and the note survived into the log's `remarks` block, which selects by
  /// note text rather than by answer. Harmless-looking until that text became
  /// the "Sanitary Defect / Violation" column of a legal order: a deficiency
  /// the inspector had already taken back would print as a cited violation.
  void setAnswer(String itemId, String answer) {
    answers[itemId] = answer;
    if (answer != 'Fail') {
      itemNotes.remove(itemId);
      itemCorrections.remove(itemId);
    }
    notifyListeners();
  }

  void setNote(String itemId, String note) {
    itemNotes[itemId] = note;
    notifyListeners();
  }

  void setCorrection(String itemId, String correction) {
    itemCorrections[itemId] = correction;
    notifyListeners();
  }

  void setValue(String itemId, String label, dynamic value) {
    (itemValues[itemId] ??= {})[label] = value;
    notifyListeners();
  }

  // [REF: SCORING_ENGINE]
  int get totalDemerits {
    int totalPenalty = 0;
    answers.forEach((itemId, ans) {
      if (ans == 'Fail') {
        totalPenalty += _weights[itemId] ?? 5; // fallback to 5
      }
    });
    return totalPenalty;
  }

  int? get score {
    // If weights map is empty, we can't score. Wait until initialized.
    if (_weights.isEmpty) return null;
    
    // We must answer ALL items initialized in weights
    if (answers.length < _weights.length) return null;

    return (100 - totalDemerits).clamp(0, 100);
  }

  bool get isCompleted => score != null;

  // [REF: RATING_LABEL]
  /// Band label for the current score. The bands themselves live in
  /// [RatingScale] so the app and the web dashboard cannot drift apart.
  String get ratingLabel => RatingScale.labelOf(score);
}
