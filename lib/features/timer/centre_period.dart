import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which window the dial's centre figure reports. Swiping the centre toggles
/// between the two — today and this month (two states only for now).
enum CentrePeriod { today, month }

class CentrePeriodController extends Notifier<CentrePeriod> {
  @override
  CentrePeriod build() => CentrePeriod.today;

  void toggle() => state = state == CentrePeriod.today
      ? CentrePeriod.month
      : CentrePeriod.today;
}

final centrePeriodProvider =
    NotifierProvider<CentrePeriodController, CentrePeriod>(
  CentrePeriodController.new,
);
