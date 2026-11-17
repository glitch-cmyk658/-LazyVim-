-- Markdown 渲染在 nvim 里全部关闭：看排版/公式用 Pebrel 的 Markdown 文档标签。
-- 本机实测：LazyVim 自带的 markdown extras 会把 render-markdown.nvim 拉起来
-- （conceallevel=3 + 虚拟行），长行折行时会压字，所以这里显式禁用。
return {
  { "OXY2DEV/markview.nvim", enabled = false },
  { "MeanderingProgrammer/render-markdown.nvim", enabled = false },
  { "MeanderingProgrammer/markdown.nvim", enabled = false },
}
