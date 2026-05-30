-- cpu_monitor.lua
-- CPU 轮询监测表盘 + 折线趋势图

-- 颜色常量（集中管理）
local C_BG        = '#000000'
local C_GREEN     = '#00ff00'
local C_GREEN_DIM = '#0a3a0a'
local C_GREEN_DK  = '#004400'
local C_GREEN_LBL = '#0a6a0a'
local C_RED       = '#ff0000'
local C_RED_DK    = '#440000'
local C_ORANGE    = '#ffaa00'
local C_ORANGE_DK = '#443300'
local C_PANEL_BG  = '#111111'

local maxBufferLines = 12
local isMonitoring = false
local monitorTimer = nil
local cpuBuffer = {}       -- 文本历史
local cpuHistory = {}      -- CPU% 数值历史（用于折线图）

-- 图表参数
local CHART_TOP = 28
local CHART_H = 142
local CHART_BOTTOM = CHART_TOP + CHART_H  -- 170
local CHART_LEFT = 12
local POINT_SPACING = 3
local MAX_POINTS = math.floor((lvgl.HOR_RES() - CHART_LEFT * 2) / POINT_SPACING)  -- 26

local root = lvgl.Object(nil, {
    x = 0,
    y = 0,
    w = lvgl.HOR_RES(),
    h = lvgl.VER_RES() - 70,
    border_width = 0,
    bg_color = C_BG,
})
root:clear_flag(lvgl.FLAG.SCROLLABLE)

-- === 图表区域 ===

-- 标题
local chartTitle = lvgl.Label(root, {
    x = CHART_LEFT,
    y = 5,
    w = 200,
    h = 18,
    text = "=== CPU Trend ===",
    font_size = 16,
    text_color = '#00cc00',
    bg_opa = 0,
})

-- 网格线
local gridLevels = { 25, 50, 75 }
for _, v in ipairs(gridLevels) do
    local y = CHART_BOTTOM - (v / 100) * CHART_H
    -- 横线
    lvgl.Object(root, {
        x = CHART_LEFT,
        y = math.floor(y),
        w = lvgl.HOR_RES() - CHART_LEFT * 2,
        h = 1,
        bg_color = C_GREEN_DIM,
        border_width = 0,
    })
    -- 百分比标签
    lvgl.Label(root, {
        x = 0,
        y = math.floor(y) - 7,
        w = 24,
        h = 14,
        text = tostring(v) .. "%",
        font_size = 11,
        text_color = C_GREEN_LBL,
        bg_opa = 0,
    })
end

-- 连接条 Object（预创建，初始隐藏）
local pointObjs = {}
local BAR_W = POINT_SPACING + 1  -- 比间距宽 1px，水平重叠形成连续线
for i = 1, MAX_POINTS do
    local p = lvgl.Object(root, {
        x = CHART_LEFT + (i - 1) * POINT_SPACING,
        y = CHART_BOTTOM,
        w = BAR_W,
        h = 1,
        bg_color = C_GREEN,
        border_width = 0,
    })
    p:add_flag(lvgl.FLAG.HIDDEN)
    table.insert(pointObjs, p)
end

-- 分隔线
lvgl.Object(root, {
    x = 5,
    y = CHART_BOTTOM + 5,
    w = lvgl.HOR_RES() - 10,
    h = 1,
    bg_color = C_GREEN_DIM,
    border_width = 0,
})

-- === 文本区域 ===

local textareaY = CHART_BOTTOM + 10
local textareaH = lvgl.VER_RES() - 80 - textareaY

local terminal = lvgl.Textarea(root, {
    w = lvgl.HOR_RES() - 10,
    h = textareaH,
    x = 5,
    y = textareaY,
    text = '',
    bg_color = C_BG,
    font_size = 18,
    text_color = C_GREEN,
    border_width = 0,
})
terminal:set { text = "CPU Monitor\nPress START\n" }

-- === 控制面板 ===

local controlPanel = lvgl.Object(nil, {
    x = 0,
    y = lvgl.VER_RES() - 70,
    w = lvgl.HOR_RES(),
    h = 70,
    bg_color = C_PANEL_BG,
    border_width = 0,
})
controlPanel:clear_flag(lvgl.FLAG.SCROLLABLE)

local startStopBtn = lvgl.Label(controlPanel, {
    x = 20,
    y = 13,
    w = 120,
    h = 45,
    text = "START",
    radius = 5,
    border_width = 1,
    border_color = C_GREEN,
    bg_color = C_GREEN_DK,
    font_size = 32,
    text_color = C_GREEN,
})
startStopBtn:add_flag(lvgl.FLAG.CLICKABLE)

local clearBtn = lvgl.Label(controlPanel, {
    x = 160,
    y = 13,
    w = 120,
    h = 45,
    text = "CLEAR",
    radius = 5,
    border_width = 1,
    border_color = C_ORANGE,
    bg_color = C_ORANGE_DK,
    font_size = 32,
    text_color = C_ORANGE,
})
clearBtn:add_flag(lvgl.FLAG.CLICKABLE)

