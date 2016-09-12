
--- === hs._asm.enclosure.toolbar ===
---
--- Create and manipulate toolbars which can be attached to the Hammerspoon console or hs._asm.enclosure objects.
---
--- Toolbars are attached to titled windows and provide buttons which can be used to perform various actions within the application. Hammerspoon can use this module to add toolbars to the console or `hs._asm.enclosure` objects which have a title bar (see `hs._asm.enclosure.windowMasks` and `hs._asm.enclosure:windowStyle`). Toolbars are identified by a unique identifier which is used by OS X to identify information which can be auto saved in the application's user defaults to reflect changes the user has made to the toolbar button order or active button list (this requires setting [hs._asm.enclosure.toolbar:autosaves](#autosaves) and [hs._asm.enclosure.toolbar:canCustomize](#canCustomize) both to true).
---
--- Multiple copies of the same toolbar can be made with the [hs._asm.enclosure.toolbar:copy](#copy) method so that multiple enclosure windows use the same toolbar, for example. If the user customizes a copied toolbar, changes to the active buttons or their order will be reflected in all copies of the toolbar.
---
--- Example:
--- ~~~lua
--- t = require("hs._asm.enclosure.toolbar")
--- a = t.new("myConsole", {
---         { id = "select1", selectable = true, image = hs.image.imageFromName("NSStatusAvailable") },
---         { id = "NSToolbarSpaceItem" },
---         { id = "select2", selectable = true, image = hs.image.imageFromName("NSStatusUnavailable") },
---         { id = "notShown", default = false, image = hs.image.imageFromName("NSBonjour") },
---         { id = "NSToolbarFlexibleSpaceItem" },
---         { id = "navGroup", label = "Navigation", groupMembers = { "navLeft", "navRight" }},
---         { id = "navLeft", image = hs.image.imageFromName("NSGoLeftTemplate"), allowedAlone = false },
---         { id = "navRight", image = hs.image.imageFromName("NSGoRightTemplate"), allowedAlone = false },
---         { id = "NSToolbarFlexibleSpaceItem" },
---         { id = "cust", label = "customize", fn = function(t, w, i) t:customizePanel() end, image = hs.image.imageFromName("NSAdvanced") }
---     }):canCustomize(true)
---       :autosaves(true)
---       :selectedItem("select2")
---       :setCallback(function(...)
---                         print("a", inspect(table.pack(...)))
---                    end)
---
--- t.attachToolbar(a)
--- ~~~
---
--- Note: This module is supported in OS X versions prior to 10.10 (for the Hammerspoon console only), even though its parent `hs._asm.enclosure` is not. To load this module directly, use `require("hs._asm.enclosure.toolbar")` instead of relying on module auto-loading.

local USERDATA_TAG = "hs._asm.enclosure.toolbar"
local module       = require(USERDATA_TAG..".internal")
local toolbarMT    = hs.getObjectMetatable(USERDATA_TAG)

-- required for image support
require("hs.image")

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

module.systemToolbarItems = _makeConstantsTable(module.systemToolbarItems)
module.itemPriorities     = _makeConstantsTable(module.itemPriorities)


--- hs._asm.enclosure.toolbar:addItems(toolbarTable) -> toolbarObject
--- Method
--- Add one or more toolbar items to the toolbar
---
--- Paramters:
---  * `toolbarTable` - a table describing a single toolbar item, or an array of tables, each describing a separate toolbar item, to be added to the toolbar.
---
--- Returns:
---  * the toolbarObject
---
--- Notes:
--- * Each toolbar item is defined as a table of key-value pairs.  The following list describes the valid keys used when describing a toolbar item for this method, the constructor [hs._asm.enclosure.toolbar.new](#new), and the [hs._asm.enclosure.toolbar:modifyItem](#modifyItem) method.  Note that the `id` field is **required** for all three uses.
---   * `id`           - A unique string identifier required for each toolbar item and group.  This key cannot be changed after an item has been created.
---   * `allowedAlone` - a boolean value, default true, specifying whether or not the toolbar item can be added to the toolbar, programmatically or through the customization panel, (true) or whether it can only be added as a member of a group (false).
---   * `default`      - a boolean value, default matching the value of `allowedAlone` for this item, indicating whether or not this toolbar item or group should be displayed in the toolbar by default, unless overridden by user customization or a saved configuration (when such options are enabled).
---   * `enable`       - a boolean value, default true, indicating whether or not the toolbar item is active (and can be clicked on) or inactive and greyed out.  This field is ignored when applied to a toolbar group; apply it to the group members instead.
---   * `fn`           - a callback function, or false to remove, specific to the toolbar item. This property is ignored if assigned to the button group. This function will override the toolbar callback defined with [hs._asm.enclosure.toolbar:setCallback](#setCallback) for this specific item. The function should expect three (four, if the item is a `searchfield`) arguments and return none.  See [hs._asm.enclosure.toolbar:setCallback](#setCallback) for information about the callback's arguments.
---   * `groupMembers` - an array (table) of strings specifying the toolbar item ids that are members of this toolbar item group.  If set to false, this field is removed and the item is reset back to being a regular toolbar item.  Note that you cannot change a currently visible toolbar item to or from being a group; it must first be removed from active toolbar with [hs._asm.enclosure.toolbar:removeItem](#removeItem).
---   * `image`        - an `hs.image` object, or false to remove, specifying the image to use as the toolbar item's icon when icon's are displayed in the toolbar or customization panel. This key is ignored for a toolbar item group, but not for it's individual members.
---   * `label`        - a string label, or false to remove, for the toolbar item or group when text is displayed in the toolbar or in the customization panel. For a toolbar item, the default is the `id` string; for a group, the default is `false`. If a group has a label assigned to it, the group label will be displayed for the group of items it contains. If a group does not have a label, the individual items which make up the group will each display their individual labels.
---   * `priority`     - an integer value used to determine toolbar item order and which items are displayed or put into the overflow menu when the number of items in the toolbar exceed the width of the window in which the toolbar is attached. Some example values are provided in the [hs._asm.enclosure.toolbar.itemPriorities](#itemPriorities) table. If a toolbar item is in a group, it's priority is ignored and the item group is ordered by the item group's priority.
---   * `searchfield`  - a boolean (default false) specifying whether or not this toolbar item is a search field. If true, the following additional keys are allowed:
---     * `searchHistory`             - an array (table) of strings, specifying previous searches to automatically include in the search field menu, if `searchPredefinedMenuTitle` is not false
---     * `searchHistoryAutosaveName` - a string specifying the key name to save search history with in the application deafults (accessible through `hs.settings`). If this value is set, search history will be maintained through restarts of Hammerspoon.
---     * `searchHistoryLimit`        - the maximum number of items to store in the search field history.
---     * `searchPredefinedMenuTitle` - a string or boolean specifying how a predefined list of search field "response" should be included in the search field menu. If this item is `true`, this list of items specified for `searchPredefinedSearches` will be displayed in a submenu with the title "Predefined Searches". If this item is a string, the list of items will be displayed in a submenu with the title specified by this string value. If this item is `false`, then the search field menu will only contain the items specified in `searchPredefinedSearches` and no search history will be included in the menu.
---     * `searchPredefinedSearches`  - an array (table) of strings specifying the items to be listed in the predefined search submenu. If set to false, any existing menu will be removed and the search field menu will be reset to the default.
---     * `searchText`                - a string specifying the text to display in the search field.
---     * `searchWidth`               - the width of the search field text entry box.
---   * `selectable`   - a boolean value, default false, indicating whether or not this toolbar item is selectable (i.e. highlights, like a selected tab) when clicked on. Only one selectable toolbar item can be highlighted at a time, and you can get or set/reset the selected item with [hs._asm.enclosure.toolbar:selectedItem](#selectedItem).
---   * `tag`          - an integer value which can be used for own purposes; has no affect on the visual aspect of the item or its behavior.
---   * `tooltip`      - a string label, or false to remove, which is displayed as a tool tip when the user hovers the mouse over the button or button group. If a button is in a group, it's tooltip is ignored in favor of the group tooltip.
toolbarMT.addItems = function(self, ...)
    local args = table.pack(...)
    if args.n == 1 then
        if #args[1] > 1 then -- it's already a table of tables
            args = args[1]
        end
    end
    args.n = nil
    return self:_addItems(args)
end

--- hs._asm.enclosure.toolbar:removeItem(index | identifier) -> toolbarObject
--- Method
--- Remove the toolbar item at the index position specified, or with the specified identifier, if currently present in the toolbar.
---
--- Parameters:
---  * `index` - the numerical position of the toolbar item to remove.
---      or
---  * `identifier` - the identifier of the toolbar item to remove, if currently active in the toolbar
---
--- Returns:
---  * the toolbar object
---
--- Notes:
---  * the toolbar position must be between 1 and the number of currently active toolbar items.
toolbarMT.removeItem = function(self, item)
    if type(item) == "string" then
        local found = false
        for i, v in ipairs(self:items()) do
            if v == item then
                item  = i
                found = true
                break
            end
        end
        if not found then return self end
    end
    return self:_removeItemAtIndex(item)
end

-- Return Module Object --------------------------------------------------

return module
