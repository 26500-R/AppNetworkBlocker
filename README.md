# App Network Blocker

一个用于创建 Windows Defender 防火墙规则的小工具，可以按程序路径或文件夹批量屏蔽应用联网。

## 使用方式

1. 右键 `Run-AppNetworkBlocker.bat`，选择“以管理员身份运行”。
2. 在菜单里选择：
   - `1`：屏蔽程序或文件夹出站联网，通常用这个就够了。
   - `2`：同时屏蔽出站和入站。
   - `3`：查看本工具创建的规则。
   - `4`：解除指定程序或文件夹屏蔽。
   - `5`：删除本工具创建的全部规则。

也可以直接在管理员 PowerShell 里运行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# 屏蔽一个程序出站联网
.\AppNetworkBlocker.ps1 Block "C:\Path\To\App.exe"

# 屏蔽某个文件夹下的程序，不扫描子文件夹
.\AppNetworkBlocker.ps1 Block "C:\Path\To\AppFolder"

# 屏蔽某个文件夹及所有子文件夹下的程序
.\AppNetworkBlocker.ps1 Block "C:\Path\To\AppFolder" -Recurse

# 同时屏蔽出站和入站
.\AppNetworkBlocker.ps1 Block "C:\Path\To\App.exe" -Inbound

# 一次屏蔽多个程序或文件夹
.\AppNetworkBlocker.ps1 Block "C:\App1.exe" "C:\AppFolder"

# 查看规则
.\AppNetworkBlocker.ps1 List

# 解除某个程序的屏蔽
.\AppNetworkBlocker.ps1 Unblock "C:\Path\To\App.exe"

# 解除某个文件夹及子文件夹下程序的屏蔽
.\AppNetworkBlocker.ps1 Unblock "C:\Path\To\AppFolder" -Recurse

# 删除本工具创建的全部规则
.\AppNetworkBlocker.ps1 Unblock -All
```

## 文件夹屏蔽说明

- Windows 防火墙更适合按“具体程序路径”建规则，而不是按“一整个文件夹”建一条规则。
- 本工具会扫描文件夹里的 `.exe`、`.com`、`.scr`，然后逐个创建阻止联网规则。
- 普通文件、图片、文档、配置文件、DLL 本身不会独立联网；需要屏蔽的是实际启动的可执行程序。
- 默认只扫描当前文件夹；加 `-Recurse` 才会扫描所有子文件夹。
- 如果文件夹以后新增了程序，或应用更新后程序路径变化，需要再运行一次工具。

## 注意

- 创建和删除防火墙规则必须使用管理员权限。
- 本工具只管理 `App Network Blocker` 规则组里的规则，不会删除你手动创建的其他防火墙规则。
- 默认只屏蔽出站连接，因为大多数应用“联网”主要依赖出站连接。
