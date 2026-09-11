-- Stub of just enough ESO client to exercise PBsChatWindowCustomizer.
local DIR = ADDON_DIR

unpack = unpack or table.unpack

-- ---- string table -------------------------------------------------------------------
local stringValues = {}
local nextId = 1
function ZO_CreateStringId(id, value) if not _G[id] then _G[id] = nextId; nextId = nextId + 1 end; stringValues[_G[id]] = value end
function SafeAddVersion() end
function SafeAddString(id, value) stringValues[id] = value end
function GetString(id) return stringValues[id] or ("<missing " .. tostring(id) .. ">") end

-- ---- chat / misc --------------------------------------------------------------------
Chat = {}
CHAT_ROUTER = { AddSystemMessage = function(_, t) Chat[#Chat + 1] = t; print("[chat] " .. t) end }
function d(t) print("[d] " .. tostring(t)) end
SLASH_COMMANDS = {}
local pendingCallLater = {}
function zo_callLater(fn, ms) pendingCallLater[#pendingCallLater + 1] = fn end
function FlushCallLater() local q = pendingCallLater; pendingCallLater = {}; for _, fn in ipairs(q) do fn() end; return #q end
function PendingCallLater() return #pendingCallLater end

local frameTime = 0
function GetFrameTimeMilliseconds() return frameTime end
function AdvanceFrame(ms) frameTime = frameTime + (ms or 1000) end

function GetAddOnManager()
	return {
		GetNumAddOns = function() return 1 end,
		GetAddOnInfo = function(_, i) return "PBsChatWindowCustomizer", "|cFF69B4PB\u{2019}s ChatWindowCustomizer|r 1.0.1" end,
	}
end

-- ---- constants ----------------------------------------------------------------------
TOP, LEFT, BOTTOM, RIGHT, CENTER = 1, 2, 4, 8, 128
TOPLEFT, TOPRIGHT, BOTTOMLEFT, BOTTOMRIGHT = 3, 9, 6, 12
CT_LABEL, CT_TEXTURE, CT_CONTROL = "label", "texture", "control"
DL_OVERLAY, DT_HIGH = "overlay", "high"
TEXT_WRAP_MODE_ELLIPSIS = 1
SCENE_FRAGMENT_SHOWING, SCENE_FRAGMENT_SHOWN, SCENE_FRAGMENT_HIDING, SCENE_FRAGMENT_HIDDEN = "showing", "shown", "hiding", "hidden"

-- ---- events -------------------------------------------------------------------------
EVENT_ADD_ON_LOADED = "EVENT_ADD_ON_LOADED"
EVENT_PLAYER_ACTIVATED = "EVENT_PLAYER_ACTIVATED"
local handlers = {}
EVENT_MANAGER = {
	RegisterForEvent = function(_, name, event, fn) handlers[event] = handlers[event] or {}; handlers[event][name] = fn end,
	UnregisterForEvent = function(_, name, event) if handlers[event] then handlers[event][name] = nil end end,
}
function Fire(event, ...) for _, fn in pairs(handlers[event] or {}) do fn(event, ...) end end

local callbacks = {}
CALLBACK_MANAGER = {
	RegisterCallback = function(_, name, fn) callbacks[name] = callbacks[name] or {}; table.insert(callbacks[name], fn) end,
	-- Like ZO_CallbackObject: the callback gets the arguments, not the event name.
	FireCallbacks = function(_, name, ...) for _, fn in ipairs(callbacks[name] or {}) do fn(...) end end,
}

-- ---- saved variables ----------------------------------------------------------------
SavedStore = {}
local function DeepCopy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = DeepCopy(v) end
	return out
end
ZO_SavedVars = {
	NewAccountWide = function(_, name, version, namespace, defaults)
		SavedStore[name] = SavedStore[name] or {}
		local store = SavedStore[name]
		for k, v in pairs(defaults or {}) do if store[k] == nil then store[k] = DeepCopy(v) end end
		return store
	end,
}

-- ---- fonts --------------------------------------------------------------------------
-- $(GP_n) resolves per language. These are the Japanese client's values, from
-- fontstrings/japanese: a build that wrote the setting number back as a raw size, instead of
-- the measured one, would change the text on a Japanese client and be caught here.
GP_SIZES = { [18] = 14, [20] = 15, [22] = 17, [25] = 20, [27] = 21, [34] = 28 }
CHAT_FACE = "EsoUI/Common/Fonts/FTN57.slug"
ZoFontGamepadChat = { GetFontInfo = function() return CHAT_FACE, 15, "soft-shadow-thick" end }

-- Every descriptor with a raw size that the client would have to build.
FontBuilds = {}
local function ResolveFont(descriptor)
	local face, sizeText, style = descriptor:match("^([^|]+)|([^|]+)|?(.*)$")
	if not face then
		return { face = descriptor, size = 22 } -- a named font object such as ZoFontGamepad22
	end
	local gp = sizeText:match("^%$%(GP_(%d+)%)$")
	local size
	if gp then
		size = assert(GP_SIZES[tonumber(gp)], "undefined $(GP_" .. gp .. ")")
	else
		size = assert(tonumber(sizeText), "unparseable size in " .. descriptor)
		FontBuilds[descriptor] = (FontBuilds[descriptor] or 0) + 1
	end
	return { face = face, size = size, style = style }
end

-- ---- controls -----------------------------------------------------------------------
Writes = {}
local function CountWrite(control, what)
	Writes[control.name] = Writes[control.name] or {}
	Writes[control.name][what] = (Writes[control.name][what] or 0) + 1
end

GuiRoot = { name = "GuiRoot" }
local rootWidth, rootHeight = 1920, 1080
function GuiRoot:GetDimensions() return rootWidth, rootHeight end
function GuiRoot:GetName() return "GuiRoot" end
function SetRootSize(w, h) rootWidth, rootHeight = w, h end

local Control = {}
Control.__index = Control
function MakeControl(name, parent, kind)
	return setmetatable({ name = name, parent = parent or GuiRoot, kind = kind, anchors = {}, width = 0, height = 0, hidden = false, handlers = {} }, Control)
end
function Control:GetName() return self.name end
function Control:GetParent() return self.parent end
function Control:ClearAnchors() CountWrite(self, "anchor"); self.anchors = {} end
function Control:SetAnchor(point, relativeTo, relativePoint, offsetX, offsetY, constrains)
	CountWrite(self, "anchor")
	assert(#self.anchors < 2, self.name .. " already has two anchors")
	table.insert(self.anchors, { point = point, relativeTo = relativeTo, relativePoint = relativePoint or point, offsetX = offsetX or 0, offsetY = offsetY or 0, constrains = constrains })
end
function Control:SetAnchorFill(target) self:ClearAnchors(); self:SetAnchor(TOPLEFT, target, TOPLEFT); self:SetAnchor(BOTTOMRIGHT, target, BOTTOMRIGHT) end
function Control:GetAnchor(index)
	local a = self.anchors[index + 1]
	if not a then return false end
	return true, a.point, a.relativeTo, a.relativePoint, a.offsetX, a.offsetY, a.constrains
end
function Control:SetDimensions(w, h)
	CountWrite(self, "dimensions")
	local c = self.constraints
	if c then
		-- The client applies the constraints when the size is set.
		w = math.max(c[1], math.min(c[3], w)); h = math.max(c[2], math.min(c[4], h))
	end
	self.width, self.height = w, h
end
function Control:GetDimensions() return self.width, self.height end
function Control:SetWidth(w) self.width = w end
function Control:SetHeight(h) self.height = h end
function Control:GetHeight() return self.height end
function Control:SetDimensionConstraints(a, b, c, d) CountWrite(self, "constraints"); self.constraints = { a, b, c, d } end
function Control:GetDimensionConstraints() local c = self.constraints or { 0, 0, 0, 0 }; return c[1], c[2], c[3], c[4] end
function Control:SetHidden(h) self.hidden = h end
function Control:IsHidden() return self.hidden end
function Control:SetMouseEnabled() end
function Control:SetDrawLayer(v) self.drawLayer = v end
function Control:SetDrawTier(v) self.drawTier = v end
function Control:SetHandler(name, fn) self.handlers[name] = fn end
function Control:SetColor(r, g, b, a) self.color = { r, g, b, a } end
function Control:SetText(t) self.text = t end
function Control:SetWrapMode(m) self.wrapMode = m end
function Control:SetMaxLineCount(n) self.maxLines = n end
function Control:SetFont(descriptor)
	CountWrite(self, "font")
	self.font = descriptor
	self.resolved = ResolveFont(descriptor)
end
function Control:GetFontSize() return self.resolved and self.resolved.size end
function Control:GetFontHeight() return self.resolved and math.ceil(self.resolved.size * 1.25) or 0 end
-- Only corner anchors on the screen are needed here.
function Control:GetLeft()
	local a = self.anchors[1]
	if not a then return 0 end
	if a.point == TOPLEFT or a.point == BOTTOMLEFT then return a.offsetX end
	return rootWidth + a.offsetX - self.width
end
function Control:GetTop()
	local a = self.anchors[1]
	if not a then return 0 end
	if a.point == TOPLEFT or a.point == TOPRIGHT then return a.offsetY end
	return rootHeight + a.offsetY - self.height
end
function Control:Tick() if self.handlers.OnUpdate then self.handlers.OnUpdate(self) end end

CreatedControls = {}
WINDOW_MANAGER = {
	CreateControl = function(_, name, parent, kind)
		assert(not CreatedControls[name], "duplicate control name " .. tostring(name))
		local c = MakeControl(name, parent, kind); CreatedControls[name] = c; return c
	end,
	CreateTopLevelWindow = function(_, name)
		assert(not CreatedControls[name], "duplicate control name " .. tostring(name))
		local c = MakeControl(name, GuiRoot, "toplevel"); CreatedControls[name] = c; return c
	end,
}

-- ---- the gamepad chat ---------------------------------------------------------------
-- Mirrors gamepadchatsystem.lua / sharedchatsystem.lua: the top-level control is built from the
-- XML template (350 x 155, no anchor) and only placed by LoadSettings, which runs from the
-- chat's own EVENT_PLAYER_ACTIVATED.
GameFontSetting = 20
function GetGamepadChatFontSize() return GameFontSetting end

local function GameDescriptor(n)
	return string.format("%s|$(GP_%d)|%s", CHAT_FACE, n, n <= 14 and "soft-shadow-thin" or "soft-shadow-thick")
end

local chatControl = MakeControl("ZO_GamepadTextChat", GuiRoot, "toplevel")
chatControl.width, chatControl.height = 350, 155
GAMEPAD_CHAT_SYSTEM = {
	control = chatControl,
	loaded = false,
	containers = {},
	minContainerWidth = 300, maxContainerWidth = 550, minContainerHeight = 170, maxContainerHeight = 380,
}
local chat = GAMEPAD_CHAT_SYSTEM

function chat:SetFontSize(n)
	for _, container in ipairs(self.containers) do
		for _, window in ipairs(container.windows) do
			if window.fontSize ~= n then
				window.fontSize = n
				window.buffer:SetFont(GameDescriptor(n))
			end
		end
	end
end

-- SharedChatContainer:CalculateConstraints, run whenever the tabs are laid out.
function chat:PerformLayout()
	self.control:SetDimensionConstraints(self.minContainerWidth, self.minContainerHeight, self.maxContainerWidth, self.maxContainerHeight)
end

-- GamepadChatContainer:LoadSettings, and the window creation around it.
function chat:LoadSettings()
	self.control:ClearAnchors()
	self.control:SetAnchor(BOTTOMRIGHT, nil, BOTTOMRIGHT, 0, -215)
	self.control:SetDimensions(490, 280)
end

function LoadChat()
	local container = { windows = {} }
	for i = 1, 3 do
		container.windows[i] = { buffer = MakeControl("ZO_GamepadChatWindow" .. i .. "Buffer", nil, "textbuffer") }
	end
	chat.containers = { container }
	chat.primaryContainer = container
	chat:PerformLayout()
	chat:LoadSettings()
	chat:SetFontSize(GetGamepadChatFontSize())
	chat.loaded = true
end

function ChatBufferFont(i) return chat.containers[1].windows[i or 1].buffer.font end

-- ---- scenes -------------------------------------------------------------------------
local hudCallbacks = {}
HUD_FRAGMENT = { RegisterCallback = function(_, name, fn) table.insert(hudCallbacks, fn) end }
function FireHud(state) for _, fn in ipairs(hudCallbacks) do fn(nil, state) end end
CurrentScene = { name = "gamepad_settings" }
SCENE_MANAGER = { GetCurrentScene = function() return CurrentScene end }

SCENE_SHOWING, SCENE_SHOWN, SCENE_HIDING, SCENE_HIDDEN = "showing", "shown", "hiding", "hidden"
local function MakeScene(name)
	local scene = { name = name, state = SCENE_HIDDEN, callbacks = {} }
	function scene:RegisterCallback(_, fn) table.insert(self.callbacks, fn) end
	function scene:IsShowing() return self.state == SCENE_SHOWN end
	function scene:SetState(state) self.state = state; for _, fn in ipairs(self.callbacks) do fn(nil, state) end end
	return scene
end
MenuScene = CurrentScene

-- ---- LibHarvensAddonSettings --------------------------------------------------------
-- The console copy of the library, as far as selection goes (votan73/ESO,
-- LibHarvensAddonSettings/Main.lua + Console/Settings.lua): the panel scene is only created the
-- first time the main menu opens, and picking an add-on from the list calls Select() -- which
-- fires AddonSelected, *then* sets .selected -- and only after that pushes the panel scene.
-- Select() returns early for the add-on that is already selected.
PanelRows = {}
local panels = {}
LibHarvensAddonSettings = {
	ST_LABEL = "label", ST_SECTION = "section", ST_CHECKBOX = "checkbox", ST_SLIDER = "slider", ST_DROPDOWN = "dropdown", ST_BUTTON = "button",
	AddAddon = function(_, title)
		local panel = { title = title, name = title, updates = 0, selected = false }
		function panel:AddSetting(row) if self == Panel then PanelRows[#PanelRows + 1] = row end end
		function panel:UpdateControls() self.updates = self.updates + 1 end
		function panel:Select()
			if self.selected then return end
			CALLBACK_MANAGER:FireCallbacks("LibHarvensAddonSettings_AddonSelected", self.name, self)
			for _, other in ipairs(panels) do other.selected = false end
			self.selected = true
		end
		table.insert(panels, panel)
		if title:find("ChatWindowCustomizer", 1, true) then Panel = panel end
		return panel
	end,
}
function OpenMainMenu()
	if not LibHarvensAddonSettings.scene then
		LibHarvensAddonSettings.scene = MakeScene("LibHarvensAddonSettingsScene")
	end
	CurrentScene = MenuScene
end

-- activatedCallback in the library's add-on list.
function OpenPanel(panel)
	OpenMainMenu()
	panel:Select()
	local scene = LibHarvensAddonSettings.scene
	scene:SetState(SCENE_SHOWING)
	CurrentScene = scene
	scene:SetState(SCENE_SHOWN)
end

-- Back out of a panel to the list.
function ClosePanel()
	local scene = LibHarvensAddonSettings.scene
	scene:SetState(SCENE_HIDING)
	CurrentScene = MenuScene
	scene:SetState(SCENE_HIDDEN)
end

function Row(label)
	for _, row in ipairs(PanelRows) do
		if row.label == label then return row end
	end
	error("no row " .. tostring(label))
end

-- ---- load the add-on ----------------------------------------------------------------
dofile(DIR .. "/lang/strings.lua")
dofile(DIR .. "/lang/jp.lua")
dofile(DIR .. "/Main.lua")
dofile(DIR .. "/Preview.lua")
dofile(DIR .. "/Settings.lua")

-- Another add-on's panel. Ours is added later, at our EVENT_ADD_ON_LOADED.
OtherPanel = LibHarvensAddonSettings:AddAddon("Someone else's add-on")
