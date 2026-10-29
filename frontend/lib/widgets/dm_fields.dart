import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/dm_theme.dart';

/// Rounded input with a leading icon and a hint (no floating label) to match
/// the reference design.
class DmField extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final int maxLines;
  final int? maxLength;
  final bool readOnly;
  final bool enabled;
  final VoidCallback? onTap;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode? focusNode;
  final String? helper;

  const DmField({
    super.key,
    this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.maxLength,
    this.readOnly = false,
    this.enabled = true,
    this.onTap,
    this.inputFormatters,
    this.focusNode,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscure,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          validator: validator,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          maxLines: obscure ? 1 : maxLines,
          maxLength: maxLength,
          readOnly: readOnly,
          enabled: enabled,
          onTap: onTap,
          inputFormatters: inputFormatters,
          style: TextStyle(fontSize: 14, color: softWhite),
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            prefixIcon: Icon(icon, size: 20),
            suffixIcon: suffix,
            alignLabelWithHint: true,
          ),
        ),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(helper!, style: dmCaption(size: 11)),
          ),
      ],
    );
  }
}

/// Read-only field that opens a date picker.
class DmDateField extends StatelessWidget {
  final String hint;
  final IconData icon;
  final DateTime? value;
  final VoidCallback onTap;
  final String? Function(String?)? validator;

  const DmDateField({
    super.key,
    required this.hint,
    required this.value,
    required this.onTap,
    this.icon = Icons.calendar_month_outlined,
    this.validator,
  });

  static String format(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  static String toApiDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return FormField<String>(
      initialValue: value == null ? null : 'set',
      validator: validator,
      builder: (state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radiusField),
              child: InputDecorator(
                decoration: InputDecoration(
                  prefixIcon: Icon(icon, size: 20),
                  suffixIcon:
                      const Icon(Icons.edit_calendar_outlined, size: 18),
                  errorText: state.errorText,
                ),
                child: Text(
                  value == null ? hint : format(value!),
                  style: TextStyle(
                      fontSize: 14,
                      color:
                          value == null ? const Color(0xFF6F7681) : softWhite),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Checkbox + rich text used for Terms / consent rows.
class DmAgreementRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final List<InlineSpan> text;
  const DmAgreementRow(
      {super.key,
      required this.value,
      required this.onChanged,
      required this.text});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: Checkbox(
                  value: value, onChanged: (next) => onChanged(next ?? false)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text.rich(
                    TextSpan(style: dmCaption(size: 11.8), children: text)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small uppercase section label ("STEP 3", "TRAINING", ...).
class DmSectionLabel extends StatelessWidget {
  final String text;
  final Color? color;
  const DmSectionLabel(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
          color: color ?? red,
        ),
      ),
    );
  }
}

/// Multi-select / single-select chip used for languages and driving skills.
class DmSelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final IconData? icon;

  const DmSelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return FilterChip(
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      avatar: icon == null
          ? null
          : Icon(icon, size: 15, color: selected ? Colors.white : muted),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : softWhite,
        ),
      ),
      backgroundColor: panel,
      selectedColor: redDeep,
      side: BorderSide(color: selected ? redDeep : hairline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    );
  }
}
