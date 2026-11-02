-- Stable public property API; policy, discovery and mutation have separate owners.
local Properties = {}
require('./propertyRead').install(Properties)
require('./propertyWrite').install(Properties)
return Properties
