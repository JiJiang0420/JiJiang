# Game Programming Patterns · 学习指南

- 入口：[官方站点 / 原始资料](https://gameprogrammingpatterns.com/)
- 适合：已经写出一个小原型，开始遇到状态和模块耦合问题。
- 学习状态：待学习、待实践；以下是练习建议，并非已完成记录。
- 外链状态：尚未逐个联网核验；使用时记录访问日期与适用版本。

## 建议学习顺序

1. 先阅读 Introduction 与 Architecture, Performance, and Games。
2. State：表达角色或流程状态。
3. Observer：拆分事件发送者和接收者。
4. Object Pool：复用高频对象。
5. Component 与 Event Queue：按实际需要继续。

## 动手练习

把原型中的待机、移动、受击改为显式状态；用事件更新 UI，避免 UI 直接管理角色状态。

## 完成标准

列出合法状态转换；重复受击、结束后输入等边界行为明确；改造前后玩法一致。

## 注意事项

先明确实际问题再引入模式。对象池需要重置状态，并不保证所有场景都更快；性能结论需要测量。

## 留下学习记录

复制[学习笔记模板](../../templates/learning-note.md)，记录使用版本、实际步骤、输出或截图、遇到的问题与解决证据。将新笔记加入[笔记索引](../../notes/README.md)。未执行的步骤保留待办状态。

返回[资源索引](../README.md)。
