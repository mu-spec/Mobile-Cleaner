import 'package:flutter/material.dart';
import 'package:mobile_cleaner/core/constants/app_constants.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const <Widget>[
          ListTile(
            leading: Icon(Icons.brightness_6_outlined),
            title: Text('Appearance'),
            subtitle: Text('Uses your device theme'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('App version'),
            subtitle: Text(AppConstants.appVersion),
          ),
        ],
      ),
    );
  }
}
