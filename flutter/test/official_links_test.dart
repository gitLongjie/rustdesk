import 'package:flutter_hbb/utils/url_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official links are blocked while self-hosted URLs remain allowed', () async {
    for (final value in [
      'https://rustdesk.com',
      'https://API.RUSTDESK.COM./version/latest',
      'https://rustdesk.com/docs/en/client/mac/'
    ]) {
      final url = Uri.parse(value);
      expect(isOfficialUrl(url), isTrue);
      expect(await launchUrl(url), isFalse);
    }
    for (final value in [
      'http://remote.brigecode.icu:21114',
      'https://rustdesk.com@selfhost.example',
      'https://rustdesk.com.selfhost.example'
    ]) {
      expect(isOfficialUrl(Uri.parse(value)), isFalse);
    }
  });
}
