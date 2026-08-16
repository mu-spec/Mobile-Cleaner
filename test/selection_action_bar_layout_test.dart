import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_selection.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/selection_action_bar.dart';

const int _mib = 1024 * 1024;

ScannedFile _file(int i, {String scheme = 'content'}) {
  return ScannedFile(
    id: '$i',
    name: 'Screenshot_$i.png',
    path: '/storage/emulated/0/Pictures/Screenshots/Screenshot_$i.png',
    uri: '$scheme://media/external/images/media/$i',
    sizeBytes: 30 * _mib,
    category: FileCategory.images,
    dateModified: DateTime(2026, 5, 1),
    mimeType: 'image/png',
  );
}

FileSelection _selectionOf(int count, {String scheme = 'content'}) {
  return const FileSelection.empty().selectAll(<ScannedFile>[
    for (int i = 1; i <= count; i++) _file(i, scheme: scheme),
  ]);
}

/// Hosts the bar the way the cleaners do: inside a `Column`, below an
/// `Expanded` child.
///
/// The `Column` is what handed the bar unbounded width and produced
/// `BoxConstraints forces an infinite width`, so reproducing that ancestry is
/// the whole point of this harness.
Widget _host({
  required FileSelection selection,
  int? deletableCount,
  VoidCallback? onClear,
  VoidCallback? onDelete,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView.builder(
                itemCount: 30,
                itemBuilder: (BuildContext context, int index) =>
                    ListTile(title: Text('row $index')),
              ),
            ),
            SelectionActionBar(
              selection: selection,
              onClear: onClear ?? () {},
              onDelete: onDelete ?? () {},
              deletableCount: deletableCount,
              barKey: const Key('bar'),
              countKey: const Key('count'),
              bytesKey: const Key('bytes'),
              clearKey: const Key('clear'),
              deleteKey: const Key('delete'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Real phone widths, narrowest first.
const List<Size> _phoneSizes = <Size>[
  Size(320, 640), // small/legacy Android
  Size(360, 720), // very common budget phone
  Size(392, 800), // Pixel-class
  Size(412, 915), // large phone
];

void main() {
  group('SelectionActionBar layout', () {
    for (final Size size in _phoneSizes) {
      testWidgets('renders without layout errors at ${size.width.toInt()}dp', (
        WidgetTester tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(_host(selection: _selectionOf(3)));
        await tester.pumpAndSettle();

        // The regression: an infinite-width constraint throws during layout,
        // which surfaces here.
        expect(
          tester.takeException(),
          isNull,
          reason: 'layout threw at ${size.width}dp',
        );

        expect(find.byKey(const Key('clear')), findsOneWidget);
        expect(find.byKey(const Key('delete')), findsOneWidget);

        // Both buttons must have finite, on-screen bounds.
        for (final String key in <String>['clear', 'delete']) {
          final Rect rect = tester.getRect(find.byKey(Key(key)));
          expect(rect.width.isFinite, isTrue, reason: '$key width infinite');
          expect(rect.height.isFinite, isTrue, reason: '$key height infinite');
          expect(rect.width, greaterThan(0));
          expect(
            rect.right <= size.width + 0.5,
            isTrue,
            reason: '$key is cut off at ${size.width}dp',
          );
        }
      });
    }

    testWidgets('the Delete button is never given an infinite width', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_host(selection: _selectionOf(2)));
      await tester.pumpAndSettle();

      final RenderBox box = tester.renderObject<RenderBox>(
        find.byKey(const Key('delete')),
      );
      expect(box.constraints.maxWidth.isFinite, isTrue);
      expect(box.size.width.isFinite, isTrue);
      // A sane button, not one stretched across the bar.
      expect(box.size.width, lessThan(360));
      expect(tester.takeException(), isNull);
    });

    testWidgets('buttons keep a comfortable tap height', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_host(selection: _selectionOf(1)));
      await tester.pumpAndSettle();

      final Rect delete = tester.getRect(find.byKey(const Key('delete')));
      expect(delete.height, greaterThanOrEqualTo(44));
      expect(delete.height.isFinite, isTrue);
    });

    testWidgets('survives a long size label and a large font scale', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          // A partly deletable selection renders the longest label.
          child: _host(selection: _selectionOf(9), deletableCount: 4),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('delete')), findsOneWidget);
      expect(find.byKey(const Key('clear')), findsOneWidget);
    });

    testWidgets('Clear and Delete both fire', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      int cleared = 0;
      int deleted = 0;
      await tester.pumpWidget(
        _host(
          selection: _selectionOf(2),
          onClear: () => cleared++,
          onDelete: () => deleted++,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('clear')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete')));
      await tester.pumpAndSettle();

      expect(cleared, 1);
      expect(deleted, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the count and size, and disables an undeletable set', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _host(selection: _selectionOf(2), deletableCount: 0),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('count'))).data,
        '2 selected',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('bytes'))).data,
        '60.0 MB',
      );
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('delete'))).onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
