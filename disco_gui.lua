dofile_once("data/scripts/lib/utilities.lua")

---Order is left, right, top, bottom
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
function GUIElement:ForceUpdate()
    -- Virtual function for making entities refresh their cached properties
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
function GUIElement:_on_click()
    if self.root.click_disabled then return end
    if self.on_click then table.insert(self.root.callbacks, {self = self, func = self.on_click}) end
end
function GUIElement:_on_right_click()
    if self.on_right_click then
        table.insert(self.root.callbacks, {self = self, func = self.on_right_click})
    end
end
function GUIElement:_on_hover_start()
    if self.on_hover_start then
        table.insert(self.root.callbacks, {self = self, func = self.on_hover_start})
    end
end
function GUIElement:_on_hover()
    local parent = self.parent
    while parent.children and parent ~= self.root do
        parent.child_hovered = true
        parent = parent.parent
    end
    if self.on_hover then table.insert(self.root.callbacks, {self = self, func = self.on_hover}) end
end
function GUIElement:_on_hover_end()
    if self.on_hover_end then
        table.insert(self.root.callbacks, {self = self, func = self.on_hover_end})
    end
end
function GUIElement:_on_drag_start()
    if self.on_drag_start then
        table.insert(self.root.callbacks, {self = self, func = self.on_drag_start})
    end
end
function GUIElement:_on_drag()
    if self.on_drag then table.insert(self.root.callbacks, {self = self, func = self.on_drag}) end
end
function GUIElement:_on_drag_end()
    if self.on_drag_end then
        table.insert(self.root.callbacks, {self = self, func = self.on_drag_end})
    end
    self.root.click_disabled = true
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
    self.culled =
        self.root.cull_aabb and not isInAABB(self.root.cull_aabb, self.true_x, self.true_y)
    self:compute_aabb()
end
function GUIElement:render() print_error("called virtual render function") end
function GUIElement:postRender()
    local gui = self.root.handle
    local prev_data = self.last_render_data
    self.last_render_data = GetWidgetInfoPacked(gui)
    local data = self.last_render_data
    local mpos = self.root:GetMouse()
    if self.root.cull_aabb and not isInAABB(self.root.cull_aabb, mpos.x, mpos.y) then
        if data then
            data.clicked = false
            data.right_clicked = false
            data.hovered = false
        end
    end
    if data and data.clicked then self:_on_click() end
    if data and data.right_clicked then self:_on_right_click() end
    if data and data.hovered then
        table.insert(self.root.hovered, self)
        if prev_data and not prev_data.hovered then self:_on_hover_start() end
        self:_on_hover()
        if self.tooltip then
            self.root.tooltip = {entity = self.tooltip, x = data.x, y = data.y}
        end
    elseif prev_data and prev_data.hovered then
        self:_on_hover_end()
    end
end

function GUIElement:compute_aabb()
    -- Virtual function
end
---@return AABB
function GUIElement:getAABB() return self._aabb end

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
    GUIElement._update(self)
    if self.children then for _, v in ipairs(self.children) do v:_update() end end
end

---@param px number
---@param py number
function GUIContainer:updatePosition(px, py, pz)
    if not self.enabled then return end
    GUIElement.updatePosition(self, px, py, pz)
    if self.children then
        for _, v in ipairs(self.children) do
            v:updatePosition(self.true_x, self.true_y, self.true_z)
        end
    end
end
function GUIContainer:render()
    self.child_hovered = false
    if (self.culled and not self.no_cull) or not self.enabled then return end
    if self.children then for _, v in ipairs(self.children) do v:render() end end
end
---@return AABB
function GUIContainer:getAABB()
    if not self.enabled then return nil end
    local aabb = nil
    for _, v in ipairs(self.children) do
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
    for _, v in ipairs(self.children) do str = str .. "\n - " .. tostring(v) end
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

---@class ScrollContainer
local ScrollContainer = {}
setmetatable(ScrollContainer, {__index = GUIContainer})
ScrollContainer.__tostring = function(self)
    local str = "ScrollContainer with children:"
    for _, v in ipairs(self.children) do str = str .. "\n - " .. tostring(v) end
    return str
