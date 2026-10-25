import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every user-visible label is sentence case.
///
/// The app had both: "add habit" against "Add Task", "remove" against
/// "Remove", "retake" and "skip" one screen away from "Keep" and "Share".
/// Twelve labels were lowercase and about forty were not, so the exceptions
/// read as mistakes rather than as a style.
///
/// Each line below is a label that was changed and the file it lives in.
/// Source text, because that is what a careless revert touches.
void main() {
  const changed = <String, (String, String)>{
    'habits: add': ('lib/features/habits/habits_screen.dart', "label: 'Add habit',"),
    'habits: remove': ('lib/features/habits/habits_screen.dart', "label: 'Remove',"),
    'review: retake': (
      'lib/features/photos/capture_review_screen.dart',
      "label: 'Retake',",
    ),
    'review: keeping': (
      'lib/features/photos/capture_review_screen.dart',
      "'Keeping…'",
    ),
    'review: sharing': (
      'lib/features/photos/capture_review_screen.dart',
      "'Sharing…'",
    ),
    'camera: skip': ('lib/features/photos/sondr_camera.dart', "label: 'Skip',"),
    'camera: flash off': (
      'lib/features/photos/sondr_camera.dart',
      "CaptureFlash.off => 'Flash off',",
    ),
    'camera: flash on': (
      'lib/features/photos/sondr_camera.dart',
      "CaptureFlash.on => 'Flash on',",
    ),
    'camera: flash auto': (
      'lib/features/photos/sondr_camera.dart',
      "CaptureFlash.auto => 'Flash auto',",
    ),
    'camera: flip': ('lib/features/photos/sondr_camera.dart', "word('Flip'"),
    'focus: running': ('lib/features/focus/focus_view.dart', "'In session'"),
    'focus: paused': ('lib/features/focus/focus_view.dart', "'Paused'"),
    'day detail: logged': (
      'lib/features/history/day_detail_sheet.dart',
      "'Logged',",
    ),
    'tasks: add': (
      'lib/features/timer/widgets/task_dropdown.dart',
      "footerAction('Add task'",
    ),
    'friends: add': (
      'lib/features/friends/friends_screen.dart',
      "'Add friends',",
    ),
  };

  changed.forEach((what, where) {
    final (path, needle) = where;
    test('$what is sentence case', () {
      expect(
        File(path).readAsStringSync(),
        contains(needle),
        reason: '$what drifted back out of sentence case',
      );
    });
  });

  test('the old lowercase forms are gone', () {
    const gone = <String, List<String>>{
      'lib/features/habits/habits_screen.dart': [
        "label: 'add habit'",
        "label: 'remove'",
      ],
      'lib/features/photos/capture_review_screen.dart': [
        "label: 'retake'",
        "'saving…'",
        // Replaced by per-action labels: one flag said "Sharing…" on a Keep.
        "'Saving…'",
      ],
      'lib/features/photos/sondr_camera.dart': [
        "label: 'skip'",
        "'flash off'",
        "'flash on'",
        "'flash auto'",
        "word('flip'",
      ],
      'lib/features/focus/focus_view.dart': ["'in session'", "'paused'"],
      'lib/features/history/day_detail_sheet.dart': ["'logged',"],
      'lib/features/timer/widgets/task_dropdown.dart': ["'Add Task'"],
      'lib/features/friends/friends_screen.dart': ["'Add Friends'"],
    };
    gone.forEach((path, needles) {
      final src = File(path).readAsStringSync();
      for (final needle in needles) {
        expect(src.contains(needle), isFalse, reason: '$path still has $needle');
      }
    });
  });

  test('the deliberate exceptions are left alone', () {
    // Settings is a proper noun — it is the name of an app.
    expect(
      File('lib/features/photos/sondr_camera.dart').readAsStringSync(),
      contains("label: 'Open Settings',"),
    );
    // The unit labels beside a figure are not actions and stay lowercase.
    final profile = File(
      'lib/features/profile/profile_screen.dart',
    ).readAsStringSync();
    for (final unit in ["'day streak'", "'milestones'", "'hours'"]) {
      expect(profile, contains(unit), reason: '$unit should be lowercase');
    }
  });

  /// The timer's own words, in three languages.
  ///
  /// Home and Focus Mode are Dart, the Home Screen widget and the Lock
  /// Screen card are Swift, and nothing but this links them. The rule:
  /// the control that gets a session going is the right-hand one and
  /// reads "Start" — even going again after a pause — and a screen
  /// reader is told "Resume" there, because that is what it does.
  group('the timer says the same words everywhere', () {
    test('the paused control reads "Start" and is spoken "Resume"', () {
      final dart = File(
        'lib/features/timer/timer_screen.dart',
      ).readAsStringSync();
      expect(dart, contains("secondLabel: 'Start',"));
      expect(dart, contains("secondSemanticLabel: 'Resume',"));
      expect(
        dart.contains("firstLabel: 'Resume'"),
        isFalse,
        reason: 'the paused control went back to saying Resume',
      );

      final focus = File(
        'lib/features/focus/focus_view.dart',
      ).readAsStringSync();
      expect(focus, contains("firstLabel: 'Stop',"));
      expect(focus, contains("isRunning ? 'Pause' : 'Start'"));

      final words = File(
        'ios/SondrWidgets/WidgetTasks.swift',
      ).readAsStringSync();
      expect(words, contains('static let start = "Start"'));
      expect(words, contains('static let pause = "Pause"'));
      expect(words, contains('static let resumeSpoken = "Resume"'));

      for (final path in const [
        'ios/SondrWidgets/SondrTaskWidget.swift',
        'ios/SondrWidgets/SondrSessionActivity.swift',
      ]) {
        final src = File(path).readAsStringSync();
        expect(
          src,
          contains('.accessibilityLabel(PrimaryWord.resumeSpoken)'),
          reason: '$path does not say what it does',
        );
        expect(
          src.contains('word: "Resume"') || src.contains('word("Resume")'),
          isFalse,
          reason: '$path writes Resume where it should say Start',
        );
      }
    });

    test('every control on the widget is plain text', () {
      final src = File(
        'ios/SondrWidgets/SondrTaskWidget.swift',
      ).readAsStringSync();
      final buttons = 'Button('.allMatches(src).length;
      final plain = '.buttonStyle(.plain)'.allMatches(src).length;
      expect(
        plain,
        buttons,
        reason:
            'a widget Button without a plain style is drawn by the system '
            'as a tinted capsule',
      );
    });
  });
}
