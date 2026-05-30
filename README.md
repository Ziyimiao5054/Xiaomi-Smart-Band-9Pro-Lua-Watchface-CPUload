# SysInfo Watchface — 小米手环 9 Pro 系统监测表盘

Vela Lua 编写的适用于小米手环9Pro的表盘，可在表盘上实时查看 **CPU 占用率**（含实时折线图）。适用于搭载Xiaomi Vela OS的手环/手表设备。

---

## 特性

### CPU 监测
- **实时折线图** — 动态绘制 CPU% 趋势，网格线辅助阅读（25%/50%/75% 参考线）
- **文本日志** — 显示最近 12 条采集记录，含时间戳
- **500ms 采集间隔** — 实时跟踪系统负载变化
- **START / STOP 控制** — 按需启动和停止监测
---

## 使用方法

### 安装到手表

1. 使用 **Easyface** 打开 `monika.fprj`
2. 编译并刷写编译后的二进制文件到设备
3. 在表盘列表中切换并使用

### 操作说明

| 操作 | 按钮 | 行为 |
|------|------|------|
| 开始监测 | **START** | 启动轮询，按钮变为红色 **STOP** |
| 停止监测 | **STOP** | 暂停轮询，销毁定时器 |
| 清空历史 | **CLEAR** | 清除文本日志和折线图数据 |

### 文件说明

```
CPU占用监测/
├── app/_lua/monika/monika.lua   # CPU 监测主程序（含折线图）
├── mem.lua                       # 内存监测主程序
├── images/preview.png            # 预览图
├── output/
│   ├── lua demo.face             # 编译后的表盘文件
│   └── lua demo.info             # 设备元信息
├── monika.fprj                   # 表盘项目文件
└── README.md
```


### 折线图实现

使用预创建的 LVGL Object 作为像素条，相邻点之间用垂直矩形条连接，水平重叠形成连续折线。图表高度 142px，映射 0–100% CPU 范围。


### 鸣谢
- [**sf-yuzifu/Monika**](https://github.com/sf-yuzifu/Monika) — 将《心跳文学部》莫妮卡带到小米手环上的表盘项目

本项目的monika.fprj 项目结构、app/_lua/monika/目录布局基于此项目。
