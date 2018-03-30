--[[
	Author: Dennis Werner Garske (DWG)
	License: MIT License
]]

-- Setup to wrap our stuff in a table so we don't pollute the global environment
local _G = _G or getfenv(0);
local MMC = _G.CastModifier or {};
_G.CastModifier = MMC;
MMC.Hooks = MMC.Hooks or {};
MMC.mouseoverUnit = MMC.mouseoverUnit or nil;

MMC.Extensions = MMC.Extensions or {};

-- Attempts to execute a macro by the given name
-- name: The name of the macro
-- returns: Whether the macro was executed or not
function MMC.ExecuteMacroByName(name)
    local macroId = GetMacroIndexByName(name);
    if not macroId then
        return false;
    end
    
    local _,_, body = GetMacroInfo(macroId);
    if not body then
        return false;
    end
    
    local lines = MMC.splitString(body, "\n");
    for k,v in pairs(lines) do
        ChatFrameEditBox:SetText(v);
        ChatEdit_SendText(ChatFrameEditBox);
    end
end

-- Searches for a ':', '>' or '<' in the given word and returns its position
-- word: The word to search in
-- returns: The position of the delimeter or nil and 1 for '>' or 2 for '<'
function MMC.FindDelimeter(word)
    local delimeter = string.find(word, ":");
    local which = nil;
    
    if not delimeter then
        delimeter = string.find(word, ">");
        which = 1;
        if not delimeter then
            delimeter = string.find(word, "<");
            which = 0;
        end
    end
    
    if not delimeter then
        which = nil;
    end
    
    return delimeter, which;
end

-- Parses the given message and looks for any conditionals
-- msg: The message to parse
-- returns: A set of conditionals found inside the given string
function MMC.parseMsg(msg)
	local modifier = "";
	local modifierEnd = string.find(msg, "]");
	local help = nil;
	
    -- If we find conditionals trim down the message to everything except the conditionals
	if string.sub(msg, 1, 1) == "[" and modifierEnd then
		modifier = string.sub(msg, 2, modifierEnd - 1);
		msg = string.sub(msg, modifierEnd + 1);
    -- No conditionals found. Just return the message as is
	elseif string.sub(msg, 1, 1) ~= "!" then
		return msg;
	end
	
    local target;
    local conditionals = {};
    
    
    if string.sub(msg, 1, 1) == "!" then
        msg = string.sub(msg, 2);
        conditionals.checkchanneled = msg;
    end
        
    local pattern = "(@?%w+:?>?<?%w*[_?%-?%w*]*[/?%w*]*)";
    for w in string.gfind(modifier, pattern) do
        local delimeter, which = MMC.FindDelimeter(w);
        -- x:y
        if delimeter then
            local conditional = string.sub(w, 1, delimeter - 1);
            if which then
                conditionals[conditional] = { bigger = which, amount = string.sub(w, delimeter + 1) };
            else
                conditionals[conditional] = string.sub(w, delimeter + 1);
            end
        -- @target
        elseif string.sub(w, 1, 1) == "@" then
            conditionals["target"] = string.sub(w,  2);
        -- Any other keyword like harm or help
        elseif MMC.Keywords[w] ~= nil then
            conditionals[w] = 1;
        end
    end
    
	return msg, conditionals;
end

function MMC.SetHelp(conditionals)
    if conditionals.help then
        conditionals.help = 1;
    elseif conditionals.harm then
        conditionals.help = 0;
    end
end

-- Fixes the conditionals' target by using the player's current target if it exists or falling back to the player itself if it doesn'target
-- conditionals: The conditionals containing the current target
-- returns: Whether or not we've changed the player's current target
function MMC.FixEmptyTarget(conditionals)
    if not conditionals.target then
        if UnitExists("target") then
            conditionals.target = "target";
        else
            conditionals.target = "player";
        end
    end
    
    return false;
end

