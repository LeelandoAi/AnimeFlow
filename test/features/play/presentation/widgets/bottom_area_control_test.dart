import 'package:anime_flow/app/localization/app_localizations.dart';
import 'package:anime_flow/app/localization/app_localizations_delegates.dart';
import 'package:anime_flow/app/router/model/play_route_extra.dart';
import 'package:anime_flow/app/router/routes_args.dart';
import 'package:anime_flow/core/constants/storage_key.dart';
import 'package:anime_flow/core/settings/storage.dart';
import 'package:anime_flow/features/play/application/danmaku_session.dart';
import 'package:anime_flow/features/play/application/danmaku_state.dart';
import 'package:anime_flow/features/play/presentation/providers/danmaku_state_provider.dart';
import 'package:anime_flow/features/play/presentation/providers/episodes_provider.dart';
import 'package:anime_flow/features/play/presentation/providers/play_provider.dart';
import 'package:anime_flow/features/play/presentation/providers/video_ui_provider.dart';
import 'package:anime_flow/features/play/presentation/widgets/player/ui/control/bottom_area_control.dart';
import 'package:anime_flow/features/play/presentation/widgets/player/ui/player_progress_bar.dart';
import 'package:anime_flow/features/play/presentation/widgets/player/ui/player_time_display.dart';
import 'package:anime_flow/features/user/presentation/providers/user_state_provider.dart';
import 'package:anime_flow/shared/models/flow/flow_users.dart';
import 'package:anime_flow/shared/widgets/danmaku_text_field.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

const _extra = PlayRouteExtra(
  playExtra: PlayExtra(
      subjectId: 1,
      subjectName: 'Subject',
      subjectCover: '',
      subjectAliases: []),
);

void main() {
  final settings = _Settings();
  setUpAll(() => Storage.setting = settings);
  setUp(() => settings.showMiniProgress = true);

  for (final showMini in [true, false]) {
    testWidgets(
        'auto-hide retains drafts and subscriptions with mini progress $showMini',
        (tester) async {
      settings.showMiniProgress = showMini;
      final episodes = _TestEpisodes();
      final container = _container(episodes: episodes);
      addTearDown(container.dispose);
      await _mount(tester, container);
      final ui = container.read(videoUiProvider.notifier);
      final inputState = tester.state(find.byType(DanmakuTextField));
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;
      controller.text = 'unfinished danmaku';

      for (var cycle = 0; cycle < 3; cycle++) {
        ui.hideControlsUi();
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(BottomAreaControl)).height,
            showMini ? 3 : 0);
        expect(
            identical(tester.state(find.byType(DanmakuTextField)), inputState),
            isTrue);
        final input = tester.widget<TextField>(find.byType(TextField));
        expect(input.focusNode!.canRequestFocus, isFalse);
        final ignore = find
            .ancestor(
                of: find.byType(DanmakuTextField),
                matching: find.byType(IgnorePointer))
            .first;
        expect(tester.widget<IgnorePointer>(ignore).ignoring, isTrue);

        container
            .read(playStateProvider.notifier)
            .setPosition(Duration(seconds: cycle + 20));
        await tester.pump();
        if (showMini) {
          expect(
              tester
                  .widget<MiniPlayerProgressBar>(
                      find.byType(MiniPlayerProgressBar))
                  .position,
              Duration(seconds: cycle + 20));
        }
        ui.showControlsUi();
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(find.byType(TextField)).controller,
            same(controller));
        expect(controller.text, 'unfinished danmaku');
        expect(episodes.builds, 1);
        expect(episodes.disposals, 0);
      }

      await tester.pumpWidget(UncontrolledProviderScope(
          container: container, child: const SizedBox.shrink()));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 1));
      expect(episodes.disposals, 1);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  testWidgets(
      'progress, account and danmaku changes rebuild only their regions',
      (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await _mount(tester, container);
    final playState = container.read(playStateProvider.notifier);
    final fullscreenButton = find.ancestor(
        of: find.byIcon(Icons.fullscreen), matching: find.byType(IconButton));
    final buttonBefore = tester.widget<IconButton>(fullscreenButton);
    final controlRow =
        find.ancestor(of: fullscreenButton, matching: find.byType(Row)).first;
    final rowBefore = tester.widget<Row>(controlRow);
    final time = find.descendant(
        of: find.byType(PlayerTimeDisplay), matching: find.byType(Text));
    final timeBefore = tester.widget<Text>(time);
    final inputBefore =
        tester.widget<DanmakuTextField>(find.byType(DanmakuTextField));

    playState
      ..setPosition(const Duration(milliseconds: 10500))
      ..setBuffered(const Duration(seconds: 40))
      ..setRate(1.5);
    (container.read(currentUserInfoProvider.notifier) as _TestCurrentUserInfo)
        .setProfile(_user('New name'));
    await tester.pump();
    expect(tester.widget<Text>(time), same(timeBefore));
    expect(tester.widget<DanmakuTextField>(find.byType(DanmakuTextField)),
        same(inputBefore));
    expect(
        tester
            .widget<PlayerProgressBar>(find.byType(PlayerProgressBar))
            .position,
        const Duration(milliseconds: 10500));

    playState.toggleContentExpanded();
    await tester.pump();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(BottomAreaControl)));
    expect(find.text(l10n.episodeSelection), findsOneWidget);
    container.read(danmakuStateProvider.notifier).toggleEnabled();
    await tester.pump();
    expect(find.byType(DanmakuTextField), findsNothing);
    expect(tester.widget<IconButton>(fullscreenButton), same(buttonBefore));
    expect(tester.widget<Row>(controlRow), same(rowBefore));

    playState.setPosition(const Duration(seconds: 11));
    await tester.pump();
    expect(tester.widget<Text>(time).data, '00:11 / 02:00');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('auto-hide retains the danmaku send cooldown', (tester) async {
    final session = _Session();
    final container = _container(session: session);
    addTearDown(container.dispose);
    await _mount(tester, container);
    final l10n =
        AppLocalizations.of(tester.element(find.byType(BottomAreaControl)));
    await tester.enterText(find.byType(TextField), 'sent danmaku');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(session.danmaku.sent, ['sent danmaku']);
    final ui = container.read(videoUiProvider.notifier);
    ui.hideControlsUi();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    ui.showControlsUi();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.hintText, l10n.waitToSendDanmaku(5));
    expect(field.onSubmitted, isNull);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.widget<TextField>(find.byType(TextField)).onSubmitted,
        isNotNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}

