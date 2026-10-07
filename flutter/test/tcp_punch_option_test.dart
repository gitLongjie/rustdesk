import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TCP hole punching writes an explicit value when toggled', () {
    expect(bool2option(kOptionEnableTcpPunch, true), 'Y');
    expect(bool2option(kOptionEnableTcpPunch, false), 'N');
  });
}