-- Fixes the conditionals' target by targeting the target with the given name
-- conditionals: The conditionals containing the current target
-- name: The name of the player to target
-- hook: The target hook
-- returns: Whether or not we've changed the player's current target
function MMC.FixEmptyTargetSetTarget(conditionals, name, hook)
    if not conditionals.target then
        hook(name);
        conditionals.target = "target";
        return true;
    end
    return false;
end

-- Returns the name of the focus target or nil
function MMC.GetFocusName()
    if ClassicFocus_CurrentFocus then
        return ClassicFocus_CurrentFocus;
    elseif CURR_FOCUS_TARGET then
        return CURR_FOCUS_TARGET;
    end
    
    return nil;
end

-- Attempts to target the focus target.
-- returns: Whether or not it succeeded
function MMC.TryTargetFocus()
    local name = MMC.GetFocusName();
    if not name then
        return false;
    end
    
    MMC.Hooks.TARGET_SlashCmd(name);
    return true;
end

-- Does the given action with a set of conditionals provided by the given msg
-- msg: The conditions followed by the action's parameters
-- hook: The hook of the function we've intercepted
-- fixEmptyTargetFunc: A function setting the player's target if the player has none. Required to return true if we need to re-target later or false if not
-- targetBeforeAction: A boolean value that determines whether or not we need to target the target given in the conditionals before performing the given action
-- action: A function that is being called when everything checks out
function MMC.DoWithConditionals(msg, hook, fixEmptyTargetFunc, targetBeforeAction, action)
    local msg, conditionals = MMC.parseMsg(msg);
    
    -- trim leading and trailing white spaces
    msg = gsub(msg,"^%s*(.-)%s*$","%1");
    
    -- No conditionals. Just exit.
    if not conditionals then
        if not msg then
            return false;
        else
            if string.sub(msg, 1, 1) == "{" and string.sub(msg, -1) == "}" then
                return MMC.ExecuteMacroByName(string.sub(msg, 2, -2));
            end
            
            if hook then
                hook(msg);
            end
            return true;
        end
    end
    
    if conditionals.target == "mouseover" then
        if not UnitExists("mouseover") then
            conditionals.target = MMC.mouseoverUnit;
        end
        if not conditionals.target or (conditionals.target ~= "focus" and not UnitExists(conditionals.target)) then
            return false;
        end
    end
    
    local needRetarget = false;
    if fixEmptyTargetFunc then
        needRetarget = fixEmptyTargetFunc(conditionals, msg, hook)
    end
    
    MMC.SetHelp(conditionals);
    
    if conditionals.target == "focus" then
        if not MMC.TryTargetFocus() then
            return false;
        end
        conditionals.target = "target";
        needRetarget = true;
    end
    
    for k, v in pairs(conditionals) do
        if not MMC.Keywords[k] or not MMC.Keywords[k](conditionals) then
            if needRetarget then
                TargetLastTarget();
                needRetarget = false;
            end
            return false;
        end
    end
    
    if targetBeforeAction then
        if not UnitIsUnit("target", conditionals.target) then
            needRetarget = true;
        end
        
        TargetUnit(conditionals.target);
    else
        if needRetarget then
            TargetLastTarget();
            needRetarget = false;
        end
    end
    
    local result = true;
    if string.sub(msg, 1, 1) == "{" and string.sub(msg, -1) == "}" then
        result = MMC.ExecuteMacroByName(string.sub(msg, 2, -2));
    else
        action(msg);
    end
    
    if needRetarget then
        TargetLastTarget();
    end
    
    return result;
end

-- Attempts to cast a single spell from the given set of conditional spells
-- msg: The player's macro text
function MMC.DoCast(msg)
    local handled = false;
    for k, v in pairs(MMC.splitString(msg, ";%s*")) do
        if MMC.DoWithConditionals(v, MMC.Hooks.CAST_SlashCmd, MMC.FixEmptyTarget, true, CastSpellByName) then
            handled = true; -- we parsed at least one command
            break;
        end
    end
    return handled;
