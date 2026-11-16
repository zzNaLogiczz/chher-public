import 'models.dart';

/// A contiguous run of images, with its position in the unmodified post.
/// URL duplicates are intentional: gallery navigation is positional.
class ImageStackGroup {
  final List<String> urls;
  final List<double?> aspectRatios;
  final int galleryStartIndex;
  final int blockIndex;

  ImageStackGroup({
    required List<String> urls,
    List<double?>? aspectRatios,
    required this.galleryStartIndex,
    required this.blockIndex,
  }) : assert(urls.length >= 2),
       assert(galleryStartIndex >= 0),
       assert(blockIndex >= 0),
       assert(aspectRatios == null || aspectRatios.length == urls.length),
       aspectRatios = List.unmodifiable(
         aspectRatios ?? List.filled(urls.length, null),
       ),
       urls = List.unmodifiable(urls);
}

/// Either an untouched content block or a contiguous multi-image group.
/// [galleryIndex] counts only top-level images preceding this segment.
class PostContentSegment {
  final ContentBlock? block;
  final ImageStackGroup? imageStack;
  final List<SiteLinkBlock>? siteLinks;
  final bool linksGrouped;
  final bool linkGroupStart;
  final bool linkGroupEnd;
  final int blockIndex;
  final int galleryIndex;

  const PostContentSegment.block(
    ContentBlock value, {
    required this.blockIndex,
    required this.galleryIndex,
  }) : block = value,
       imageStack = null,
       siteLinks = null,
       linksGrouped = false,
       linkGroupStart = true,
       linkGroupEnd = true;

  PostContentSegment.stack(ImageStackGroup value)
    : block = null,
      siteLinks = null,
      linksGrouped = false,
      linkGroupStart = true,
      linkGroupEnd = true,
      imageStack = value,
      blockIndex = value.blockIndex,
      galleryIndex = value.galleryStartIndex;

  PostContentSegment.links(
    List<SiteLinkBlock> links, {
    required this.blockIndex,
    required this.galleryIndex,
    this.linksGrouped = false,
    this.linkGroupStart = true,
    this.linkGroupEnd = true,
  }) : block = links.first,
       imageStack = null,
       siteLinks = List.unmodifiable(links);
}

/// Groups before presentation filters run, so even an omitted quote remains
/// a boundary between the images on either side. Quoted children stay intact.
List<PostContentSegment> groupPostImages(
  List<ContentBlock> blocks, {
  bool groupImages = true,
}) {
  final segments = <PostContentSegment>[];
  var index = 0;
  var galleryIndex = 0;
  while (index < blocks.length) {
    final block = blocks[index];
    if (block is SiteLinkBlock) {
      var end = index + 1;
      while (end < blocks.length && blocks[end] is SiteLinkBlock) {
        end++;
      }
      // A long card remains one visual surface but each row stays a sliver
      // entry, keeping viewport loading and the 24-fragment reveal budget.
      if (end - index > 12) {
        for (var i = index; i < end; i++) {
          segments.add(
            PostContentSegment.links(
              [blocks[i] as SiteLinkBlock],
              blockIndex: i,
              galleryIndex: galleryIndex,
              linksGrouped: true,
              linkGroupStart: i == index,
              linkGroupEnd: i == end - 1,
            ),
          );
        }
      } else {
        segments.add(
          PostContentSegment.links(
            blocks.sublist(index, end).cast<SiteLinkBlock>(),
            blockIndex: index,
            galleryIndex: galleryIndex,
          ),
        );
      }
      index = end;
      continue;
    }
    if (block is! ImageBlock || !groupImages) {
      segments.add(
        PostContentSegment.block(
          block,
          blockIndex: index,
          galleryIndex: galleryIndex,
        ),
      );
      if (block is ImageBlock) galleryIndex++;
      index++;
      continue;
    }
    var end = index + 1;
    while (end < blocks.length && blocks[end] is ImageBlock) {
      end++;
    }
    if (end - index == 1) {
      segments.add(
        PostContentSegment.block(
          block,
          blockIndex: index,
          galleryIndex: galleryIndex,
        ),
      );
    } else {
      segments.add(
        PostContentSegment.stack(
          ImageStackGroup(
            urls: [
              for (var i = index; i < end; i++) (blocks[i] as ImageBlock).url,
            ],
            aspectRatios: [
              for (var i = index; i < end; i++)
                (blocks[i] as ImageBlock).aspectRatio,
            ],
            galleryStartIndex: galleryIndex,
            blockIndex: index,
          ),
        ),
      );
    }
    galleryIndex += end - index;
    index = end;
  }
  return List.unmodifiable(segments);
}
