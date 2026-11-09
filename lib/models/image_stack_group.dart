import 'models.dart';

/// A contiguous run of images, with its position in the unmodified post.
/// URL duplicates are intentional: gallery navigation is positional.
class ImageStackGroup {
  final List<String> urls;
  final int galleryStartIndex;
  final int blockIndex;

  ImageStackGroup({
    required List<String> urls,
    required this.galleryStartIndex,
    required this.blockIndex,
  }) : assert(urls.length >= 2),
       assert(galleryStartIndex >= 0),
       assert(blockIndex >= 0),
       urls = List.unmodifiable(urls);
}

/// Either an untouched content block or a contiguous multi-image group.
/// [galleryIndex] counts only top-level images preceding this segment.
class PostContentSegment {
  final ContentBlock? block;
  final ImageStackGroup? imageStack;
  final int blockIndex;
  final int galleryIndex;

  const PostContentSegment.block(
    ContentBlock value, {
    required this.blockIndex,
    required this.galleryIndex,
  }) : block = value,
       imageStack = null;

  PostContentSegment.stack(ImageStackGroup value)
    : block = null,
      imageStack = value,
      blockIndex = value.blockIndex,
      galleryIndex = value.galleryStartIndex;
}

/// Groups before presentation filters run, so even an omitted quote remains
/// a boundary between the images on either side. Quoted children stay intact.
List<PostContentSegment> groupPostImages(List<ContentBlock> blocks) {
  final segments = <PostContentSegment>[];
  var index = 0;
  var galleryIndex = 0;
  while (index < blocks.length) {
    final block = blocks[index];
    if (block is! ImageBlock) {
      segments.add(
        PostContentSegment.block(
          block,
          blockIndex: index,
          galleryIndex: galleryIndex,
        ),
      );
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