end

-- Attempts to target a unit by its name using a set of conditionals
-- msg: The raw message intercepted from a /target command
function MMC.DoTarget(msg)
    local handled = false;
    
    local action = function(msg)
        if string.sub(msg, 1, 1) == "@" then
            msg = UnitName(string.sub(msg, 2));
        end
        
        MMC.Hooks.TARGET_SlashCmd(msg);
    end
    
    for k, v in pairs(MMC.splitString(msg, ";%s*")) do
        if MMC.DoWithConditionals(v, MMC.Hooks.TARGET_SlashCmd, MMC.FixEmptyTargetSetTarget, false, action) then
            handled = true;
            break;
        end
    end
    return handled;
end

-- Attempts to attack a unit by a set of conditionals
-- msg: The raw message intercepted from a /petattack command
function MMC.DoPetAttack(msg)
    local handled = false;
    for k, v in pairs(MMC.splitString(msg, ";%s*")) do
        if MMC.DoWithConditionals(v, nil, MMC.FixEmptyTarget, true, PetAttack) then
            handled = true;
            break;
        end
    end
    return handled;
end

-- Searches for the given itemName in the player's iventory
-- itemName: The name of the item to look for
-- returns: The bag number and the slot number if the item has been found. nil otherwhise
function MMC.FindItem(itemName)
    MMCTooltip:SetOwner(WorldFrame, "ANCHOR_NONE");
    for i = 0, 4 do
        for j = 1, GetContainerNumSlots(i) do
            MMCTooltip:ClearLines();
            MMCTooltip:SetBagItem(i, j);
            if MMCTooltipTextLeft1:GetText() == itemName then
                return i, j;
            end
        end
    end
    
    for i = 0, 19 do
        MMCTooltip:ClearLines();
        hasItem = MMCTooltip:SetInventoryItem("player", i);
        
        if hasItem and MMCTooltipTextLeft1:GetText() == itemName then
            return -i;
        end
    end
end

-- Attempts to use or equip an item from the player's inventory by a  set of conditionals
-- msg: The raw message intercepted from a /use or /equip command
function MMC.DoUse(msg)
    local handled = false;
    
    local action = function(msg)
        local bag, slot = MMC.FindItem(msg);
        
        if bag and bag < 0 then
            return UseInventoryItem(-bag);
        end
        
        if not bag or not slot then
            return;
        end
        UseContainerItem(bag, slot);
    end
    
    for k, v in pairs(MMC.splitString(msg, ";%s*")) do
        if MMC.DoWithConditionals(v, action, MMC.FixEmptyTarget, true, action) then
            handled = true;
            break;
        end
    end
    return handled;
end

function MMC.DoEquipOffhand(msg)
    local handled = false;
    
    local action = function(msg)
        local bag, slot = MMC.FindItem(msg);
        if not bag or not slot then
            return;
        end
        PickupContainerItem(bag, slot);
        PickupInventoryItem(17);
    end
    
    for k, v in pairs(MMC.splitString(msg, ";%s*")) do
        if MMC.DoWithConditionals(v, action, MMC.FixEmptyTarget, true, action) then
            handled = true;
            break;
        end
    end
    return handled;
end

function MMC.DoUnshift(msg)
    local handled;
    
    local action = function(msg)
        local currentShapeshiftIndex = MMC.GetCurrentShapeshiftIndex();
        if currentShapeshiftIndex ~= 0 then
            CastShapeshiftForm(currentShapeshiftIndex);
        end
    end
    
    for k, v in pairs(MMC.splitString(msg, ";%s*")) do
        handled = false;
        if MMC.DoWithConditionals(v, action, MMC.FixEmptyTarget, true, action) then
            handled = true;
            break;
        end
    end
    
    if handled == nil then
        action();
    end
    
    return handled;
end

