-- Inspector descriptions of Node, world and environment properties.
-- Editor text only: the classes carry no hint of their own.
-- Shape: { ClassName = { property = 'text' } }; a subclass inherits its base class entries.
return {
    Actor = {
        autoStart = 'Start the workers when the node is created.',
        messagesPerFrame = 'Largest number of results delivered per worker per frame.',
        script = 'Lua file the worker threads run. It registers handlers with Actor.on(topic, fn).',
        workers = 'Worker threads running the script. Requests go to the least busy one.',
    },
    ClickDetector3D = {
        priority = 'Order when several detectors cover the same click: higher runs first, equal '
            .. 'priorities run in creation order.',
    },
}
