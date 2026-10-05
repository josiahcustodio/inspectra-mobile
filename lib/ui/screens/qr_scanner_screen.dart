import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../data/services/offline_service.dart';
import '../../data/models/establishment.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController controller = MobileScannerController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isNavigating = false;
  List<Establishment> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  // [REF: QR_MANUAL_SEARCH]
  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      if (_suggestions.isNotEmpty) {
        setState(() => _suggestions = []);
      }
      return;
    }

    final allEst = OfflineService.getLocalEstablishments();
    final matches = allEst.where((est) {
      return est.name.toLowerCase().contains(query) ||
             est.id.toLowerCase().contains(query);
    }).take(5).toList();

    setState(() {
      _suggestions = matches;
    });
  }

  void _onSuggestionTap(Establishment establishment) {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);
    controller.stop();
    _searchFocusNode.unfocus();
    context.pushReplacement('/inspection', extra: establishment);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    controller.dispose();
    super.dispose();
  }

  // [REF: SCAN_QR_CODE]
  void _onDetect(BarcodeCapture capture) {
    if (_isNavigating) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code != null && code.isNotEmpty) {
        final establishment = OfflineService.getEstablishmentById(code);
        if (establishment != null) {
          setState(() => _isNavigating = true);
          controller.stop();
          context.pushReplacement('/inspection', extra: establishment);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Establishment not found in local DB.'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
        break; // Process only the first valid code found
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    const frameSize = 250.0; // Slightly larger for better UX

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera feed ──────────────────────────────
          MobileScanner(
            controller: controller,
            onDetect: _onDetect,
          ),

          // ── Dark overlay with hole ───────────────────
          Positioned.fill(
            child: CustomPaint(
              painter: _OverlayPainter(frameSize: frameSize),
            ),
          ),

          // ── Clean 2px white border scan box ───────────
          Center(
            child: Container(
              width: frameSize,
              height: frameSize,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2.0),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          // ── Instruction text ──────────────────────────
          Center(
            child: Transform.translate(
              // Position 20px below the frame box (which is frameSize/2 from center)
              offset: const Offset(0, frameSize / 2 + 20),
              child: const Text(
                'Align QR code within the frame',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  shadows: [
                    Shadow(
                        color: Colors.black87,
                        blurRadius: 4,
                        offset: Offset(0, 1))
                  ],
                ),
              ),
            ),
          ),

          // ── Top header bar ──────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(76), // 30% black
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_back,
                            color: Colors.white, size: 22),
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      'Scan QR Code',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                        shadows: [
                          Shadow(
                              color: Colors.black87,
                              blurRadius: 4,
                              offset: Offset(0, 1))
                        ],
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => controller.toggleTorch(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(76),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.highlight,
                            color: Colors.white, size: 22),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom Action Bar ───────────────────────────
          Positioned(
            bottom: 32,
            left: 24,
            right: 24,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_suggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(70),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          )
                        ],
                      ),
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final est = _suggestions[index];
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              title: Text(est.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              // D1 — never the id or the category badge.
                              // Full address first, owner as fallback,
                              // matching the sibling picker in
                              // new_inspection_modal so the two agree.
                              subtitle: Text(
                                est.fullAddress.toUpperCase() != 'N/A'
                                    ? est.fullAddress
                                    : est.ownerName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _onSuggestionTap(est),
                            ),
                          );
                        },
                      ),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: primary, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(70),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        )
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      decoration: InputDecoration(
                        hintText: 'Search by Establishment Name or ID...',
                        hintStyle: TextStyle(
                            color: Colors.grey.shade500, fontSize: 13),
                        prefixIcon: Icon(Icons.search, color: primary),
                        suffixIcon: _searchController.text.isNotEmpty 
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.grey), 
                                onPressed: () {
                                  _searchController.clear();
                                  _searchFocusNode.unfocus();
                                }
                              ) 
                            : null,
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Overlay with transparent window (Cutout) ────────
class _OverlayPainter extends CustomPainter {
  final double frameSize;
  _OverlayPainter({required this.frameSize});

  @override
  void paint(Canvas canvas, Size size) {
    // Semi-transparent dark overlay for the outside (approx 75% opacity)
    final paint = Paint()..color = Colors.black.withAlpha(190);
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Define the clear scanning box hole
    final rect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: frameSize,
      height: frameSize,
    );

    // Creates the punched hole effect using evenOdd rule (fixes Flutter Web solid-fill bugs)
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)));

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => old.frameSize != frameSize;
}
