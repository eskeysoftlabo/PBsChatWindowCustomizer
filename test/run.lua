-- Behavioural tests for PB's ChatWindowCustomizer.
--
-- The add-on runs on a console, where one real test costs a whole session: build, upload,
-- boot the PS5, log in. harness.lua stubs the part of the client the add-on actually touches
-- -- the gamepad chat's top-level control and its tab buffers, the chat's own LoadSettings /
-- SetFontSize / CalculateConstraints, a label that resolves "$(GP_n)" the way the Japanese
-- client does, saved variables, the HUD fragment and LibHarvensAddonSettings -- so the logic
-- can be exercised here instead.
--
--   lua test/run.lua        (from the add-on folder; any Lua 5.1+)

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/") or ".")
ADDON_DIR = HERE .. "/.."
dofile(HERE .. "/harness.lua")

local failures = 0
local function check(label, got, want)
	local ok = got == want
	if not ok then failures = failures + 1 end
	print(string.format("%s %-58s got=%s want=%s", ok and "PASS" or "FAIL", label, tostring(got), tostring(want)))
end

local chat = GAMEPAD_CHAT_SYSTEM
local control = chat.control
local function Anchor(index)
	local a = control.anchors[(index or 0) + 1]
	return a and string.format("%d:%d,%d", a.point, a.offsetX, a.offsetY) or "none"
end
local function Dims() return string.format("%dx%d", control.width, control.height) end
local function Limits() local c = control.constraints; return c and table.concat(c, ",") or "none" end
local function CountBuilds() local n = 0; for _ in pairs(FontBuilds) do n = n + 1 end; return n end
local function ChatWrites(what) return (Writes.ZO_GamepadTextChat or {})[what] or 0 end
local function BufferWrites() return (Writes.ZO_GamepadChatWindow1Buffer or {}).font or 0 end
local GAME_FONT_20 = CHAT_FACE .. "|$(GP_20)|soft-shadow-thick"

