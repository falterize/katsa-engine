local Paths = require('source.engine.scenes.paths')
local Archive = require('source.engine.scenes.archive')
local Layout = require('source.engine.scenes.layout')

local Package = {}
Package.__index = Package
local mounts = {}

local function rootAt(path)
    return love.filesystem.getInfo(path .. '/settings.lua', 'file')
        and love.filesystem.getInfo(path .. '/main.lua', 'file')
end

local function sceneRoot(mount)
    if rootAt(mount) then
        return mount
    end
    local found
    for _, name in ipairs(love.filesystem.getDirectoryItems(mount)) do
        local path = mount .. '/' .. name
        if love.filesystem.getInfo(path, 'directory') and rootAt(path) then
            assert(not found, 'Archive contains multiple scene roots; choose one package per scene')
            found = path
        end
    end
    return assert(
        found,
        'Scene requires settings.lua and main.lua at its root or one enclosing folder'
    )
end

local function mountArchive(source)
    local data = Archive.read(source)
    assert(
        data and data.typeOf and data:typeOf('FileData'),
        'Scene source must be a directory, archive path or FileData'
    )
    local hash = love.data.encode('string', 'hex', love.data.hash('sha256', data))
    local entry = mounts[hash]
    if not entry then
        local mount = '_scenePackages/' .. hash
        -- PhysicsFS keys memory mounts by archive name, not by mountpoint. Two
        -- external files named scene.zip must remain independent during a switch.
        local extension = data:getFilename():match('%.([%w]+)$') or 'zip'
        local archiveName = 'katsa-scene-' .. hash .. '.' .. extension
        local ok, message = love.filesystem.mount(data, archiveName, mount, true)
        assert(
            ok,
            'Cannot mount scene archive; use ZIP/.love or a format supported by this LÖVE build: '
                .. tostring(message)
        )
        local valid, root = pcall(sceneRoot, mount)
        if not valid then
            love.filesystem.unmount(data)
            error(root, 0)
        end
        entry = { data = data, root = root, references = 0, hash = hash }
        mounts[hash] = entry
    end
    entry.references = entry.references + 1
    return entry
end

function Package.open(source)
    local directory = type(source) == 'string' and love.filesystem.getInfo(source, 'directory')
    local archive = not directory and mountArchive(source)
    local root = directory and Paths.normalize(source) or archive.root
    local self =
        setmetatable({ root = root, archive = archive, modules = {}, references = 1 }, Package)
    local ok, message = pcall(function()
        assert(rootAt(root), 'Scene requires settings.lua and main.lua: ' .. root)
        self.settings = self:require('settings')
        assert(
            type(self.settings) == 'table'
                and type(self.settings.id) == 'string'
                and self.settings.id:match('^[%w_-]+$'),
            'Scene settings require a non-empty stable id'
        )
        Layout.validate(root, self.settings)
        self.paths = { scene = root .. '/assets', shared = 'assets', package = self }
    end)
    if not ok then
        self:release()
        error(message, 0)
    end
    return self
end

function Package:require(name)
    assert(self.references > 0, 'Scene package is released')
    assert(
        type(name) == 'string' and name:match('^[%w_]+[%.%w_]*$') and not name:find('..', 1, true),
        'Use a dotted scene module name'
    )
    local cached = self.modules[name]
    assert(cached ~= false, 'Circular scene module dependency: ' .. name)
    if cached ~= nil then
        return cached
    end
    local path = self.root .. '/' .. name:gsub('%.', '/') .. '.lua'
    local chunk, message = love.filesystem.load(path)
    assert(chunk, message)
    self.modules[name] = false
    if not self.environment then
        local import = require
        self.environment = setmetatable({
            require = function(module)
                if module:sub(1, 6) == 'scene.' then
                    return self:require(module:sub(7))
                end
                return import(require('source.engine.physics.3d.legacyImports').resolve(module))
            end,
        }, { __index = _G })
    end
    setfenv(chunk, self.environment)
    local ok, value = pcall(chunk)
    if not ok then
        self.modules[name] = nil
        error(path .. ': ' .. tostring(value), 0)
    end
    self.modules[name] = value == nil and true or value
    return self.modules[name]
end

function Package:registerNodes(world, names)
    for _, name in ipairs(names) do
        local definition = self:require('nodes.' .. name)
        if definition.register then
            definition.register(world)
        else
            world:registerNodeType(name, definition)
        end
    end
end

function Package:retain()
    assert(self.references > 0, 'Scene package is released')
    self.references = self.references + 1
end

function Package:release()
    if self.references == 0 then
        return
    end
    self.references = self.references - 1
    if self.references == 0 then
        self.modules = {}
        local archive = self.archive
        if archive then
            archive.references = archive.references - 1
            if archive.references == 0 then
                assert(love.filesystem.unmount(archive.data), 'Could not unmount scene archive')
                mounts[archive.hash] = nil
            end
        end
    end
end

return Package
