local ADDON_NAME = "GroupTypingIndicator"
local ADDON_VERSION = 1

local DEBUG_MODE = false

local GROUP_SOCKET_MESSAGE_TYPE = 10
local GROUP_SOCKET_MESSAGE_VERSION = 1

local MESSAGE_PROTOCOL_TYPING = 255
local MESSAGE_PROTOCOL_STOPPED_TYPING = 254

local WINDOW_MANAGER = GetWindowManager()
local GROUP_SOCKET = LibStub("LibGroupSocket")

-- Minimum wait between sending a group message that we are typing.
local TIME_BETWEEN_TYPING_INDICATOR_SENDS = 6000
local lastTypingIndicatorSendTime = 0

-- Need this for sanity
local TIME_BETWEEN_TYPING_END_INDICATOR_SENDS = 1000
local lastTypingEndIndicatorSendTime = 0

-- How long we display the typing indicator for when we receive a group message saying someone is typing.
local TYPING_INDICATOR_LIFETIME = 9000

local recentlyTyping = {}

local function TactiDebug(...) if (DEBUG_MODE) then d(...) end end

local lblTypingIndicator = lblTypingIndicator or nil
local function CreateTypingIndicator()
	lblTypingIndicator = WINDOW_MANAGER:CreateControl("lblTypingIndicator", ZO_ChatWindow, CT_LABEL)
	lblTypingIndicator:SetColor(0.8, 0.8, 0.8, 1)
	lblTypingIndicator:SetFont("$(CHAT_FONT)|$(KB_16)|soft-shadow-thin")
	lblTypingIndicator:SetScale(1)
	lblTypingIndicator:SetWrapMode(TEX_MODE_CLAMP)
	lblTypingIndicator:SetDrawTier(DT_HIGH)
	lblTypingIndicator:SetInheritAlpha(false)
	lblTypingIndicator:SetText("")
	lblTypingIndicator:SetAnchor(BOTTOMLEFT, ZO_ChatWindow, BOTTOMLEFT, 16, 16)
	lblTypingIndicator:SetDimensions(ZO_ChatWindow:GetWidth(), 20)
end

local function SendTypingIndicatorToGroup(isTyping)
	if (not IsUnitGrouped("player")) then return end
	
	local data = {}
	local index = 1
	if (isTyping) then
		index = GROUP_SOCKET:WriteUint8(data, index, MESSAGE_PROTOCOL_TYPING)
	else
		index = GROUP_SOCKET:WriteUint8(data, index, MESSAGE_PROTOCOL_STOPPED_TYPING)
	end
	
	GROUP_SOCKET:Send(GROUP_SOCKET_MESSAGE_TYPE, data)
end

local function RefreshTypingIndicatorText()
	-- "User1 is typing..."
	-- "User1 and User2 are typing..."
	-- "User1, User2 and User3 are typing..."
	-- "Several people are typing..."
	local text = ""
	
	local isFirst = true
	local count = 0
	for unitName in pairs(recentlyTyping) do
		if (isFirst) then
			isFirst = false
		else
			if (next(recentlyTyping, unitName) == nil) then
				text = text .. " and "
			else
				text = text .. ", "
			end
		end
		text = text .. unitName
		count = count + 1
	end
	
	if (count == 1) then
		text = text .. " is typing..."
	end
	if (count > 1) then
		text = text .. " are typing..."
	end
	
	lblTypingIndicator:SetText(text)
	
	if (lblTypingIndicator:GetStringWidth(text) + 20 > lblTypingIndicator:GetWidth()) then
		lblTypingIndicator:SetText("Several people are typing...")
	end
end

local originalChatTextEntryTextChanged
local function ChatTextEntryTextChanged(control, newText)
	originalChatTextEntryTextChanged(control, newText)
	
	local isTyping = (newText ~= "")
	local currentTime = GetGameTimeMilliseconds()
	if (not isTyping) then
		if (currentTime > lastTypingEndIndicatorSendTime + TIME_BETWEEN_TYPING_END_INDICATOR_SENDS) then
			lastTypingEndIndicatorSendTime = currentTime
			lastTypingIndicatorSendTime = currentTime - TIME_BETWEEN_TYPING_INDICATOR_SENDS
			TactiDebug("Sending end typing indicator to group.")
			SendTypingIndicatorToGroup(false)
			return
		end
		return
	end
	
	if (currentTime > lastTypingIndicatorSendTime + TIME_BETWEEN_TYPING_INDICATOR_SENDS) then
		lastTypingIndicatorSendTime = currentTime
		TactiDebug("Sending typing indicator to group.")
		SendTypingIndicatorToGroup(true)
		return
	end
end
local function InitChatTextEntryTextChangedHook()
	originalChatTextEntryTextChanged = ZO_ChatTextEntry_TextChanged
	ZO_ChatTextEntry_TextChanged = ChatTextEntryTextChanged
end

local function EnableGroupSocketSending()
	-- Hack to get LGS to seamlessly work out of the box.
	local originalDebug = d
	d = function (...) end
	SLASH_COMMANDS["/lgs"]("1")
	d = originalDebug
end

local function OnUnitCreated(_, unitTag)
	EnableGroupSocketSending()
end
     
EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_UNIT_CREATED, OnUnitCreated)

local function OnActivated(_, initial)
    EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_PLAYER_ACTIVATED)

	EnableGroupSocketSending()
    CreateTypingIndicator()
	InitChatTextEntryTextChangedHook()
	
	GROUP_SOCKET:RegisterCallback(GROUP_SOCKET_MESSAGE_TYPE, function (unitTag, data, isSelf)
		TactiDebug("Received a GROUP_SOCKET message, unitTag=" .. unitTag .. ", isSelf=" .. (isSelf and "true" or "false") .. ".")
		
		-- Ignore messages we send ourselves
		if (isSelf and not DEBUG_MODE) then return end
		
		local index = 1
		local dataFirstByte, index = GROUP_SOCKET:ReadUint8(data, index)
		if (dataFirstByte == MESSAGE_PROTOCOL_TYPING) then
			-- TODO: Replace with roleplay name eventually when roleplay profiles comes out.
			local unitName = GetUnitName(unitTag)
			recentlyTyping[unitName] = GetGameTimeMilliseconds()
			RefreshTypingIndicatorText()
		elseif (dataFirstByte == MESSAGE_PROTOCOL_STOPPED_TYPING) then
			-- TODO: Replace with roleplay name eventually when roleplay profiles comes out.
			local unitName = GetUnitName(unitTag)
			recentlyTyping[unitName] = nil
			RefreshTypingIndicatorText()
		end
	end)
	
	EVENT_MANAGER:RegisterForUpdate(ADDON_NAME, TIME_BETWEEN_TYPING_INDICATOR_SENDS / 2, function ()
		local currentTime = GetGameTimeMilliseconds()
		for unitName, timestamp in pairs(recentlyTyping) do
			if (currentTime >= timestamp + TYPING_INDICATOR_LIFETIME) then
				recentlyTyping[unitName] = nil
			end
		end
	
		RefreshTypingIndicatorText()
	end)
end
EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_PLAYER_ACTIVATED, OnActivated)

local function OnAddonLoaded()
	local handler, saveData = GROUP_SOCKET:RegisterHandler(GROUP_SOCKET_MESSAGE_TYPE, GROUP_SOCKET_MESSAGE_VERSION)
	if (handler) then
		-- TODO: Maybe we'll have some settings in here.
	end
	handler = GROUP_SOCKET:GetHandler(GROUP_SOCKET_MESSAGE_TYPE)

	EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED)
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddonLoaded)