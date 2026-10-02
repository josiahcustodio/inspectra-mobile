import 'package:flutter_test/flutter_test.dart';

import 'package:clowtec_inspector/core/category_suggester.dart';

/// Every live category id. Passed as the availability set wherever a test is
/// about matching rather than about the availability gate itself.
const _allIds = {'1', '2', '3', '9', '11', '12', '13', '14', '15', '16', '17'};

CategorySuggestion? suggest(String name, {Set<String> available = _allIds}) =>
    CategorySuggester.suggestFor(name, availableCategoryIds: available);

/// Tests for the offline category suggestion rules (D6).
///
/// The suggester's output pre-fills a field on a government audit record, so
/// the properties worth pinning are not just "does it find the obvious cases":
/// they are that it stays silent when it does not know, that a short keyword
/// cannot fire inside a longer word, that the two genuinely ambiguous keywords
/// resolve the way the live data already resolved them, and that an unavailable
/// category degrades to no suggestion rather than to a different one.
///
/// Names marked "live" below are real `business_name` values from the
/// production `establishments` collection.
void main() {
  group('one clear hit per category that has rules', () {
    test('Food', () {
      expect(suggest('Zeus Eatery')?.categoryId, '1'); // live: "zeus eatery"
      expect(suggest('Lola Nena Carinderia')?.categoryId, '1');
      expect(suggest('Batangas Bakeshop')?.categoryId, '1');
    });

    test('Supermarkets', () {
      expect(suggest('Puregold Supermarket')?.categoryId, '2');
      expect(suggest('Rose Grocery Store')?.categoryId, '2');
      expect(suggest('Lucky Minimart')?.categoryId, '2');
    });

    test('Laundry Establishments', () {
      expect(suggest('Sunshine Laundry Shop')?.categoryId, '12');
      expect(suggest('Labahan ni Nanay')?.categoryId, '12');
    });

    test('Hotels, Motels, Apartments, Condominiums and Transient Houses', () {
      expect(suggest('Hotel Ventura')?.categoryId, '13');
      expect(suggest('Casa Inn')?.categoryId, '13');
      expect(suggest('Seaview Transient House')?.categoryId, '13');
    });

    test('Swimming Pool and Bathhouse', () {
      expect(suggest('Aqua Swimming Pool')?.categoryId, '11');
      expect(suggest('Marina Bathhouse')?.categoryId, '11');
    });

    test('Public Places', () {
      expect(suggest('Bauan Public Market')?.categoryId, '3');
      expect(suggest('City Plaza')?.categoryId, '3');
      expect(suggest("Tony's Barbershop")?.categoryId, '3');
    });

    test("Day Care, Pre-School and Children's Institution", () {
      expect(suggest('Little Stars Day Care')?.categoryId, '16');
      expect(suggest('Bright Minds Preschool')?.categoryId, '16');
      expect(suggest('ABC Learning Center')?.categoryId, '16');
    });

    test('Vessel', () {
      expect(suggest('MV Starlight Vessel')?.categoryId, '14');
      expect(suggest('Montenegro Ferry')?.categoryId, '14');
    });

    test('Port', () {
      expect(suggest('Batangas Port')?.categoryId, '15');
      expect(suggest('Fishermans Wharf')?.categoryId, '15');
    });
  });

  group('no match means no suggestion', () {
    test('the real test-junk names in the live data suggest nothing', () {
      // These are live business_name values. None of them is a category hint,
      // and a catch-all guess for any of them would land on an audit record.
      for (final name in [
        'zafra',
        'Kreezby',
        'cananimus',
        'hot',
        'hiy',
        'Coper',
        'Hug',
        'royce',
        'jsjsjjsjsj',
        'Bukatots',
      ]) {
        expect(suggest(name), isNull, reason: name);
      }
    });

    test('an empty or blank name suggests nothing', () {
      expect(suggest(''), isNull);
      expect(suggest('   '), isNull);
    });
  });

  group('case and spacing are normalized', () {
    test('case is ignored', () {
      expect(suggest('JOLLIBEE')?.categoryId, '1');
      expect(suggest('jollibee')?.categoryId, '1');
      expect(suggest('JoLLiBeE')?.categoryId, '1');
    });

    test('a phrase keyword survives a doubled space', () {
      expect(suggest('Tita  Ice  Candy')?.keyword, 'ice candy');
    });
  });

  group('live establishment names', () {
    test('brands resolve to Food', () {
      expect(suggest('Jollibee')?.categoryId, '1');
      expect(suggest('Starbucks')?.categoryId, '1');
      expect(suggest('MCDO')?.categoryId, '1');
      expect(suggest('mcdo')?.categoryId, '1');
      expect(suggest('KFC')?.categoryId, '1');
      // Live, spelled as one word — this is why `burger` is not whole-word.
      expect(suggest('Burgerking')?.keyword, 'burger');
      expect(suggest('tita ice candy')?.keyword, 'ice candy');
    });

    test('Brizamar beach resort follows the city\'s own assignment', () {
      // The live record is categorised Swimming Pool and Bathhouse, which is
      // the precedent the `resort` rule is built on.
      final match = suggest('Brizamar beach resort');
      expect(match?.categoryId, '11');
      expect(match?.keyword, 'resort');
    });
  });

  group('a keyword cannot fire inside a longer word', () {
    test('no keyword matches mid-word, in either match mode', () {
      // These hold because BOTH modes require a word boundary before the
      // keyword, so they would pass with wholeWord off too — they pin the
      // compiled prefix, not the flag.
      expect(suggest('Dinner Bell'), isNull); // not `inn`
      expect(suggest('Transport Report Services'), isNull); // not `port`
      expect(suggest('Seafood City Trading'), isNull); // not `food`
    });

    test('whole-word mode is what stops a keyword running on', () {
      // These are the cases the flag actually buys. Each keyword DOES start a
      // word here, so the shared prefix is satisfied and only the trailing
      // boundary rejects them. Drop `wholeWord` from these rules and every one
      // of these turns into a wrong suggestion.
      expect(suggest('Spangle Supplies'), isNull); // not `spa`
      expect(suggest('Marketing Solutions'), isNull); // not `market`
      expect(suggest('Shipshape Printing'), isNull); // not `ship`
      expect(suggest('Innocent Trading'), isNull); // not `inn`
    });

    test('a whole-word keyword still matches its plural', () {
      expect(suggest('Sunset Pools')?.categoryId, '11');
      expect(suggest('Central Markets')?.categoryId, '3');
    });

    test('`market` does not steal a supermarket', () {
      // Not a tiebreak — `market` cannot match inside "Supermarket" at all,
      // because the default and whole-word modes both require a word boundary
      // before the keyword.
      expect(suggest('SM Supermarket')?.categoryId, '2');
    });

    test('every keyword at or under the length floor is whole-word', () {
      for (final rule in CategorySuggester.rules) {
        if (rule.keyword.length <=
            CategorySuggester.wholeWordRequiredUpToLength) {
          expect(rule.wholeWord, isTrue,
              reason: '"${rule.keyword}" is short enough to need whole-word '
                  'matching, or it will fire inside unrelated words');
        }
      }
    });
  });

  group('the winner is the most specific keyword, deterministically', () {
    test('a longer keyword beats a shorter one', () {
      expect(suggest('Bauan Public Market')?.keyword, 'public market');
      expect(suggest('Burger King Lipa')?.keyword, 'burger king');
      // "Refreshment Parlor" is a real LGU line-of-business string: Food has to
      // win over Public Places' `parlor`, and does so on length alone.
      final parlor = suggest('Aling Nena Refreshment Parlor');
      expect(parlor?.categoryId, '1');
      expect(parlor?.keyword, 'refreshment');
    });

    test('no keyword belongs to two categories', () {
      final owner = <String, String>{};
      for (final rule in CategorySuggester.rules) {
        final existing = owner[rule.keyword];
        expect(existing == null || existing == rule.categoryId, isTrue,
            reason: '"${rule.keyword}" is claimed by both $existing and '
                '${rule.categoryId}; the tiebreak would decide it by '
                'declaration order, which is not a decision anyone made');
        owner[rule.keyword] = rule.categoryId;
      }
    });
  });

  group('the ambiguous keywords land where documented', () {
    test('`resort` is a bathhouse, not a hotel', () {
      expect(suggest('Villa Esperanza Resort')?.categoryId, '11');
    });

    test('`terminal` is a public place, not a port', () {
      expect(suggest('Grand Terminal')?.categoryId, '3');
    });
  });

  group('the availability gate', () {
    test('rejects a suggestion for a category that is not selectable', () {
      // Nothing changes about the match — only whether it is offered.
      expect(suggest('Zeus Eatery', available: const {'1'})?.categoryId, '1');
      expect(suggest('Zeus Eatery', available: const {'2', '3'}), isNull);
    });

    test('does not fall through to a weaker rule', () {
      // "resort" (6 chars) outranks "cafe" (4) on keyword length, so with
      // Swimming Pool unavailable the answer is silence — NOT Food. Falling
      // through would make the same business name suggest different categories
      // on two phones with different sync states.
      expect(suggest('Seaside Resort Cafe')?.categoryId, '11');
      final degraded =
          suggest('Seaside Resort Cafe', available: const {'1', '2', '3'});
      expect(degraded, isNull);
    });

    test('an empty availability set suggests nothing', () {
      expect(suggest('Jollibee', available: const {}), isNull);
    });
  });

  test('Livestock Farm has no rules while it cannot be scored', () {
    // D25: category '17' renders in the picker but is not selectable, because
    // all 13 of its templates carry weight 0. A rule pointing at it could only
    // ever produce a suggestion the inspector is unable to accept. When a
    // weighting is finally published, add the rules and delete this test.
    expect(
      CategorySuggester.rules.where((r) => r.categoryId == '17'),
      isEmpty,
    );
  });
}
