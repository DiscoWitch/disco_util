dofile_once("data/scripts/lib/utilities.lua")
dofile_once("mods/azoth/files/lib/disco_util/disco_util.lua")

---@class AABB

---@param aabb AABB
---@param x number
---@param y number
---@return boolean
local function isInAABB(aabb, x, y)
    return x > aabb[1] and x < aabb[2] and y > aabb[3] and y < aabb[4]
end
---@param aabb AABB
---@param x number
---@param y number
---@return AABB
local function offsetAABB(aabb, x, y) return {aabb[1] + x, aabb[2] + x, aabb[3] + y, aabb[4] + y} end

local function GetWidgetInfoPacked(gui)
    local data = {}
    data.clicked, data.right_clicked, data.hovered, data.x, data.y, data.width, data.height, data.draw_x, data.draw_y, data.draw_width, data.draw_height =
        GuiGetPreviousWidgetInfo(gui)
    return data
end

---@class GUIElement
local GUIElement = {}
GUIElement.__tostring = function(self) return "GUIElement" end
GUIElement.__index = GUIElement
---@param x number
---@param y number
---@return GUIElement
function GUIElement:Create(x, y)
    local output = {x = x, y = y, enabled = true, data = {}, options = {}}
    output.options[GUI_OPTION.NoPositionTween] = true
    return output
end
function GUIElement:applyModifiers()
    local gui = self.root.handle
    if self.color then
        GuiColorSetForNextWidget(gui, self.color.r, self.color.g, self.color.b, self.color.a)
    end
    if self.options then
        for k, v in pairs(self.options) do if v then GuiOptionsAddForNextWidget(gui, k) end end
    end
    if self.true_z then GuiZSetForNextWidget(gui, self.true_z) end
end
function GUIElement:_update() if self.update then self:update() end end
---@param px number
---@param py number
function GUIElement:updatePosition(px, py, pz)
    if not self.enabled then return end
    if self.id then self.root.used_ids[self.id] = true end
    self.true_x = self.x + px
    self.true_y = self.y + py
    self.true_z = pz + (self.z or -0.1)
    if self.tooltip then self.tooltip:updatePosition(self.true_x, self.true_y, self.true_z) end
end
function GUIElement:render() print_error("called virtual render function") end
function GUIElement:postRender()
    local gui = self.root.handle
    self.last_render_data = GetWidgetInfoPacked(gui)
    if self.last_render_data and self.last_render_data.hovered then
        if self.tooltip then self.tooltip:render() end
    end
end

---@return AABB
function GUIElement:getAABB()
    if not self.enabled then return nil end
    local data = self.last_render_data
    return data and {
        data.x - self.true_x,
        data.x + data.width - self.true_x,
        data.y - self.true_y,
        data.y + data.height - self.true_y
    }
end

---@class GUIContainer
local GUIContainer = {}
setmetatable(GUIContainer, {__index = GUIElement})
---@param x number
---@param y number
---@return GUIContainer
function GUIContainer:Create(x, y)
    local output = GUIElement:Create(x, y)
    output.children = {}
    return output
end
function GUIContainer:addChild(child) table.insert(self.children, child) end
---@return table old_children
function GUIContainer:clearChildren()
    local old_children = self.children
    self.children = {}
    return old_children
end
function GUIContainer:_update()
    if self.update then self:update() end
    if self.children then for k, v in ipairs(self.children) do v:_update() end end
end

---@param px number
---@param py number
function GUIContainer:updatePosition(px, py, pz)
    if not self.enabled then return end
    GUIElement.updatePosition(self, px, py, pz)
    if self.children then
        for k, v in ipairs(self.children) do
            v:updatePosition(self.true_x, self.true_y, self.true_z)
        end
    end
end
function GUIContainer:render()
    if not self.enabled then return end
    for k, v in ipairs(self.children) do v:render() end
end
---@return AABB
function GUIContainer:getAABB()
    if not self.enabled then return nil end
    local aabb = nil
    for k, v in ipairs(self.children) do
        local child_aabb = v:getAABB()
        if child_aabb then
            if not aabb then
                aabb = child_aabb
            else
                -- Expand x bounds
                if child_aabb[1] < aabb[1] then aabb[1] = child_aabb[1] end
                if child_aabb[2] > aabb[2] then aabb[2] = child_aabb[2] end
                -- Expand y bounds
                if child_aabb[3] < aabb[3] then aabb[3] = child_aabb[3] end
                if child_aabb[4] > aabb[4] then aabb[4] = child_aabb[4] end
            end
        end
    end
    return aabb
