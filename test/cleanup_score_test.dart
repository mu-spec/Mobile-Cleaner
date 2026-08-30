import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/home/domain/cleanup_score.dart';

const int _mib = 1024 * 1024;
const int _gib = 1024 * 1024 * 1024;

ScannedFile _file(String id, int bytes) => ScannedFile(
  id: id,
  name: '$id.bin',
  path: '/storage/emulated/0/$id.bin',
  uri: 'content://media/external/file/$id',
  sizeBytes: bytes,
  category: FileCategory.other,
  dateModified: DateTime(2026, 1, 1),
);

CleanupScanSnapshot _snapshot({
  int totalBytes = 100 * _gib,
  List<CleanupOpportunity> opportunities = const <CleanupOpportunity>[],
}) => CleanupScanSnapshot(
  totalStorageBytes: totalBytes,
  opportunities: opportunities,
  scannedAt: DateTime(2026, 8, 30),
);

void main() {
  group('CleanupScoreCalculator', () {
    test('a genuinely clean completed scan scores 100 and Excellent', () {
      final CleanupScore score = CleanupScoreCalculator.calculate(_snapshot());

      expect(score.value, 100);
      expect(score.label, CleanupScoreLabel.excellent);
      expect(score.opportunityBytes, 0);
      expect(score.breakdown, isEmpty);
    });

    test('meaningful real findings lower the score', () {
      final CleanupScore score = CleanupScoreCalculator.calculate(
        _snapshot(
          opportunities: <CleanupOpportunity>[
            CleanupOpportunity(
              kind: CleanupOpportunityKind.oldDownloads,
              files: <ScannedFile>[_file('download', 5 * _gib)],
            ),
          ],
        ),
      );

      expect(score.value, lessThan(100));
      expect(score.opportunityBytes, 5 * _gib);
    });

    test('a larger opportunity produces an appropriately worse score', () {
      CleanupScore scoreFor(int bytes) => CleanupScoreCalculator.calculate(
        _snapshot(
          opportunities: <CleanupOpportunity>[
            CleanupOpportunity(
              kind: CleanupOpportunityKind.exactDuplicates,
              files: <ScannedFile>[_file('duplicate', bytes)],
            ),
          ],
        ),
      );

      expect(scoreFor(10 * _gib).value, lessThan(scoreFor(1 * _gib).value));
    });

    test('the score is always clamped from 0 through 100', () {
      final CleanupScore huge = CleanupScoreCalculator.calculate(
        _snapshot(
          totalBytes: 1 * _gib,
          opportunities: <CleanupOpportunity>[
            for (final CleanupOpportunityKind kind
                in CleanupOpportunityKind.values)
              CleanupOpportunity(
                kind: kind,
                files: <ScannedFile>[
                  for (int index = 0; index < 120; index++)
                    _file('${kind.name}-$index', 100 * _mib),
                ],
              ),
          ],
        ),
      );

      expect(huge.value, inInclusiveRange(0, 100));
      expect(
        CleanupScoreCalculator.calculate(_snapshot()).value,
        inInclusiveRange(0, 100),
      );
    });

    test('the same snapshot always produces the same result', () {
      final CleanupScanSnapshot input = _snapshot(
        opportunities: <CleanupOpportunity>[
          CleanupOpportunity(
            kind: CleanupOpportunityKind.oldScreenshots,
            files: <ScannedFile>[
              _file('shot-a', 80 * _mib),
              _file('shot-b', 120 * _mib),
            ],
          ),
        ],
      );

      final CleanupScore first = CleanupScoreCalculator.calculate(input);
      final CleanupScore second = CleanupScoreCalculator.calculate(input);

      expect(second.value, first.value);
      expect(second.opportunityBytes, first.opportunityBytes);
      expect(second.weightedOpportunityBytes, first.weightedOpportunityBytes);
      expect(
        second.breakdown.map((CleanupScoreBreakdown item) => item.kind),
        first.breakdown.map((CleanupScoreBreakdown item) => item.kind),
      );
    });

    test('recoverable opportunity bytes use the real file sizes', () {
      final CleanupScore score = CleanupScoreCalculator.calculate(
        _snapshot(
          opportunities: <CleanupOpportunity>[
            CleanupOpportunity(
              kind: CleanupOpportunityKind.apkInstallers,
              files: <ScannedFile>[
                _file('one', 240 * _mib),
                _file('two', 60 * _mib),
              ],
            ),
          ],
        ),
      );

      expect(score.opportunityBytes, 300 * _mib);
      expect(score.breakdown.single.bytes, 300 * _mib);
    });

    test('an identifiable overlapping file is counted exactly once', () {
      final ScannedFile shared = _file('shared', 700 * _mib);
      final CleanupScore score = CleanupScoreCalculator.calculate(
        _snapshot(
          opportunities: <CleanupOpportunity>[
            CleanupOpportunity(
              kind: CleanupOpportunityKind.largeFiles,
              files: <ScannedFile>[shared],
            ),
            CleanupOpportunity(
              kind: CleanupOpportunityKind.oldDownloads,
              files: <ScannedFile>[shared],
            ),
            CleanupOpportunity(
              kind: CleanupOpportunityKind.apkInstallers,
              files: <ScannedFile>[shared],
            ),
          ],
        ),
      );

      expect(score.opportunityBytes, 700 * _mib);
      expect(score.opportunityCount, 1);
      expect(score.breakdown, hasLength(1));
      expect(score.breakdown.single.kind, CleanupOpportunityKind.apkInstallers);
    });

    test('multiple categories create an accurate non-empty breakdown', () {
      final CleanupScore score = CleanupScoreCalculator.calculate(
        _snapshot(
          opportunities: <CleanupOpportunity>[
            CleanupOpportunity(
              kind: CleanupOpportunityKind.exactDuplicates,
              files: <ScannedFile>[_file('copy', 300 * _mib)],
            ),
            CleanupOpportunity(
              kind: CleanupOpportunityKind.oldScreenshots,
              files: <ScannedFile>[_file('shot', 100 * _mib)],
            ),
            const CleanupOpportunity(
              kind: CleanupOpportunityKind.largeVideos,
              files: <ScannedFile>[],
            ),
          ],
        ),
      );

      expect(score.breakdown, hasLength(2));
      expect(score.opportunityBytes, 400 * _mib);
      expect(
        score.breakdown.map((CleanupScoreBreakdown item) => item.kind),
        <CleanupOpportunityKind>[
          CleanupOpportunityKind.exactDuplicates,
          CleanupOpportunityKind.oldScreenshots,
        ],
      );
    });

    test('centralized score labels use the required thresholds', () {
      expect(CleanupScoreLabel.fromScore(100), CleanupScoreLabel.excellent);
      expect(CleanupScoreLabel.fromScore(90), CleanupScoreLabel.excellent);
      expect(CleanupScoreLabel.fromScore(89), CleanupScoreLabel.good);
      expect(CleanupScoreLabel.fromScore(75), CleanupScoreLabel.good);
      expect(CleanupScoreLabel.fromScore(74), CleanupScoreLabel.needsAttention);
      expect(CleanupScoreLabel.fromScore(50), CleanupScoreLabel.needsAttention);
      expect(
        CleanupScoreLabel.fromScore(49),
        CleanupScoreLabel.cleanupRecommended,
      );
    });
  });
}
