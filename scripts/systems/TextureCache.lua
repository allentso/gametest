--- NanoVG 纹理缓存 - LRU 淘汰
local TextureCache = {}
local cache = {}
local accessTime = {}
local nvgCtx = nil
local MAX_CACHE = 32

function TextureCache.init(ctx) nvgCtx = ctx end

function TextureCache.load(path, flags)
    if cache[path] then
        accessTime[path] = os.clock and os.clock() or 0
        return cache[path]
    end
    if TextureCache.count() >= MAX_CACHE then
        TextureCache.evictOldest()
    end
    local img = nvgCreateImage(nvgCtx, path, flags or 0)
    if img and img > 0 then
        cache[path] = img
        accessTime[path] = os.clock and os.clock() or 0
        return img
    end
    return nil
end

function TextureCache.count()
    local n = 0
    for _ in pairs(cache) do n = n + 1 end
    return n
end

function TextureCache.evictOldest()
    local oldestPath, oldestTime = nil, math.huge
    for path, t in pairs(accessTime) do
        if t < oldestTime then oldestPath = path; oldestTime = t end
    end
    if oldestPath then
        nvgDeleteImage(nvgCtx, cache[oldestPath])
        cache[oldestPath] = nil
        accessTime[oldestPath] = nil
    end
end

function TextureCache.release()
    if nvgCtx then
        for _, img in pairs(cache) do nvgDeleteImage(nvgCtx, img) end
    end
    cache = {}
    accessTime = {}
end

return TextureCache
