/// The matching rule behind the sidebar search.
///
/// One place decides what "matches" means, so the search page, the sidebar
/// field and the tests cannot drift apart. It is deliberately free of widgets
/// and of app state: the caller hands in the items and the text to look at.
library;

/// How many hits one section of the search page shows.
///
/// A keyword like "a" matches most of a library; the cap keeps the page a
/// browsable list instead of a rebuild of the whole thing.
const int searchResultLimit = 50;

/// Whether [query] appears in any of [fields], ignoring case.
///
/// An empty query matches nothing: a section with no query would otherwise
/// list the entire library, which is what an empty search page must not do.
bool matchesSearchQuery(String query, Iterable<String?> fields) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return false;
  }
  for (final field in fields) {
    if (field != null && field.toLowerCase().contains(needle)) {
      return true;
    }
  }
  return false;
}

/// The first [limit] items of [items] that [fields] match [query] on.
List<T> filterBySearchQuery<T>(
  Iterable<T> items, {
  required String query,
  required Iterable<String?> Function(T item) fields,
  int limit = searchResultLimit,
}) {
  final result = <T>[];
  if (query.trim().isEmpty) {
    return result;
  }
  for (final item in items) {
    if (matchesSearchQuery(query, fields(item))) {
      result.add(item);
      if (result.length >= limit) {
        break;
      }
    }
  }
  return result;
}
