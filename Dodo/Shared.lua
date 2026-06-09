-- Dodo 插件包 —— 公共库 (Shared library)
-- 所有 Dodo 子插件可复用的"素材路径 + 公共函数",通过全局表 _G.Dodo 调用。
-- 例:
--   local icon = Dodo.icon                 -- 共享图标完整路径
--   local path = Dodo.Media("Dodo.tga")    -- 拼共享素材路径
--   db = Dodo.CopyDefaults(db, DEFAULTS)   -- 补默认值
--   Dodo.Print("Map", "已就绪")            -- 带前缀彩色打印
--   Dodo.Register("DodoMap", DodoMap)      -- 把自己登记进包(便于将来统一管理)

local Dodo = _G.Dodo or {}
_G.Dodo = Dodo

Dodo.version = "1.0.0"

-- ============================================================
-- 共享素材(所有子插件复用同一份,避免每个插件各存一份)
-- ============================================================
Dodo.mediaPath = "Interface\\AddOns\\Dodo\\Media\\"
Dodo.icon      = Dodo.mediaPath .. "Dodo.tga"

-- 拼一个共享素材的完整路径:Dodo.Media("Dodo.tga")
function Dodo.Media(file)
    return Dodo.mediaPath .. (file or "")
end

-- ============================================================
-- 公共工具函数(纯函数,可放心复用)
-- ============================================================

-- 递归填充默认值:把 src 中 dst 缺少的键补进去,不覆盖已有值。返回 dst。
function Dodo.CopyDefaults(dst, src)
    if type(dst) ~= "table" then dst = {} end
    if type(src) ~= "table" then return dst end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = Dodo.CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- 数值夹取到 [lo, hi]
function Dodo.Clamp(x, lo, hi)
    x = tonumber(x) or lo
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end

-- 带前缀的彩色打印:Dodo.Print("Map", "文本") -> |Dodo|[Map] 文本
function Dodo.Print(tag, msg)
    local prefix
    if tag and tag ~= "" then
        prefix = "|cff33ff99Dodo|r|cffffd200[" .. tostring(tag) .. "]|r "
    else
        prefix = "|cff33ff99Dodo|r "
    end
    print(prefix .. tostring(msg))
end

-- 把铜钱格式化成 "12g 34s" 文本(采集/拍卖类子插件常用)
function Dodo.Money(copper)
    if type(copper) ~= "number" or copper <= 0 then return "0g" end
    copper = math.floor(copper + 0.5)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    if g > 0 then return string.format("%dg %ds", g, s) end
    return string.format("%ds", s)
end

-- ============================================================
-- 模块登记(子插件可把自己挂到包里,便于将来做统一开关/面板)
-- ============================================================
Dodo.modules = Dodo.modules or {}
function Dodo.Register(name, module)
    Dodo.modules[name] = module or true
end

-- ============================================================
-- 初始化:共享 SavedVariables(给将来的包级设置预留)
-- ============================================================
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
    if name == "Dodo" then
        DodoDB = DodoDB or {}
        Dodo.db = DodoDB
        f:UnregisterAllEvents()
    end
end)
