import 'package:anime_flow/app/localization/app_localizations.dart';
import 'package:anime_flow/app/localization/app_localizations_delegates.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoLocalizations;
import 'package:flutter/widgets.dart';
import 'package:flutter/cupertino.dart' as flutter_cupertino;
import 'package:flutter/material.dart' as flutter_material;
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart'
    show MaterialApp, MaterialLocalizations, Scaffold;

const _zhHans = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');

void main() {
  // 组件来自独立的 material_ui / cupertino_ui 包，各自定义了同名的本地化类型。
  // 注册 flutter_localizations 的全局代理无法满足这些组件，必须在代理列表中
  // 提供两个包自己的实现，否则运行时会报 “No MaterialLocalizations found”。
  test('delegates cover material_ui/cupertino_ui types for zh_Hans', () {
    final materialDelegates = appLocalizationsDelegates
        .whereType<LocalizationsDelegate<MaterialLocalizations>>()
        .where((delegate) => delegate.isSupported(_zhHans));
    expect(materialDelegates, hasLength(1));

    final cupertinoDelegates = appLocalizationsDelegates
        .whereType<LocalizationsDelegate<CupertinoLocalizations>>()
        .where((delegate) => delegate.isSupported(_zhHans));
    expect(cupertinoDelegates, hasLength(1));
  });

  test('delegates cover Flutter Cupertino for every supported locale', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final delegates = appLocalizationsDelegates
          .whereType<
              LocalizationsDelegate<flutter_cupertino.CupertinoLocalizations>>()
          .where((delegate) => delegate.isSupported(locale));
      expect(delegates, hasLength(1), reason: '$locale');
    }
  });

  testWidgets('MaterialLocalizations resolves for zh_Hans', (tester) async {
    String? cancelLabel;
    await tester.pumpWidget(
      MaterialApp(
        locale: _zhHans,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            cancelLabel = MaterialLocalizations.of(context).cancelButtonLabel;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(cancelLabel, isNotNull);
  });

  testWidgets('iOS Markdown long press can copy with app localizations',
      (tester) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(
      MaterialApp(
        locale: _zhHans,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: MarkdownBody(data: 'Release notes', selectable: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPressAt(
      tester.getTopLeft(find.byType(flutter_material.SelectableText)) +
          const Offset(12, 8),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final context = tester.element(find.byType(MarkdownBody));
    final copyLabel =
        flutter_cupertino.CupertinoLocalizations.of(context).copyButtonLabel;
    expect(find.text(copyLabel), findsOneWidget);
    await tester.tap(find.text(copyLabel));
    await tester.pumpAndSettle();
    expect(copiedText, 'Release');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
