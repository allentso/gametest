--- 存档 HMAC 校验
---@diagnostic disable: undefined-global
local SaveGuard = {}
local SALT = "shanhai_xunguang_2026"

function SaveGuard.computeHMAC(data, deviceId)
    local key = deviceId .. SALT
    local hash = 0
    for i = 1, #data do
        hash = (hash * 31 + string.byte(data, i) + string.byte(key, ((i - 1) % #key) + 1)) % 2147483647
    end
    return string.format("%010d", hash)
end

function SaveGuard.save(path, tbl, deviceId)
    local json = cjson.encode(tbl)
    local hmac = SaveGuard.computeHMAC(json, deviceId)
    local wrapped = cjson.encode({ data = tbl, hmac = hmac })
    -- 确保目录存在
    local dir = string.match(path, "(.+)/[^/]+$")
    if dir then
        fileSystem:CreateDir(dir)
    end
    local file = File(path, FILE_WRITE)
    if not file:IsOpen() then
        print("[SaveGuard] 写入失败: " .. path)
        return false
    end
    file:WriteString(wrapped)
    file:Close()
    return true
end

function SaveGuard.load(path, deviceId)
    if not fileSystem:FileExists(path) then return nil end
    local file = File(path, FILE_READ)
    if not file:IsOpen() then return nil end
    local raw = file:ReadString()
    file:Close()
    if not raw or #raw == 0 then return nil end
    local ok, wrapped = pcall(cjson.decode, raw)
    if not ok or not wrapped then return nil end
    local json = cjson.encode(wrapped.data)
    local expected = SaveGuard.computeHMAC(json, deviceId)
    if wrapped.hmac ~= expected then
        print("[SaveGuard] 校验失败: " .. path)
        return nil
    end
    return wrapped.data
end

return SaveGuard
