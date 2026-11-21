import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/artist_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/listening_stats_utils.dart';
import 'package:musify/utilities/mediaitem.dart';
import 'package:musify/widgets/song_artwork.dart';

/// Loads a profile only when its avatar enters the visible scroll viewport.
class RecapArtistAvatar extends StatefulWidget {
  const RecapArtistAvatar({
    required this.artist,
    required this.size,
    super.key,
  });
  final ListeningArtist artist;
  final double size;

  @override
  State<RecapArtistAvatar> createState() => _RecapArtistAvatarState();
}

class _RecapArtistAvatarState extends State<RecapArtistAvatar> {
  ScrollPosition? _position;
  String? _image;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    offlineMode.addListener(_onOfflineChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_scheduleCheck);
      _position = position;
      _position?.addListener(_scheduleCheck);
    }
    _scheduleCheck();
  }

  @override
  void didUpdateWidget(covariant RecapArtistAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artist.id != widget.artist.id ||
        oldWidget.artist.name != widget.artist.name ||
        oldWidget.artist.topSong['ytid'] != widget.artist.topSong['ytid']) {
      _requested = false;
      _image = null;
      _scheduleCheck();
    }
  }

  void _onOfflineChanged() {
    if (!mounted) return;
    setState(() {});
    _scheduleCheck();
  }

  void _scheduleCheck() {
    if (!_requested)
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  bool _isVisible() {
    if (!mounted ||
        !TickerMode.valuesOf(context).enabled ||
        ModalRoute.of(context)?.isCurrent == false)
      return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return false;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (!rect.overlaps(Offset.zero & MediaQuery.sizeOf(context))) return false;
    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    return viewport is! RenderBox ||
        !viewport.hasSize ||
        rect.overlaps(viewport.localToGlobal(Offset.zero) & viewport.size);
  }

  void _check() {
    final artist = widget.artist;
    final id = artist.id;
    if (id == null || _requested || !_isVisible() || offlineMode.value) {
      return;
    }
    _requested = true;
    Future<void> load() async {
      try {
        final profile = await getArtistProfile(
          id,
          preferredName: artist.name,
          preferredVerified: true,
        );
        if (!mounted || widget.artist.id != id) return;
        if (!_isVisible() || offlineMode.value) {
          _requested = false;
          return;
        }
        final image = profile?['image']?.toString();
        if (image != null && image.isNotEmpty) {
          setState(() => _image = image);
        }
      } catch (_) {
        // The song artwork remains usable if the cache or network is unavailable.
      }
    }

    load();
  }

  @override
  void dispose() {
    offlineMode.removeListener(_onOfflineChanged);
    _position?.removeListener(_scheduleCheck);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget fallback() => SongArtworkWidget(
      size: widget.size,
      borderRadius: widget.size / 2,
      metadata: mapToMediaItem(widget.artist.topSong),
    );
    final image = _image;
    if (image == null || offlineMode.value) return fallback();
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: image,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback(),
        errorWidget: (_, _, _) => fallback(),
      ),
    );
  }
}
