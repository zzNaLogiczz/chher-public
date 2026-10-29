/// 版块排序文案与参数沿用站点自己的排序链接。
enum ThreadSort {
  latest('最后发表', null, null),
  posted('发帖时间', 'author', 'dateline'),
  replies('回复/查看', 'reply', 'replies'),
  views('查看', 'reply', 'views');

  const ThreadSort(this.label, this.filter, this.orderby);

  final String label;
  final String? filter;
  final String? orderby;

  static const fallback = ThreadSort.latest;
}
