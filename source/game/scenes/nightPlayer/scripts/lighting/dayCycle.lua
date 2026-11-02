local Methods = {}

function Methods:setTimeOfDay(hour)
    self.dayHour = hour % 24
    if self.daySlider then
        self.daySlider.value = self.dayHour
    end
    local sun = require('./directional').create(self.scene.world, 'DaySun')
    local elevation = math.sin((self.dayHour - 6) / 24 * math.pi * 2)
    local daylight = math.max(0, elevation)
    sun.enabled = daylight > 0.01
    sun.rotation = require('source.engine.lighting.orientation').rotation({
        -math.cos((self.dayHour - 6) / 24 * math.pi * 2),
        -math.max(0.05, elevation),
        0.35,
    })
    sun.brightness = daylight * 1.4
    local ambient = self.scene.world.environment.ambient
    ambient[1], ambient[2], ambient[3] = 3 + daylight * 60, 5 + daylight * 70, 9 + daylight * 90
    self.scene.world.environment.sky.brightness = 0.025 + daylight * 0.975
    if self.dayLabel then
        self.dayLabel.text = string.format(
            'time of day: %02d:%02d',
            math.floor(self.dayHour),
            math.floor(self.dayHour % 1 * 60)
        )
    end
end

return Methods
