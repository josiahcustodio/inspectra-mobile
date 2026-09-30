import 'package:flutter/foundation.dart';
import '../core/rating_scale.dart';
import '../data/models/checklist_template.dart';

class RatingProvider extends ChangeNotifier {
  Map<String, String> answers = {};
  Map<String, String> itemNotes = {};

  final Map<String, int> _weights = {};

  /// Atomically resets all state and initializes weights from [templates],
  /// so there is no partially-initialized state window during rapid navigation.
  void init(List<ChecklistTemplate> templates) {
    answers.clear();
    itemNotes.clear();
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
    _weights.clear();
    notifyListeners();
  }

  void setAnswer(String itemId, String answer) {
    answers[itemId] = answer;
    if (answer == 'Pass') {
      itemNotes.remove(itemId);
    }
    notifyListeners();
  }

  void setNote(String itemId, String note) {
    itemNotes[itemId] = note;
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
