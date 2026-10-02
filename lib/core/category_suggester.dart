/// [REF: CATEGORY_SUGGESTER]
/// Offline keyword rules that propose a checklist category from a business name
/// (D6).
///
/// Deliberately pure Dart — no Flutter import, no Hive, no Firestore — because
/// this is the one piece of the picker whose output lands on a government audit
/// record, and it has to be testable without a device, a box or a network.
///
/// Three properties the rest of the design leans on:
///
///  * **Explainable.** A suggestion carries the keyword that produced it, so the
///    UI can say *why* it suggested what it did. An inspector who can see
///    "matched 'eatery'" can judge the guess; one shown a bare pre-filled
///    category cannot.
///  * **Deterministic.** The rules are a `List`, not a `Map`, and the winner is
///    picked by an explicit documented policy — never by iteration order. The
///    same business name must produce the same suggestion on every phone and in
///    every release, or the audit trail stops being reproducible.
///  * **Silent on no match.** There is no catch-all and no default. A wrong
///    pre-filled category on an inspection record is worse than an empty one.
library;

/// A single keyword rule, keyed on the `categories` **document id**.
///
/// This file is the one place in Dart where database ids appear as literals,
/// and that is a deliberate trade, not an oversight: category *names* are
/// mutable — Chunk 2.5 renamed two of them, having found that `'2' 'Water'`
/// had been holding the SUPERMARKETS checklist all along — while the doc ids
/// have never changed and were the only identity in that collection that was
/// never a lie.
class CategoryKeywordRule {
  /// `categories/{id}`.
  final String categoryId;

  /// Lower-case. May contain spaces; `ice cream` and `public market` are
  /// phrases, matched as written.
  final String keyword;

  /// When true the keyword must end on a word boundary as well as start on one
  /// (a trailing plural `s` is still allowed). See [CategorySuggester] for why
  /// short keywords must set this.
  final bool wholeWord;

  const CategoryKeywordRule(
    this.categoryId,
    this.keyword, {
    this.wholeWord = false,
  });
}

/// What the suggester found: which category, and the keyword that earned it.
class CategorySuggestion {
  final String categoryId;
  final String keyword;

  const CategorySuggestion({required this.categoryId, required this.keyword});

  @override
  String toString() => 'CategorySuggestion($categoryId, "$keyword")';

  @override
  bool operator ==(Object other) =>
      other is CategorySuggestion &&
      other.categoryId == categoryId &&
      other.keyword == keyword;

  @override
  int get hashCode => Object.hash(categoryId, keyword);
}

class CategorySuggester {
  CategorySuggester._();

  /// A keyword this short or shorter must set [CategoryKeywordRule.wholeWord].
  ///
  /// Both modes require a word boundary *before* the keyword, so neither can
  /// fire mid-word — `inn` never matches "Dinner Bell", nor `port`
  /// "Transport". What the default mode allows is a keyword that starts a word
  /// and then runs on, which is what makes `restaurant` fire on `Restaurante`
  /// and `burger` on the live record spelled `Burgerking`. That generosity is
  /// wrong for a short keyword: `inn` would fire on "Innocent Trading", `spa`
  /// on "Spangle Supplies" and `ship` on "Shipshape Cleaners", suggesting a
  /// hotel checklist for a canteen. Whole-word mode closes the tail as well;
  /// the optional trailing `s` keeps `Pools` and `Spas` working.
  ///
  /// Four is the floor this table happens to need, not a law — most five- and
  /// six-letter keywords here are whole-word too. `category_suggester_test.dart`
  /// asserts it over every rule, so a short keyword added later cannot
  /// reintroduce the false positive quietly.
  static const int wholeWordRequiredUpToLength = 4;

