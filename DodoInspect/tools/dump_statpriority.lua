-- DodoInspect - tools/dump_statpriority.lua
-- Print the SHIPPED stat priorities as flat comparable lines, one per
-- (specID, hero tree, content bucket):
--
--     263|54|raid|mastery=haste > crit > versatility
--
-- Hero tree 0 means "no per-tree split". Consumed by
-- tools/scan_statpriority.py so the Wowhead diff compares against the
-- real table rather than against someone reading the file.
--
--     lua tools/dump_statpriority.lua

local ns = {}
local chunk = assert(loadfile("Data/StatPriority.lua"))
chunk("DodoInspect", ns)

local function orderText(order)
    local parts = {}
    for _, element in ipairs(order) do
        if type(element) == "table" then
            parts[#parts + 1] = table.concat(element, "=")
        else
            parts[#parts + 1] = element
        end
    end
    return table.concat(parts, " > ")
end

local function emit(specID, tree, row)
    if row.raid then
        print(string.format("%d|%d|raid|%s", specID, tree, orderText(row.raid)))
    end
    if row.mythic then
        print(string.format("%d|%d|mythic|%s", specID, tree, orderText(row.mythic)))
    end
end

local ids = {}
for specID in pairs(ns.StatPriority) do ids[#ids + 1] = specID end
table.sort(ids)

for _, specID in ipairs(ids) do
    local spec = ns.StatPriority[specID]
    print(string.format("%d|meta|current=%s|provisional=%s|date=%s|source=%s",
        specID, tostring(spec.current == true), tostring(spec.provisional == true),
        tostring(spec.date), tostring(spec.source)))
    if spec.builds then
        local trees = {}
        for tree in pairs(spec.builds) do trees[#trees + 1] = tree end
        table.sort(trees)
        for _, tree in ipairs(trees) do emit(specID, tree, spec.builds[tree]) end
    else
        emit(specID, 0, spec)
    end
end
