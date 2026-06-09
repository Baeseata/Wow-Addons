-- DodoPool - Geometry
-- 球桌几何 + 坐标常量。一切以"球桌felt局部像素坐标"为准:
-- 原点 = felt 左下角，+x 向右(长轴)，+y 向上。渲染/物理共用这套坐标。

local DP = _G.DodoPool or {}
_G.DodoPool = DP

local geo = {}
DP.geo = geo

-- ============================================================
-- 尺寸常量(像素)。九球桌长宽比 2:1。
-- ============================================================
geo.FELT_W   = 860      -- 台面长(长轴)
geo.FELT_H   = 430      -- 台面宽
geo.RAIL     = 32       -- 库边(木框)厚度
geo.BALL_R   = 13       -- 球半径
geo.POCKET_R = 22       -- 袋口半径(视觉 + 落袋判定)

-- 关键位置(felt 局部坐标)
geo.CENTER_Y = geo.FELT_H / 2
geo.FOOT_X   = geo.FELT_W * 0.72   -- 摆球区顶点(1号球)x，靠右
geo.HEAD_X   = geo.FELT_W * 0.22   -- 开球线(母球)x，靠左

-- ============================================================
-- 6 个袋:4 角 + 2 长边中点
-- ============================================================
function geo.Pockets()
    local W, H = geo.FELT_W, geo.FELT_H
    return {
        { x = 0,     y = 0 },   -- 左下
        { x = W / 2, y = 0 },   -- 下中
        { x = W,     y = 0 },   -- 右下
        { x = 0,     y = H },   -- 左上
        { x = W / 2, y = H },   -- 上中
        { x = W,     y = H },   -- 右上
    }
end

-- ============================================================
-- 九球钻石摆球:顶点(1号)朝左对着母球，9号在正中心。
-- 列数 1,2,3,2,1 共 9 个位置。返回 {x,y} 列表(felt 坐标)。
-- 约定:pos[1] = 顶点(放 1 号)，pos[5] = 钻石正中(放 9 号)。
-- ============================================================
function geo.RackPositions()
    local r  = geo.BALL_R
    local d  = 2 * r            -- 球紧贴时球心间距
    local dx = d * 0.866        -- 三角紧排的列水平步长 (cos30)
    local cx, cy = geo.FOOT_X, geo.CENTER_Y

    -- 每列相对中线的 y 偏移(单位 = d)
    local cols = {
        { 0 },               -- col0 顶点
        { -0.5, 0.5 },       -- col1
        { -1, 0, 1 },        -- col2 (中间那个 = 钻石正中)
        { -0.5, 0.5 },       -- col3
        { 0 },               -- col4 尾
    }

    local pos = {}
    for ci, ys in ipairs(cols) do
        local x = cx + (ci - 1) * dx
        for _, yo in ipairs(ys) do
            pos[#pos + 1] = { x = x, y = cy + yo * d }
        end
    end
    return pos   -- pos[1]=顶点, pos[5]=正中(9号)
end

-- 数值夹取(优先用公共库的，没有就本地兜底)
function geo.Clamp(x, lo, hi)
    if _G.Dodo and _G.Dodo.Clamp then return _G.Dodo.Clamp(x, lo, hi) end
    x = tonumber(x) or lo
    if x < lo then return lo elseif x > hi then return hi end
    return x
end