  // [REF: CATEGORY_SUGGESTER_RULES]
  /// Ordering is part of the contract: see [suggestFor] for the tiebreak.
  ///
  /// `'17'` Livestock Farm has **no rules on purpose.** Its templates are all
  /// weight 0 (D22), so the picker renders it unselectable (D25) and a
  /// suggestion pointing at it could never be accepted — a dead suggestion is a
  /// worse experience than none. When a demerit weighting is finally published
  /// for that form, add `piggery`, `poultry`, `livestock`, `farm`, `hatchery`
  /// and `feedlot` here; nothing else needs to change.
  static const List<CategoryKeywordRule> rules = [
    // ── '1' Food ────────────────────────────────────────────────────────────
    CategoryKeywordRule('1', 'eatery'),
    CategoryKeywordRule('1', 'karinderya'),
    CategoryKeywordRule('1', 'carinderia'),
    CategoryKeywordRule('1', 'kainan', wholeWord: true),
    CategoryKeywordRule('1', 'turo-turo'),
    CategoryKeywordRule('1', 'restaurant'),
    CategoryKeywordRule('1', 'resto', wholeWord: true),
    CategoryKeywordRule('1', 'canteen'),
    CategoryKeywordRule('1', 'cafeteria'),
    CategoryKeywordRule('1', 'cafe', wholeWord: true),
    CategoryKeywordRule('1', 'coffee', wholeWord: true),
    CategoryKeywordRule('1', 'bakery'),
    CategoryKeywordRule('1', 'bakeshop'),
    CategoryKeywordRule('1', 'panaderia'),
    CategoryKeywordRule('1', 'panciteria'),
    CategoryKeywordRule('1', 'grill', wholeWord: true),
    CategoryKeywordRule('1', 'grillhouse'),
    CategoryKeywordRule('1', 'barbecue'),
    CategoryKeywordRule('1', 'bbq', wholeWord: true),
    CategoryKeywordRule('1', 'lechon', wholeWord: true),
    CategoryKeywordRule('1', 'catering'),
    CategoryKeywordRule('1', 'caterer'),
    CategoryKeywordRule('1', 'food court'),
    CategoryKeywordRule('1', 'fast food'),
    CategoryKeywordRule('1', 'food', wholeWord: true),
    CategoryKeywordRule('1', 'snack', wholeWord: true),
    CategoryKeywordRule('1', 'refreshment'),
    CategoryKeywordRule('1', 'ice cream'),
    CategoryKeywordRule('1', 'ice candy'),
    CategoryKeywordRule('1', 'milk tea'),
    CategoryKeywordRule('1', 'milktea'),
    CategoryKeywordRule('1', 'juice', wholeWord: true),
    CategoryKeywordRule('1', 'pizza', wholeWord: true),
    CategoryKeywordRule('1', 'burger'),
    CategoryKeywordRule('1', 'chicken'),
    CategoryKeywordRule('1', 'kitchen'),
    CategoryKeywordRule('1', 'silog', wholeWord: true),
    CategoryKeywordRule('1', 'lugawan'),
    // Brands. Worth carrying explicitly: a branch named only "Jollibee" or
    // "MCDO" — both real records in the live data — matches nothing generic.
    CategoryKeywordRule('1', 'jollibee'),
    CategoryKeywordRule('1', 'mcdonald'),
    CategoryKeywordRule('1', 'mcdo', wholeWord: true),
    CategoryKeywordRule('1', 'kfc', wholeWord: true),
    CategoryKeywordRule('1', 'chowking'),
    CategoryKeywordRule('1', 'greenwich'),
    CategoryKeywordRule('1', 'starbucks'),
    CategoryKeywordRule('1', 'dunkin'),
    CategoryKeywordRule('1', 'burger king'),
    CategoryKeywordRule('1', 'shakey'),
    CategoryKeywordRule('1', 'mang inasal'),
    CategoryKeywordRule('1', 'inasal'),
    CategoryKeywordRule('1', 'bonchon'),

    // ── '2' Supermarkets ────────────────────────────────────────────────────
    // `supermarket` outranks `'3'`'s `market` by length, and `market` cannot
    // fire inside "Supermarket" anyway — the default mode still requires a word
    // boundary *before* the keyword.
    CategoryKeywordRule('2', 'supermarket'),
    CategoryKeywordRule('2', 'hypermarket'),
    CategoryKeywordRule('2', 'grocery'),
    CategoryKeywordRule('2', 'groceries'),
    CategoryKeywordRule('2', 'mini mart'),
    CategoryKeywordRule('2', 'minimart'),
    CategoryKeywordRule('2', 'convenience store'),
    CategoryKeywordRule('2', '7-eleven'),
    CategoryKeywordRule('2', 'alfamart'),
    CategoryKeywordRule('2', 'puregold'),
    CategoryKeywordRule('2', 'savemore'),

    // ── '12' Laundry Establishments ─────────────────────────────────────────
    CategoryKeywordRule('12', 'laundromat'),
    CategoryKeywordRule('12', 'laundry'),
    CategoryKeywordRule('12', 'labahan'),
    CategoryKeywordRule('12', 'dry cleaning'),
    CategoryKeywordRule('12', 'dry clean'),

    // ── '13' Hotels, Motels, Apartments, Condominiums, Transient Houses ─────
    CategoryKeywordRule('13', 'hotel', wholeWord: true),
    CategoryKeywordRule('13', 'motel', wholeWord: true),
    CategoryKeywordRule('13', 'hostel', wholeWord: true),
    CategoryKeywordRule('13', 'inn', wholeWord: true),
    CategoryKeywordRule('13', 'lodge', wholeWord: true),
    CategoryKeywordRule('13', 'lodging'),
    CategoryKeywordRule('13', 'apartelle'),
    CategoryKeywordRule('13', 'apartment'),
    CategoryKeywordRule('13', 'condominium'),
    CategoryKeywordRule('13', 'condo', wholeWord: true),
    CategoryKeywordRule('13', 'transient'),
    CategoryKeywordRule('13', 'pension'),
    CategoryKeywordRule('13', 'dormitory'),

    // ── '11' Swimming Pool and Bathhouse ────────────────────────────────────
    // `resort` is genuinely ambiguous against '13' — a resort rents rooms as
    // well as operating a pool. It goes here because the city's own assignment
    // is the precedent: the live `Brizamar beach resort` is categorised
    // Swimming Pool and Bathhouse. `beach` follows the same record.
    CategoryKeywordRule('11', 'swimming'),
    CategoryKeywordRule('11', 'pool', wholeWord: true),
    CategoryKeywordRule('11', 'bathhouse'),
    CategoryKeywordRule('11', 'bath house'),
    CategoryKeywordRule('11', 'waterpark'),
    CategoryKeywordRule('11', 'water park'),
    CategoryKeywordRule('11', 'resort'),
    CategoryKeywordRule('11', 'beach', wholeWord: true),
    CategoryKeywordRule('11', 'spa', wholeWord: true),
    CategoryKeywordRule('11', 'sauna', wholeWord: true),

    // ── '3' Public Places ───────────────────────────────────────────────────
    // `terminal` is the other real ambiguity, against '15' Port. It lands here
    // because '15' is the checklist for a maritime facility and already owns
    // `port`, `pier`, `wharf` and `jetty`; an unqualified "terminal" in an LGU
    // masterlist is far more often a land transport terminal, which is a public
    // place. A ferry terminal therefore mis-suggests — accepted, because it is
    // one tap to override and the matched keyword is shown.
    CategoryKeywordRule('3', 'public market'),
    CategoryKeywordRule('3', 'market', wholeWord: true),
    CategoryKeywordRule('3', 'terminal'),
    CategoryKeywordRule('3', 'plaza', wholeWord: true),
    CategoryKeywordRule('3', 'mall', wholeWord: true),
    CategoryKeywordRule('3', 'cemetery'),
    CategoryKeywordRule('3', 'memorial park'),
    CategoryKeywordRule('3', 'church', wholeWord: true),
    CategoryKeywordRule('3', 'chapel', wholeWord: true),
    CategoryKeywordRule('3', 'barbershop'),
    CategoryKeywordRule('3', 'barber shop'),
    CategoryKeywordRule('3', 'salon', wholeWord: true),
    // "Refreshment Parlor" is a real LGU line-of-business string, so `parlor`
    // has to lose to '1' `refreshment` — and does, on length alone.
    CategoryKeywordRule('3', 'parlor', wholeWord: true),
    CategoryKeywordRule('3', 'parlour', wholeWord: true),

    // ── '16' Day Care, Pre-School, Children's Institution ───────────────────
    CategoryKeywordRule('16', 'day care'),
    CategoryKeywordRule('16', 'daycare'),
    CategoryKeywordRule('16', 'pre-school'),
    CategoryKeywordRule('16', 'preschool'),
    CategoryKeywordRule('16', 'nursery'),
    CategoryKeywordRule('16', 'kindergarten'),
    CategoryKeywordRule('16', 'learning center'),
    CategoryKeywordRule('16', 'learning centre'),
    CategoryKeywordRule('16', 'child care'),
    CategoryKeywordRule('16', 'childcare'),
    CategoryKeywordRule('16', 'orphanage'),

    // ── '14' Vessel ─────────────────────────────────────────────────────────
    CategoryKeywordRule('14', 'vessel'),
    CategoryKeywordRule('14', 'motor banca'),
    CategoryKeywordRule('14', 'banca', wholeWord: true),
    CategoryKeywordRule('14', 'ferry'),
    CategoryKeywordRule('14', 'barge', wholeWord: true),
    CategoryKeywordRule('14', 'ship', wholeWord: true),
    CategoryKeywordRule('14', 'boat', wholeWord: true),
    CategoryKeywordRule('14', 'ro-ro', wholeWord: true),
    CategoryKeywordRule('14', 'roro', wholeWord: true),

    // ── '15' Port ───────────────────────────────────────────────────────────
    CategoryKeywordRule('15', 'seaport'),
    CategoryKeywordRule('15', 'port', wholeWord: true),
    CategoryKeywordRule('15', 'pier', wholeWord: true),
    CategoryKeywordRule('15', 'wharf', wholeWord: true),
    CategoryKeywordRule('15', 'jetty', wholeWord: true),
  ];

