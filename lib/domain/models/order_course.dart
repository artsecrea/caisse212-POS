/// Courses: entrée, plat, dessert.
///
/// Stored on an order line as a small integer (`OrderProducts.courseNo`) so
/// the kitchen ticket's sections sort themselves — starters above mains
/// whatever language the till is running in. Null means the cashier did not
/// say, which is the normal state: the whole feature is off by default.
class OrderCourse {
  final int number;
  final String labelKey;

  const OrderCourse._(this.number, this.labelKey);

  static const starter = OrderCourse._(1, 'course_starter');
  static const main = OrderCourse._(2, 'course_main');
  static const dessert = OrderCourse._(3, 'course_dessert');

  /// In serving order, which is also the order they print in.
  static const values = [starter, main, dessert];

  /// A short badge for the order line — one letter, because the line has room
  /// for a chip and not for "Entrée".
  String get badgeKey => 'course_badge_$number';

  static OrderCourse? fromNumber(int? n) {
    if (n == null) return null;
    for (final c in values) {
      if (c.number == n) return c;
    }
    // An unknown number from a newer build or a hand-edited row: treat it as
    // unset rather than crashing a kitchen ticket over it.
    return null;
  }
}

/// The course a value means, or null for anything that is not a course.
///
/// The normalisation every boundary should run an incoming value through:
/// 0, a negative, 4, a stray 99 from a future build all become "no course"
/// rather than being stored as themselves. Display and printing already treat
/// an unknown number as untagged ([OrderCourse.fromNumber] returns null), so
/// nothing was ever going to render wrong — but storing a 7 that every reader
/// then has to remember to ignore is how a field rots. Normalise on the way
/// in and the column only ever holds 1, 2, 3 or null.
///
/// This lives here rather than in the LAN server because it is a property of
/// the type, and because the waiter app vendors this file: the guarantee then
/// holds on both sides of the wire instead of only in whichever one thought
/// to check.
int? normalizeCourseNo(Object? raw) {
  final n = raw is num ? raw.toInt() : null;
  return OrderCourse.fromNumber(n)?.number;
}

/// Whether a set of lines is worth splitting into course sections.
///
/// False when nothing is tagged, when only one line is being printed, or when
/// every line shares one course — in all three the sections would be pure
/// noise, and the kitchen gets the ticket it has always had. This is the rule
/// the whole feature turns on, so it lives here rather than inside the
/// printer where it could not be tested.
bool shouldSplitByCourse(Iterable<int?> courseNumbers) {
  final lines = courseNumbers.toList();
  if (lines.length < 2) return false;
  final distinct = lines.map((n) => OrderCourse.fromNumber(n)?.number).toSet();
  return distinct.length > 1;
}

/// Lines grouped into their courses, in serving order, with untagged lines
/// last under their own heading.
///
/// Untagged lines are kept rather than dropped: a line with no course is
/// still food somebody ordered, and a kitchen ticket that silently omitted it
/// would be the worst possible failure of this feature.
Map<int?, List<T>> groupByCourse<T>(List<T> items, int? Function(T) courseOf) {
  final out = <int?, List<T>>{};
  for (final course in OrderCourse.values) {
    final own = [
      for (final i in items)
        if (OrderCourse.fromNumber(courseOf(i))?.number == course.number) i,
    ];
    if (own.isNotEmpty) out[course.number] = own;
  }
  final untagged = [
    for (final i in items)
      if (OrderCourse.fromNumber(courseOf(i)) == null) i,
  ];
  if (untagged.isNotEmpty) out[null] = untagged;
  return out;
}

/// Whether the cashier should be asked to finish tagging.
///
/// Choosing a course is never obligatory — until somebody chooses one. At
/// that point the order is being worked in courses, and a line with none
/// would land in an "Other" section at the bottom of the kitchen ticket,
/// which is exactly the confusion the feature exists to remove.
///
/// So: false when nothing is tagged (the normal case, and the reason the
/// feature costs nothing), false when everything is tagged, true only for the
/// half-finished state.
bool hasPartialCourses(Iterable<int?> courseNumbers) {
  var tagged = 0;
  var untagged = 0;
  for (final n in courseNumbers) {
    if (OrderCourse.fromNumber(n) == null) {
      untagged++;
    } else {
      tagged++;
    }
  }
  return tagged > 0 && untagged > 0;
}
