import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/theme/app_theme.dart';
import '../services/nominatim_search_service.dart';

/// Google Maps-style top floating search bar with instant autocomplete suggestions
class RouteSearchBar extends StatefulWidget {
  final ValueChanged<NominatimResult> onDestinationSelected;
  final VoidCallback onThemeToggle;
  final bool isDarkTheme;
  final LatLng? userLocation;

  const RouteSearchBar({
    super.key,
    required this.onDestinationSelected,
    required this.onThemeToggle,
    required this.isDarkTheme,
    this.userLocation,
  });

  @override
  State<RouteSearchBar> createState() => _RouteSearchBarState();
}

class _RouteSearchBarState extends State<RouteSearchBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<NominatimResult> _suggestions = [];
  bool _isSearching = false;
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() {
        _showSuggestions = _focusNode.hasFocus && _suggestions.isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _onQueryChanged(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    final results = await NominatimSearchService.search(
      trimmed,
      userLocation: widget.userLocation,
    );
    if (!mounted) return;

    setState(() {
      _suggestions = results;
      _showSuggestions = results.isNotEmpty && _focusNode.hasFocus;
      _isSearching = false;
    });
  }

  void _clearSearch() {
    _controller.clear();
    setState(() {
      _suggestions = [];
      _showSuggestions = false;
    });
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Floating Google Maps Style Search Card
            Container(
              decoration: BoxDecoration(
                color: AppTheme.primaryDark,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppTheme.accentLightGreen.withValues(alpha: 0.8),
                  width: 1.2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x59000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 14, right: 8),
                    child: Icon(
                      Icons.search_rounded,
                      color: AppTheme.accentLightGreen,
                      size: 22,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Search destination or place...',
                        hintStyle: TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                      onChanged: _onQueryChanged,
                    ),
                  ),
                  if (_isSearching)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.accentLightGreen,
                        ),
                      ),
                    )
                  else if (_controller.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                      onPressed: _clearSearch,
                    ),
                  Container(
                    height: 24,
                    width: 1,
                    color: Colors.white24,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  IconButton(
                    tooltip: 'Toggle Map Theme',
                    icon: Icon(
                      widget.isDarkTheme ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                      color: AppTheme.accentLightGreen,
                      size: 20,
                    ),
                    onPressed: widget.onThemeToggle,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),

            // Dropdown Autocomplete Suggestions
            if (_showSuggestions && _suggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                constraints: const BoxConstraints(maxHeight: 280),
                decoration: BoxDecoration(
                  color: AppTheme.primaryDark,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.accentLightGreen.withValues(alpha: 0.4),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) => Divider(
                    color: Colors.white.withValues(alpha: 0.08),
                    height: 1,
                  ),
                  itemBuilder: (context, index) {
                    final place = _suggestions[index];
                    return ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.location_on_outlined,
                          color: AppTheme.accentLightGreen,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        place.shortName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        place.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                      onTap: () {
                        _controller.text = place.shortName;
                        _focusNode.unfocus();
                        setState(() => _showSuggestions = false);
                        widget.onDestinationSelected(place);
                      },
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