end
ScrollContainer.__index = ScrollContainer
ScrollContainer.is_scroll_container = true
---@param px number
---@param py number
function ScrollContainer:updatePosition(px, py, pz)
    if not self.enabled then return end
    GUIElement.updatePosition(self, px, py, pz)
    if self.children then
        -- Set a culling AABB and don't bother rendering things outside it
        local temp = self.root.cull_aabb
        self.root.cull_aabb = self.cull_aabb
        for _, v in ipairs(self.children) do
            v:updatePosition(-self.aabb[1], -self.aabb[3], self.true_z)
        end
        self.root.cull_aabb = temp
    end
end
function ScrollContainer:render()
    if not self.enabled then return end
    local gui = self.root.handle
    local id = self.id or self.root:autoID()
    local left = self.true_x + self.aabb[1]
    local width = self.aabb[2] - self.aabb[1]
    local top = self.true_y + self.aabb[3]
    local height = self.aabb[4] - self.aabb[3]
    local focusable = self.focusable or true
    local margin_x = self.margin_x or 2
    local margin_y = self.margin_y or 2
    GuiBeginScrollContainer(gui, id, left, top, width, height, focusable, margin_x, margin_y)
    -- Draw an invisible button at 0,0 to use as a reference for the scroll bar
    GuiButton(gui, self.root:autoID(), 0, 0, "")
    local data = GetWidgetInfoPacked(gui)
    -- Set an offset to the mouse position for 
    self.scroll_offset = {x = left + margin_x - data.x, y = top + margin_y - data.y}
    local cull_margin = self.cull_margin or 0
    -- Set a culling box with margins for drawing children on the next frame    
    self.cull_aabb = {
        self.scroll_offset.x + cull_margin.x,
        self.scroll_offset.x + width - cull_margin.x,
        self.scroll_offset.y + cull_margin.y,
        self.scroll_offset.y + height - cull_margin.y
    }
    -- Set an exact screenspace cull box without margins for mouse detection right now
    local temp_cull_aabb = self.root.cull_aabb
    self.root.cull_aabb = {left, left + width, top, top + height}
    for _, v in ipairs(self.children) do v:render() end
    self.root.cull_aabb = temp_cull_aabb
    -- Draw another button at the bottom right corner to force a constant size
    local inside_aabb = GUIContainer.getAABB(self)
    if inside_aabb then GuiButton(gui, self.root:autoID(), inside_aabb[2], inside_aabb[4], "") end
    GuiEndScrollContainer(gui)
end
---@return AABB
function ScrollContainer:getAABB()
    if not self.enabled then return nil end
    local aabb = offsetAABB(self.aabb, self.true_x, self.true_y)
    local margin_x = self.margin_x or 2
    local margin_y = self.margin_y or 2
    aabb[2] = aabb[2] + 10 + 2 * margin_x
    aabb[4] = aabb[4] + 2 * margin_y
    return aabb
end

---@param x number
---@param y number
---@param aabb AABB
---@return ScrollContainer
function GUIContainer:ScrollContainer(x, y, aabb)
    local output = GUIContainer:Create()
    output.x = x
    output.y = y
    output.aabb = aabb
    output.parent = self
    output.root = self.root
    setmetatable(output, ScrollContainer)
    self:addChild(output)
    return output
end

---@class DragContainer
local DragContainer = {}
setmetatable(DragContainer, {__index = GUIContainer})
DragContainer.__tostring = function(self)
    local str = "DragContainer with children:"
    for _, v in ipairs(self.children) do str = str .. "\n - " .. tostring(v) end
    return str
end
DragContainer.__index = DragContainer

