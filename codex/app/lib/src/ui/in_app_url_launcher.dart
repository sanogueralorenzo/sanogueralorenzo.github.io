import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<bool> openInAppUrl(BuildContext context, String url) {
  return launchUrl(
    Uri.parse(url),
    mode: LaunchMode.inAppBrowserView,
    webViewConfiguration: const WebViewConfiguration(
      enableJavaScript: true,
      enableDomStorage: true,
    ),
  );
}
