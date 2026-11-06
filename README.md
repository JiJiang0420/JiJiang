# 魔女的盛宴 2.0 · 垂直切片 v0.1

这是可试玩版本的交付分支。源码、Godot 工程、Blender 模型与策划文档均在源码包中。

## 下载

| 文件 | 用途 |
| --- | --- |
| [Windows 试玩包](https://raw.githubusercontent.com/JiJiang0420/JiJiang/refs/heads/codex/witches-feast-delivery/WitchesFeast2-v0.1-windows.zip) | 约 37 MB；解压后双击 WitchesFeast2.exe，无需安装 Godot |
| [Linux 试玩包](https://raw.githubusercontent.com/JiJiang0420/JiJiang/refs/heads/codex/witches-feast-delivery/WitchesFeast2-v0.1-linux.zip) | 约 28 MB；解压后运行 WitchesFeast2.x86_64 |
| [Web 试玩包](https://raw.githubusercontent.com/JiJiang0420/JiJiang/refs/heads/codex/witches-feast-delivery/WitchesFeast2-v0.1-web.zip) | 约 10 MB；解压后用 HTTP 服务提供目录，不能直接双击 HTML |
| [完整源码](https://raw.githubusercontent.com/JiJiang0420/JiJiang/refs/heads/codex/witches-feast-delivery/WitchesFeast2-v0.1-source.zip) | 约 1.3 MB；Godot 4.6.3 导入 game/project.godot |

若浏览器显示文件页面，可点击页面的 Download raw file。校验表见 [SHA256SUMS.txt](SHA256SUMS.txt)。

## 试玩

建议先进入「试炼场」，熟悉后体验「快速试玩 / 3 分钟」。标准模式为八分钟，包含三次阶段商店和最后的首领战。

WASD 移动；左键拖绘、松开施法；右键取消；1/2/3 切换；空格闪避；中键拖动旋转镜头；Home 复位；Esc 暂停；H 操作指南。

包含三斗篷、手绘法术、三类普通敌人、首领、局内商店、局外变律与永久进度存档。角色与场景为简化素材及程序动画，尚无正式骨骼动作或布料模拟。

![实际战斗画面](preview.png)

## 已执行验证

- 51 项真实机制检查通过。
- 29 项 Xorg 窗口输入检查通过；这是自动输入，不代表人工手感验收。
- Linux 独立包渲染与原生窗口关闭通过，无脚本或资源泄漏错误。
- Chromium 本地加载、3D 试炼场、斗篷切换与暂停通过；未覆盖其他浏览器和完整单局兼容性。
- Windows 已交叉导出，尚未在 Windows 实机验证。
- 图形检查使用软件渲染，不代表目标显卡性能。没有验证可听音频质量。

每个平台包内保留 Godot 引擎与 Noto 字体许可。源码包附测试、程序建模、音效/字体生成及打包脚本。当前为玩法验收切片，不是完整发行版本。
