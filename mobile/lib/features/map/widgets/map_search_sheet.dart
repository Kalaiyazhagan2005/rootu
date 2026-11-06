import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/theme/app_theme.dart';
import '../services/nominatim_search_service.dart';

/// Modal bottom sheet allowing searching and pinning locations via OpenStreetMap Nominatim
class MapSearchSheet extends StatefulWidget {
  final String title;
  final LatLng? userLocation;
  final ValueChanged<NominatimResult> onLocationSelected;

  const MapSearchSheet({
    super.key,
    this.title = 'Search & Pin Location',
    this.userLocation,
    required this.onLocationSelected,
  });

  static Future<void> show({
    required BuildContext context,
    String title = 'Search & Pin Location',
    LatLng? userLocation,
    required ValueChanged<NominatimResult> onLocationSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.primaryDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => MapSearchSheet(
        title: title,
        userLocation: userLocation,
        onLocationSelected: onLocationSelected,
      ),
    );
  }

  @override
  State<MapSearchSheet> createState() => _MapSearchSheetState();
}

class _MapSearchSheetState extends State<MapSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<NominatimResult> _results = [];
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final results = await NominatimSearchService.search(
        query,
        userLocation: widget.userLocation,
      );
      if (mounted) {
        setState(() {
          _results = results;
          if (results.isEmpty) {
            _errorMessage = 'No results found. Try a different city or street name.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Search error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pin_drop_rounded, color: AppTheme.accentLightGreen),
              const SizedBox(width: 8),
              Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white60),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'e.g. Kallakurichi, Salem, Chennai...',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              prefixIcon: const Icon(Icons.search, color: AppTheme.accentLightGreen),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => _performSearch(),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentLightGreen,
                foregroundColor: AppTheme.primaryDark,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _performSearch,
              icon: _isSearching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryDark),
                    )
                  : const Icon(Icons.navigation_rounded),
              label: const Text(
                'FIND LOCATION',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ],
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'SEARCH RESULTS',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _results.length,
                separatorBuilder: (_, __) => Divider(color: Colors.white.withValues(alpha: 0.08)),
                itemBuilder: (context, index) {
                  final result = _results[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.location_on_rounded, color: AppTheme.accentLightGreen, size: 20),
                    title: Text(
                      result.shortName,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    subtitle: Text(
                      result.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onLocationSelected(result);
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

