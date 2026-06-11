-- DodoRush - Geometry
-- 跑道常量。坐标系:原点 = 跑道左下角,+x 向右,+y 向上(Dodo 系列惯例)。
-- 纯 2D 俯视:世界向下滚动,人群固定在 CROWD_Y 高度,只能横移。

local DR = _G.DodoRush or {}
_G.DodoRush = DR

local geo = {}
DR.geo = geo

geo.ROAD_W  = 392    -- 跑道宽(与 DodoBricks 棋盘同宽,窗口 436x624)
geo.ROAD_H  = 534    -- 跑道高
geo.CROWD_Y = 120    -- 人群中心固定高度(离底边)
geo.EDGE    = 40     -- 人群中心横向可达范围 [EDGE, ROAD_W-EDGE]
geo.CURB    = 6      -- 左右路肩宽

-- 门:一排两块,中缝即左右分界
geo.GATE_GAP = 8                                       -- 边距与中缝
geo.GATE_W   = (geo.ROAD_W - 3 * geo.GATE_GAP) / 2     -- = 184
geo.GATE_H   = 64
geo.GATE_XL  = geo.GATE_GAP + geo.GATE_W / 2           -- 左门中心 x = 100
geo.GATE_XR  = geo.ROAD_W - geo.GATE_GAP - geo.GATE_W / 2  -- 右门中心 x = 292