function DragContainer:_update()
    local mouse = self.root:GetMouse()
    -- If clicked, set variables to start checking for dragging
    if not self.culled and self.child_hovered and self.root.drag_handle ~= self then
        if mouse.left_frame == self.root.cur_frame then
            -- If we're inside a scroll container, compute a screen space position specially
            local true_x = self.true_x
            local true_y = self.true_y
            local parent = self.parent
            while parent ~= self.root do
                if parent.is_scroll_container then
                    true_x = true_x + parent.true_x + parent.aabb[1]
                    true_y = true_y + parent.true_y + parent.aabb[3]
                    if parent.scroll_offset then
                        true_x = true_x - parent.scroll_offset.x
                        true_y = true_y - parent.scroll_offset.y
                    end
                end
                parent = parent.parent
            end

            self.root.drag_handle = self
            self.predrag_pos = {x = self.x, y = self.y}
            self.click_pos = {x = mouse.x, y = mouse.y}
            self.drag_offset = {x = true_x - mouse.x, y = true_y - mouse.y}
        end
    end
    -- Start dragging if the mouse moves while clicking
    if self.root.drag_handle == self and not self.is_dragging then
        if mouse.left then
            if (mouse.x - self.click_pos.x) ^ 2 + (mouse.y - self.click_pos.y) ^ 2 > 10 ^ 2 then
                self.is_dragging = true
                self:_on_drag_start()
            end
        else
            self.root.drag_handle = nil
        end
    end
    -- Stop dragging when mouse is released
    if self.is_dragging and not mouse.left then
        self.is_dragging = false
        self.root.drag_handle = nil
        if self.free_drag then
            self.x = self.predrag_pos.x + mouse.x - self.click_pos.x
            self.y = self.predrag_pos.y + mouse.y - self.click_pos.y
        else
            self.x = self.predrag_pos.x
            self.y = self.predrag_pos.y
        end
        self:_on_drag_end()
    end
    GUIContainer._update(self)
end
---@param px number
---@param py number
function DragContainer:updatePosition(px, py, pz)
    GUIElement.updatePosition(self, px, py, pz)
    -- Follow the mouse while dragging
    if self.is_dragging then
        local mouse = self.root:GetMouse()
        self.x = mouse.x + self.drag_offset.x
        self.y = mouse.y + self.drag_offset.y
        self:_on_drag()

        GUIContainer.updatePosition(self, 0, 0, pz)
    else
        GUIContainer.updatePosition(self, px, py, pz)
    end
end
function DragContainer:render()
    -- We use a special render order while dragging to prevent hierarchy issues
    if not self.enabled or self.is_dragging then return end
    GUIContainer.render(self)
end
function DragContainer:render_drag()
    if self.is_dragging then for _, v in ipairs(self.children) do v:render() end end
end
---@return AABB
function DragContainer:getAABB()
    if not self.enabled then return nil end
    -- Don't contribute to parent AABB while dragging
    if self.is_dragging then
        return nil
    else
        return GUIContainer.getAABB(self)
    end
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
    for _, v in ipairs(self.children) do str = str .. "\n - " .. tostring(v) end
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

    -- local true_x = self.true_x
    -- local true_y = self.true_y
    -- local parent = self.parent
    -- while parent ~= self.root do
    --     if parent.is_scroll_container then
    --         true_x = true_x + parent.true_x + parent.aabb[1]
    --         true_y = true_y + parent.true_y + parent.aabb[3]
    --     end
    --     parent = parent.parent
    -- end
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
    for _, v in ipairs(self.children) do str = str .. "\n - " .. tostring(v) end
    return str
end
GridBox.__index = GridBox
-- Don't cull grid boxes because they render stuff far away from themselves
GridBox.no_cull = true
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
            for _, v in ipairs(self.children) do
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
            -- Draw rows of children
            for _, v in ipairs(self.children) do
                if v.enabled then
                    v:updatePosition(edge_x, edge_y, self.true_z)
                    local aabb = v:getAABB() or {0, 0, 0, 0}
                    local width = aabb[2] - aabb[1]
                    local height = aabb[4] - aabb[3]
                    -- if width == 0 then print("zero width!") end
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

