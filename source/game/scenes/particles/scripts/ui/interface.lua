local Interface = {}

function Interface.create(self)
    self.scene.package:require('scripts.ui.panels.controls').build(self)
end

return Interface
