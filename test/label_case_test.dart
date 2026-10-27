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
      'lib/features/photos/share_review_scaffold.dart',
      "'Keeping…'",
    ),
    'review: sharing': (
      'lib/features/photos/share_review_scaffold.dart',
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
      'lib/features/photos/share_review_scaffold.dart': ["'saving…'", "'Saving…'"],
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

  /// The way out of a blur view is "Back", and the comments field has no
  /// placeholder — the sheet's own heading says what it takes.
  group('blur views and the comments field', () {
    test('every blur view and confirm backs out with "Back"', () {
      expect(File('lib/shared/blur_sheet.dart').readAsStringSync(),
          contains("this.cancelLabel = 'Back',"));
      final prompt = File('lib/shared/sondr_prompt.dart').readAsStringSync();
      expect("String cancelLabel = 'Back',".allMatches(prompt).length, 3);
      expect(prompt.contains("cancelLabel = 'Cancel'"), isFalse);
    });

    test('the comments composer has no hint, and its empty word is Close', () {
      final sheet = File('lib/features/feed/widgets/comments_sheet.dart').readAsStringSync();
      expect(sheet.contains("hint: 'Add a comment'"), isFalse);
      expect(sheet.contains('Replying to'), isFalse);
      expect(sheet, contains("label: 'Close',"));
      expect(sheet, contains("label: 'Post',"));
      expect(sheet.contains("'Cancel'"), isFalse);
    });
  });
}