---@class GUIAlias
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
    output.data = nil
    output.original = original
    output.instance_index = instance_index
    if original.children then
        output.children = {}
        for _, v in ipairs(original.children) do
            local clone = Alias.Create(v.x, v.y, v, output, instance_index)
            table.insert(output.children, clone)
        end
    end
    if original.tooltip then
        output.tooltip = Alias.Create(original.tooltip.x, original.tooltip.y, original.tooltip,
                                      output, instance_index)
    end
    output.parent = parent
    output.root = parent.root
    setmetatable(output, Alias)
    if output._init then output:_init() end
    if output.init then output:init() end
    return output
end
---@param x number
---@param y number
---@param original GUIElement
---@return GUIAlias
function GUIContainer:Alias(x, y, original)
    local output = Alias.Create(x, y, original, self)
    self:addChild(output)
    return output
end

---@class GridBoxInstanced
local GridBoxInstanced = {}
setmetatable(GridBoxInstanced, {__index = GridBox})
GridBoxInstanced.__tostring = function(self)
    local str = "GridBox with instanced children:"
    for _, v in ipairs(self.children) do str = str .. "\n - " .. tostring(v) end
    return str
end
GridBoxInstanced.__index = function(self, key)
    if key == "children" then
        if self.count ~= self.prev_count or self.update_children then
            -- Update instances
            self.children_instanced = {}
            for i = 1, self.count do
                for k, v in ipairs(self._children) do
                    local clone = Alias.Create(0, 0, v, self, i)
                    table.insert(self.children_instanced, clone)
                end
            end
            self.prev_count = self.count
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
    self.update_children = true
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
    if self.root.cull_aabb then
        local id = self.root:autoID()
        GuiButton(gui, id, self.true_x, self.true_y, self.text)
    else
        GuiText(gui, self.true_x, self.true_y, self.text)
    end
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
function Text:compute_aabb()
    if not self.enabled then return nil end
    -- If we have a precomputed bounding box
    local w, h = GuiGetTextDimensions(self.root.handle, self.text, 1, 2)
    local x = self.true_x
    local y = self.true_y
    if self.centered then
        x = x - w / 2
        y = y - h / 2
    end
    self._aabb = {x, x + w, y, y + h}
end
---@return AABB
function Text:getAABB()
    if not self.enabled then return nil end
    return self._aabb
end

---@class Button
local Button = {}
setmetatable(Button, {__index = Text})
Button.__tostring = function(self) return "Button: " .. self.text end
Button.__index = Button

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
    local scale_x = self.scale_x or 1
    local scale_y = self.scale_y or scale_x
    if self.hovered then
        scale_x = scale_x * 1.1
        scale_y = scale_y * 1.1
    end
    local rotation = self.rotation or 0
    local x = self.true_x
    local y = self.true_y
    if self.centered then
        local w, h = GuiGetImageDimensions(gui, self.sprite, scale_x)
        x = x - w * math.cos(rotation) / 2 + h * math.sin(rotation) / 2
        y = y - h * math.cos(rotation) / 2 - w * math.sin(rotation) / 2
    end
    local anim_type = self.anim_type or GUI_RECT_ANIMATION_PLAYBACK.Loop
    local anim_name = self.anim_name or "none"
    GuiImage(gui, id, x, y, self.sprite, alpha, scale_x, scale_y, rotation, anim_type, anim_name)
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
function Image:compute_aabb()
    if not self.enabled then return nil end
    local w, h = GuiGetImageDimensions(self.root.handle, self.sprite, self.scale or 1)
    local x = self.true_x
    local y = self.true_y
    if self.centered then
        x = x - w / 2
        y = y - h / 2
    end
    self._aabb = {x, x + w, y, y + h}
end
---@return AABB
function Image:getAABB()
    if not self.enabled then return nil end
    return self._aabb
end

---@class ImageButton
local ImageButton = {}
setmetatable(ImageButton, {__index = Image})
ImageButton.__tostring = function(self) return "ImageButton: " .. self.sprite end
ImageButton.__index = ImageButton
function ImageButton:_update()
    if self.wobble then self.rotation = math.cos(self.root.now * math.pi / 20) * math.pi / 32 end
    GUIElement._update(self)
end

