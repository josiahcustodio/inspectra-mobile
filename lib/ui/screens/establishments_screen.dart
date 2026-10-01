import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import '../../data/services/offline_service.dart';

class EstablishmentsScreen extends StatefulWidget {
  const EstablishmentsScreen({super.key});

  @override
  State<EstablishmentsScreen> createState() => _EstablishmentsScreenState();
}

class _EstablishmentsScreenState extends State<EstablishmentsScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    
    // [REF: ESTABLISHMENT_LIST]
    var establishments = OfflineService.getLocalEstablishments();
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      // Matched against the same three fields the row renders, so a hit is
      // always visible in the result — searching a hidden field would look
      // like the filter was broken.
      establishments = establishments.where((e) =>
        e.name.toLowerCase().contains(query) ||
        e.ownerName.toLowerCase().contains(query) ||
        e.formattedAddress.toLowerCase().contains(query)
      ).toList();
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Text(
                'Establishments',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: primary,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                    )
                  ],
                ),
                child: TextField(
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search establishments…',
                    prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // List
            Expanded(
              child: establishments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.store_outlined,
                              size: 64, color: primary.withValues(alpha: 0.3)),
                          const SizedBox(height: 12),
                          Text(
                            'No establishments yet',
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      itemCount: establishments.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final e = establishments[i];
                        return InkWell(
                          // Same entry point the new-inspection modal uses, so
                          // both routes into an inspection behave identically.
                          onTap: () => context.push('/inspection', extra: e),
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                )
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child:
                                      Icon(Icons.store_rounded, color: primary),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      if (e.ownerName.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          e.ownerName,
                                          style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 12),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                      const SizedBox(height: 2),
                                      Text(
                                        e.formattedAddress,
                                        style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 12),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded,
                                    color: Colors.grey.shade400),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
