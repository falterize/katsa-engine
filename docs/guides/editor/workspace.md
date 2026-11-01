# Workspace editor

Open the side tab or press F2. Opening and closing use real time, take 0.25 seconds and can reverse during motion. World3D, the scene's ScreenUI/CanvasGroup hierarchy, BillboardUI children and Lighting settings are visible. The editor's own CanvasGroup is excluded. Branches collapse; both panes support touch scrolling and mouse wheels.

Select a node to inspect its supported public properties. Boolean buttons toggle directly. Scalar, string and vector-component buttons open an input field. Apply/Enter commits; Cancel/Escape cancels. Android requests the native text keyboard. Camera3D movement is suspended during text entry. Validation rejects non-finite numbers, invalid ranges and conflicting mesh names. Renames update World3D.byName and BillboardUI adornee references. Position/rotation edits teleport rigid bodies through the physics backend.

Local shadows switches the sun off and enables local mapping. New local lights cast by default; explicit castShadow=false remains opt-out. Lighting settings and light flags can also be edited separately.

Changes are runtime-only. Source Lua files are not rewritten. Physics collider resizing requires rebuilding the body and is rejected by the property editor. World3D retains the fixed physical coordinate system. Script-driven transforms can be overwritten by their owning controller or animation. GPU objects, callbacks and caches are not editable.

UIStroke/UICorner length editors display Scale/Offset; UDim2 displays two pairs.
UIGradient supports live stop alpha/RGB/HEX edits, deep Cancel, Add and Remove.
Image/Decal mode controls conditionally reveal applicable settings without erasing
inactive values. User types registered in a World3D supply propertySchema descriptors
to the same inspector. New ClickDetector3D nodes expose radius, enabled and explicit
positionSource. Parent remains read-only; Adornee and positionSource have node pickers.
The drawer is a debugging tool: no source rewriting, undo stack or scene serialization.
