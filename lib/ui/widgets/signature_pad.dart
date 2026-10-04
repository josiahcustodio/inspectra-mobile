import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../../core/theme/app_colors.dart';

// [REF: SIGNATURE_PAD]
/// The inspector's sign-off pad.
///
/// Resurrected from the pre-rework build (`c3b67b8`), where it was dead code
/// attached to the deleted establishment-create screen. Here it captures the
/// digital replacement for the wet-ink SSSR/Signature column of the paper
/// masterlist — the mark the inspector draws across DATE INSPECTED — so the
/// bytes it exports end up on an audit record, not a convenience field.
///
/// The export is PNG on an explicit white background. Transparent would look
/// identical on this screen but the web masterlist renders the image over a
/// grid cell whose background it does not control, and a hash is taken of
/// these exact bytes at submit — so the export must be deterministic about
/// everything, background included.
class SignaturePadWidget extends StatefulWidget {
  final String title;

  /// Fired with the exported PNG bytes when a signature is saved, and with
  /// null when it is cleared, so the form always holds the same bytes the
  /// preview is showing.
  final ValueChanged<Uint8List?> onSaved;

  /// Restores a previously saved signature. The form swaps its entire body
  /// for a spinner while submitting, which disposes this State; without this,
  /// a failed submit would come back to an empty pad over a form that still
  /// held — and would still upload — the old bytes.
  final Uint8List? initialBytes;

  const SignaturePadWidget({
    super.key,
    required this.title,
    required this.onSaved,
    this.initialBytes,
  });

  @override
  State<SignaturePadWidget> createState() => SignaturePadWidgetState();
}

/// Public (no leading underscore) so the form can reach [exportIfDrawn]
/// through a GlobalKey at submit time — see the comment on that method.
class SignaturePadWidgetState extends State<SignaturePadWidget> {
  /// The blueprint's ~600px-wide target. Note that `toPngBytes(width:)` PADS
  /// rather than scales — the drawing is centered at its natural stroke
  /// resolution on a canvas this wide — so this normalizes the file's
  /// dimensions for the masterlist cell without resampling anything, and
  /// keeps the PNG far below the 200 KB cap storage.rules enforces.
  static const int _exportWidth = 600;

  final SignatureController _controller = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  Uint8List? _savedBytes;

  @override
  void initState() {
    super.initState();
    _savedBytes = widget.initialBytes;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Exports whatever is on the pad, saved or not. Null only when the pad is
  /// genuinely blank.
  ///
  /// Submit calls this instead of trusting the saved bytes alone, because the
  /// Save button is a preview convenience, not a data gate: an inspector who
  /// signed and went straight to Submit has still signed, and bouncing them
  /// with "add your signature" over a visibly signed pad would read as a
  /// broken form.
  Future<Uint8List?> exportIfDrawn() async {
    if (_savedBytes != null) return _savedBytes;
    if (_controller.isEmpty) return null;
    final bytes = await _exportPng();
    if (bytes == null) return null;
    // onSaved reaches into the form's setState, so it is gated on mounted
    // along with our own: if the screen was popped during the export, the
    // form State is as dead as this one. The caller still gets the bytes and
    // does its own mounted check before using them.
    if (mounted) {
      setState(() => _savedBytes = bytes);
      widget.onSaved(bytes);
    }
    return bytes;
  }

  Future<Uint8List?> _exportPng() {
    // toPngBytes(width:) centers the natural-size drawing on a canvas of the
    // requested width — padding, not upscaling — and it asserts in debug
    // (silently crops in release) when that width is smaller than the
    // drawing's own bounding box. So the 600px canvas is requested only when
    // the drawing fits inside it; a signature drawn wider than 600 logical
    // px (tablet) exports at its natural size instead of losing its edges.
    final drawnWidth = _controller.defaultWidth;
    final padToTarget = drawnWidth != null && drawnWidth < _exportWidth;
    return _controller.toPngBytes(width: padToTarget ? _exportWidth : null);
  }

  Future<void> _handleSave() async {
    if (_controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draw your signature first.')),
      );
      return;
    }
    final bytes = await _exportPng();
    if (bytes == null || !mounted) return;
    setState(() => _savedBytes = bytes);
    widget.onSaved(bytes);
  }

  void _handleClear() {
    _controller.clear();
    widget.onSaved(null);
  }

  void _handleRedo() {
    // Back to a blank pad, not the old strokes: the controller only ever held
    // points for the current drawing session, and a disposed/rebuilt State
    // (post-submit-failure) never had them at all. A consistent "redo means
    // start over" is better than a redo that sometimes restores and sometimes
    // doesn't.
    _controller.clear();
    setState(() => _savedBytes = null);
    widget.onSaved(null);
  }

  @override
  Widget build(BuildContext context) {
    final saved = _savedBytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontFamily: '.SF Pro Display',
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          height: 180,
          decoration: BoxDecoration(
            // White rather than AppColors.background: the pad has to look
            // like the exported image, and the export background is white.
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderStrong, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: saved != null
                ? Image.memory(saved, fit: BoxFit.contain)
                : Signature(
                    controller: _controller,
                    backgroundColor: Colors.white,
                  ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: saved != null
              ? [
                  TextButton.icon(
                    onPressed: _handleRedo,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Redo signature'),
                  ),
                ]
              : [
                  TextButton(
                    onPressed: _handleClear,
                    child: const Text('Clear'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _handleSave,
                    child: const Text('Save Signature'),
                  ),
                ],
        ),
      ],
    );
  }
}