end

GUIContainer.__tostring = function(self)
    local str = "GUIContainer with children:"
    for k, v in ipairs(self.children) do str = str .. "\n - " .. tostring(v) end
    return str
end
GUIContainer.__index = GUIContainer
---@param x number
---@param y number
---@return GUIContainer
function GUIContainer:GUIContainer(x, y)
    local output = GUIContainer:Create(x, y)
    output.parent = self
    output.root = self.root
    setmetatable(output, GUIContainer)
    self:addChild(output)
    return output
end

---@class DragContainer
local DragContainer = {}
setmetatable(DragContainer, {__index = GUIContainer})
DragContainer.__tostring = function(self)
    local str = "DragContainer with children:"
    for k, v in ipairs(self.children) do str = str .. "\n - " .. tostring(v) end
    return str
end
DragContainer.__index = DragContainer

---@param px number
---@param py number
function DragContainer:updatePosition(px, py, pz)
    GUIContainer.updatePosition(self, px, py, pz)
    local mpos = self.root:GetMousePos()
    local aabb = self.aabb
    if aabb then
        aabb = offsetAABB(aabb, self.true_x, self.true_y)
    else
        aabb = self:getAABB()
    end
    if not self.root.drag_handle ~= self and aabb and isInAABB(aabb, mpos.x, mpos.y) then
        if self.root.player.ControlsComponent.mButtonFrameFire == self.root.cur_frame then
            self.root.drag_handle = self
            self.drag_offset = {x = self.x - mpos.x, y = self.y - mpos.y}
        end
    end
    -- Stop dragging when mouse is released
    if not self.root.player.ControlsComponent.mButtonDownFire then self.root.drag_handle = nil end
    if self.root.drag_handle == self then
        self.x = mpos.x + self.drag_offset.x
        self.y = mpos.y + self.drag_offset.y
    end
    GUIContainer.updatePosition(self, px, py, pz)
end
---@param x number
---@param y number
---@param aabb AABB|nil
---@return DragContainer
function GUIContainer:DragContainer(x, y, aabb)
    local output = GUIContainer:Create()
    output.x = x
    output.y = y
    output.aabb = aabb
    output.parent = self
    output.root = self.root
    setmetatable(output, DragContainer)
    self:addChild(output)
    return output
end

---@class AutoBox
local AutoBox = {}
setmetatable(AutoBox, {__index = GUIContainer})
AutoBox.__tostring = function(self)
    local str = "AutoBox with children:"
    for k, v in ipairs(self.children) do str = str .. "\n - " .. tostring(v) end
    return str
end
AutoBox.__index = AutoBox
function AutoBox:render()
    if not self.enabled then return end
    local gui = self.root.handle
    local id = self.id or self.root:autoID()
    local alpha = self.alpha or 1
    local sprite = self.sprite or "data/ui_gfx/decorations/9piece0_gray.png"
    local sprite_highlight = self.sprite_highlight or sprite
    local aabb = self.aabb
    if aabb then
        aabb = offsetAABB(aabb, self.true_x, self.true_y)
    else
        aabb = self:getAABB()
    end
    if aabb then
        self:applyModifiers()
        local left = aabb[1] - self.margins[1]
        local top = aabb[3] - self.margins[3]
        local width = aabb[2] + self.margins[2] - left
        local height = aabb[4] + self.margins[4] - top
        GuiImageNinePiece(gui, id, left, top, width, height, alpha, sprite, sprite_highlight)
        self:postRender()
    end
    for _, v in ipairs(self.children) do v:render() end
end
---@param x number
---@param y number
---@param sprite string
---@param aabb AABB|nil
---@param id integer|nil
---@return AutoBox
function GUIContainer:AutoBox(x, y, sprite, aabb, id)
    local output = GUIContainer:Create(x, y)
    output.sprite = sprite
    output.aabb = aabb
    output.margins = {0, 0, 0, 0}
    output.parent = self
    output.root = self.root
    setmetatable(output, AutoBox)
    self:addChild(output)
    return output
end

---@class GridBox
local GridBox = {}
setmetatable(GridBox, {__index = GUIContainer})
GridBox.__tostring = function(self)
    local str = "GridBox with children:"
    for k, v in ipairs(self.children) do str = str .. "\n - " .. tostring(v) end
    return str
