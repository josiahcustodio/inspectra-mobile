import 'package:flutter/foundation.dart';
import '../data/models/checklist_template.dart';

class RatingProvider extends ChangeNotifier {
  Map<String, String> answers = {};
  Map<String, String> itemNotes = {};

  final Map<String, int> _weights = {};

  /// Atomically resets all state and initializes weights from [templates].
  /// Prefer this over calling reset() + initWeights() separately to avoid
  /// a partially-initialized state window during rapid navigation.
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

  void initWeights(List<ChecklistTemplate> templates) {
    for (var t in templates) {
      _weights[t.id] = t.weight;
    }
  }

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

  String get ratingLabel {
    final currentScore = score;
    if (currentScore == null) return 'Not Scored Yet';
    
    if (currentScore >= 90) return 'Excellent';
    if (currentScore >= 70) return 'Very Satisfactory';
    if (currentScore >= 50) return 'Satisfactory';
    return 'Action Required';
  }
}
