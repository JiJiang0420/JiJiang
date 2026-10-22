# Unity：命名空间与第一个组件

状态：原理整理。以下示例未在本云环境中编译或运行；本仓库不是完整 Unity 项目。

## 从现有片段开始

仓库原有文件 `人类群星闪耀时` 包含 `using Unity.Engine;`。Unity 常用引擎 API 的命名空间是 `UnityEngine`，实际脚本中应写：

```csharp
using UnityEngine;
```

`using` 让代码可以直接使用命名空间中的类型，但它不会创建组件，也不会自动安装引擎。原文件作为历史片段保留。

## 一个最小组件

在 Unity 项目的 `Assets` 目录创建 `HelloGame.cs`，文件名与类名保持一致：

```csharp
using UnityEngine;

public class HelloGame : MonoBehaviour
{
    private void Start()
    {
        Debug.Log("开始制作我的游戏！");
    }
}
```

把脚本挂到场景中的一个启用的 GameObject 上，再进入 Play 模式。此处 `MonoBehaviour` 是组件基类，`Start` 用于在组件首次更新前执行初始化逻辑。

## 待执行的验证

- [ ] 在项目记录中写下 Unity 编辑器版本。
- [ ] 确认 Console 没有编译错误。
- [ ] 挂载组件并进入 Play 模式，确认 Console 出现日志。
- [ ] 若日志未出现，检查对象和组件是否启用、脚本是否成功挂载。

## 参考

- [Unity 脚本 API：MonoBehaviour](https://docs.unity3d.com/ScriptReference/MonoBehaviour.html)
- [Unity 脚本 API：Start](https://docs.unity3d.com/ScriptReference/MonoBehaviour.Start.html)
- [C# using 指令](https://learn.microsoft.com/zh-cn/dotnet/csharp/language-reference/keywords/using-directive)
