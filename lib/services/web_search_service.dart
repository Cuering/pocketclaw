import 'dart:convert';
import 'dart:io';

import 'connectivity_service.dart';

class WebSearchService {
  WebSearchService._();
  static final WebSearchService instance = WebSearchService._();

  Future<String?> searchSummary(String query) async {
    if (!await ConnectivityService.instance.hasInternet()) return null;
    final uri = Uri.https('api.duckduckgo.com', '/', {
      'q': query,
      'format': 'json',
      'no_html': '1',
      'skip_disambig': '1',
    });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final lines = <String>[];
      final abstract = (data['AbstractText'] as String? ?? '').trim();
      if (abstract.isNotEmpty) lines.add(abstract);
      final source = (data['AbstractURL'] as String? ?? '').trim();
      if (source.isNotEmpty) lines.add('Source: $source');
      final related = data['RelatedTopics'];
      if (related is List) {
        for (final item in related.take(4)) {
          if (item is Map<String, dynamic>) {
            final text = (item['Text'] as String? ?? '').trim();
            final url = (item['FirstURL'] as String? ?? '').trim();
            if (text.isNotEmpty) {
              lines.add(url.isEmpty ? text : '$text ($url)');
            }
          }
        }
      }
      if (lines.isEmpty) return null;
      return lines.join('\n');
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
