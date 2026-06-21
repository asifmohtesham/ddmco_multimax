import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// ERPNext v15 avatar: primary-tinted circle (or rounded square) showing 1–2
/// letter initials in `primary`, or an image. Colors from [BuildContext.scheme].
class AppAvatar extends StatelessWidget {
  final String? initials;
  final ImageProvider? image;
  final double size;
  final bool square;

  const AppAvatar({
    super.key,
    this.initials,
    this.image,
    this.size = 36,
    this.square = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final bg = Color.alphaBlend(s.primary.withValues(alpha: 0.16), s.fg);
    final label = (initials ?? '').trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: image == null ? bg : null,
        shape: square ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: square ? BorderRadius.circular(AppRadius.md) : null,
        image: image != null
            ? DecorationImage(image: image!, fit: BoxFit.cover)
            : null,
      ),
      child: image != null || label.isEmpty
          ? null
          : Text(
              label.length > 2 ? label.substring(0, 2).toUpperCase() : label.toUpperCase(),
              style: TextStyle(
                color: s.primary,
                fontWeight: FontWeight.w600,
                fontSize: size * 0.34,
                height: 1.0,
              ),
            ),
    );
  }
}

/// A row of overlapping [AppAvatar]s (assignees / shared-with). Each overlaps
/// the previous by [overlap] px and carries a 2px `fg` ring; rendered with a
/// Stack so the overlap actually reclaims horizontal space (a Row cannot do
/// negative spacing). Assumes each child is [avatarSize] wide.
class AvatarGroup extends StatelessWidget {
  final List<Widget> children;
  final double avatarSize;
  final double overlap;

  const AvatarGroup({
    super.key,
    required this.children,
    this.avatarSize = 36,
    this.overlap = 10,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    const ring = 2.0;
    final step = avatarSize - overlap; // horizontal advance per avatar
    final ringed = avatarSize + ring * 2;
    final width = children.isEmpty ? 0.0 : ringed + step * (children.length - 1);
    return SizedBox(
      height: ringed,
      width: width,
      child: Stack(
        children: [
          for (var i = 0; i < children.length; i++)
            Positioned(
              left: i * step,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: s.fg, width: ring),
                ),
                child: children[i],
              ),
            ),
        ],
      ),
    );
  }
}