end
GridBox.__index = GridBox
---@param px number
---@param py number
function GridBox:updatePosition(px, py, pz)
    if not self.enabled then return end
    GUIElement.updatePosition(self, px, py, pz)
    if self.children then
        local edge_x = self.true_x
        local edge_y = self.true_y
        local sep_x = self.separation_x or 0
        local sep_y = self.separation_y or 0
        if self.vertical then
            local col_width = 0
            for k, v in ipairs(self.children) do
                if v.enabled then
                    v:updatePosition(edge_x, edge_y, self.true_z)
                    local aabb = v:getAABB() or {0, 0, 0, 0}
                    local width = aabb[2] - aabb[1]
                    local height = aabb[4] - aabb[3]
                    edge_y = edge_y + height + sep_y
                    if self.max_length and edge_y - self.true_y > self.max_length then
                        edge_y = self.true_y
                        edge_x = edge_x + col_width + sep_x
                        col_width = 0
                        v:updatePosition(edge_x, edge_y, self.true_z)
                        edge_y = self.true_y + height + sep_y
                    end
                    if width > col_width then col_width = width end
                end
            end
        else
            local row_height = 0
            for k, v in ipairs(self.children) do
                if v.enabled then
                    v:updatePosition(edge_x, edge_y, self.true_z)
                    local aabb = v:getAABB() or {0, 0, 0, 0}
                    local width = aabb[2] - aabb[1]
                    local height = aabb[4] - aabb[3]
                    edge_x = edge_x + width + sep_x
                    if self.max_length and edge_x - self.true_x > self.max_length + 1 then
                        edge_x = self.true_x
                        edge_y = edge_y + row_height + sep_y
                        row_height = 0
                        v:updatePosition(edge_x, edge_y, self.true_z)
                        edge_x = self.true_x + width + sep_x
                    end
                    if height > row_height then row_height = height end
                end
            end
        end
    end
end
---@param x number
---@param y number
---@param vertical boolean
---@param max_length number|nil
---@param separation_x number|nil
---@param separation_y number|nil
---@return GridBox
function GUIContainer:GridBox(x, y, vertical, max_length, separation_x, separation_y)
    local output = GUIContainer:Create(x, y)
    output.max_length = max_length
    output.separation_x = separation_x
    output.separation_y = separation_y
    output.vertical = vertical
    output.parent = self
    output.root = self.root
    setmetatable(output, GridBox)
    self:addChild(output)
    return output
end

---@class Alias
local Alias = {}
setmetatable(Alias, {__index = GUIElement})
Alias.__tostring = function(self) return "Alias: " .. tostring(self.original) end
Alias.__index = function(self, key)
    if self.original[key] then
        return self.original[key]
    else
        return Alias[key]
    end
end
function Alias:render()
    -- render as original
end
---@return AABB
function Alias:getAABB()
    -- Get original's bounding box
end
function Alias.Create(x, y, original, parent, instance_index)
    local output = GUIElement:Create(x, y)
    output.options = nil
    output.original = original
    output.instance_index = instance_index
    if original.children then
        output.children = {}
        for k, v in ipairs(original.children) do
            local clone = Alias.Create(v.x, v.y, v, output, instance_index)
            table.insert(output.children, clone)
        end
    end
    output.parent = parent
    output.root = parent.root
    setmetatable(output, Alias)
    return output
end
---@param x number
---@param y number
---@param original GUIElement
---@return Alias
function GUIContainer:Alias(x, y, original)
    local output = Alias:Create(x, y, original, self)
    self:addChild(output)
    return output
end

---@class GridBoxInstanced
local GridBoxInstanced = {}
setmetatable(GridBoxInstanced, {__index = GridBox})
GridBoxInstanced.__tostring = function(self)
    local str = "GridBox with instanced children:"
    for k, v in ipairs(self.children) do str = str .. "\n - " .. tostring(v) end
    return str
end
GridBoxInstanced.__index = function(self, key)
    if key == "children" then
        -- Do instancing logic
        if self.count ~= self.real_count or self.update_children then
            -- Update instances
            self.children_instanced = {}
            for i = 1, self.count do
                for k, v in ipairs(self._children) do
                    local clone = Alias.Create(0, 0, v, self, i)
                    table.insert(self.children_instanced, clone)
                end
            end
            self.real_count = self.count
            self.update_children = false
        end
        return self.children_instanced
    end
    return GridBoxInstanced[key]
