import 'package:anime_flow/app/localization/app_localizations.dart';
import 'package:anime_flow/app/localization/app_localizations_delegates.dart';
import 'package:anime_flow/shared/models/enums/collect_type.dart';
import 'package:anime_flow/shared/widgets/collection_button.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(
  CollectType? type,
  Future<void> Function(CollectType) onChanged, {
  VoidCallback? onMenuOpen,
  VoidCallback? onMenuClose,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: CollectionButton(
        collectType: type,
        onCollectTypeChanged: onChanged,
        onMenuOpen: onMenuOpen,
        onMenuClose: onMenuClose,
        buttonBuilder: (context, label, icon, onPressed) =>
            TextButton(onPressed: onPressed, child: Text(label)),
      ),
    ),
  );
}

void main() {
  testWidgets('menu lifecycle handles both dismissal and selection',
      (tester) async {
    final events = <String>[];
    await tester.pumpWidget(_app(
      null,
      (_) async => events.add('selected'),
      onMenuOpen: () => events.add('opened'),
      onMenuClose: () => events.add('closed'),
    ));

    await tester.tap(find.text('Collection'));
    await tester.pumpAndSettle();
    expect(events, ['opened']);
    await tester.tapAt(const Offset(750, 550));
    await tester.pumpAndSettle();
    expect(events, ['opened', 'closed']);

    await tester.tap(find.text('Collection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Watching'));
    await tester.pumpAndSettle();
    expect(events, ['opened', 'closed', 'opened', 'closed', 'selected']);
  });

  testWidgets('collected item offers cancellation and returns to collect state',
      (tester) async {
    final selected = <CollectType>[];
    await tester.pumpWidget(_app(CollectType.watching, (type) async {
      selected.add(type);
    }));

    await tester.tap(find.text('Watching'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from collection'));
    await tester.pumpAndSettle();

    expect(selected, [CollectType.none]);
    expect(find.text('Collection'), findsOneWidget);
    await tester.tap(find.text('Collection'));
    await tester.pumpAndSettle();
    expect(find.text('Remove from collection'), findsNothing);
  });

  testWidgets('uncollected item has no cancellation action', (tester) async {
    await tester.pumpWidget(_app(null, (_) async {}));
    await tester.tap(find.text('Collection'));
    await tester.pumpAndSettle();
    expect(find.text('Remove from collection'), findsNothing);
  });
}