-- === 功能函数 ===

local __firstRead = true

local function readCpuLoad()
    local f = io.open('/proc/cpuload', 'r')
    if not f then return "ERR:open", 0, nil end
    local content = f:read('*all')
    f:close()
    if not content or content == "" then return "ERR:empty", 0, nil end

    local vals = {}
    for n in content:gmatch("[%d%.]+") do
        table.insert(vals, n)
    end
    if #vals == 0 then return "NODATA", 0, content end

    local pct = 0
    if #vals == 1 then
        -- 单数值：直接作为 CPU 百分比
        pct = math.floor(tonumber(vals[1]) or 0)
    elseif #vals >= 2 then
        -- 多数值：第一个为总 tick，第二个为已用 tick
        local total = tonumber(vals[1]) or 0
        local used  = tonumber(vals[2]) or 0
        if total > 0 then
            pct = math.floor(used / total * 100)
        end
    end
    return string.format("CPU:%d%%", pct), pct, content
end

-- 更新折线图：相邻点之间用垂直连接条，水平重叠形成连续线
local function updateChart()
    local count = #cpuHistory
    for i = 1, MAX_POINTS do
        if i <= count then
            local pct = cpuHistory[i]
            local cy = CHART_BOTTOM - (pct / 100) * CHART_H  -- 当前点 Y

            if i == 1 then
                -- 第一个点：小标记
                pointObjs[i]:set { y = math.floor(cy), h = 2 }
            else
                -- 连接条：从前一个点的 Y 连到当前点的 Y
                local prevPct = cpuHistory[i - 1]
                local prevY = CHART_BOTTOM - (prevPct / 100) * CHART_H
                local topY = math.min(cy, prevY)
                local segH = math.max(math.abs(cy - prevY), 1)
                pointObjs[i]:set { y = math.floor(topY), h = math.ceil(segH) }
            end
            pointObjs[i]:clear_flag(lvgl.FLAG.HIDDEN)
        else
            pointObjs[i]:add_flag(lvgl.FLAG.HIDDEN)
        end
    end
end

-- 刷新文本显示（使用 table.concat 避免逐行拼接产生大量中间字符串）
local function refreshDisplay()
    local lines = {}
    lines[#lines + 1] = "Status: " .. (isMonitoring and "RUNNING" or "STOPPED")
    lines[#lines + 1] = string.rep("-", 28)
    for _, line in ipairs(cpuBuffer) do
        lines[#lines + 1] = line
    end
    if #cpuBuffer == 0 then
        lines[#lines + 1] = "No data yet"
    end
    terminal:set { text = table.concat(lines, "\n") }
end

local function addRecord(line)
    table.insert(cpuBuffer, 1, line)
    while #cpuBuffer > maxBufferLines do
        table.remove(cpuBuffer)
    end
    refreshDisplay()
end

-- 采集 CPU 数据
local function collectOnce()
    local data, pct, raw = readCpuLoad()
    local timestamp = os.date("%H:%M:%S")
    local record = string.format("[%s] %s", timestamp, data)
    addRecord(record)

    -- 首次读取：输出原始文件内容用于调试
    -- 利用 readCpuLoad 已读到的 raw，避免二次文件 I/O
    if __firstRead then
        __firstRead = false
        local escaped = (raw or "nil"):gsub("\n", "\\n"):gsub("\r", "\\r")
        addRecord(">>> RAW: [" .. escaped .. "]")
    end

    -- 更新图表
    table.insert(cpuHistory, pct)
    while #cpuHistory > MAX_POINTS do
        table.remove(cpuHistory, 1)
    end
    updateChart()
end

-- Timer 回调
local function onTimer()
    if isMonitoring then
        collectOnce()
    end
end

-- 启动监控
local function startMonitor()
    if isMonitoring then return end
    isMonitoring = true

    monitorTimer = lvgl.Timer({
        period = 500,
        repeat_count = -1,
        cb = onTimer,
    })
    monitorTimer:resume()

    startStopBtn:set { text = "STOP", bg_color = C_RED_DK, border_color = C_RED }
    addRecord(">>> Monitoring Started (500ms interval)")
    collectOnce()
end

-- 停止监控（销毁 Timer 避免对象堆积）
local function stopMonitor()
    if not isMonitoring then return end
    isMonitoring = false

    if monitorTimer then
        monitorTimer:delete()
        monitorTimer = nil
    end

    startStopBtn:set { text = "START", bg_color = C_GREEN_DK, border_color = C_GREEN }
    addRecord(">>> Monitoring Stopped")
end

-- 清空历史
local function clearHistory()
    cpuBuffer = {}
    cpuHistory = {}
    updateChart()    -- 隐藏所有点
    refreshDisplay()
end

-- 按钮事件
startStopBtn:onevent(lvgl.EVENT.CLICKED, function()
    if isMonitoring then
        stopMonitor()
    else
        startMonitor()
    end
end)

clearBtn:onevent(lvgl.EVENT.CLICKED, function()
    clearHistory()
end)

refreshDisplay()
print("CPU Monitor + Chart Loaded - Press START")
