import 'package:flutter/material.dart';

import '../theme/dm_theme.dart';

/// Tappable select field.
///
/// Opens a bottom sheet with a search box and a scrollable list. This scales to
/// hundreds of options (cities, states) and behaves exactly like a dropdown,
/// while staying fast and reachable with one thumb.
class DmSelectField extends StatelessWidget {
  final String hint;
  final IconData icon;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final String? Function(String?)? validator;
  final bool enabled;
  final String? disabledHint;
  final String searchHint;

  const DmSelectField({
    super.key,
    required this.hint,
    required this.options,
    required this.onChanged,
    this.value,
    this.icon = Icons.arrow_drop_down_rounded,
    this.validator,
    this.enabled = true,
    this.disabledHint,
    this.searchHint = 'Search',
  });

  Future<void> _open(BuildContext context) async {
    if (!enabled) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => _OptionSheet(
        title: hint,
        options: options,
        selected: value,
        searchHint: searchHint,
      ),
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return FormField<String>(
      initialValue: value,
      validator: validator,
      builder: (state) {
        // Keep the displayed value in sync when the parent rebuilds with a new one.
        final display = value ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: enabled ? () => _open(context) : null,
              borderRadius: BorderRadius.circular(radiusField),
              child: InputDecorator(
                isEmpty: display.isEmpty,
                decoration: InputDecoration(
                  prefixIcon: Icon(icon, size: 20),
                  suffixIcon:
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                  enabled: enabled,
                  errorText: state.errorText,
                  filled: true,
                  fillColor: enabled ? panel : panel3,
                ),
                child: Text(
                  // When a value is set show it; otherwise show the "disabled"
                  // hint only while the field is actually disabled.
                  display.isNotEmpty
                      ? display
                      : (enabled ? hint : (disabledHint ?? hint)),
                  style: TextStyle(
                    fontSize: 14,
                    color:
                        display.isEmpty ? const Color(0xFF6B7280) : softWhite,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OptionSheet extends StatefulWidget {
  final String title;
  final List<String> options;
  final String? selected;
  final String searchHint;

  const _OptionSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.searchHint,
  });

  @override
  State<_OptionSheet> createState() => _OptionSheetState();
}

class _OptionSheetState extends State<_OptionSheet> {
  static const double _rowHeight = 48;

  late List<String> _visible;
  late final ScrollController _scroll;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _visible = widget.options;
    // Open the list at the current selection instead of always at the top.
    final index =
        widget.selected == null ? 0 : widget.options.indexOf(widget.selected!);
    _scroll = ScrollController(
        initialScrollOffset: index <= 0 ? 0 : index * _rowHeight);
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _filter(String query) {
    final text = query.trim().toLowerCase();
    setState(() {
      _visible = text.isEmpty
          ? widget.options
          : widget.options
              .where((option) => option.toLowerCase().contains(text))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                  color: hairline, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Select ${widget.title.toLowerCase()}',
                        style: dmHeading(size: 18)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            if (widget.options.length > 8)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 12),
                child: TextField(
                  controller: _search,
                  onChanged: _filter,
                  autofocus: false,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: widget.searchHint,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _search.clear();
                              _filter('');
                            },
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                  ),
                ),
              )
            else
              const SizedBox(height: 6),
            Expanded(
              child: _visible.isEmpty
                  ? Center(
                      child: Text('Nothing matched that search.',
                          style: dmCaption(size: 12.5)),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.only(bottom: 20),
                      itemCount: _visible.length,
                      itemBuilder: (context, index) {
                        final option = _visible[index];
                        final isSelected = option == widget.selected;
                        return ListTile(
                          dense: true,
                          title: Text(
                            option,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: isSelected ? red : softWhite,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle_rounded,
                                  color: red, size: 19)
                              : null,
                          onTap: () => Navigator.pop(context, option),
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
