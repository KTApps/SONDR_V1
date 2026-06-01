import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  // ProviderScope hosts all Riverpod state. Repositories start as local
  // in-memory implementations and swap to Firebase later without touching the
  // feature code that depends on them.
  runApp(const ProviderScope(child: SondrApp()));
}
