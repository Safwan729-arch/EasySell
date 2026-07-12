import 'dart:async';

import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/presentation/auth_controller.dart';
import 'package:ai_shopkeeper/shared/providers/connectivity_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'sign-in while offline fails fast with NetworkFailure without hitting the repo',
    () async {
      // A long-lived controller so the StreamProvider has an active source and
      // isn't disposed mid-loading; we emit the offline reading, then act.
      final connectivity = StreamController<bool>.broadcast();
      addTearDown(connectivity.close);

      final container = ProviderContainer(
        overrides: [
          isOnlineProvider.overrideWith((ref) => connectivity.stream),
          // If the guard is broken and the network call is attempted, building
          // the repo throws — turning a regression into a hard test failure
          // instead of a real (hanging) network request.
          authRepositoryProvider.overrideWith(
            (ref) => throw StateError('repo must not be built while offline'),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Keep the provider alive and wait until it reports offline.
      final sub = container.listen(isOnlineProvider, (_, _) {});
      addTearDown(sub.close);
      connectivity.add(false);
      await container.read(isOnlineProvider.future);
      expect(container.read(isOnlineProvider).value, isFalse);

      await container
          .read(authControllerProvider.notifier)
          .signInWithEmail('shopkeeper@example.com', 'password123');

      final state = container.read(authControllerProvider);
      expect(state, isA<AsyncError<void>>());
      expect((state as AsyncError).error, isA<NetworkFailure>());
    },
  );
}
