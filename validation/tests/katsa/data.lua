return function(T)
    local Data = require('source.katsa.core.data')
    local function hex(text)
        return Data.encode('string', 'hex', text)
    end

    T.check(hex(Data.hash('md5', 'abc')) == '900150983cd24fb0d6963f7d28e17f72', 'md5 vector')
    T.check(
        hex(Data.hash('sha1', 'abc')) == 'a9993e364706816aba3e25717850c26c9cd0d89d',
        'sha1 vector'
    )
    T.check(
        hex(Data.hash('sha256', 'abc'))
            == 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        'sha256 vector'
    )
    T.check(Data.encode('string', 'base64', 'hello!!') == 'aGVsbG8hIQ==', 'base64 encode')
    T.check(Data.decode('string', 'base64', 'aGVsbG8hIQ==') == 'hello!!', 'base64 decode')
    local packed = Data.pack('string', '<i4 s1 d', -5, 'xy', 2.5)
    local a, b, c = Data.unpack('<i4 s1 d', packed)
    T.check(a == -5 and b == 'xy' and c == 2.5, 'pack/unpack round trip')
    T.check(Data.newByteData('abc'):getString() == 'abc', 'ByteData keeps its contents')

    -- The platform save path ends with the identity; changing identity later must not nest it.
    local FS = require('source.katsa.core.filesystem')
    local oldIdentity, oldDir = FS.getIdentity(), FS.getSaveDirectory()
    FS.setIdentity('demo')
    FS.setSaveDirectory('/data/Katsa/demo')
    FS.setIdentity('demo')
    T.check(FS.getSaveDirectory() == '/data/Katsa/demo', 'save directory is not nested after setIdentity')
    FS.setIdentity('other')
    T.check(FS.getSaveDirectory() == '/data/Katsa/other', 'another identity is a sibling directory')
    FS.setIdentity(oldIdentity)
    if oldDir ~= '.' then
        FS.setSaveDirectory(oldDir)
    end
end
