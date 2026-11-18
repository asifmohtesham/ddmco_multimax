import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/native_intake.dart';

const _channel = MethodChannel('com.ddmco.multimax/intake');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  NativeIntake make() => NativeIntake(channel: _channel, isIOS: () => true);

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  test('isRunningOnMac returns the native answer and caches it', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'isRunningOnMac');
      calls++;
      return true;
    });
    final intake = make();
    expect(await intake.isRunningOnMac(), isTrue);
    expect(await intake.isRunningOnMac(), isTrue);
    expect(calls, 1);
  });

  test('a channel error reads as not a Mac', () async {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      throw PlatformException(code: 'boom');
    });
    expect(await make().isRunningOnMac(), isFalse);
  });

  test(
    'off iOS every call answers empty without touching the channel',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls++;
        return true;
      });
      final intake = NativeIntake(channel: _channel, isIOS: () => false);
      expect(await intake.isRunningOnMac(), isFalse);
      expect(await intake.takeStrandedShare(), isEmpty);
      expect(await intake.sharedFolders(), isEmpty);
      await intake.markShareHandled();
      expect(calls, 0);
    },
  );

  test('takeStrandedShare returns the paths', () async {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'takeStrandedShare');
      return <Object?>['/t/a.jpg', '/t/b.jpg'];
    });
    expect(await make().takeStrandedShare(), ['/t/a.jpg', '/t/b.jpg']);
  });

  test('takeStrandedShare reads an error or null as nothing', () async {
    messenger.setMockMethodCallHandler(_channel, (call) async => null);
    expect(await make().takeStrandedShare(), isEmpty);
    messenger.setMockMethodCallHandler(_channel, (call) async {
      throw PlatformException(code: 'boom');
    });
    expect(await make().takeStrandedShare(), isEmpty);
  });

  test('markShareHandled and sharedFolders use their methods', () async {
    final seen = <String>[];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      seen.add(call.method);
      return call.method == 'sharedFolders' ? <Object?>['/t/dir'] : null;
    });
    final intake = make();
    await intake.markShareHandled();
    expect(await intake.sharedFolders(), ['/t/dir']);
    expect(seen, ['markShareHandled', 'sharedFolders']);
  });

  test('a dropped call is emitted on drops', () async {
    final intake = make();
    final first = intake.drops.first;
    await messenger.handlePlatformMessage(
      _channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('dropped', ['/t/a.jpg']),
      ),
      (_) {},
    );
    expect(await first, ['/t/a.jpg']);
  });
}
