--- === hs._asm.canvas ===
---
--- A different approach to drawing in Hammerspoon
---
--- `hs.drawing` approaches graphical images as independant primitives, each "shape" being a separate drawing object based on the core primitives: ellipse, rectangle, point, line, text, etc.  This model works well with graphical elements that are expected to be managed individually and don't have complex clipping interactions, but does not scale well when more complex combinations or groups of drawing elements need to be moved or manipulated as a group, and only allows for simple inclusionary clipping regions.
---
--- This module works by designating a canvas and then assigning a series of graphical primitives to the canvas.  Included in this assignment list are rules about how the individual elements interact with each other within the canvas (compositing and clipping rules), and direct modification of the canvas itself (move, resize, etc.) causes all of the assigned elements to be adjusted as a group.
---
--- This is an experimental work in progress, so we'll see how it goes...
---
--- ### Overview
---
--- The canvas elements are defined in an array, and each entry of the array is a table of key-value pairs describing the element at that position.  Elements are rendered in the order in which they are assigned to the array (i.e. element 1 is drawn before element 2, etc.).
---
--- Attributes for canvas elements are defined in [hs._asm.canvas.attributes](#attributes). All canvas elements require the `type` field; all other attributes have default values.  Fields required to properly define the element (for example, `frame` for the `rectangle` element type) will be copied into the element definition with their default values if they are not specified at the time of creation. Optional attributes will only be assigned in the element definition if they are specified.  When the module requires the value for an element's attribute it first checks the element definition itself, then the defaults are looked for in the canvas defaults, and then finally in the module's built in defaults (specified in the descriptions below).

--- hs._asm.canvas.attributes
--- Field
--- Canvas Element Attributes
---
--- * `type` - specifies the type of canvas element the table represents. This attribute has no default and must be specified for each element in the canvas array. Valid type strings are:
---   * `arc`           - an arc inscribed on a circle, defined by `radius`, `center`, `startAngle`, and `endAngle`.
---   * `view`          - an independent userdata object, possibly defined by another module, which can be displayed as an element within the specified frame. Defined by `view` and `frame`.
---   * `circle`        - a circle, defined by `radius` and `center`.
---   * `ellipticalArc` - an arc inscribed on an oval, defined by `frame`, `startAngle`, and `endAngle`.
---   * `image`         - an image as defined by one of the `hs.image` constructors.
---   * `oval`          - an oval, defined by `frame`
---   * `points`        - a list of points defined in `coordinates`.
---   * `rectangle`     - a rectangle, optionally with rounded corners, defined by `frame`.
---   * `resetClip`     - a special type -- indicates that the current clipping shape should be reset to the canvas default (the full canvas area).  See `Clipping Example`.  All other attributes, except `action` are ignored.
---   * `segments`      - a list of line segments or bezier curves with control points, defined in `coordinates`.
---   * `text`          - a string or `hs.styledtext` object, defined by `text` and `frame`.
---   * `view`          - an independent userdata object, possibly defined by another module, which can be displayed as an element within the specified frame. Defined by `view` and `frame`. See [hs._asm.canvas.views](#views) for more information.
---
--- * The following is a list of all valid attributes.  Not all attributes apply to every type, but you can set them for any type.
---   * `action`              - Default `strokeAndFill`. A string specifying the action to take for the element in the array.  The following actions are recognized:
---     * `clip`          - append the shape to the current clipping region for the canvas. Ignored for `canvas`, `image`, and `text` types.
---     * `build`         - do not render the element -- its shape is preserved and the next element in the canvas array is appended to it.  This can be used to create complex shapes or clipping regions. The stroke and fill settings for a complex object created in this manner will be those of the final object of the group. Ignored for `canvas`, `image`, and `text` types.
---     * `fill`          - fill the canvas element, if it is a shape, or display it normally if it is a `canvas`, `image` or `text`.  Ignored for `resetClip`.
---     * `skip`          - ignore this element or its effects.  Can be used to temporarily "remove" an object from the canvas.
---     * `stroke`        - stroke (outline) the canvas element, if it is a shape, or display it normally if it is a `canvas`, `image` or `text`.  Ignored for `resetClip`.
---     * `strokeAndFill` - stroke and fill the canvas element, if it is a shape, or display it normally if it is a `canvas`, `image` or `text`.  Ignored for `resetClip`.
---   * `absolutePosition`    - Default `true`. If false, numeric location and size attributes (`frame`, `center`, `radius`, and `coordinates`) will be automatically adjusted when the canvas is resized with [hs._asm.canvas:size](#size) or [hs._asm.canvas:frame](#frame) so that the element remains in the same relative position in the canvas.
---   * `absoluteSize`        - Default `true`. If false, numeric location and size attributes (`frame`, `center`, `radius`, and `coordinates`) will be automatically adjusted when the canvas is resized with [hs._asm.canvas:size](#size) or [hs._asm.canvas:frame](#frame) so that the element maintains the same relative size in the canvas.
---   * `antialias`           - Default `true`.  Indicates whether or not antialiasing should be enabled for the element.
---   * `arcRadii`            - Default `true`. Used by the `arc` and `ellipticalArc` types to specify whether or not line segments from the element's center to the start and end angles should be included in the element's visible portion.  This affects whether the object's stroke is a pie-shape or an arc with a chord from the start angle to the end angle.
---   * `arcClockwise`        - Default `true`.  Used by the `arc` and `ellipticalArc` types to specify whether the arc should be drawn from the start angle to the end angle in a clockwise (true) direction or in a counter-clockwise (false) direction.
---   * `compositeRule`       - A string, default "sourceOver", specifying how this element should be combined with earlier elements of the canvas.  See [hs._asm.canvas.compositeTypes](#compositeTypes) for a list of valid strings and their descriptions.
---   * `center`              - Default `{ x = "50%", y = "50%" }`.  Used by the `circle` and `arc` types to specify the center of the canvas element.  The `x` and `y` fields can be specified as numbers or as a string. When specified as a string, the value is treated as a percentage of the canvas size.  See the section on [percentages](#percentages) for more information.
---   * `clipToPath`          - Default `false`.   Specifies whether the clipping regions should be temporarily limited to the element's shape while rendering this element or not.  This can be used to produce crisper edges, as seen with `hs.drawing` but reduces stroke width granularity for widths less than 1.0 and causes occasional "missing" lines with the `segments` element type. Ignored for the `canvas`, `image`, `point`, and `text` types.
---   * `closed`              - Default `false`.  Used by the `segments` type to specify whether or not the shape defined by the lines and curves defined should be closed (true) or open (false).  When an object is closed, an implicit line is stroked from the final point back to the initial point of the coordinates listed.
---   * `coordinates`         - An array containing coordinates used by the `segments` and `points` types to define the lines and curves or points that make up the canvas element.  The following keys are recognized and may be specified as numbers or strings (see the section on [percentages](#percentages)).
---     * `x`   - required for `segments` and `points`, specifying the x coordinate of a point.
---     * `y`   - required for `segments` and `points`, specifying the y coordinate of a point.
---     * `c1x` - optional for `segments, specifying the x coordinate of the first control point used to draw a bezier curve between this point and the previous point.  Ignored for `points` and if present in the first coordinate in the `coordinates` array.
---     * `c1y` - optional for `segments, specifying the y coordinate of the first control point used to draw a bezier curve between this point and the previous point.  Ignored for `points` and if present in the first coordinate in the `coordinates` array.
---     * `c2x` - optional for `segments, specifying the x coordinate of the second control point used to draw a bezier curve between this point and the previous point.  Ignored for `points` and if present in the first coordinate in the `coordinates` array.
---     * `c2y` - optional for `segments, specifying the y coordinate of the second control point used to draw a bezier curve between this point and the previous point.  Ignored for `points` and if present in the first coordinate in the `coordinates` array.
---   * `endAngle`            - Default `360.0`. Used by the `arc` and `ellipticalArc` to specify the ending angle position for the inscribed arc.
---   * `fillColor`           - Default `{ red = 1.0 }`.  Specifies the color used to fill the canvas element when the `action` is set to `fill` or `strokeAndFill` and `fillGradient` is equal to `none`.  Ignored for the `canvas`, `image`, `points`, and `text` types.
---   * `fillGradient`        - Default "none".  A string specifying whether a fill gradient should be used instead of the fill color when the action is `fill` or `strokeAndFill`.  May be "none", "linear", or "radial".
---   * `fillGradientAngle`   - Default 0.0.  Specifies the direction of a linear gradient when `fillGradient` is linear.
---   * `fillGradientCenter`  - Default `{ x = 0.0, y = 0.0 }`. Specifies the relative center point within the elements bounds of a radial gradient when `fillGradient` is `radial`.  The `x` and `y` fields must both be between -1.0 and 1.0 inclusive.
---   * `fillGradientColors`  - Default `{ { white = 0.0 }, { white = 1.0 } }`.  Specifies the colors to use for the gradient when `fillGradient` is not `none`.  You must specify at least two colors, each of which must be convertible into the RGB color space (i.e. they cannot be an image being used as a color pattern).  The gradient will blend from the first to the next, and so on until the last color.  If more than two colors are specified, the "color stops" will be placed at evenly spaced intervals within the element.
---   * `flatness`            - Default `0.6`.  A number which specifies the accuracy (or smoothness) with which curves are rendered. It is also the maximum error tolerance (measured in pixels) for rendering curves, where smaller numbers give smoother curves at the expense of more computation.
---   * `flattenPath`         - Default `false`. Specifies whether curved line segments should be converted into straight line approximations. The granularity of the approximations is controlled by the path's current flatness value.
---   * `frame`               - Default `{ x = "0%", y = "0%", h = "100%", w = "100%" }`.  Used by the `rectangle`, `oval`, `ellipticalArc`, `text`, `view` and `image` types to specify the element's position and size.  When the key value for `x`, `y`, `h`, or `w` are specified as a string, the value is treated as a percentage of the canvas size.  See the section on [percentages](#percentages) for more information.
---   * `id`                  - An optional string or number which is included in mouse callbacks to identify the element which was the target of the mouse event.  If this is not specified for an element, it's index position is used instead.
---   * `image`               - Defaults to a blank image.  Used by the `image` type to specify an `hs.image` object to display as an image.
---   * `imageAlpha`          - Defaults to `1.0`.  A number between 0.0 and 1.0 specifying the alpha value to be applied to the image specified by `image`.  Note that if an image is a template image, then this attribute will internally default to `0.5` unless explicitly set for the element.
---   * `imageAlignment`      - Default "center". A string specifying the alignment of the image within the canvas element's frame.  Valid values for this attribute are "center", "bottom", "topLeft", "bottomLeft", "bottomRight", "left", "right", "top", and "topRight".
---   * `imageAnimationFrame` - Default `0`. An integer specifying the image frame to display when the image is from an animated GIF.  This attribute is ignored for other image types.  May be specified as a negative integer indicating that the image frame should be calculated from the last frame and calculated backwards (i.e. specifying `-1` selects the last frame for the GIF.)
---   * `imageAnimates`       - Default `false`. A boolean specifying whether or not an animated GIF should be animated or if only a single frame should be shown.  Ignored for other image types.
---   * `imageScaling`        - Default "scalePropertionally".  A string specifying how the image should be scaled within the canvas element's frame.  Valid values for this attribute are:
---     * `scaleToFit`          - shrink the image, preserving the aspect ratio, to fit the drawing frame only if the image is larger than the drawing frame.
---     * `shrinkToFit`         - shrink or expand the image to fully fill the drawing frame.  This does not preserve the aspect ratio.
---     * `none`                - perform no scaling or resizing of the image.
---     * `scaleProportionally` - shrink or expand the image to fully fill the drawing frame, preserving the aspect ration.
---   * `miterLimit`          - Default `10.0`. The limit at which miter joins are converted to bevel join when `strokeJoinStyle` is `miter`.  The miter limit helps you avoid spikes at the junction of two line segments.  When the ratio of the miter length—the diagonal length of the miter join—to the line thickness exceeds the miter limit, the joint is converted to a bevel join. Ignored for the `canvas`, `text`, and `image` types.
---   * `padding`             - Default `0.0`. When an element specifies position information by percentage (i.e. as a string), the actual frame used for calculating position values is inset from the canvas frame on all sides by this amount. If you are using shadows with your elements, the shadow position is not included in the element's size and position specification; this attribute can be used to provide extra space for the shadow to be fully rendered within the canvas.
---   * `radius`              - Default "50%". Used by the `arc` and `circle` types to specify the radius of the circle for the element. May be specified as a string or a number.  When specified as a string, the value is treated as a percentage of the canvas size.  See the section on [percentages](#percentages) for more information.
---   * `reversePath`         - Default `false`.  Specifies drawing direction for the canvas element.  By default, canvas elements are drawn from the point nearest the origin (top left corner) in a clockwise direction.  Setting this to true causes the element to be drawn in a counter-clockwise direction. This will mostly affect fill and stroke dash patterns, but can also be used with clipping regions to create cut-outs.  Ignored for `canvas`, `image`, and `text` types.
---   * `roundedRectRadii`    - Default `{ xRadis = 0.0, yRadius = 0.0 }`.
---   * `shadow`              - Default `{ blurRadius = 5.0, color = { alpha = 1/3 }, offset = { h = -5.0, w = 5.0 } }`.  Specifies the shadow blurring, color, and offset to be added to an element which has `withShadow` set to true.
---   * `startAngle`          - Default `0.0`. Used by the `arc` and `ellipticalArc` to specify the starting angle position for the inscribed arc.
---   * `strokeCapStyle`      - Default "butt". A string which specifies the shape of the endpoints of an open path when stroked.  Primarily noticeable for lines rendered with the `segments` type.  Valid values for this attribute are "butt", "round", and "square".
---   * `strokeColor`         - Default `{ white = 0 }`.  Specifies the stroke (outline) color for a canvas element when the action is set to `stroke` or `strokeAndFill`.  Ignored for the `canvas`, `text`, and `image` types.
---   * `strokeDashPattern`   - Default `{}`.  Specifies an array of numbers specifying a dash pattern for stroked lines when an element's `action` attribute is set to `stroke` or `strokeAndFill`.  The numbers in the array alternate with the first element specifying a dash length in points, the second specifying a gap length in points, the third a dash length, etc.  The array repeats to fully stroke the element.  Ignored for the `canvas`, `image`, and `text` types.
---   * `strokeDashPhase`     - Default `0.0`.  Specifies an offset, in points, where the dash pattern specified by `strokeDashPattern` should start. Ignored for the `canvas`, `image`, and `text` types.
---   * `strokeJoinStyle`     - Default "miter".  A string which specifies the shape of the joints between connected segments of a stroked path.  Valid values for this attribute are "miter", "round", and "bevel".  Ignored for element types of `canvas`, `image`, and `text`.
---   * `strokeWidth`         - Default `1.0`.  Specifies the width of stroked lines when an element's action is set to `stroke` or `strokeAndFill`.  Ignored for the `canvas`, `image`, and `text` element types.
---   * `text`                - Default `""`.  Specifies the text to display for a `text` element.  This may be specified as a string, or as an `hs.styledtext` object.
---   * `textAlignment`       - Default `natural`. A string specifying the alignment of the text within a canvas element of type `text`.  This field is ignored if the text is specified as an `hs.styledtext` object.  Valid values for this attributes are:
---     * `left`      - the text is visually left aligned.
---     * `right`     - the text is visually right aligned.
---     * `center`    - the text is visually center aligned.
---     * `justified` - the text is justified
---     * `natural`   - the natural alignment of the text’s script
---   * `textColor`           - Default `{ white = 1.0 }`.  Specifies the color to use when displaying the `text` element type, if the text is specified as a string.  This field is ignored if the text is specified as an `hs.styledtext` object.
---   * `textFont`            - Defaults to the default system font.  A string specifying the name of thefont to use when displaying the `text` element type, if the text is specified as a string.  This field is ignored if the text is specified as an `hs.styledtext` object.
---   * `textLineBreak`       - Default `wordWrap`. A string specifying how to wrap text which exceeds the canvas element's frame for an element of type `text`.  This field is ignored if the text is specified as an `hs.styledtext` object.  Valid values for this attribute are:
---     * `wordWrap`       - wrap at word boundaries, unless the word itself doesn’t fit on a single line
---     * `charWrap`       - wrap before the first character that doesn’t fit
---     * `clip`           - do not draw past the edge of the drawing object frame
---     * `truncateHead`   - the line is displayed so that the end fits in the frame and the missing text at the beginning of the line is indicated by an ellipsis
---     * `truncateTail`   - the line is displayed so that the beginning fits in the frame and the missing text at the end of the line is indicated by an ellipsis
---     * `truncateMiddle` - the line is displayed so that the beginning and end fit in the frame and the missing text in the middle is indicated by an ellipsis
---   * `textSize`            - Default `27.0`.  Specifies the font size to use when displaying the `text` element type, if the text is specified as a string.  This field is ignored if the text is specified as an `hs.styledtext` object.
---   * `trackMouseByBounds`  - Default `false`. If true, mouse events are based on the element's bounds (smallest rectangle which completely contains the element); otherwise, mouse events are based on the visible portion of the canvas element.
---   * `trackMouseEnterExit` - Default `false`.  Generates a callback when the mouse enters or exits the canvas element.  For `canvas` and `text` types, the `frame` of the element defines the boundaries of the tracking area.
---   * `trackMouseDown`      - Default `false`.  Generates a callback when mouse button is clicked down while the cursor is within the canvas element.  For `canvas` and `text` types, the `frame` of the element defines the boundaries of the tracking area.
---   * `trackMouseUp`        - Default `false`.  Generates a callback when mouse button is released while the cursor is within the canvas element.  For `canvas` and `text` types, the `frame` of the element defines the boundaries of the tracking area.
---   * `trackMouseMove`      - Default `false`.  Generates a callback when the mouse cursor moves within the canvas element.  For `canvas` and `text` types, the `frame` of the element defines the boundaries of the tracking area.
---   * `transformation`      - Default `{ m11 = 1.0, m12 = 0.0, m21 = 0.0, m22 = 1.0, tX = 0.0, tY = 0.0 }`. Specifies a matrix transformation to apply to the element before displaying it.  Transformations may include rotation, translation, scaling, skewing, etc.
---   * `view`                - Defaults to nil. The userdata object which is to be displayed for an element of type `view`.  The object must not currently belong to a visible window.  Assign nil to this property to release a previously assigned object for use elsewhere as an element or on its own (if supported).  See [hs._asm.canvas.views](#views) for more information.
---   * `viewAlpha`           - Default `1.0`.  Specifies the alpha value to apply to the view in a canvas element of the `view` type.
---   * `windingRule`         - Default "nonZero".  A string specifying the winding rule in effect for the canvas element. May be "nonZero" or "evenOdd".  The winding rule determines which portions of an element to fill. This setting will only have a visible effect on compound elements (built with the `build` action) or elements of type `segments` when the object is made from lines which cross.
---   * `withShadow`          - Default `false`. Specifies whether a shadow effect should be applied to the canvas element.  Ignored for the `text` type.


local USERDATA_TAG = "hs._asm.canvas"
local module       = require(USERDATA_TAG..".internal")
module.matrix      = require(USERDATA_TAG..".matrix")

-- include these so that their support functions are available to us
require("hs.image")
require("hs.styledtext")

local canvasMT     = hs.getObjectMetatable(USERDATA_TAG)

-- private variables and methods -----------------------------------------

local _kMetaTable = {}
_kMetaTable._k = setmetatable({}, {__mode = "k"})
_kMetaTable._t = setmetatable({}, {__mode = "k"})
_kMetaTable.__index = function(obj, key)
        if _kMetaTable._k[obj] then
            if _kMetaTable._k[obj][key] then
                return _kMetaTable._k[obj][key]
            else
                for k,v in pairs(_kMetaTable._k[obj]) do
                    if v == key then return k end
                end
            end
        end
        return nil
    end
_kMetaTable.__newindex = function(obj, key, value)
        error("attempt to modify a table of constants",2)
        return nil
    end
_kMetaTable.__pairs = function(obj) return pairs(_kMetaTable._k[obj]) end
_kMetaTable.__len = function(obj) return #_kMetaTable._k[obj] end
_kMetaTable.__tostring = function(obj)
        local result = ""
        if _kMetaTable._k[obj] then
            local width = 0
            for k,v in pairs(_kMetaTable._k[obj]) do width = width < #tostring(k) and #tostring(k) or width end
            for k,v in require("hs.fnutils").sortByKeys(_kMetaTable._k[obj]) do
                if _kMetaTable._t[obj] == "table" then
                    result = result..string.format("%-"..tostring(width).."s %s\n", tostring(k),
                        ((type(v) == "table") and "{ table }" or tostring(v)))
                else
                    result = result..((type(v) == "table") and "{ table }" or tostring(v)).."\n"
                end
            end
        else
            result = "constants table missing"
        end
        return result
    end
_kMetaTable.__metatable = _kMetaTable -- go ahead and look, but don't unset this

local _makeConstantsTable
_makeConstantsTable = function(theTable)
    if type(theTable) ~= "table" then
        local dbg = debug.getinfo(2)
        local msg = dbg.short_src..":"..dbg.currentline..": attempting to make a '"..type(theTable).."' into a constant table"
        if module.log then module.log.ef(msg) else print(msg) end
        return theTable
    end
    for k,v in pairs(theTable) do
        if type(v) == "table" then
            local count = 0
            for a,b in pairs(v) do count = count + 1 end
            local results = _makeConstantsTable(v)
            if #v > 0 and #v == count then
                _kMetaTable._t[results] = "array"
            else
                _kMetaTable._t[results] = "table"
            end
            theTable[k] = results
        end
    end
    local results = setmetatable({}, _kMetaTable)
    _kMetaTable._k[results] = theTable
    local count = 0
    for a,b in pairs(theTable) do count = count + 1 end
    if #theTable > 0 and #theTable == count then
        _kMetaTable._t[results] = "array"
    else
        _kMetaTable._t[results] = "table"
    end
    return results
end

-- Public interface ------------------------------------------------------

module.compositeTypes  = _makeConstantsTable(module.compositeTypes)
module.windowBehaviors = _makeConstantsTable(module.windowBehaviors)
module.windowLevels    = _makeConstantsTable(module.windowLevels)
module.windowMasks     = _makeConstantsTable(module.windowMasks)

--- hs._asm.canvas:windowStyle(mask) -> canvasObject | currentMask
--- Method
--- Get or set the window display style
---
--- Parameters:
---  * mask - if present, this mask should be a combination of values found in [hs._asm.canvas.windowMasks](#windowMasks) describing the window style.  The mask should be provided as one of the following:
---    * integer - a number representing the style which can be created by combining values found in [hs._asm.canvas.windowMasks](#windowMasks) with the logical or operator.
---    * string  - a single key from [hs._asm.canvas.windowMasks](#windowMasks) which will be toggled in the current window style.
---    * table   - a list of keys from [hs._asm.canvas.windowMasks](#windowMasks) which will be combined to make the final style by combining their values with the logical or operator.
---
--- Returns:
---  * if a mask is provided, then the canvasObject is returned; otherwise the current mask value is returned.
canvasMT.windowStyle = function(self, ...)
    local arg = table.pack(...)
    local theMask = canvasMT._windowStyle(self)

    if arg.n ~= 0 then
        if type(arg[1]) == "number" then
            theMask = arg[1]
        elseif type(arg[1]) == "string" then
            if module.windowMasks[arg[1]] then
                theMask = theMask ~ module.windowMasks[arg[1]]
            else
                return error("unrecognized style specified: "..arg[1])
            end
        elseif type(arg[1]) == "table" then
            theMask = 0
            for i,v in ipairs(arg[1]) do
                if module.windowMasks[v] then
                    theMask = theMask | module.windowMasks[v]
                else
                    return error("unrecognized style specified: "..v)
                end
            end
        else
            return error("invalid type: number, string, or table expected, got "..type(arg[1]))
        end
        return canvasMT._windowStyle(self, theMask)
    else
        return theMask
    end
end

--- hs._asm.canvas:behaviorAsLabels(behaviorTable) -> canvasObject | currentValue
--- Method
--- Get or set the window behavior settings for the canvas object using labels defined in [hs._asm.canvas.windowBehaviors](#windowBehaviors).
---
--- Parameters:
---  * behaviorTable - an optional table of strings and/or numbers specifying the desired window behavior for the canvas object.
---
--- Returns:
---  * If an argument is provided, the canvas object; otherwise the current value.
canvasMT.behaviorAsLabels = function(obj, ...)
    local args = table.pack(...)

    if args.n == 0 then
        local results = {}
        local behaviorNumber = obj:behavior()

        if behaviorNumber ~= 0 then
            for i, v in pairs(module.windowBehaviors) do
                if type(i) == "string" then
                    if (behaviorNumber & v) > 0 then table.insert(results, i) end
                end
            end
        else
            table.insert(results, module.windowBehaviors[0])
        end
        return setmetatable(results, { __tostring = function(_)
            table.sort(_)
            return "{ "..table.concat(_, ", ").." }"
        end})
    elseif args.n == 1 and type(args[1]) == "table" then
        local newBehavior = 0
        for i,v in ipairs(args[1]) do
            local flag = tonumber(v) or module.windowBehaviors[v]
            if flag then newBehavior = newBehavior | flag end
        end
        return obj:behavior(newBehavior)
    elseif args.n > 1 then
        error("behaviorByLabels method expects 0 or 1 arguments", 2)
    else
        error("behaviorByLabels method argument must be a table", 2)
    end
end

--- hs._asm.canvas:frame([rect]) -> canvasObject | currentValue
--- Method
--- Get or set the frame of the canvasObject.
---
--- Parameters:
---  * rect - An optional rect-table containing the co-ordinates and size the canvas object should be moved and set to
---
--- Returns:
---  * If an argument is provided, the canvas object; otherwise the current value.
---
--- Notes:
---  * a rect-table is a table with key-value pairs specifying the new top-left coordinate on the screen of the canvas (keys `x`  and `y`) and the new size (keys `h` and `w`).  The table may be crafted by any method which includes these keys, including the use of an `hs.geometry` object.
---
---  * elements in the canvas that have the `absolutePosition` attribute set to false will be moved so that their relative position within the canvas remains the same with respect to the new size.
---  * elements in the canvas that have the `absoluteSize` attribute set to false will be resized so that their relative size with respect to the canvas remains the same with respect to the new size.
canvasMT.frame = function(obj, ...)
    local args = table.pack(...)

    if args.n == 0 then
        local topLeft = obj:topLeft()
        local size    = obj:size()
        return {
            __luaSkinType = "NSRect",
            x = topLeft.x,
            y = topLeft.y,
            h = size.h,
            w = size.w,
        }
    elseif args.n == 1 and type(args[1]) == "table" then
        obj:size(args[1])
        obj:topLeft(args[1])
        return obj
    elseif args.n > 1 then
        error("frame method expects 0 or 1 arguments", 2)
    else
        error("frame method argument must be a table", 2)
    end
end

--- hs._asm.canvas:bringToFront([aboveEverything]) -> canvasObject
--- Method
--- Places the canvas object on top of normal windows
---
--- Parameters:
---  * aboveEverything - An optional boolean value that controls how far to the front the canvas should be placed. Defaults to false.
---    * if true, place the canvas on top of all windows (including the dock and menubar and fullscreen windows).
---    * if false, place the canvas above normal windows, but below the dock, menubar and fullscreen windows.
---
--- Returns:
---  * The canvas object
canvasMT.bringToFront = function(obj, ...)
    local args = table.pack(...)

    if args.n == 0 then
        return obj:level(module.windowLevels.floating)
    elseif args.n == 1 and type(args[1]) == "boolean" then
        return obj:level(module.windowLevels[(args[1] and "screenSaver" or "floating")])
    elseif args.n > 1 then
        error("bringToFront method expects 0 or 1 arguments", 2)
    else
        error("bringToFront method argument must be boolean", 2)
    end
end

--- hs._asm.canvas:sendToBack() -> canvasObject
--- Method
--- Places the canvas object behind normal windows, between the desktop wallpaper and desktop icons
---
--- Parameters:
---  * None
---
--- Returns:
---  * The canvas object
canvasMT.sendToBack = function(obj, ...)
    local args = table.pack(...)

    if args.n == 0 then
        return obj:level(module.windowLevels.desktopIcon - 1)
    else
        error("sendToBack method expects 0 arguments", 2)
    end
end

--- hs._asm.canvas:isVisible() -> boolean
--- Method
--- Returns whether or not the canvas is currently showing and is (at least partially) visible on screen.
---
--- Parameters:
---  * None
---
--- Returns:
---  * a boolean indicating whether or not the canvas is currently visible.
---
--- Notes:
---  * This is syntactic sugar for `not hs._asm.canvas:isOccluded()`.
---  * See (hs._asm.canvas:isOccluded)[#isOccluded] for more details.
canvasMT.isVisible = function(obj, ...) return not obj:isOccluded(...) end

--- hs._asm.canvas:appendElements(element, ...) -> canvasObject
--- Method
--- Appends the elements specified to the canvas.
---
--- Parameters:
---  * `element` - a table containing key-value pairs that define the element to be appended to the canvas.  You can specify one or more elements and they will be appended in the order they are listed.
---
--- Returns:
---  * the canvas object
---
--- Notes:
---  * You can also specify multiple elements in a table as an array, where each index in the table contains an element table, and use the array as a single argument to this method if this style works better in your code.
canvasMT.appendElements = function(obj, ...)
    local elementsArray = table.pack(...)
    if elementsArray.n == 1 and #elementsArray[1] ~= 0 then elementsArray = elementsArray[1] end
    for i,v in ipairs(elementsArray) do obj:insertElement(v) end
    return obj
end

--- hs._asm.canvas:replaceElements(element, ...) -> canvasObject
--- Method
--- Replaces all of the elements in the canvas with the elements specified.  Shortens or lengthens the canvas element count if necessary to accomodate the new canvas elements.
---
--- Parameters:
---  * `element` - a table containing key-value pairs that define the element to be assigned to the canvas.  You can specify one or more elements and they will be appended in the order they are listed.
---
--- Returns:
---  * the canvas object
---
--- Notes:
---  * You can also specify multiple elements in a table as an array, where each index in the table contains an element table, and use the array as a single argument to this method if this style works better in your code.
canvasMT.replaceElements = function(obj,  ...)
    local elementsArray = table.pack(...)
    if elementsArray.n == 1 and #elementsArray[1] ~= 0 then elementsArray = elementsArray[1] end
    for i,v in ipairs(elementsArray) do obj:assignElement(v, i) end
    while (#obj > #elementArray) do obj:removeElement() end
    return obj
end

--- hs._asm.canvas:rotateElement(index, angle, [point], [append]) -> canvasObject
--- Method
--- Rotates an element about the point specified, or the elements center if no point is specified.
---
--- Parameters:
---  * `index`  - the index of the element to rotate
---  * `angle`  - the angle to rotate the object in a clockwise direction
---  * `point`  - an optional point table, defaulting to the elements center, specifying the point around which the object should be rotated
---  * `append` - an optional boolean, default false, specifying whether or not the rotation transformation matrix should be appended to the existing transformation assigned to the element (true) or replace it (false).
---
--- Returns:
---  * the canvas object
---
--- Notes:
---  * a point-table is a table with key-value pairs specifying a coordinate in the canvas (keys `x`  and `y`). The table may be crafted by any method which includes these keys, including the use of an `hs.geometry` object.
---  * The center of the object is determined by getting the element's bounds with [hs._asm.canvas:elementBounds](#elementBounds).
---  * If the third argument is a boolean value, the `point` argument is assumed to be the element's center and the boolean value is used as the `append` argument.
---
---  * This method uses [hs._asm.canvas.matrix](MATRIX.md) to generate the rotation transformation and provides a wrapper for `hs._asm.canvas.matrix.translate(x, y):rotate(angle):translate(-x, -y)` which is then assigned or appended to the element's existing `transformation` attribute.
canvasMT.rotateElement = function(obj, index, angle, point, append)
    if type(point) == "boolean" then
        append, point = point, nil
    end
    if not point then
        local bounds = obj:elementBounds(index)
        point = {
            x = bounds.x + bounds.w / 2,
            y = bounds.y + bounds.h / 2,
        }
    end

    local currentTransform = obj:elementAttribute(index, "transformation")
    if append then
        obj[index].transformation = obj[index].transformation:translate(point.x, point.y)
                                                             :rotate(angle)
                                                             :translate(-point.x, -point.y)
    else
        obj[index].transformation = module.matrix.translate(point.x, point.y):rotate(angle)
                                                                             :translate(-point.x, -point.y)
    end
    return obj
end

--- hs._asm.canvas:copy() -> canvasObject
--- Method
--- Creates a copy of the canvas.
---
--- Parameters:
---  * None
---
--- Returns:
---  * a copy of the canvas
---
--- Notes:
---  * The copy of the canvas will be identical in all respectes except:
---    * The new canvas will not have a callback function assigned, even if the original canvas does.
---    * The new canvas will not initially be visible, even if the original is.
---  * The new canvas is an independant entity -- any subsequent changes to either canvas will not be reflected in the other canvas.
---
---  * This method allows you to display a canvas in multiple places or use it as a canvas element multiple times.
canvasMT.copy = function(obj)
    local newObj = module.new(obj:frame()):alpha(obj:alpha())
                                 :behavior(obj:behavior())
                                 :canvasMouseEvents(obj:canvasMouseEvents())
                                 :clickActivating(obj:clickActivating())
                                 :level(obj:level())
                                 :transformation(obj:transformation())
                                 :wantsLayer(obj:wantsLayer())
    for i, v in ipairs(obj:canvasDefaultKeys()) do
      newObj:canvasDefaultFor(v, obj:canvasDefaultFor(v))
    end

    for i = 1, #obj, 1 do
      for i2, v2 in ipairs(obj:elementKeys(i)) do
          local value = obj:elementAttribute(i, v2)
          if v2 ~= "view" then
              newObj:elementAttribute(i, v2, value)
          else
              if getmetatable(value).copy then
                  newObj:elementAttribute(i, v2, value:copy())
              else
                  print(string.format("-- no copy method exists for %s object at index %d", tostring(value), i))
              end
          end
      end
    end
    return newObj
end

local elementMT = {
    __e = setmetatable({}, { __mode="k" }),
}

elementMT.__index = function(_, k)
    local obj = elementMT.__e[_]
    if obj.field then
        return obj.value[obj.field][k]
    elseif obj.key then
        if type(obj.value[k]) == "table" then
            local newTable = {}
            elementMT.__e[newTable] = { self = obj.self, index = obj.index, key = obj.key, value = obj.value, field = k }
            return setmetatable(newTable, elementMT)
        else
            return obj.value[k]
        end
    else
        local value
        if obj.index == "_default" then
            value = obj.self:canvasDefaultFor(k)
        else
            value = obj.self:elementAttribute(obj.index, k)
        end
        if type(value) == "table" then
            local newTable = {}
            elementMT.__e[newTable] = { self = obj.self, index = obj.index, key = k, value = value }
            return setmetatable(newTable, elementMT)
        else
            return value
        end
    end
end

elementMT.__newindex = function(_, k, v)
    local obj = elementMT.__e[_]
    local key, value
    if obj.field then
        key = obj.key
        obj.value[obj.field][k] = v
        value = obj.value
    elseif obj.key then
        key = obj.key
        obj.value[k] = v
        value = obj.value
    else
        key = k
        value = v
    end
    if obj.index == "_default" then
        return obj.self:canvasDefaultFor(key, value)
    else
        return obj.self:elementAttribute(obj.index, key, value)
    end
end

elementMT.__pairs = function(_)
    local obj = elementMT.__e[_]
    local keys = {}
    if obj.field then
        keys = obj.value[obj.field]
    elseif obj.key then
        keys = obj.value
    else
        if obj.index == "_default" then
            for i, k in ipairs(obj.self:canvasDefaultKeys()) do keys[k] = _[k] end
        else
            for i, k in ipairs(obj.self:elementKeys(obj.index)) do keys[k] = _[k] end
        end
    end
    return function(_, k)
            local v
            k, v = next(keys, k)
            return k, v
        end, _, nil
end

elementMT.__len = function(_)
    local obj = elementMT.__e[_]
    local value
    if obj.field then
        value = obj.value[obj.field]
    elseif obj.key then
        value = obj.value
    else
        value = {}
    end
    return #value
end

local dump_table
dump_table = function(depth, value)
    local result = "{\n"
    for k,v in require("hs.fnutils").sortByKeys(value) do
        local displayValue = v
        if type(v) == "table" then
            displayValue = dump_table(depth + 2, v)
        elseif type(v) == "string" then
            displayValue = "\"" .. v .. "\""
        end
        local displayKey = k
        if type(k) == "number" then
            displayKey = "[" .. tostring(k) .. "]"
        end
        result = result .. string.rep(" ", depth + 2) .. string.format("%s = %s,\n", tostring(displayKey), tostring(displayValue))
    end
    result = result .. string.rep(" ", depth) .. "}"
    return result
end

elementMT.__tostring = function(_)
    local obj = elementMT.__e[_]
    local value
    if obj.field then
        value = obj.value[obj.field]
    elseif obj.key then
        value = obj.value
    else
        value = _
    end
    if type(value) == "table" then
        return dump_table(0, value)
    else
        return tostring(value)
    end
end

--- hs._asm.canvas.object[index]
--- Field
--- An array-like method for accessing the attributes for the canvas element at the specified index
---
--- Metamethods are assigned to the canvas object so that you can refer to individual elements of the canvas as if the canvas object was an array.  Each element is represented by a table of key-value pairs, where each key represents an attribute for that element.  Valid index numbers range from 1 to [hs._asm.canvas:elementCount()](#elementCount) when getting an element or getting or setting one of its attributes, and from 1 to [hs._asm.canvas:elementCount()](#elementCount) + 1 when assign an element table to an index in the canvas.  For example:
---
--- ~~~lua
--- c = require("hs._asm.canvas")
--- a = c.new{ x = 100, y = 100, h = 100, w = 100 }:show()
--- a:insertElement({ type = "rectangle", fillColor = { blue = 1 } })
--- a:insertElement({ type = "circle", fillColor = { green = 1 } })
--- ~~~
--- can also be expressed as:
--- ~~~lua
--- c = require("hs._asm.canvas")
--- a = c.new{ x = 100, y = 100, h = 100, w = 100 }:show()
--- a[1] = { type = "rectangle", fillColor = { blue = 1 } }
--- a[2] = { type = "circle", fillColor = { green = 1 } }
--- ~~~
---
--- In addition, you can change a canvas's element using this same style: `a[2].fillColor.alpha = .5` will adjust the alpha value for element 2 of the canvas without adjusting any of the other color fields.  To replace the color entirely, assign it like this: `a[2].fillColor = { white = .5, alpha = .25 }`
---
--- The canvas defaults can also be accessed with the `_default` field like this: `a._default.strokeWidth = 5`.
---
--- It is important to note that these methods are a convenience and that the canvas object is not a true table.  The tables are generated dynamically as needed; as such `hs.inspect` cannot properly display them; however, you can just type in the element or element attribute you wish to see expanded in the Hammerspoon console (or in a `print` command) to see the assigned attributes, e.g. `a[1]` or `a[2].fillColor`, and an inspect-like output will be provided.  Attributes which allow using a string to specify a percentage (see [percentages](#percentages)) can also be retrieved as their actual number for the canvas's current size by appending `_raw` to the attribute name, e.g. `a[2].frame_raw`.
---
--- Because the canvas object is actually a Lua userdata, and not a real table, you cannot use the `table.insert` and `table.remove` functions on it.  For inserting or removing an element in any position except at the end of the canvas, you must still use [hs._asm.canvas:insertElement](#insertElement) and [hs._asm.canvas:removeElement](#removeElement).
---
--- You can, however, remove the last element with `a[#a] = nil`.
---
--- To print out all of the elements in the canvas with: `for i, v in ipairs(a) do print(v) end`.  The `pairs` iterator will also work, and will work on element sub-tables (transformations, fillColor and strokeColor, etc.), but this iterator does not guarantee order.
canvasMT.__index = function(self, key)
    if type(key) == "string" then
        if key == "_default" then
            local newTable = {}
            elementMT.__e[newTable] = { self = self, index = "_default" }
            return setmetatable(newTable, elementMT)
        else
            return canvasMT[key]
        end
    elseif type(key) == "number" and key > 0 and key <= self:elementCount() and math.tointeger(key) then
        local newTable = {}
        elementMT.__e[newTable] = { self = self, index = math.tointeger(key) }
        return setmetatable(newTable, elementMT)
    else
        return nil
    end
end

canvasMT.__newindex = function(self, key, value)
    if type(key) == "number" and key > 0 and key <= (self:elementCount() + 1) and math.tointeger(key) then
        if type(value) == "table" or type(value) == "nil" then
            return self:assignElement(value, math.tointeger(key))
        else
            error("element definition must be a table", 2)
        end
    else
        error("index invalid or out of bounds", 2)
    end
end

canvasMT.__len = function(self)
    return self:elementCount()
end

canvasMT.__pairs = function(self)
    local keys = {}
    for i = 1, self:elementCount(), 1 do keys[i] = self[i] end
    return function(_, k)
            local v
            k, v = next(keys, k)
            return k, v
        end, self, nil
end

local help_table
help_table = function(depth, value)
    local result = "{\n"
    for k,v in require("hs.fnutils").sortByKeys(value) do
        if not ({class = 1, objCType = 1, memberClass = 1})[k] then
            local displayValue = v
            if type(v) == "table" then
                displayValue = help_table(depth + 2, v)
            elseif type(v) == "string" then
                displayValue = "\"" .. v .. "\""
            end
            local displayKey = k
            if type(k) == "number" then
                displayKey = "[" .. tostring(k) .. "]"
            end
            result = result .. string.rep(" ", depth + 2) .. string.format("%s = %s,\n", tostring(displayKey), tostring(displayValue))
        end
    end
    result = result .. string.rep(" ", depth) .. "}"
    return result
end

--- hs._asm.canvas.help([attribute]) -> string
--- Function
--- Provides specification information for the recognized attributes, or the specific attribute specified.
---
--- Parameters:
---  * `attribute` - an optional string specifying an element attribute. If this argument is not provided, all attributes are listed.
---
--- Returns:
---  * a string containing some of the information provided by the [hs._asm.canvas.elementSpec](#elementSpec) in a manner that is easy to reference from the Hammerspoon console.
module.help = function(what)
    local help = module.elementSpec()
    if what and help[what] then what, help = nil, help[what] end
    if type(what) ~= "nil" then
        error("unrecognized argument `" .. tostring(what) .. "`", 2)
    end
    print(help_table(0, help))
end

--- hs._asm.canvas.percentages
--- Field
--- Canvas attributes which specify the location and size of canvas elements can be specified with an absolute position or as a percentage of the canvas size.
---
--- Percentages may be assigned to the following attributes:
---  * `frame`       - the frame used by the `rectangle`, `oval`, `ellipticalArc`, `text`, and `image` types.  The `x` and `w` fields will be a percentage of the canvas's width, and the `y` and `h` fields will be a percentage of the canvas's height.
---  * `center`      - the center point for the `circle` and `arc` types.  The `x` field will be a percentage of the canvas's width and the `y` field will be a percentage of the canvas's height.
---  * `radius`      - the radius for the `circle` and `arc` types.  The radius will be a percentage of the canvas's width.
---  * `coordinates` - the point coordinates used by the `segments` and `points` types.  X coordinates (fields `x`, `c1x`, and `c2x`) will be a percentage of the canvas's width, and Y coordinates (fields `y`, `c1y`, and `c2y`) will be a percentage of the canvas's height.
---
--- Percentages are assigned to these fields as a string.  If the number in the string ends with a percent sign (%), then the percentage is the whole number which precedes the percent sign.  If no percent sign is present, the percentage is expected in decimal format (e.g. "1.0" is the same as "100%").
---
--- Because a shadow applied to a canvas element is not considered as part of the element's bounds, you can also set the `padding` attribute to a positive number of points to inset the calculated values by from each edge of the canvas's frame so that the shadow will be fully visible within the canvas, even when an element is set to a width and height of "100%".

--- hs._asm.canvas.views
--- Field
--- A userdata object, potentially from another module, which can be displayed as an element within a Canvas.
---
--- The canvas element of type `view` is special in that it provides a placeholder for an appropriately generated view to be displayed as part of the canvas. This feature allows embedding the content of other modules within a canvas -- the canvas acts as its window.  The userdata object must conform to the following to be a valid candidate for this element type:
---  * it must be a subclass of the Objective-C class `NSView`.
---  * it must not be currently assigned to a visible (showing) window.
---
--- Notes:
---  * Views can only be covered by other views - they exist above the other non-view canvas elements in the owning canvas. If you need to "draw" on top of a `view` element, you will need to add a new canvas as an additional `view` element to the parent canvas.
---  * A view with it's own controls can only receive mouse events if the canvas can.  This requires that the canvas has a callback function defined, even though mouse events affecting the view are not handled by the canvas callback function. `canvasObject:mouseCallback(function() end)` is sufficient for this purpose if no other canvas element requires the callback function.

---
--- Candidate `view` objects:
---  * A canvas object, which is not currently being shown, conforms to these requirements, so it is possible to use this element type to embed a canvas within another canvas.
---  * `hs.webview` objects currently do not meet these requirements, but the necessary changes are currently under consideration.
---  * `hs.drawing` objects do not meet these requirements, but as this module is under consideration as a replacement for `hs.drawing`, this will likely not change.  See `hs._asm.canvas.drawing` for the status of a wrapper for replacing the `hs.drawing` module.
---  * An example of a "separate" module which can act as a valid object for this element type is being worked on as `hs._asm.canvas.avplayer`; updates will be added here as they occur.

-- Return Module Object --------------------------------------------------

return module
