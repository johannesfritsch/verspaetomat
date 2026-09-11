import 'package:flutter/material.dart';

import 'checkin_flow.dart';

/// The raised "Einchecken" square in the bottom nav (decided 10 September 2026).
///
/// Since docs/24 §1 it always runs the three steps — Von wo? · Wohin? · Welcher Zug? — as
/// bottom sheets over the current tab, so the source station is answerable rather than an
/// assertion, and a wrong choice is one swipe away.
Future<void> startCheckin(BuildContext context) => runCheckinFlow(context);
