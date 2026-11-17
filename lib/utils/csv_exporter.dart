import 'dart:convert';
import 'dart:html' as html;

class CsvExporter {
  static String _escape(dynamic value) {
    final str = (value ?? '').toString().replaceAll('\n', ' ').trim();
    if (str.contains(',') || str.contains('"')) {
      return '"${str.replaceAll('"', '""')}"';
    }
    return str;
  }

  static void downloadCsv({
    required String filename,
    required List<String> headers,
    required List<List<dynamic>> rows,
  }) {
    final buffer = StringBuffer();
    buffer.write('\uFEFF'); // BOM para compatibilidad directa con Microsoft Excel
    buffer.writeln(headers.map(_escape).join(','));
    for (final row in rows) {
      buffer.writeln(row.map(_escape).join(','));
    }

    final bytes = utf8.encode(buffer.toString());
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}