Future<void> _mount(WidgetTester tester, ProviderContainer container) async {
  container.read(playStateProvider.notifier)
    ..setIsWideScreen(true)
    ..setDuration(const Duration(minutes: 2))
    ..setPosition(const Duration(seconds: 10));
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: Column(children: [BottomAreaControl()])),
    ),
  ));
  await tester.pumpAndSettle();
}

ProviderContainer _container({_TestEpisodes? episodes, _Session? session}) =>
    ProviderContainer(overrides: [
      playExtraProvider.overrideWithValue(_extra),
      playSessionProvider.overrideWithValue(session ?? _Session()),
      videoUiProvider.overrideWith(_TestVideoUiNotifier.new),
      danmakuStateProvider.overrideWith(_TestDanmakuStateNotifier.new),
      episodesProvider.overrideWith(() => episodes ?? _TestEpisodes()),
      currentUserInfoProvider.overrideWith(_TestCurrentUserInfo.new),
    ]);

FlowUsers _user(String nickname) =>
    FlowUsers(id: 1, email: '', nickname: nickname, createTime: 0);

class _TestCurrentUserInfo extends CurrentUserInfo {
  void setProfile(FlowUsers user) => state = AsyncData(user);

  @override
  Future<FlowUsers?> build() async => _user('Name');
}

class _TestVideoUiNotifier extends VideoUiNotifier {
  @override
  VideoUiState build() {
    ref.onDispose(cancelUiTimer);
    return const VideoUiState();
  }
}

class _TestDanmakuStateNotifier extends DanmakuStateNotifier {
  @override
  DanmakuState build() => const DanmakuState();
}

class _TestEpisodes extends Episodes {
  int builds = 0;
  int disposals = 0;

  @override
  Future<EpisodesData> build() async {
    builds++;
    ref.onDispose(() => disposals++);
    return const EpisodesData();
  }
}

class _Session implements PlaySession {
  @override
  final _DanmakuSession danmaku = _DanmakuSession();

  @override
  Future<void> startPlaying() async {}

  @override
  Future<void> stopPlaying({Duration? duration}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _DanmakuSession implements DanmakuSession {
  final sent = <String>[];

  @override
  Future<bool> send(String text,
      {required int bgmUserId, Color? color, int type = 1}) async {
    sent.add(text);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Settings implements Box<dynamic> {
  bool showMiniProgress = true;

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      key == PlaybackKey.showMiniProgressBar ? showMiniProgress : defaultValue;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
