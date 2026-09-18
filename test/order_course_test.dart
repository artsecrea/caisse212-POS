import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/order_course.dart';

/// Courses only ever cost a shop something when it uses them. The kitchen
/// ticket splits into sections when — and only when — the lines being printed
/// actually carry more than one course; everything else prints exactly as it
/// always has. These pin that contract, because breaking it silently changes
/// every kitchen ticket in every shop that never asked for the feature.

void main() {
  group('when to split the ticket', () {
    test('nothing tagged — the ticket every shop already gets', () {
      expect(shouldSplitByCourse([null, null, null]), isFalse);
    });

    test('a single line is never worth a heading', () {
      expect(shouldSplitByCourse([1]), isFalse);
      expect(shouldSplitByCourse([null]), isFalse);
    });

    test('every line on the same course is one section, so no sections', () {
      expect(shouldSplitByCourse([2, 2, 2]), isFalse);
    });

    test('two courses split', () {
      expect(shouldSplitByCourse([1, 2]), isTrue);
    });

    test('a half-tagged order splits — the untagged lines are a section', () {
      expect(shouldSplitByCourse([1, null]), isTrue);
    });

    test('an empty ticket does not split', () {
      expect(shouldSplitByCourse(const []), isFalse);
    });

    test('an unknown course number counts as untagged, not as its own', () {
      // A newer build or a hand-edited row must not invent a fourth section.
      expect(shouldSplitByCourse([9, 9]), isFalse);
      expect(shouldSplitByCourse([9, null]), isFalse);
      expect(shouldSplitByCourse([1, 9]), isTrue);
    });
  });

  group('grouping', () {
    List<String> flatten(Map<int?, List<String>> g) => [
      for (final e in g.entries) '${e.key}:${e.value.join("+")}',
    ];

    test(
      'sections come out in serving order, whatever order they were rung',
      () {
        final g = groupByCourse<String>([
          'ice cream',
          'soup',
          'steak',
        ], (s) => {'ice cream': 3, 'soup': 1, 'steak': 2}[s]);
        expect(flatten(g), ['1:soup', '2:steak', '3:ice cream']);
      },
    );

    test('lines keep their order within a section', () {
      final g = groupByCourse<String>(['soup', 'salad'], (_) => 1);
      expect(g[1], ['soup', 'salad']);
    });

    test('untagged lines go last, under their own heading — never dropped', () {
      // A line with no course is still food somebody ordered. Silently
      // omitting it would be the worst possible failure of this feature.
      final g = groupByCourse<String>([
        'water',
        'steak',
      ], (s) => s == 'steak' ? 2 : null);
      expect(flatten(g), ['2:steak', 'null:water']);
    });

    test('an absent course produces no empty section', () {
      final g = groupByCourse<String>(['steak'], (_) => 2);
      expect(g.keys.toList(), [2]);
    });
  });

  group('when to nag the cashier', () {
    test('nothing tagged is the normal case and never nags', () {
      expect(hasPartialCourses([null, null]), isFalse);
    });

    test('everything tagged is finished work', () {
      expect(hasPartialCourses([1, 2, 3]), isFalse);
    });

    test('half-tagged is the only state worth asking about', () {
      expect(hasPartialCourses([1, null]), isTrue);
    });

    test('an empty order never nags', () {
      expect(hasPartialCourses(const []), isFalse);
    });

    test('an unknown number counts as untagged', () {
      expect(hasPartialCourses([1, 9]), isTrue);
    });
  });

  group('normalising what arrives from the wire', () {
    /// The guarantee the waiter app pointed out was living in THEIR code
    /// rather than in this contract. A client that promises to send only 1-3
    /// is one build away from not doing so, and a column holding a stray 7
    /// that every reader must remember to ignore is how a field rots.
    test('a real course passes through', () {
      expect(normalizeCourseNo(1), 1);
      expect(normalizeCourseNo(2), 2);
      expect(normalizeCourseNo(3), 3);
    });

    test('zero is not a course — the case they flagged', () {
      expect(normalizeCourseNo(0), isNull);
    });

    test('out of range, negative and absurd all become no course', () {
      expect(normalizeCourseNo(4), isNull);
      expect(normalizeCourseNo(-1), isNull);
      expect(normalizeCourseNo(99), isNull);
    });

    test('null and a missing key are the same thing', () {
      expect(normalizeCourseNo(null), isNull);
    });

    test('a non-number is not coerced, it is refused', () {
      // JSON is not typed. A client sending "2" as a string gets no course
      // rather than a silently accepted one.
      expect(normalizeCourseNo('2'), isNull);
      expect(normalizeCourseNo(true), isNull);
      expect(normalizeCourseNo(const {}), isNull);
    });

    test('a double is truncated to its course, not rejected', () {
      // Dart's JSON decoder hands back a double for 2.0 on some platforms.
      expect(normalizeCourseNo(2.0), 2);
    });
  });
}
