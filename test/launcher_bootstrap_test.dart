import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/launcher_controller.dart';
import 'package:nte_translation_launcher/main.dart';

void main() {
  testWidgets('shows a visible startup screen while dependencies initialize', (
    tester,
  ) async {
    final initialization = Completer<LauncherController>();

    await tester.pumpWidget(
      LauncherBootstrap(
        arguments: const [],
        initializer: (_) => initialization.future,
      ),
    );

    expect(find.text('Iniciando o launcher…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('surfaces bootstrap errors and allows retrying', (tester) async {
    var attempts = 0;
    var initialization = Completer<LauncherController>();

    Future<LauncherController> failInitialization(List<String> _) {
      attempts++;
      initialization = Completer<LauncherController>();
      return initialization.future;
    }

    await tester.pumpWidget(
      LauncherBootstrap(arguments: const [], initializer: failInitialization),
    );
    initialization.completeError(StateError('startup unavailable'));
    await tester.pump();

    expect(find.text('Não foi possível iniciar o launcher'), findsOneWidget);
    expect(find.textContaining('startup unavailable'), findsOneWidget);
    expect(attempts, 1);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();

    expect(attempts, 2);
  });
}
