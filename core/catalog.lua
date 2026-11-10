--[[--
Textbook catalog loader.

The catalog is the single runtime source of truth for provinces, grades,
textbook editions, and unit metadata.  It is intentionally plain JSON so it can
be bundled with the plugin and read without any network access.
--]]--

local JSON = require("json")
local logger = require("logger")
local util = require("util")

local Catalog = {}

local cache = {}

local function read_json(path)
    local content, err = util.readFromFile(path, "rb")
    if not content then return nil, err or ("cannot read " .. path) end
    local ok, data = pcall(JSON.decode, content)
    if not ok or type(data) ~= "table" then
        return nil, tostring(data or "invalid JSON")
    end
    return data
end

function Catalog.load(plugin_path)
    if not plugin_path or plugin_path == "" then return nil, "plugin path missing" end
    if cache[plugin_path] then return cache[plugin_path] end
    local data, err = read_json(plugin_path .. "/data/catalog.json")
    if not data then return nil, err end
    if type(data.subjects) ~= "table" or type(data.provinces) ~= "table" then
        return nil, "catalog missing subjects/provinces"
    end
    cache[plugin_path] = data
    return data
end

function Catalog.grades(plugin_path)
    local data = Catalog.load(plugin_path)
    if not data then return { 1, 2, 3, 4, 5, 6 } end
    return data.grades or { 1, 2, 3, 4, 5, 6 }
end

function Catalog.provinces(plugin_path)
    local data = Catalog.load(plugin_path)
    if not data then return {} end
    return data.provinces or {}
end

function Catalog.province(plugin_path, province_id)
    for _, item in ipairs(Catalog.provinces(plugin_path)) do
        if item.id == province_id then return item end
    end
    return nil
end

function Catalog.recommended_math(plugin_path, province_id)
    local province = Catalog.province(plugin_path, province_id)
    return province and province.default_math or "renjiao"
end

function Catalog.editions(plugin_path, subject)
    local data = Catalog.load(plugin_path)
    if not data then return {} end
    local subject_data = data.subjects and data.subjects[subject]
    if not subject_data then return {} end
    local out = {}
    local order = subject_data.order or {}
    for _, edition_id in ipairs(order) do
        local edition = subject_data.editions and subject_data.editions[edition_id]
        if edition then
            table.insert(out, { id = edition_id, name = edition.name or edition_id })
        end
    end
    if #out == 0 then
        for edition_id, edition in pairs(subject_data.editions or {}) do
            table.insert(out, { id = edition_id, name = edition.name or edition_id })
        end
        table.sort(out, function(a, b) return a.id < b.id end)
    end
    return out
end

function Catalog.edition_name(plugin_path, subject, edition_id)
    local data = Catalog.load(plugin_path)
    local subject_data = data and data.subjects and data.subjects[subject]
    local edition = subject_data and subject_data.editions and subject_data.editions[edition_id]
    return edition and edition.name or edition_id
end

function Catalog.grade_data(plugin_path, subject, edition, grade, semester)
    local data, err = Catalog.load(plugin_path)
    if not data then return nil, err end
    local subject_data = data.subjects and data.subjects[subject]
    if not subject_data then return nil, "subject not found" end
    local edition_data = subject_data.editions and subject_data.editions[edition]
    if not edition_data then return nil, "edition not found" end
    local grade_data = edition_data.grades and edition_data.grades[tostring(grade)]
    if not grade_data then return nil, "grade not found" end
    local semester_data = grade_data[semester]
    if type(semester_data) ~= "table" then return nil, "semester not found" end
    return semester_data
end

function Catalog.units(plugin_path, subject, edition, grade, semester)
    local data, err = Catalog.grade_data(plugin_path, subject, edition, grade, semester)
    if not data then return nil, err end
    if type(data.units) ~= "table" then return nil, "units missing" end
    return data.units
end

function Catalog.bank_path(plugin_path, subject, edition, grade, semester)
    local data, err = Catalog.grade_data(plugin_path, subject, edition, grade, semester)
    if not data then return nil, err end
    if type(data.file) ~= "string" then return nil, "bank file missing" end
    return plugin_path .. "/data/" .. data.file
end

function Catalog.find_unit(plugin_path, subject, edition, grade, semester, unit_id)
    local units = Catalog.units(plugin_path, subject, edition, grade, semester)
    if not units then return nil end
    for _, unit in ipairs(units) do
        if unit.id == unit_id then return unit end
    end
    return nil
end

function Catalog.clear_cache()
    cache = {}
    logger.dbg("KidLearn: catalog cache cleared")
end

return Catalog