end
---@return table children
function GridBoxInstanced:clearChildren()
    local old_children = self._children
    self._children = {}
    return old_children
end
---@param child GUIElement
function GridBoxInstanced:addChild(child)
    table.insert(self._children, child)
    self.update_children = true
end

---@param x number
---@param y number
---@param count number
---@param vertical boolean|nil
---@param max_length number|nil
---@return GridBox
function GUIContainer:GridBoxInstanced(x, y, count, vertical, max_length)
    local output = GUIContainer:Create(x, y)
    output._children = {}
    output.children = nil
    self.update_children = true
    output.max_length = max_length
    output.count = count
    output.vertical = vertical or false
    output.parent = self
    output.root = self.root
    setmetatable(output, GridBoxInstanced)
    self:addChild(output)
    return output
end

---@class Text
local Text = {}
setmetatable(Text, {__index = GUIElement})
Text.__tostring = function(self) return "Text: " .. self.text end
Text.__index = Text
function Text:render()
    if not self.enabled then return end
    GUIElement.applyModifiers(self)
    local gui = self.root.handle
    GuiText(gui, self.true_x, self.true_y, self.text)
    GUIElement.postRender(self)
end
---@param x number
---@param y number
---@param text string
---@return Text
function GUIContainer:Text(x, y, text)
    local output = GUIElement:Create(x, y)
    output.text = text or ""
    output.parent = self
    output.root = self.root
    setmetatable(output, Text)
    self:addChild(output)
    return output
end
---@return AABB
function Text:getAABB()
    if not self.enabled then return nil end
    local w, h = GuiGetTextDimensions(self.root.handle, self.text, 1, 2)
    local x = self.true_x
    local y = self.true_y
    if self.centered then
        x = x - w / 2
        y = y - h / 2
    end
    return {x, x + w, y, y + h}
end

---@class Button
local Button = {}
setmetatable(Button, {__index = GUIElement})
Button.__tostring = function(self) return "Button: " .. self.text end
Button.__index = Button
function Button:render()
    if not self.enabled then return end
    GUIElement.applyModifiers(self)
    local id = self.id or self.root:autoID()
    local gui = self.root.handle
    local clicked, rclicked = GuiButton(gui, id, self.true_x, self.true_y, self.text)
    GUIElement.postRender(self)
    if clicked and self.on_click then self:on_click() end
    if rclicked and self.on_right_click then self:on_right_click() end
end
---@param x number
---@param y number
---@param text string|nil
---@param id integer|nil
---@return Button
function GUIContainer:Button(x, y, text, id)
    local output = GUIElement:Create(x, y)
    output.text = text or ""
    output.id = id
    output.parent = self
    output.root = self.root
    setmetatable(output, Button)
    self:addChild(output)
    return output
end
---@return AABB
function Button:getAABB()
    if not self.enabled then return nil end
    local w, h = GuiGetTextDimensions(self.root.handle, self.text, 1, 2)
    local x = self.true_x
    local y = self.true_y
    if self.centered then
        x = x - w / 2
        y = y - h / 2
    end
    return {x, x + w, y, y + h}
end

---@class Image
local Image = {}
setmetatable(Image, {__index = GUIElement})
Image.__tostring = function(self) return "Image: " .. self.sprite end
Image.__index = Image
function Image:render()
    if not self.enabled then return end
    GUIElement.applyModifiers(self)
    local gui = self.root.handle
    local id = self.id or self.root:autoID()
    local alpha = self.alpha or 1
    local scale = self.scale or 1
    local rotation = self.rotation or 0
    local x = self.true_x
    local y = self.true_y
    if self.centered then
        local w, h = GuiGetImageDimensions(gui, self.sprite, scale)
        x = x - w / 2
        y = y - h / 2
    end
    GuiImage(gui, id, x, y, self.sprite, alpha, scale, rotation)
    GUIElement.postRender(self)
end
---@param x number
---@param y number
---@param sprite string|nil
---@param id integer|nil
---@return Image
function GUIContainer:Image(x, y, sprite, id)
    local output = GUIElement:Create(x, y)
    output.centered = true
    output.sprite = sprite
    output.id = id
    output.parent = self
    output.root = self.root
    setmetatable(output, Image)
    self:addChild(output)
    return output
