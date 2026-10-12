// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_collection_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(UserCollections)
final userCollectionsProvider = UserCollectionsProvider._();

final class UserCollectionsProvider
    extends $NotifierProvider<UserCollections, UserCollectionsState> {
  UserCollectionsProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'userCollectionsProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$userCollectionsHash();

  @$internal
  @override
  UserCollections create() => UserCollections();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UserCollectionsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UserCollectionsState>(value),
    );
  }
}

String _$userCollectionsHash() => r'df5d48586195ea4a7487e3e9a9199567b179b843';

abstract class _$UserCollections extends $Notifier<UserCollectionsState> {
  UserCollectionsState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<UserCollectionsState, UserCollectionsState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<UserCollectionsState, UserCollectionsState>,
        UserCollectionsState,
        Object?,
        Object?>;
    element.handleCreate(ref, build);
  }
}