function ImageButton:_on_hover_start()
    self.hovered = true
    GUIElement._on_hover_start(self)
end
function ImageButton:_on_hover_end()
    self.hovered = false
    GUIElement._on_hover_end(self)
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

---@class Tooltip
local Tooltip = {}
setmetatable(Tooltip, {__index = GUIContainer})
Tooltip.__tostring = function(self)
    local str = "Tooltip with children:"
    for _, v in ipairs(self.children) do str = str .. "\n - " .. tostring(v) end
    return str
end
Tooltip.__index = Tooltip
-- function Tooltip:render() if not self.enabled then return end end
---@return Tooltip
function GUIElement:Tooltip(x, y)
    x = x or 0
    y = y or 0
    local output = GUIContainer:Create(x, y)
    output.parent = self
    output.root = self.root
    setmetatable(output, Tooltip)
    self.tooltip = output
    return output
end

---Loads information needed to render spell cards and generate draggable inventory slots.
---It's wrapped in a function because it needs to load the whole spells table and invert it
---for sprite lookup, so it's a waste of processing time if you aren't using it
function GUIInitInventory()
    dofile_once("data/scripts/gun/gun_enums.lua")
    dofile_once("data/scripts/gun/gun_actions.lua")

    local spell_data = {}
    for k, v in ipairs(actions) do spell_data[v.id] = v end

    local spell_borders = {}
    spell_borders[ACTION_TYPE_PROJECTILE] = "data/ui_gfx/inventory/item_bg_projectile.png"
    spell_borders[ACTION_TYPE_STATIC_PROJECTILE] =
        "data/ui_gfx/inventory/item_bg_static_projectile.png"
    spell_borders[ACTION_TYPE_MODIFIER] = "data/ui_gfx/inventory/item_bg_modifier.png"
    spell_borders[ACTION_TYPE_DRAW_MANY] = "data/ui_gfx/inventory/item_bg_draw_many.png"
    spell_borders[ACTION_TYPE_MATERIAL] = "data/ui_gfx/inventory/item_bg_material.png"
    spell_borders[ACTION_TYPE_OTHER] = "data/ui_gfx/inventory/item_bg_other.png"
    spell_borders[ACTION_TYPE_UTILITY] = "data/ui_gfx/inventory/item_bg_utility.png"
    spell_borders[ACTION_TYPE_PASSIVE] = "data/ui_gfx/inventory/item_bg_passive.png"

    function SortSpells(a, b)
        local sda = spell_data[a.ItemActionComponent.action_id]
        local sdb = spell_data[b.ItemActionComponent.action_id]
        if sda.type == sdb.type then
            return GameTextGetTranslatedOrNot(sda.name) < GameTextGetTranslatedOrNot(sdb.name)
        else
            return sda.type < sdb.type
        end
    end

    ---@class InventorySlot
    local InventorySlot = {}
    setmetatable(InventorySlot, {__index = GUIContainer})
    InventorySlot.__tostring = function(self)
        return "InventorySlot: " .. tostring(self.item or "Empty")
    end
    InventorySlot.__index = InventorySlot

    function InventorySlot:putItem(item)
        if not item then
            print_error("Invalid drag item")
            return
        end
        if self.inventory then
            -- Put it in the linked inventory
            item.ItemComponent.inventory_slot = self.slot or {x = 0, y = 0}
            item:setParent(self.inventory)
            if self.update_inventory then self:update_inventory() end
        else
            -- Just hold a reference to the item
            self:setItem(item)
        end
    end

    ---@param item Entity|nil
    function InventorySlot:setItem(item)
        -- Clear previous item
        self.data = {}
        self.item = item
        self:clearChildren()
        -- Draw a new background
        self:Image(0, 0, "data/ui_gfx/inventory/quick_inventory_box.png").z = 0
        if not item then return end

        local item_handle = nil
        if self.disable_drag then
            item_handle = self:GUIContainer(0, 0)
        else
            item_handle = self:DragContainer(0, 0)
        end
        function item_handle:on_drag_end()
            local src_slot = self.parent
            for _, v in ipairs(self.root.hovered) do
                local dest_slot = v.parent
                if (src_slot.data.has_item and dest_slot.accept_items)
                    or (src_slot.data.has_spell and dest_slot.accept_spells) then
                    dest_slot:putItem(src_slot.item)
                    if src_slot.update_inventory then src_slot:update_inventory() end
                end
            end
        end

        local iac = item.ItemActionComponent
        if iac then
            -- Spell cards
            self.data.has_spell = true
            local sd = spell_data[iac.action_id]
            self.data.border = item_handle:Image(0, 0, spell_borders[sd.type])
            self.data.sprite = item_handle:ImageButton(0, 0, sd.sprite)
            local uses = item.ItemComponent.uses_remaining
            if uses ~= -1 then
                self.data.uses = item_handle:Text(-10, -10, tostring(uses))
                self.data.uses.z = -0.3
            end
            self.data.sprite.z = -0.2
            self.data.sprite.wobble = true

            function self.data.sprite.on_click() self:on_click() end
            function self.data.sprite.on_right_click() self:on_right_click() end

            self.data.tooltip = self.data.border:Tooltip(30, 0)
            local ttbox = self.data.tooltip:AutoBox(0, 0)
            ttbox.margins = {5, 5, 5, 5}
            local ttgrid = ttbox:GridBox(0, 0, true)
            ttgrid:Text(0, 0, GameTextGetTranslatedOrNot(sd.name):upper())
            ttgrid:Text(0, 0, sd.description)
        else
            self.data.has_item = true
            local ac = item.AbilityComponent
            local ic = item.ItemComponent
        end
    end

    ---@param x any
    ---@param y any
    ---@param item any
    function GUIContainer:InventorySlot(x, y, item)
        local output = self:GUIContainer(x, y)
        output.accept_items = true
        output.accept_spells = true
        setmetatable(output, InventorySlot)
        output:setItem(item)
        return output
    end
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
    output.cache_frame = {}
    setmetatable(output, GUI)
    return output
