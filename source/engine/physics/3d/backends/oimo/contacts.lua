local O = require('./types')

local Contacts = {}

-- One event policy for initial shapes and replacement colliders on both backends.
function Contacts.create(body)
    local self = body
    local callback = O.ContactCallback.new()

    local function notify(phase, contact)
        if self.destroyed or self.object.destroyed or self.object._destroying then
            return
        end
        local first, second = contact:getShape1().userData, contact:getShape2().userData
        local other = first == self and second or first
        self:_recordContact(other, contact, phase == 'begin')
        self.object:emit(phase == 'begin' and 'contactBegin' or 'contactEnd', other, contact)
        if not self.destroyed and not self.object.destroyed and self.settings.onContact then
            self.settings.onContact(self, phase, contact)
        end
    end
    callback.beginContact = function(_, contact)
        notify('begin', contact)
    end
    callback.endContact = function(_, contact)
        notify('end', contact)
    end
    return callback
end

return Contacts
