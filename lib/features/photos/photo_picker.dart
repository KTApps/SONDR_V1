import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Shared photo capture front-end: offers the camera/library choice, then picks
/// and downscales the image (1080px wide, quality 80). Returns the chosen file,
/// or null if the user backed out of the source sheet or the picker, or if the
/// camera/library failed to open (a snackbar explains that case).
///
/// Bundled here so the session capture flow and the milestone share flow present
/// the identical choice and produce identically-sized uploads.
Future<File?> pickAndDownscale(BuildContext context) async {
  final source = await _pickSource(context);
  if (source == null) return null; // backed out of the source sheet

  final XFile? picked;
  try {
    picked = await ImagePicker()
        .pickImage(source: source, maxWidth: 1080, imageQuality: 80);
  } catch (e) {
    debugPrint('SONDR photo pick error: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
            content: Text('Couldn’t open the camera or library.')));
    }
    return null;
  }
  if (picked == null) return null; // backed out of the picker
  return File(picked.path);
}

/// Camera vs photo library (library is the simulator-testable path).
Future<ImageSource?> _pickSource(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from library'),
            onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
}
