import 'package:flutter/material.dart';

class PermissionTile extends StatelessWidget {
  const PermissionTile({
    super.key,
    required this.title,
    required this.description,
    required this.granted,
    required this.onOpenSettings,
    this.actionLabel = 'Odpri nastavitve',
  });

  final String title;
  final String description;
  final bool granted;
  final VoidCallback onOpenSettings;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        granted ? Icons.check_circle : Icons.radio_button_unchecked,
        color: granted ? Colors.green : theme.colorScheme.outline,
      ),
      title: Text(title),
      subtitle: Text(description),
      isThreeLine: description.length > 40,
      trailing: granted
          ? null
          : FilledButton.tonal(onPressed: onOpenSettings, child: Text(actionLabel)),
    );
  }
}