print("\n== 1. load ==")
Fire(EVENT_ADD_ON_LOADED, "PBsChatWindowCustomizer")
local addon = PBS_CHAT_WINDOW_CUSTOMIZER
check("version read from manifest", addon.version, "1.3.1")
check("slash command registered", type(SLASH_COMMANDS["/pbchatwin"]), "function")
check("short slash command registered", type(SLASH_COMMANDS["/pbcw"]), "function")
check("HUD fragment callback registered", addon.hudRegistered, true)
check("scene callback registered", addon.scenesRegistered, true)
-- explanation, 2 checkboxes, heading + dropdown + 2 sliders (position), heading + 2 sliders
-- (size), heading + slider (text), heading + checkbox + dropdown + slider (showing),
-- heading + button + hint
check("settings rows", #PanelRows, 20)
check("nothing touched the chat at load", ChatWrites("anchor"), 0)

print("\n== 2. the first apply waits for the chat ==")
Fire(EVENT_PLAYER_ACTIVATED)
FlushCallLater() -- the first-apply delay
check("chat not loaded yet: nothing captured", addon.original, nil)
check("and a retry is pending", PendingCallLater(), 1)
LoadChat()
local gameAnchorWrites = ChatWrites("anchor")
FlushCallLater()
check("first apply done", addon.firstApplyDone, true)
check("game layout captured", addon.original ~= nil, true)
check("game corner measured", addon:GameLayout().corner, "bottomRight")
check("game x measured", addon:GameLayout().x, 0)
check("game y measured", addon:GameLayout().y, 215)
check("game width measured", addon:GameLayout().width, 490)
check("game height measured", addon:GameLayout().height, 280)

print("\n== 3. untouched install writes nothing ==")
check("layout does not differ", addon:LayoutDiffers(), false)
check("font does not differ", addon:FontDiffers(), false)
check("no anchor written by us", ChatWrites("anchor"), gameAnchorWrites)
check("chat still at the game's anchor", Anchor(), "12:0,-215")
check("buffer still has the game's font", ChatBufferFont(), GAME_FONT_20)
check("no font built", CountBuilds(), 0)
check("no handler added to the chat while untouched", next(chat.control.named), nil)
check("default text size is the measured one, not 20", addon:DefaultFontSize(), 15)

print("\n== 4. width ==")
Row(GetString(SI_PBSCWC_WIDTH)).setFunction(700)
check("layout differs", addon:LayoutDiffers(), true)
check("width written past the game's 550 limit", Dims(), "700x280")
check("still held by the bottom right", Anchor(), "12:0,-215")
check("limits widened on the control", Limits(), "200,100,1920,1080")
check("limits widened on the chat's own fields", chat.maxContainerWidth, 1920)
chat:PerformLayout() -- the game re-lays its tabs out
control:SetDimensions(700, 280)
check("a later tab layout keeps the wider limit", Dims(), "700x280")

print("\n== 5. position ==")
Row(GetString(SI_PBSCWC_POSITION_X)).setFunction(100)
Row(GetString(SI_PBSCWC_POSITION_Y)).setFunction(300)
check("moved in from the right and up from the bottom", Anchor(), "12:-100,-300")
check("screen left", control:GetLeft(), 1920 - 100 - 700)
check("screen top", control:GetTop(), 1080 - 300 - 280)

print("\n== 6. switching corner keeps the window where it is ==")
local left, top = control:GetLeft(), control:GetTop()
Row(GetString(SI_PBSCWC_CORNER)).setFunction(nil, nil, { data = "topLeft" })
check("now held by the top left", control.anchors[1].point, TOPLEFT)
check("same left", control:GetLeft(), left)
check("same top", control:GetTop(), top)
check("x re-expressed", addon:Layout().x, left)
check("y re-expressed", addon:Layout().y, top)
check("panel told to re-read", Panel.updates >= 1, true)
Row(GetString(SI_PBSCWC_HEIGHT)).setFunction(400)
check("from the top left a taller window grows down", control:GetTop(), top)

print("\n== 7. a corner switch alone does not start writing ==")
addon:ResetLayout(); addon:Refresh()
local before = ChatWrites("anchor")
addon:SetCorner("topLeft"); addon:Refresh()
check("same rectangle from another corner: no difference", addon:LayoutDiffers(), false)
check("and no write", ChatWrites("anchor"), before)

print("\n== 8. reset puts the game's layout back exactly ==")
Row(GetString(SI_PBSCWC_WIDTH)).setFunction(800)
check("written", addon.layoutWritten, true)
Row(GetString(SI_PBSCWC_RESET)).clickHandler()
check("anchor restored", Anchor(), "12:0,-215")
check("only one anchor", control.anchors[2], nil)
check("size restored", Dims(), "490x280")
check("limits restored", Limits(), "300,170,550,380")
check("chat fields restored", chat.maxContainerWidth, 550)
check("not written any more", addon.layoutWritten, false)

print("\n== 9. text size ==")
Row(GetString(SI_PBSCWC_FONT_SIZE)).setFunction(24)
local ours = CHAT_FACE .. "|24|soft-shadow-thick"
check("every tab gets the new size", ChatBufferFont(1) .. ChatBufferFont(3), ours .. ours)
check("one font built", CountBuilds(), 1)
Row(GetString(SI_PBSCWC_FONT_SIZE)).setFunction(12)
check("small text gets the thin shadow, as the game does", ChatBufferFont(), CHAT_FACE .. "|12|soft-shadow-thin")
Row(GetString(SI_PBSCWC_FONT_SIZE)).setFunction(15)
check("back at the game's size: the game's own descriptor", ChatBufferFont(), GAME_FONT_20)
check("and nothing of ours", addon.fontWritten, false)

print("\n== 10. the game's Small / Medium / Large setting ==")
Row(GetString(SI_PBSCWC_FONT_SIZE)).setFunction(24)
GameFontSetting = 25
chat:SetFontSize(25) -- what ZO_OptionsPanel_Social_OnGamepadChatTextSizeScrollListChanged does
check("the game put its own font back", ChatBufferFont(), CHAT_FACE .. "|$(GP_25)|soft-shadow-thick")
FireHud(SCENE_FRAGMENT_SHOWN)
check("ours is back on the HUD", ChatBufferFont(), ours)
check("default re-measured for the new setting", addon:DefaultFontSize(), 20)
local writes = BufferWrites()
FireHud(SCENE_FRAGMENT_SHOWN)
check("a second HUD show writes nothing", BufferWrites(), writes)
Row(GetString(SI_PBSCWC_FONT_SIZE)).setFunction(20)
check("20 is now the game's size: restored to $(GP_25)", ChatBufferFont(), CHAT_FACE .. "|$(GP_25)|soft-shadow-thick")
GameFontSetting = 20
chat:SetFontSize(20)

print("\n== 11. off and on ==")
Row(GetString(SI_PBSCWC_WIDTH)).setFunction(640)
Row(GetString(SI_PBSCWC_FONT_SIZE)).setFunction(30)
Row(GetString(SI_PBSCWC_ENABLED)).setFunction(false)
check("off: game's size", Dims(), "490x280")
check("off: game's font", ChatBufferFont(), GAME_FONT_20)
check("off: settings kept", addon:Account().layout.width, 640)
Row(GetString(SI_PBSCWC_ENABLED)).setFunction(true)
check("on: ours again", Dims(), "640x280")
check("on: our font again", ChatBufferFont(), CHAT_FACE .. "|30|soft-shadow-thick")

print("\n== 12. clamping ==")
SLASH_COMMANDS["/pbchatwin"]("size 5000 5000")
check("no bigger than the screen", Dims(), "1920x1080")
SLASH_COMMANDS["/pbchatwin"]("size 50 50")
check("no smaller than the minimum", Dims(), "200x100")
SLASH_COMMANDS["/pbchatwin"]("pos 5000 5000")
check("not off the edge", Anchor(), "12:-1720,-980")
check("saved value is kept as asked", addon:Account().layout.x, 5000)
SLASH_COMMANDS["/pbchatwin"]("font 99")
check("text size clamped", addon:FontSize(), 48)
SLASH_COMMANDS["/pbchatwin"]("reset")
check("slash reset: anchor", Anchor(), "12:0,-215")
check("slash reset: font", ChatBufferFont(), GAME_FONT_20)

print("\n== 13. slash commands ==")
SLASH_COMMANDS["/pbcw"]("corner bl")
check("corner via slash (no write: same place)", addon:Layout().corner, "bottomLeft")
check("x from the left", addon:Layout().x, 1920 - 490)
SLASH_COMMANDS["/pbcw"]("pos 40 215")
SLASH_COMMANDS["/pbcw"]("font 18")
check("pos via slash", Anchor(), "6:40,-215")
SLASH_COMMANDS["/pbcw"]("reset pos")
check("reset pos leaves the font alone", addon:Account().text.size, 18)
check("reset pos restores the window", Anchor(), "12:0,-215")
SLASH_COMMANDS["/pbcw"]("reset font")
check("reset font", addon:Account().text.size, nil)
local chatLines = #Chat
SLASH_COMMANDS["/pbcw"]("wobble")
check("usage printed for a typo", #Chat > chatLines, true)
SLASH_COMMANDS["/pbcw"]("status")

print("\n== 14. HUD shows do not rewrite a layout that is in place ==")
SLASH_COMMANDS["/pbcw"]("size 600 300")
local anchorWrites = ChatWrites("anchor")
FireHud(SCENE_FRAGMENT_SHOWN)
FireHud(SCENE_FRAGMENT_SHOWN)
check("no rewrite", ChatWrites("anchor"), anchorWrites)
chat:LoadSettings() -- anything in a later client that re-places the chat
FireHud(SCENE_FRAGMENT_SHOWN)
check("put right on the next HUD show", Dims(), "600x300")
SLASH_COMMANDS["/pbcw"]("reset")

print("\n== 15. preview, the way the console library opens a panel ==")
OpenPanel(Panel)
local frame = CreatedControls.PBsChatWindowCustomizerPreview
check("preview shown with the panel", frame ~= nil and not frame.hidden, true)
AdvanceFrame(); frame:Tick()
check("and still shown once the panel scene is up", frame ~= nil and not frame.hidden, true)
check("drawn over the menu", frame.drawLayer, DL_OVERLAY)
check("at the game's place", string.format("%d:%d,%d %dx%d", frame.anchors[1].point, frame.anchors[1].offsetX, frame.anchors[1].offsetY, frame.width, frame.height), "12:0,-215 490x280")
check("sample text in the game's font (no build)", CreatedControls.PBsChatWindowCustomizerPreviewLine1.font, GAME_FONT_20)
local shownLines = 0
for i = 1, 40 do local l = CreatedControls["PBsChatWindowCustomizerPreviewLine" .. i]; if l and not l.hidden then shownLines = shownLines + 1 end end
check("lines that fit 280 at size 15 (19 high)", shownLines, math.floor((280 - 46 - 6) / 19))
Row(GetString(SI_PBSCWC_HEIGHT)).setFunction(500)
Row(GetString(SI_PBSCWC_FONT_SIZE)).setFunction(30)
check("follows the height", frame.height, 500)
check("follows the text size", CreatedControls.PBsChatWindowCustomizerPreviewLine1.font, CHAT_FACE .. "|30|soft-shadow-thick")
check("preview and chat share the font (still one build)", FontBuilds[CHAT_FACE .. "|30|soft-shadow-thick"] ~= nil and ChatBufferFont() == CreatedControls.PBsChatWindowCustomizerPreviewLine1.font, true)

ClosePanel()
check("backing out to the list hides it", frame.hidden, true)
OpenPanel(Panel) -- Select() returns early: no AddonSelected this time
AdvanceFrame(); frame:Tick()
check("opening the same panel again shows it", frame.hidden, false)
ClosePanel()
OpenPanel(OtherPanel)
AdvanceFrame(); frame:Tick()
check("another add-on's panel does not show it", frame.hidden, true)
ClosePanel()
OpenPanel(Panel)
AdvanceFrame(); frame:Tick()
check("back to ours shows it", frame.hidden, false)
CurrentScene = { name = "hud" } -- menu button straight to the HUD
AdvanceFrame(); frame:Tick()
check("leaving the scene any other way hides it", frame.hidden, true)
ClosePanel()

OpenPanel(Panel)
Row(GetString(SI_PBSCWC_PREVIEW)).setFunction(false)
check("switched off in the panel hides it", frame.hidden, true)
ClosePanel(); OpenPanel(Panel)
check("switched off stays off", frame.hidden, true)
Row(GetString(SI_PBSCWC_PREVIEW)).setFunction(true)
check("switched back on shows it", frame.hidden, false)
ClosePanel()

CurrentScene = { name = "hud" }
SLASH_COMMANDS["/pbcw"]("preview")
check("slash preview shows it anywhere", frame.hidden, false)
AdvanceFrame(); frame:Tick()
check("and it stays while on that scene", frame.hidden, false)
SLASH_COMMANDS["/pbcw"]("preview")
check("and toggles it off", frame.hidden, true)
SLASH_COMMANDS["/pbcw"]("reset")

print("\n== 16. draw order ==")
local live = addon
check("game tier measured", live:GameDraw().tier, "medium")
check("game level measured", live:GameDraw().level, 30)
check("untouched: no draw difference", live:DrawDiffers(), false)
check("untouched: nothing written", ChatWrites("draw"), 0)
Row(GetString(SI_PBSCWC_TIER)).setFunction(nil, nil, { data = "high" })
check("tier written", control:GetDrawTier(), DT_HIGH)
check("level left at the game's", control:GetDrawLevel(), 30)
Row(GetString(SI_PBSCWC_LEVEL)).setFunction(145)
check("level written", control:GetDrawLevel(), 145)
check("differs", live:DrawDiffers(), true)
local drawWrites = ChatWrites("draw")
FireHud(SCENE_FRAGMENT_SHOWN)
check("a HUD show does not rewrite it", ChatWrites("draw"), drawWrites)
SLASH_COMMANDS["/pbcw"]("tier low")
check("tier via slash", control:GetDrawTier(), DT_LOW)
SLASH_COMMANDS["/pbcw"]("reset draw")
check("reset: the game's own tier", control:GetDrawTier(), DT_MEDIUM)
check("reset: the game's own level", control:GetDrawLevel(), 30)
check("and nothing of ours is written", live.drawWritten, false)

print("\n== 17. keeping the window on screen ==")
-- Where the game leaves it: LoadChatFromSettings minimised the chat at login.
chat:Minimize()
check("the game has it minimised", ChatMessagesShown(), false)
Row(GetString(SI_PBSCWC_ALWAYS_VISIBLE)).setFunction(true)
check("messages shown", ChatMessagesShown(), true)
check("background back to full", ChatBackgroundAlpha(), 1)
check("the client's own flag agrees", chat.isMinimized, false)
check("an expiry was pushed", ChatExpiry() ~= nil, true)
check("a repeating update is registered", UpdateCount(), 1)

-- The update pushes the expiry every 10 seconds, against the game's 20, so the chat control's
-- OnUpdate never finds it in the past.
for _ = 1, 6 do
	AdvanceFrame(10000)
	RunUpdates()
	ChatTick()
end
check("a minute later it has not minimised", ChatMessagesShown(), true)
check("and the expiry is still in the future", ChatExpiry() > GetFrameTimeSeconds(), true)

-- A menu: MINIMIZE_CHAT_FRAGMENT minimises on the way in and maximises on the way out.
MinimizeChatFragmentShow()
check("a menu still minimises it", ChatMessagesShown(), false)
MinimizeChatFragmentHide()
FireHud(SCENE_FRAGMENT_SHOWN)
check("back on the HUD it is up again", ChatMessagesShown(), true)

-- A menu that does not maximise on the way out (the fragment only does when it minimised).
chat:Minimize()
FireHud(SCENE_FRAGMENT_SHOWN)
check("the HUD show puts it right either way", ChatMessagesShown(), true)
check("background too", ChatBackgroundAlpha(), 1)

Row(GetString(SI_PBSCWC_ALWAYS_VISIBLE)).setFunction(false)
check("switched off: the update is gone", UpdateCount(), 0)
check("switched off: still on screen for now", ChatMessagesShown(), true)
AdvanceFrame(25000); ChatTick()
check("and the game's own timer minimises it", ChatMessagesShown(), false)

Row(GetString(SI_PBSCWC_ALWAYS_VISIBLE)).setFunction(true)
Row(GetString(SI_PBSCWC_ENABLED)).setFunction(false)
check("the master switch also hands it back", UpdateCount(), 0)
AdvanceFrame(25000); ChatTick()
check("and it minimises as the game would", ChatMessagesShown(), false)
SLASH_COMMANDS["/pbcw"]("always on")
check("slash always on: back on screen", ChatMessagesShown(), true)
check("and it switched the add-on back on", live:Account().enabled, true)
Row(GetString(SI_PBSCWC_RESET)).clickHandler()
check("reset turns it off as well", live:Account().alwaysVisible, false)
check("with the update unregistered", UpdateCount(), 0)
SLASH_COMMANDS["/pbcw"]("status")

print("\n== 17b. showing it in menus ==")
Row(GetString(SI_PBSCWC_ALWAYS_VISIBLE)).setFunction(false)
OpenMenu()
check("the game hides the window in a menu", ChatWindowShown(), false)
CloseMenu()
check("and shows it again on the HUD", ChatWindowShown(), true)

Row(GetString(SI_PBSCWC_IN_MENUS)).setFunction(true)
check("keeping it on screen came with it", live:Account().alwaysVisible or live:AlwaysVisible(), true)
OpenMenu()
check("the window is up in the menu", ChatWindowShown(), true)
check("with its messages", ChatMessagesShown(), true)
FlushCallLater() -- the re-assert a moment after the transition
check("still up once the transition has settled", ChatWindowShown(), true)

-- Something minimising the chat later in the same menu, with no scene change to notice it: the
-- ten-second push is the backstop.
chat:Minimize()
chat:RefreshVisibility()
RunUpdates()
check("a later minimise in the same menu is undone", ChatMessagesShown(), true)
check("and the window with it", ChatWindowShown(), true)

-- Menu to menu never touches the HUD fragment.
chat.control:SetHidden(true)
SceneShown({ name = "another menu" })
check("a scene change puts it back", ChatWindowShown(), true)

CloseMenu()
check("back on the HUD, still up", ChatWindowShown(), true)

-- The game's own "chat on the HUD" setting is never overridden.
chat.hudEnabled = false
OpenMenu()
check("nothing is forced while the player has chat off", ChatWindowShown(), false)
chat.hudEnabled = true
CloseMenu()

Row(GetString(SI_PBSCWC_IN_MENUS)).setFunction(false)
OpenMenu()
check("switched off: the game hides it again", ChatWindowShown(), false)
CloseMenu()
check("and the HUD shows it", ChatWindowShown(), true)
AdvanceFrame(25000); ChatTick()
check("and it minimises as the game would", ChatMessagesShown(), false)

print("\n== 17c. Update 51: the customizable HUD element ==")
Row(GetString(SI_PBSCWC_IN_MENUS)).setFunction(false)
Row(GetString(SI_PBSCWC_ALWAYS_VISIBLE)).setFunction(false)
SLASH_COMMANDS["/pbcw"]("reset")
check("the element's own anchor is the game's", ChatElementAnchor(), "12:0,-215")
SLASH_COMMANDS["/pbcw"]("size 900 500")
SLASH_COMMANDS["/pbcw"]("pos 40 300")
check("the control", Anchor() .. " " .. Dims(), "12:-40,-300 900x500")
check("and the element agrees", ChatElementAnchor(), "12:-40,-300")
check("still counts as the element's default, so the trackers follow", ChatElement():IsUsingDefaultAnchor(), true)

-- What U51 does by itself: PropagateSettings on a screen resize, a gamepad-mode change, or once
-- when add-ons have loaded. Before 1.3.0 this put the window back to the game's placement.
HUD_MANAGER:PropagateSettings()
check("the client's own re-apply keeps our position", Anchor(), "12:-40,-300")

-- A zone load: something writes over the window after EVENT_PLAYER_ACTIVATED has been handled.
BreakTheWindow()
check("the window is wrong", Dims(), "490x280")
Fire(EVENT_PLAYER_ACTIVATED)
BreakTheWindow() -- after our own handler, which is what the PS5 report describes
FlushCallLater()
check("a scheduled look puts the size back", Dims(), "900x500")
check("and the position with it", Anchor(), "12:-40,-300")
check("the drift is recorded for status", live.driftLog ~= nil and #live.driftLog > 0, true)

-- A screen resize is where the client's PropagateSettings runs.
chat.control:SetDimensions(490, 280)
Fire(EVENT_SCREEN_RESIZED, 1920, 1080)
FlushCallLater()
check("a resize is settled too", Dims(), "900x500")

SLASH_COMMANDS["/pbcw"]("reset")
check("reset puts the element's anchor back as well", ChatElementAnchor(), "12:0,-215")
HUD_MANAGER:PropagateSettings()
check("so the client's re-apply is the game's own again", Anchor(), "12:0,-215")
check("and the window is the game's size", Dims(), "490x280")

-- A client from before Update 51 has no element at all.
RemoveHudElement()
SLASH_COMMANDS["/pbcw"]("size 700 320")
check("without an element the control is still written", Dims(), "700x320")
check("and status says there is none", live:HudElement(), nil)
SLASH_COMMANDS["/pbcw"]("reset")
RestoreHudElement()
SLASH_COMMANDS["/pbcw"]("status")

print("\n== 17d. corrected as it happens, not on a timer ==")
SLASH_COMMANDS["/pbcw"]("reset")
check("reset took the handlers off", next(control.named), nil)
check("and the flag says so", live.rectWatchInstalled, false)
SLASH_COMMANDS["/pbcw"]("size 900 500")
SLASH_COMMANDS["/pbcw"]("pos 40 300")
check("a write installs both named handlers", (control.named["OnRectChanged:PBsChatWindowCustomizer"] ~= nil)
	and (control.named["OnEffectivelyShown:PBsChatWindowCustomizer"] ~= nil), true)
check("the client's own OnUpdate is untouched", control.handlers.OnUpdate ~= nil, true)
LayoutPass()

-- Whatever writes the game's size after a zone load, seen at the next layout: no timer has run,
-- no scheduled look has fired -- only the engine's own notice.
local correctedBefore = live.rectCorrections or 0
BreakTheWindow()
local rounds = LayoutPass()
check("the size is back at the layout pass", Dims(), "900x500")
check("with the position", Anchor(), "12:-40,-300")
check("in one correction", (live.rectCorrections or 0) - correctedBefore, 1)
check("and the layout settled", rounds <= 3, true)

-- Position written by the client (LoadSettings is what the game itself runs).
chat:LoadSettings()
LayoutPass()
check("the game's own LoadSettings is undone at once", Dims() .. " " .. Anchor(), "900x500 12:-40,-300")

-- What the client does to the HUD element on a resize.
control:SetDimensions(490, 280)
HUD_MANAGER:PropagateSettings()
LayoutPass()
check("a propagate is corrected at the layout pass too", Dims() .. " " .. Anchor(), "900x500 12:-40,-300")

-- A window that was wrong while hidden is caught as it appears.
control:SetHidden(true)
LayoutPass()
BreakTheWindow()
control.rectDirty = false -- the engine did not lay a hidden control out
control:SetHidden(false)
LayoutPass()
check("fixed the moment it is shown", Dims(), "900x500")

-- Once it is right the handler does nothing.
local writes = ChatWrites("dimensions")
LayoutPass()
check("no write when nothing is wrong", ChatWrites("dimensions"), writes)

-- A writer that fights every correction: the engine would spin on its own handler whatever this
-- add-on did, so what is ours to bound is how many corrections it is drawn into in one frame.
control:SetHandler("OnRectChanged", function() control:SetDimensions(490, 280) end, "Stubborn")
local correctedBefore = live.rectCorrections or 0
BreakTheWindow()
LayoutPass(40)
check("corrections in one frame are bounded", (live.rectCorrections or 0) - correctedBefore <= live.MAX_CORRECTIONS_PER_FRAME, true)
check("and the give-up is counted", (live.rectGaveUp or 0) > 0, true)
control:SetHandler("OnRectChanged", nil, "Stubborn")
AdvanceFrame(16) -- the next frame starts a fresh count
BreakTheWindow()
LayoutPass()
check("once it stops, the next frame puts the window right", Dims(), "900x500")

SLASH_COMMANDS["/pbcw"]("status")
SLASH_COMMANDS["/pbcw"]("reset")
check("reset removes the handlers again", next(control.named), nil)

print("\n== 18. a saved layout is applied at login, after the game's is read ==")
local store = SavedStore.PBsChatWindowCustomizer_Data
store.layout = { corner = "bottomLeft", x = 30, y = 400, width = 520, height = 360 }
store.text = { size = 22 }
-- A fresh client: new chat control, add-on loaded again.
PBS_CHAT_WINDOW_CUSTOMIZER = nil
control.anchors = {}; control.width, control.height = 350, 155; control.constraints = nil
chat.loaded = false
chat.minContainerWidth, chat.maxContainerWidth, chat.minContainerHeight, chat.maxContainerHeight = 300, 550, 170, 380
dofile(ADDON_DIR .. "/Main.lua")
Fire(EVENT_ADD_ON_LOADED, "PBsChatWindowCustomizer")
local reloaded = PBS_CHAT_WINDOW_CUSTOMIZER
LoadChat()
Fire(EVENT_PLAYER_ACTIVATED)
FlushCallLater()
check("applied at login", Anchor(), "6:30,-400")
check("size applied", Dims(), "520x360")
check("font applied", ChatBufferFont(), CHAT_FACE .. "|22|soft-shadow-thick")
check("the original captured is the game's, not ours", reloaded.original.anchors[1].offsetY, -215)
reloaded:ResetToDefaults()
check("so reset still finds the game's layout", Anchor(), "12:0,-215")

print("\n== 19. no gamepad chat on this client ==")
local saved = GAMEPAD_CHAT_SYSTEM
GAMEPAD_CHAT_SYSTEM = nil
check("apply is a quiet no-op", reloaded:ApplyLayout(), false)
SLASH_COMMANDS["/pbcw"]("status")
GAMEPAD_CHAT_SYSTEM = saved

print(string.format("\n%s  (%d failures)", failures == 0 and "ALL PASS" or "FAILURES", failures))
os.exit(failures == 0 and 0 or 1)
