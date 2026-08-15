import 'package:flutter/material.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/file_category_card.dart';

class ScannedFileTile extends StatelessWidget {
  const ScannedFileTile({required this.file, this.onTap, super.key});

  final ScannedFile file;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return ListTile(
      key: Key('file_tile_${file.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: CircleAvatar(
        backgroundColor: colors.primaryContainer,
        child: Icon(
          iconForCategory(file.category),
          size: 20,
          color: colors.primary,
        ),
      ),
      title: Text(
        file.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${_formatDate(file.dateModified)} · ${file.folderName}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: colors.onSurfaceVariant),
      ),
      trailing: Text(
        ByteFormatter.format(file.sizeBytes),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      onTap: onTap ?? () => _showDetails(context),
    );
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  file.name,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                _DetailRow(
                  label: 'Type',
                  value: file.mimeType ?? file.category.label,
                ),
                _DetailRow(
                  label: 'Size',
                  value: ByteFormatter.format(file.sizeBytes),
                ),
                _DetailRow(
                  label: 'Modified',
                  value: _formatDate(file.dateModified),
                ),
                _DetailRow(
                  label: 'Location',
                  value: file.path.isNotEmpty ? file.path : file.uri,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    if (date.millisecondsSinceEpoch == 0) {
      return 'Unknown date';
    }
    final String day = date.day.toString().padLeft(2, '0');
    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '$day ${months[date.month - 1]} ${date.year}';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
