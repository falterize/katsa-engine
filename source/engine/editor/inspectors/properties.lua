-- Stable public property API; policy, discovery and mutation have separate owners.
local Properties = {}
require('source.engine.editor.inspectors.propertyRead').install(Properties)
require('source.engine.editor.inspectors.propertyWrite').install(Properties)
return Properties
