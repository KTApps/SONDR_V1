import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/sondr_prompt.dart';
import 'report.dart';

/// What a report ended as, so the surface that started it can say the
/// right thing and hide the right amount.
enum ReportOutcome {
  /// They changed their mind — nothing written, nothing hidden.
  cancelled,

  /// We have it. A post or a comment is now hidden for this reader; a
  /// person is not, because blocking is the thing that does that.
  sent,

  /// It did not go. Nothing is hidden: a surface that emptied itself on a
  /// failure would be telling the reader something untrue.
  failed,
}

/// Ask why, then tell us.
///
/// The question is the same card the confirms use, in the same place on
/// the screen — this is a question with five answers rather than two.
Future<ReportOutcome> reportThing(
  BuildContext context,
  WidgetRef ref, {
  required ReportTarget type,
  required String targetKey,
  required String targetOwnerUid,
  required String title,
}) async {
  final reason = await showSondrChoice<ReportReason>(
    context,
    title: title,
    body: 'Why are you reporting this?',
    choices: [
      for (final r in ReportReason.values) (label: r.label, value: r),
    ],
  );
  if (reason == null) return ReportOutcome.cancelled;

  final reports = ref.read(reportsProvider);
  if (reports == null) return ReportOutcome.failed;

  final sent = await reports.send(
    type: type,
    targetKey: targetKey,
    targetOwnerUid: targetOwnerUid,
    reason: reason,
  );
  if (!sent) return ReportOutcome.failed;
  await reports.hide(type, targetKey);
  return ReportOutcome.sent;
}

/// What a surface says once we have it. Short, and a promise we have to
/// keep — the same 24 hours the terms state.
const String kReportThanks = 'Thanks. We\'ll review this within 24 hours.';

/// What it says when the report did not go.
const String kReportFailed = 'Couldn\'t send that report. Please try again.';

/// The title the reason sheet carries, by what is being reported.
String reportTitle(ReportTarget type, {String handle = ''}) =>
    switch (type) {
      ReportTarget.post => 'Report post',
      ReportTarget.comment => 'Report comment',
      ReportTarget.user => handle.isEmpty ? 'Report' : 'Report $handle',
    };
