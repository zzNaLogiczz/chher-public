# 合成解析样本

本目录只保存从零编写的最小 HTML 样本，用于离线验证 Discuz 页面结构解析。账号、UID、帖子、正文、时间、表单值和附件路径均为测试数据，不代表真实用户或会话；使用站点域名的链接只验证 URL 解析，不会由解析器发出网络请求。

- `forum_index_synthetic.html`：嵌套分区、版块归属、计数缩写。
- `thread_list_synthetic.html`、`guide_synthetic.html`、`search_synthetic.html`：列表字段、置顶、分页和不同列语义。
- `thread_synthetic.html`、`archiver_synthetic.html`：楼层、头像、编辑说明、评分、图片、内联表情和链接预览。
- `article_*_synthetic.html`：评论、引用、游客表单和文章跳转。
- `content_links_synthetic.html`、`thread_quote_synthetic.html`、`thread_reference_synthetic.html`：视频、站内外链接、显式引用标识和嵌套引用。
- `login_synthetic.html`：空白登录表单。

更新样本时，手写需要覆盖的最小结构并同步调整测试断言。不要提交抓取页面、真实正文、私信、用户名、Cookie、验证码、会话标识或截图。需要暂存的真实证据放入 Git 忽略的本地目录，不复制到这里。

运行 `flutter test` 验证全部离线测试。测试只使用合成数据或 fake transport，不向论坛发帖、评论或发送私信。
