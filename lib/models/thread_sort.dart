/// 版块排序文案与参数沿用站点自己的排序链接。
enum ThreadSort {
  latest('最新回复', null, null),
  posted('最新发布', 'author', 'dateline'),
  replies('回复最多', 'reply', 'replies'),
  views('查看最多', 'reply', 'views');

  const ThreadSort(this.label, this.filter, this.orderby);

  final String label;
  final String? filter;
  final String? orderby;

  bool get groupsByDate => this == latest || this == posted;

  static const fallback = ThreadSort.latest;
}
