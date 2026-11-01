local Objects = require('source.engine.core.objects')
local Array = require('source.engine.math.array')
local Paths = require('source.engine.scenes.paths')
local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
-- Reference-counted immutable assets shared by explicit scene scopes.
local missingImage = 'assets/textures/internal/missing.png'
local Resources = {}
Resources.__index = Resources

function Resources.new(manifest, store, paths)
    store = store or { entries = {} }
    store.imageErrors = store.imageErrors or {}
    if paths and paths.package then
        paths.package:retain()
    end
    return setmetatable({
        manifest = manifest or {},
        store = store,
        owned = {},
        leases = {},
        images = {},
        imageVariants = {},
        imageErrors = store.imageErrors,
        paths = paths,
        canonicalPaths = {},
        imageLookups = {},
    }, Resources)
end

function Resources:scope(manifest, paths)
    self.store.imageErrors = self.imageErrors
    return Resources.new(manifest or self.manifest, self.store, paths or self.paths)
end

function Resources:own(value)
    self.owned[#self.owned + 1] = value
    return value
end

function Resources:canonical(path)
    local entry = self.manifest[path]
    path = entry and entry.path or path
    local cached = self.canonicalPaths[path]
    if cached then
        return cached
    end
    local resolved = Paths.resolve(path, self.paths)
    self.canonicalPaths[path] = resolved
    return resolved
end

function Resources:cached(kind, key, loader)
    assert(not self.released, 'Resource scope is released')
    local id = kind .. ':' .. key
    local entry = self.store.entries[id]
    if not entry then
        local owner = Resources.new(self.manifest, self.store, self.paths)
        local ok, value = pcall(loader, owner)
        if not ok then
            owner:release()
            if self.store.journal then
                self.store.journal:record('Resources', value, nil, kind .. ':' .. key)
            end
            error(kind .. ' resource ' .. key .. ': ' .. tostring(value), 0)
        end
        entry = { value = value, owner = owner, references = 0 }
        self.store.entries[id] = entry
    end
    if not self.leases[id] then
        entry.references = entry.references + 1
        self.leases[id] = true
    end
    return entry.value
end

function Resources:releaseAsset(kind, key)
    local id = kind .. ':' .. key
    if not self.leases[id] then
        return
    end
    self.leases[id] = nil
    local entry = self.store.entries[id]
    entry.references = entry.references - 1
    if entry.references == 0 then
        self.store.entries[id] = nil
        entry.owner:release()
    end
end

function Resources:loadImage(source, label)
    if source == nil or source == '' then
        source = missingImage
    end
    label = label or tostring(source)
    local pixels, encoded
    if type(source) == 'string' then
        local read, data = pcall(katsa.filesystem.newFileData, source)
        if read then
            encoded = data
        end
    end
    if type(source) == 'string' or source.typeOf and not source:typeOf('ImageData') then
        local decoded, data = pcall(katsa.image.newImageData, encoded or source)
        if decoded then
            pixels = data
        end
    elseif source.typeOf and source:typeOf('ImageData') then
        pixels = source
    end
    local ok, value = pcall(katsa.graphics.newImage, pixels or source, { mipmaps = true })
    if not ok then
        self.imageErrors[label] = tostring(value)
        if self.store.journal then
            self.store.journal:record(
                'Resources',
                'Image fallback: ' .. label .. ': ' .. tostring(value),
                nil,
                label
            )
        end
        local fallback, image = pcall(katsa.graphics.newImage, missingImage)
        if fallback then
            value = image
        else
            -- The diagnostic texture must also survive a missing fallback file.
            local data = katsa.image.newImageData(16, 16)
            data:mapPixel(function(x, y)
                local cell = (math.floor(x / 4) + math.floor(y / 4)) % 2
                return cell * 0.7, 0, cell * 0.9, 1
            end)
            value = katsa.graphics.newImage(data)
            data:release()
        end
    else
        self.imageErrors[label] = nil
    end
    if ok and pixels then
        local opacitySource = encoded
        if not opacitySource and Objects.isObject(source) and source:typeOf('FileData') then
            opacitySource = source
        end
        require('source.engine.materials.opacity').register(value, pixels, opacitySource)
    end
    if encoded then
        encoded:release()
    end
    if pixels and pixels ~= source then
        pixels:release()
    end
    return self:own(value)
end

function Resources:image(name)
    return self:imageVariant(name, nil)
end

function Resources:imageVariant(name, pixel)
    if name == nil or name == '' then
        name = missingImage
    end
    local entry = self.manifest[name]
    local authored = entry and entry.path or name
    local filter = pixel == nil and (entry and entry.filter or 'linear')
        or (pixel and 'nearest' or 'linear')
    local lookup = self.imageLookups[name]
    if
        lookup
        and lookup.path == authored
        and lookup.filter == filter
        and self.leases[lookup.id]
    then
        return lookup.image
    end
    local path = self:canonical(authored)
    local image = self:cached('image', path .. '|' .. filter, function(owner)
        local value = owner:loadImage(path, path)
        local anisotropy = math.min(8, katsa.graphics.getSystemLimits().textureanisotropy or 1)
        local sampler = (path == missingImage or owner.imageErrors[path]) and 'nearest' or filter
        value:setFilter(sampler, sampler, sampler == 'linear' and anisotropy or 1)
        if sampler == 'linear' and value:getMipmapCount() > 1 then
            value:setMipmapFilter('linear')
        elseif sampler == 'nearest' then
            value:setMipmapFilter()
        end
        value:setWrap('repeat', 'repeat')
        return value
    end)
    local cache = pixel and self.imageVariants or self.images
    cache[name] = image
    lookup = lookup or {}
    self.imageLookups[name] = lookup
    lookup.path, lookup.filter, lookup.image = authored, filter, image
    lookup.id = 'image:' .. path .. '|' .. filter
    return image
end

function Resources:isMissingImage(name)
    if name == nil or name == '' or name == missingImage then
        return true
    end
    local entry = self.manifest[name]
    return self.imageErrors[self:canonical(entry and entry.path or name)] ~= nil
end

function Resources:preload(items)
    local result = {}
    for i, item in ipairs(items) do
        assert(Array.is(item), 'Preload requires typed entries')
        if item.kind == 'image' then
            result[i] = self:imageVariant(item.path, item.pixel)
        elseif item.kind == 'model' or item.kind == 'animation' then
            result[i] = require('source.engine.import.models').load(item.path, self)
        elseif item.kind == 'sound' then
            local path = self:canonical(item.path)
            result[i] = self:cached('sound', path .. '|flat', function(owner)
                assert(katsa.filesystem.getInfo(path), 'Missing sound: ' .. path)
                return { owner:own(katsa.audio.newSource(path, 'static')) }
            end)
        else
            error('Unknown preload kind: ' .. tostring(item.kind))
        end
    end
    return result
end

function Resources:releaseOwned(value)
    for i, item in ipairs(self.owned) do
        if item == value then
            item:release()
            table.remove(self.owned, i)
            return
        end
    end
end

function Resources:release()
    if self.released then
        return
    end
    self.released = true
    local firstError
    local ids = {}
    for id in pairs(self.leases) do
        ids[#ids + 1] = id
    end
    for _, id in ipairs(ids) do
        local kind, key = id:match('^([^:]+):(.*)$')
        local ok, err = pcall(self.releaseAsset, self, kind, key)
        if not ok then
            firstError = firstError or err
        end
    end
    for i = #self.owned, 1, -1 do
        local item = self.owned[i]
        local ok, err = pcall(item.release, item)
        if not ok then
            firstError = firstError or err
        end
    end
    self.owned, self.images, self.imageVariants = {}, {}, {}
    self.canonicalPaths = {}
    self.imageLookups = {}
    if self.paths and self.paths.package then
        local ok, err = pcall(self.paths.package.release, self.paths.package)
        if not ok then
            firstError = firstError or err
        end
    end
    if firstError then
        error(firstError, 0)
    end
end

return Resources