end
---@return AABB
function Image:getAABB()
    if not self.enabled then return nil end
    local w, h = GuiGetImageDimensions(self.root.handle, self.sprite, self.scale or 1)
    local x = self.true_x
    local y = self.true_y
    if self.centered then
        x = x - w / 2
        y = y - h / 2
    end
    return {x, x + w, y, y + h}
end

---@class ImageButton
local ImageButton = {}
setmetatable(ImageButton, {__index = GUIElement})
ImageButton.__tostring = function(self) return "ImageButton: " .. self.sprite end
ImageButton.__index = ImageButton
function ImageButton:render()
    if not self.enabled then return end
    GUIElement.applyModifiers(self)
    local id = self.id or self.root:autoID()
    local gui = self.root.handle
    local x = self.true_x
    local y = self.true_y
    if self.centered then
        local w, h = GuiGetImageDimensions(gui, self.sprite, 1)
        x = x - w / 2
        y = y - h / 2
    end
    local clicked, rclicked = GuiImageButton(gui, id, x, y, self.text, self.sprite)
    GUIElement.postRender(self)
    if clicked and self.on_click then self:on_click() end
    if rclicked and self.on_right_click then self:on_right_click() end
end
---@param x number
---@param y number
---@param sprite string
---@param id integer|nil
---@return ImageButton
function GUIContainer:ImageButton(x, y, sprite, id)
    local output = GUIElement:Create(x, y)
    output.centered = true
    output.text = ""
    output.sprite = sprite
    output.id = id
    output.parent = self
    output.root = self.root
    setmetatable(output, ImageButton)
    self:addChild(output)
    return output
end
function ImageButton:getAABB()
    if not self.enabled then return nil end
    local w, h = GuiGetImageDimensions(self.root.handle, self.sprite, 1)
    local x = self.true_x
    local y = self.true_y
    if self.centered then
        x = x - w / 2
        y = y - h / 2
    end
    return {x, x + w, y, y + h}
end

---@class Tooltip
local Tooltip = {}
setmetatable(Tooltip, {__index = GUIContainer})
Tooltip.__tostring = function(self)
    local str = "Tooltip with children:"
    for k, v in ipairs(self.children) do str = str .. "\n - " .. tostring(v) end
    return str
end
Tooltip.__index = Tooltip
-- function Tooltip:render() if not self.enabled then return end end
---@return Tooltip
function GUIElement:Tooltip(x, y)
    x = x or 20
    y = y or 0
    local output = GUIContainer:Create(x, y)
    output.parent = self
    output.root = self.root
    setmetatable(output, Tooltip)
    self.tooltip = output
    return output
end

---@class GUI
local GUI = {}
setmetatable(GUI, {__index = GUIContainer})
GUI.__tostring = function(self) return "GUI Root" end
GUI.__index = GUI

---@return number ID
function GUI:autoID()
    local id = self.id_counter
    while self.used_ids[id] do id = id + 1 end
    self.used_ids[id] = true
    self.id_counter = id + 1
    return id
end
---@return GUI
function GUI.Create()
    local output = {}
    output.root = output
    output.handle = GuiCreate()
    output.z = 0
    output.children = {}
    setmetatable(output, GUI)
    return output
end
---@return vector2
function GUI:GetMousePos()
    local screen_w, screen_h = GuiGetScreenDimensions(self.handle)
    local cx, cy = GameGetCameraPos()
    local vx = MagicNumbersGetValue("VIRTUAL_RESOLUTION_X")
    local vy = MagicNumbersGetValue("VIRTUAL_RESOLUTION_Y")
    local mpos = self.player.ControlsComponent.mMousePosition
    mpos.x = (mpos.x - cx) * screen_w / vx + screen_w / 2
    mpos.y = (mpos.y - cy) * screen_h / vy + screen_h / 2
    return mpos
end
function GUI:render()
    self.used_ids = {}
    self.id_counter = 1
    self.cur_frame = GameGetFrameNum()
    local status, err = pcall(function()
        GuiStartFrame(self.handle)
        self.true_z = self.z
        for k, v in ipairs(self.children) do v:_update() end
        for k, v in ipairs(self.children) do v:updatePosition(0, 0, 0) end
        for k, v in ipairs(self.children) do v:render() end
    end)
    if not status then
        print_error("error while rendering")
        print_error(tostring(err))
    end
end

return GUI