  /// Suggests a category for [businessName], or `null`.
  ///
  /// [availableCategoryIds] is required rather than optional because validating
  /// the suggestion is not a courtesy the caller may skip: a rule may point at
  /// a category that has since been deleted from Firestore, has no checklist on
  /// this device, or is unselectable for want of a demerit weighting (D25).
  /// Offering any of those would hand the inspector a suggestion they cannot
  /// act on.
  ///
  /// The gate is applied **after** the winner is chosen, not by filtering the
  /// rules first. That costs a suggestion in the rare case where the best
  /// keyword points somewhere unavailable, and the alternative — falling
  /// through to the next-best rule — was rejected: it would make the same
  /// business name suggest different categories on two phones with different
  /// sync states, which is exactly the reproducibility this module exists to
  /// provide. Degrading to *no* suggestion is the honest failure.
  static CategorySuggestion? suggestFor(
    String businessName, {
    required Iterable<String> availableCategoryIds,
  }) {
    final match = _bestMatch(businessName);
    if (match == null) return null;

    final available = availableCategoryIds.toSet();
    return available.contains(match.categoryId) ? match : null;
  }

  /// Tiebreak policy, in order: the **longest** keyword wins, because it is the
  /// most specific evidence in the name ("public market" over "market",
  /// "refreshment" over "parlor", "burger king" over "burger"); equal lengths
  /// fall to whichever rule is declared first in [rules]. Nothing here depends
  /// on hash or `Map` iteration order.
  static CategorySuggestion? _bestMatch(String businessName) {
    final haystack = _normalize(businessName);
    if (haystack.isEmpty) return null;

    _CompiledRule? best;
    for (final rule in _compiled) {
      if (rule.keyword.length <= (best?.keyword.length ?? 0)) continue;
      if (rule.pattern.hasMatch(haystack)) best = rule;
    }

    return best == null
        ? null
        : CategorySuggestion(categoryId: best.categoryId, keyword: best.keyword);
  }

