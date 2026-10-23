import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// The public site, which is where the legal and support pages live.
///
/// They are web pages rather than screens on purpose: the App Store needs a
/// privacy policy and a support page reachable without the app, and keeping
/// one copy of each means a wording change never waits on a release.
const String kSondrSite = 'https://s-ndr.com';
const String kTermsUrl = '$kSondrSite/terms';
const String kPrivacyUrl = '$kSondrSite/privacy';
const String kSupportUrl = '$kSondrSite/support';

/// Opening one of those pages.
///
/// A seam, so a test can assert which URL a word sends someone to without a
/// platform channel on the other end — `url_launcher` is a plugin, and in a
/// widget test there is nothing to answer it.
abstract interface class LegalPages {
  Future<void> open(String url);
}

class _BrowserLegalPages implements LegalPages {
  const _BrowserLegalPages();

  /// In-app browser, not Safari. The person is mid-signup; handing them to
  /// another app and relying on them to come back loses accounts, and the
  /// in-app sheet closes back onto the screen they left.
  ///
  /// A failure is logged and swallowed: there is nothing useful to say on a
  /// screen that cannot open a web page, and the words themselves are not
  /// the agreement — creating the account is.
  @override
  Future<void> open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
    } catch (e) {
      debugPrint('SONDR legal page error: ${e.runtimeType} :: $e');
    }
  }
}

final legalPagesProvider = Provider<LegalPages>(
  (ref) => const _BrowserLegalPages(),
);
