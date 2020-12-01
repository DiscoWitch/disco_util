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
---@param x number
---@param y number
---@return GUIElement
function GUIElement:Create(x, y)
    local output = {x = x, y = y, enabled = true, options = {}}
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
---@param px number
---@param py number
function GUIElement:preRender(px, py)
    if not self.enabled then return end
    if self.id then self.root.used_ids[self.id] = true end
    self.true_x = self.x + px
    self.true_y = self.y + py
    self.true_z = self.parent.true_z + (self.z or -0.1)
    if self.tooltip then self.tooltip:preRender(self.true_x, self.true_y) end
end
function GUIElement:render() print_error("called virtual render function") end
function GUIElement:postRender()
    local gui = self.root.handle
    self.last_render_data = GetWidgetInfoPacked(gui)
    if self.last_render_data and self.last_render_data.hovered == 1 then
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

---@class GUIParent
local GUIParent = {}
setmetatable(GUIParent, {__index = GUIElement})
---@param x number
---@param y number
---@return GUIParent
function GUIParent:Create(x, y)
    local output = GUIElement:Create(x, y)
    output.children = {}
    return output
end
---@return table old_children
function GUIParent:clearChildren()
    local old_children = self.children
    self.children = {}
    return old_children
end
---@param px number
---@param py number
function GUIParent:preRender(px, py)
    if not self.enabled then return end
    GUIElement.preRender(self, px, py)
    if self.children then
        for k, v in ipairs(self.children) do v:preRender(self.true_x, self.true_y) end
    end
end
function GUIParent:render()
    if not self.enabled then return end
    for k, v in ipairs(self.children) do v:render() end
end
---@return AABB
function GUIParent:getAABB()
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

---@class Anchor
local Anchor = {}
setmetatable(Anchor, {__index = GUIParent})
Anchor.__index = Anchor
---@param x number
---@param y number
---@return Anchor
function GUIParent:Anchor(x, y)
    local output = GUIParent:Create(x, y)
    output.parent = self
    output.root = self.root
    setmetatable(output, Anchor)
    table.insert(self.children, output)
    return output
end

---@class DragContainer
local DragContainer = {}
setmetatable(DragContainer, {__index = GUIParent})
DragContainer.__index = DragContainer

---@param px number
---@param py number
function DragContainer:preRender(px, py)
    GUIParent.preRender(self, px, py)
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
end
---@param x number
---@param y number
---@param aabb AABB|nil
---@return DragContainer
function GUIParent:DragContainer(x, y, aabb)
    local output = GUIParent:Create()
    output.x = x
    output.y = y
    output.aabb = aabb
    output.parent = self
    output.root = self.root
    setmetatable(output, DragContainer)
    table.insert(self.children, output)
    return output
end

---@class AutoBox
local AutoBox = {}
setmetatable(AutoBox, {__index = GUIParent})
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
        GuiImageNinePiece(gui, id, aabb[1], aabb[3], aabb[2] - aabb[1], aabb[4] - aabb[3], alpha,
                          sprite, sprite_highlight)
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
function GUIParent:AutoBox(x, y, sprite, aabb, id)
    local output = GUIParent:Create(x, y)
    output.sprite = sprite
    output.aabb = aabb
    output.parent = self
    output.root = self.root
    setmetatable(output, AutoBox)
    table.insert(self.children, output)
    return output
end
---@class Text
local Text = {}
setmetatable(Text, {__index = GUIElement})
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
function GUIParent:Text(x, y, text)
    local output = GUIElement:Create(x, y)
    output.text = text or ""
    output.parent = self
    output.root = self.root
    setmetatable(output, Text)
    table.insert(self.children, output)
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
Button.__index = Button
function Button:render()
    if not self.enabled then return end
    GUIElement.applyModifiers(self)
    local id = self.id or self.root:autoID()
    local gui = self.root.handle
    local clicked, rclicked = GuiButton(gui, id, self.true_x, self.true_y, self.text)
    GUIElement.postRender(self)
    if clicked and self.on_click then self.on_click() end
    if rclicked and self.on_right_click then self.on_right_click() end
end
---@param x number
---@param y number
---@param text string|nil
---@param id integer|nil
---@return Button
function GUIParent:Button(x, y, text, id)
    local output = GUIElement:Create(x, y)
    output.text = text or ""
    output.id = id
    output.parent = self
    output.root = self.root
    setmetatable(output, Button)
    table.insert(self.children, output)
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
function GUIParent:Image(x, y, sprite, id)
    local output = GUIElement:Create(x, y)
    output.centered = true
    output.sprite = sprite
    output.id = id
    output.parent = self
    output.root = self.root
    setmetatable(output, Image)
    table.insert(self.children, output)
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
    if clicked and self.on_click then self.on_click() end
    if rclicked and self.on_right_click then self.on_right_click() end
end
---@param x number
---@param y number
---@param sprite string
---@param id integer|nil
---@return ImageButton
function GUIParent:ImageButton(x, y, sprite, id)
    local output = GUIElement:Create(x, y)
    output.centered = true
    output.text = ""
    output.sprite = sprite
    output.id = id
    output.parent = self
    output.root = self.root
    setmetatable(output, ImageButton)
    table.insert(self.children, output)
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
setmetatable(Tooltip, {__index = GUIParent})
Tooltip.__index = Tooltip
-- function Tooltip:render() if not self.enabled then return end end
---@return Tooltip
function GUIElement:Tooltip(x, y)
    x = x or 20
    y = y or 0
    local output = GUIParent:Create(x, y)
    output.parent = self
    output.root = self.root
    setmetatable(output, Tooltip)
    self.tooltip = output
    return output
end

---@class GUI
local GUI = {}
setmetatable(GUI, {__index = GUIParent})
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
        for k, v in ipairs(self.children) do v:preRender(0, 0) end
        for k, v in ipairs(self.children) do v:render() end
    end)
    if not status then
        print("error while rendering")
        print_error(tostring(err))
    end
end

return GUI