  /// Lower-cases and collapses whitespace runs, so a phrase keyword still
  /// matches a name typed with a stray double space.
  static String _normalize(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static final List<_CompiledRule> _compiled =
      rules.map(_CompiledRule.of).toList(growable: false);
}

/// A rule with its matcher built once, at first use, rather than per call.
class _CompiledRule {
  final String categoryId;
  final String keyword;
  final RegExp pattern;

  const _CompiledRule(this.categoryId, this.keyword, this.pattern);

  factory _CompiledRule.of(CategoryKeywordRule rule) {
    // Boundaries are expressed as consuming groups rather than lookbehind:
    // `hasMatch` never needs the match offsets, and this keeps the pattern to
    // syntax every Dart RegExp backend has always supported.
    const before = r'(^|[^a-z0-9])';
    final after = rule.wholeWord ? r's?([^a-z0-9]|$)' : '';
    return _CompiledRule(
      rule.categoryId,
      rule.keyword,
      RegExp('$before${_escape(rule.keyword)}$after'),
    );
  }

  /// Hand-rolled rather than `RegExp.escape`, so the keyword table can take a
  /// name with a bracket or a dot in it without this file needing to care.
  static String _escape(String literal) => literal.replaceAllMapped(
        RegExp(r'[\\^$.|?*+()\[\]{}]'),
        (m) => '\\${m[0]}',
      );
}