end
---@return vector2
function GUI:GetMouse()
    if not self.cache_frame.mousedata then
        local screen_w, screen_h = GuiGetScreenDimensions(self.handle)
        local cx, cy = GameGetCameraPos()
        local vx = MagicNumbersGetValue("VIRTUAL_RESOLUTION_X")
        local vy = MagicNumbersGetValue("VIRTUAL_RESOLUTION_Y")
        local controls = self.player.ControlsComponent
        local mpos = controls.mMousePosition
        self.cache_frame.mousedata = {
            x = (mpos.x - cx) * screen_w / vx + screen_w / 2,
            y = (mpos.y - cy) * screen_h / vy + screen_h / 2,
            left = controls.mButtonDownFire,
            left_frame = controls.mButtonFrameFire,
            right = controls.mButtonDownRightClick,
            right_frame = controls.mButtonFrameRightClick
        }
    end
    return self.cache_frame.mousedata
end
function GUI:render()
    self.last_frame = self.now
    self.now = GameGetFrameNum()
    self.click_disabled = false
    self.used_ids = {}
    self.id_counter = 1
    self.cache_frame = {}
    self.tooltip = nil
    self.cur_frame = GameGetFrameNum()
    self.hovered = {}
    self.callbacks = {}
    local status, err = pcall(function()
        GuiStartFrame(self.handle)

        for _, v in ipairs(self.children) do v:_update() end
        for _, v in ipairs(self.children) do v:updatePosition(0, 0, 0) end
        for _, v in ipairs(self.children) do v:render() end
        for _, v in ipairs(self.callbacks) do v.func(v.self) end
        if self.drag_handle and self.drag_handle.is_dragging then
            self.drag_handle:render_drag()
        elseif self.tooltip then
            local tt = self.tooltip.entity
            tt:_update()
            tt:updatePosition(self.tooltip.x, self.tooltip.y, -10)
            tt:render()
        end
    end)
    if not status then
        print_error("error while rendering")
        print_error(tostring(err))
    end
end

return GUI