-- Holds information about the currently cast spell
MMC.CurrentSpell = {
    -- "channeled" or "cast"
    type = "",
    -- the name of the spell
    spellName = "",
    -- is the Attack ability enabled
    autoAttack = false,
    -- is the Auto Shot ability enabled
    autoShot = false,
    -- is the Shoot ability (wands) enabled
    wand = false,
};

-- Dummy Frame to hook ADDON_LOADED event in order to preserve compatiblity with other AddOns like SuperMacro
MMC.Frame = CreateFrame("FRAME");
MMC.Frame:RegisterEvent("ADDON_LOADED");
MMC.Frame:RegisterEvent("SPELLCAST_CHANNEL_START");
MMC.Frame:RegisterEvent("SPELLCAST_CHANNEL_STOP");
MMC.Frame:RegisterEvent("SPELLCAST_INTERRUPTED");
MMC.Frame:RegisterEvent("SPELLCAST_FAILED");
MMC.Frame:RegisterEvent("PLAYER_ENTER_COMBAT");
MMC.Frame:RegisterEvent("PLAYER_LEAVE_COMBAT");
MMC.Frame:RegisterEvent("START_AUTOREPEAT_SPELL");
MMC.Frame:RegisterEvent("STOP_AUTOREPEAT_SPELL");

MMC.Frame:SetScript("OnEvent", function()
    MMC.Frame[event]();
end);

function MMC.Frame.ADDON_LOADED()
    if event ~= "ADDON_LOADED" then
        return;
    end
    
    if arg1 == "CastModifier" then
        MMC.InitializeExtensions();
        return;
    end
    
    if arg1 ~= "SuperMacro" then
        return;
    end
    
    local hooks = {
        cast = { action = MMC.DoCast, },
        target = { action = MMC.DoTarget, },
        use = { action = MMC.DoUse, },
    };
    
    -- Hook SuperMacro's RunLine to stay compatible
    MMC.Hooks.RunLine = RunLine;
    MMC.RunLine = function(...)
        for i = 1, arg.n do
            local intercepted = false;
            local text = arg[i];
            
            for k,v in pairs(hooks) do
                local begin, _end = string.find(text, "^/"..k.."%s+[!%[]");
                if begin then
                    local msg = string.sub(text, _end);
                    v.action(msg);
                    intercepted = true;
                end
            end
            
            if not intercepted then
                MMC.Hooks.RunLine(text);
            end
        end
    end
    RunLine = MMC.RunLine;
end

function MMC.Frame.SPELLCAST_CHANNEL_START()
    MMC.CurrentSpell.type = "channeled";
end

function MMC.Frame.SPELLCAST_CHANNEL_STOP()
    MMC.CurrentSpell.type = "";
    MMC.CurrentSpell.spellName = "";
end

MMC.Frame.SPELLCAST_INTERRUPTED = MMC.Frame.SPELLCAST_CHANNEL_STOP;
MMC.Frame.SPELLCAST_FAILED = MMC.Frame.SPELLCAST_CHANNEL_STOP;

function MMC.Frame.PLAYER_ENTER_COMBAT()
    MMC.CurrentSpell.autoAttack = true;
end

function MMC.Frame.PLAYER_LEAVE_COMBAT()
    MMC.CurrentSpell.autoAttack = false;
end

function MMC.Frame.START_AUTOREPEAT_SPELL(...)
    local _, className = UnitClass("player");
    if className == "HUNTER" then
        MMC.CurrentSpell.autoShot = true;
    else
        MMC.CurrentSpell.wand = true;
    end
end

function MMC.Frame.STOP_AUTOREPEAT_SPELL(...)
    local _, className = UnitClass("player");
    if className == "HUNTER" then
        MMC.CurrentSpell.autoShot = false;
    else
        MMC.CurrentSpell.wand = false;
    end
end


MMC.Hooks.SendChatMessage = SendChatMessage;

function SendChatMessage(msg, ...)
    if msg and string.find(msg, "^#showtooltip ") then
        return;
    end
    MMC.Hooks.SendChatMessage(msg, unpack(arg));
end