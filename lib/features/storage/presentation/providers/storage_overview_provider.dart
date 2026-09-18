import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phone_storage_cleaner/features/storage/data/storage_repository.dart';
import 'package:phone_storage_cleaner/features/storage/domain/storage_info.dart';

final FutureProvider<StorageInfo> storageOverviewProvider =
    FutureProvider<StorageInfo>((ref) {
      return ref.watch(storageRepositoryProvider).getStorageInfo();
    });
