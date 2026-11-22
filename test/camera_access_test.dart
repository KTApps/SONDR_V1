import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/theme/greyscale_tokens.dart';
import 'package:sondr/features/auth/more_sheet.dart';
import 'package:sondr/features/photos/camera_access.dart';
import 'package:sondr/features/photos/open_app_settings.dart';
import 'package:sondr/features/photos/sondr_camera.dart';
import 'package:sondr/shared/legal.dart';

/// The camera's permission: what a refusal looks like to the camera
/// screen, what the bridge answers, and the row in the More sheet that
/// says where it stands and goes to the one place that can change it.
void main() {
  group('the camera screen reads a refusal as a refusal', () {
    for (final code in [
      'CameraAccessDenied',
      'CameraAccessDeniedWithoutPrompt',
      'CameraAccessRestricted',
    ]) {
      test('$code is "Camera access is off."', () {
        expect(cameraTroubleOf(code), CameraTrouble.denied);
      });
    }

    for (final code in ['cameraNotFound', 'CameraAccess', 'AudioAccessDenied', 'IOError', '']) {
      test('"$code" is no camera, not a refusal', () {
        expect(cameraTroubleOf(code), CameraTrouble.unavailable);
      });
    }
  });

  group('the bridge', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('sondr/live_activity');
    final calls = <String>[];
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      calls.clear();
    });

    void answer(Object? Function(String method) with_) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return with_(call.method);
      });
    }

    for (final (name, access) in [
      ('notDetermined', CameraAccess.notDetermined),
      ('authorized', CameraAccess.authorized),
      ('denied', CameraAccess.denied),
      ('restricted', CameraAccess.restricted),
    ]) {
      test('"$name" reads as $access, asked without prompting', () async {
        answer((_) => name);
        expect(await ChannelCameraAccessSource().status(), access);
        expect(calls, ['cameraStatus']);
      });
    }

    test('asking goes by its own method', () async {
      answer((_) => 'authorized');
      expect(await ChannelCameraAccessSource().request(), CameraAccess.authorized);
      expect(calls, ['requestCamera']);
    });

    test('nothing on the other end is no answer, not a crash', () async {
      expect(await ChannelCameraAccessSource().status(), isNull);
      answer((_) => 'somethingNew');
      expect(await ChannelCameraAccessSource().status(), isNull);
    });
  });

  group('the More sheet row', () {
    test('the words after the label', () {
      expect(cameraAccessDetail(CameraAccess.authorized), '· On');
      expect(cameraAccessDetail(CameraAccess.denied), '· Off');
      expect(cameraAccessDetail(CameraAccess.restricted), '· Off');
      expect(cameraAccessDetail(CameraAccess.notDetermined), '· Not set');
      expect(cameraAccessDetail(null), isNull);
    });

    late _Source source;
    late int settingsOpened;
    late List<String> pagesOpened;

    Future<void> openSheet(WidgetTester tester, CameraAccess? access, {bool signedIn = true}) async {
      source = _Source(access);
      settingsOpened = 0;
      pagesOpened = [];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cameraAccessSourceProvider.overrideWithValue(source),
            appSettingsOpenerProvider.overrideWithValue(() async => settingsOpened++),
            legalPagesProvider.overrideWithValue(_Pages(pagesOpened)),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => Center(
                  child: TextButton(
                    onPressed: () => showMoreSheet(context, ref, signedIn: signedIn),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Finder row() => find.textContaining('Camera access');

    String rowText(WidgetTester tester) => tester.widget<Text>(row()).textSpan!.toPlainText();

    for (final (access, words) in [
      (CameraAccess.authorized, 'Camera access · On'),
      (CameraAccess.denied, 'Camera access · Off'),
      (CameraAccess.restricted, 'Camera access · Off'),
      (CameraAccess.notDetermined, 'Camera access · Not set'),
    ]) {
      testWidgets('$access reads "$words"', (tester) async {
        await openSheet(tester, access);
        expect(rowText(tester), words);
      });
    }

    testWidgets('after Terms, the label in the pages\' own style, the state quiet and regular', (tester) async {
      await openSheet(tester, CameraAccess.authorized);
      expect(tester.getRect(row()).top, greaterThan(tester.getRect(find.text('Terms')).bottom));
      expect(tester.getRect(row()).bottom, lessThan(tester.getRect(find.text('Sign out')).top));
      final text = tester.widget<Text>(row());
      final terms = tester.widget<Text>(find.text('Terms'));
      expect(text.style, terms.style, reason: 'the same row');
      final tokens = GreyscaleTokens.of(tester.element(row()));
      final detail = (text.textSpan! as TextSpan).children!.single as TextSpan;
      expect(detail.text, ' · On');
      expect(detail.style!.color, tokens.textTertiary);
      expect(detail.style!.fontWeight, FontWeight.w400);
    });

    testWidgets('a guest has the row too', (tester) async {
      await openSheet(tester, CameraAccess.authorized, signedIn: false);
      expect(rowText(tester), 'Camera access · On');
      expect(find.text('Sign out'), findsNothing);
    });

    for (final access in [CameraAccess.authorized, CameraAccess.denied, CameraAccess.restricted]) {
      testWidgets('$access: a tap opens sondr\'s page in Settings and asks nothing', (tester) async {
        await openSheet(tester, access);
        await tester.tap(row());
        await tester.pumpAndSettle();
        expect(settingsOpened, 1);
        expect(source.requests, 0);
        expect(pagesOpened, isEmpty);
        expect(row(), findsOneWidget, reason: 'the sheet stays, to show what changes');
      });
    }

    testWidgets('not yet asked: a tap asks, and the row says what was answered', (tester) async {
      await openSheet(tester, CameraAccess.notDetermined);
      source.answer = CameraAccess.authorized;
      await tester.tap(row());
      await tester.pumpAndSettle();
      expect(source.requests, 1);
      expect(settingsOpened, 0);
      expect(rowText(tester), 'Camera access · On');

      // Asked once; the next tap goes to Settings.
      await tester.tap(row());
      await tester.pumpAndSettle();
      expect(source.requests, 1);
      expect(settingsOpened, 1);
    });

    testWidgets('refused at the prompt reads Off', (tester) async {
      await openSheet(tester, CameraAccess.notDetermined);
      source.answer = CameraAccess.denied;
      await tester.tap(row());
      await tester.pumpAndSettle();
      expect(rowText(tester), 'Camera access · Off');
    });

    testWidgets('coming back from Settings reads it again', (tester) async {
      await openSheet(tester, CameraAccess.denied);
      expect(rowText(tester), 'Camera access · Off');
      // Changed in Settings while sondr was in the background.
      source.status_ = CameraAccess.authorized;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(rowText(tester), 'Camera access · On');
    });
  });
}

class _Source implements CameraAccessSource {
  _Source(this.status_);
  CameraAccess? status_;
  CameraAccess? answer;
  int requests = 0;

  @override
  Future<CameraAccess?> status() async => status_;

  @override
  Future<CameraAccess?> request() async {
    requests++;
    if (status_ == CameraAccess.notDetermined) status_ = answer;
    return status_;
  }
}

class _Pages implements LegalPages {
  _Pages(this.opened);
  final List<String> opened;

  @override
  Future<void> open(String url) async => opened.add(url);
}
