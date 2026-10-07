import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

final _sessionId = UuidValue('00000000-0000-0000-0000-000000000000');

class _FakeFFI implements FFI {
  @override
  UuidValue get sessionId => _sessionId;

  @override
  late final FfiModel ffiModel = FfiModel(WeakReference(this));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('the quality monitor distinguishes P2P from relay for every transport',
      () {
    final ffi = _FakeFFI();
    final model = QualityMonitorModel(WeakReference(ffi));
    expect(model.connectionType, isNull);
    for (final entry in {
      'TCP': 'TCP',
      'UDP': 'UDP',
      'IPv6': 'UDP',
      'WebRTC': 'UDP',
    }.entries) {
      ffi.ffiModel.setConnectionType('peer', true, true, entry.key);
      expect(model.connectionType, 'P2P');
      expect(model.transport, entry.value);
    }
    for (final streamType in ['Relay', 'WebSocket', 'WebRTC']) {
      ffi.ffiModel.setConnectionType('peer', true, false, streamType);
      expect(model.connectionType, 'Relay Connection');
      expect(model.transport, 'Relay');
    }
    ffi.ffiModel.clear();
    expect(model.connectionType, isNull);
  });

  test('connection text hides WebRTC implementation details', () {
    expect(normalizeConnectionTransport(true, 'WebRTC'), 'UDP');
    expect(normalizeConnectionTransport(false, 'WebRTC'), 'Relay');
  });

  test('the quality monitor keeps the WebRTC compatibility label off desktop',
      () {
    final ffi = _FakeFFI();
    ffi.ffiModel.cachedPeerData.streamType = 'WebRTC';
    final model = QualityMonitorModel(WeakReference(ffi));
    // Off the web the session tab's tooltip already names the transport.
    expect(isWeb, isFalse);
    expect(model.webrtcTransport, isNull);
  });
}
