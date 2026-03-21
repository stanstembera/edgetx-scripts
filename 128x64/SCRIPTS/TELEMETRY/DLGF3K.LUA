--[[

  ============================
  ===  D L G    T R A C E  ===
  ============================

rev 2.1   06/15/2015
	J.W.G.  (filago on RCGroups)

rev 2.2 10/09/2016
	A.A. Costerus

rev 2.3 11/21/2021
  Stanley J. Stembera

  LUA Script for OpenTX to graph altitude vs time with DLG launch.
  X-axis will automatically re-scale by +33% seconds if the max is reached.
  Y-axis will automatically re-scale by +5 m if the max is reached.

  The graph code is leveraged from an openTX script.
  There are no other files required (such as BMP images) to run this script.

  128x64
 
--]]

--  ================================
--	  variables for user to adjust
--  ================================
local settings = {
	yMaxInit = 40,		-- initial max altitude on graph (m)
	xMaxInit = 30,		-- initial max time on graph (seconds)
	tresholdAlt = 2,	-- altitude threshold for starting and stopping the flight (m)
	saveLog = true,		-- true = to write LOGs, false disable
	audioState = true	-- true = beep when state changes 
}

--  ================================
--	  hardware variables / switch
--  ================================
local hardware = {
	launchSwitch = "sc",	-- alter to your specific needs (SA, SB, SC, SD ....), depends on your Tx hardware
}

local function safeGetFieldId(name)
	local info = getFieldInfo(name)
	return info and info.id or 0
end

local function sensorExists(name)
	return getFieldInfo(name) ~= nil
end

local hasGps = sensorExists("GSpd")

local field = {
	altId = safeGetFieldId("Alt"),
	vspdId = safeGetFieldId("VSpd"),
	rxBtId = safeGetFieldId("RxBt"),
	gspdId = safeGetFieldId("GSpd"),
	launchSwitchId = safeGetFieldId(hardware.launchSwitch)
}

local display = {
	gLeft	= 14,				-- starting column of graph
	gWidth	= 92,				-- width of graph data area, and array size
	gRight	= 106,				-- ending column of graph
	alts = {},					-- storage for graphed altitude values
	index,						-- array index position
	xMax,						-- X-axis max value (sec)
	xScale,						-- X-axis marker interval (m)
	xSpeed,						-- X-axis speed (pixels/second)
	y,							-- temp use for calculating Y coordinate
	yMax,						-- Y-axis max value (m)
	yScale						-- Y-axis marker interval (sec)
}

local value = {
	time = {
		start = 0,				-- time at start of flight
		hook = 0,				-- time at hook release
		duration,				-- duration of each flight
		lap,					-- lap time
		current,				-- current time
		takeOff,				-- take off date
		landing					-- landing date
	},
	alt = {
		launch	= 0,			-- top of launch
		max,					-- maximum altitude during flight
		current 				-- current altitude
	},
	lnchnr = 0,					-- launch counter
	swSR,						-- start / reset switch value from Tx (<0 is UP for launch mode)
	rxBt,						-- Rx battery voltage value
	state = 0,					-- program state : 0=init/stop, 1=ready, 2=launch climb, 3=gliding
	gSpd = 0,					-- current GPS speed (km/h)
	gSpdMax = 0					-- maximum GPS speed during flight (km/h)
}

logBook = {}				-- share flight results with logbook script (global for RESULT.LUA)

local round = function(number, decimals)
  local mult = 10^(decimals or 0)
  return math.floor(number * mult + 0.5) / mult
end

decimalZero = function(number)
  return string.format("%02.01f", number)
end

local getSensorName = function(i)
	return model.getSensor(i).name
end

local resetBaro = function()
  for i = 0, 31 do
    local name = getSensorName(i)

    if string.lower(name) == "alt" then
      model.resetSensor(i)
      break
    end
  end
end

local quickSort
quickSort = function(array, le, ri)
    if ri-le < 1 then 
        return array
    end

    local left = le
    local right =  ri
    local pivot = math.random( le, ri )

    array[pivot], array[right] = array[right], array[pivot]

    for i = le, ri do
        if array[i] > array[right] then
            array[left], array[i] = array[i], array[left]

            left = left + 1
        end
    end

    array[left], array[right] = array[right], array[left]

    quickSort(array, le, left-1)
    quickSort(array, left+1, ri)

    return array
end

local writeLog = function()
	local leadZero = function(number) return string.format("%02d", number) end
	local takeOff = value.time.takeOff
	local landing = value.time.landing
  	local fileName = "/LOGS/"..model.getInfo().name.."-LogBook-"..takeOff.year.."-"..takeOff.mon.."-"..takeOff.day..".csv"
  	local file = io.open(fileName, "r")
	local newFile = true

	if file ~= nil then
		newFile = false
		io.close(file)
	end
	
	file = io.open(fileName, "a") 
  
	if newFile then io.write(file, "Date,TakeOff,Land,FlightNo,LaunchAltitude,MaxAltitude,MaxSpeed,Duration,Lap,AltGraph\r\n") end

	local date = takeOff.year.."-"..leadZero(takeOff.mon).."-"..leadZero(takeOff.day)
	local takeOff = leadZero(takeOff.hour)..":"..leadZero(takeOff.min)..":"..leadZero(takeOff.sec)
	local land = leadZero(landing.hour)..":"..leadZero(landing.min)..":"..leadZero(landing.sec)
	local flightNumber = value.lnchnr
	local launchAltitude = decimalZero(value.alt.launch)
	local maxAltitude = decimalZero(value.alt.max)
	local maxSpeed = decimalZero(value.gSpdMax)
	local duration = decimalZero(value.time.duration)
	local lap = decimalZero(value.time.lap)
	local altGraph = ""
	for i = 1, #display.alts do
		if i > 1 then altGraph = altGraph .. "_" end
		altGraph = altGraph .. round(display.alts[i], 2)
	end

	io.write(file, date..","..takeOff..","..land..","..flightNumber..","..launchAltitude..","..maxAltitude..","..maxSpeed..","..duration..","..lap..","..altGraph.."\r\n")
  	io.close(file)
end

local beep = function(length)
	if settings.audioState then
		playTone(1500, length, 0, PLAY_NOW)
	end
end

local displayValues = function()
	local altitude = value.alt.max
	local xLaunch = 108
	local rxBtBlink = MIDSIZE
	
	if value.state > 1 then														-- if in a flight state
		value.time.duration = value.time.current - value.time.start				-- calculate the flight duration (sec)
		if value.state == 3 then
			value.time.lap = value.time.current - value.time.start - value.time.hook
		end
		value.alt.max = math.max(value.alt.current, value.alt.max)				-- update maximum altitude
		if hasGps then
			value.gSpdMax = math.max(value.gSpd, value.gSpdMax)				-- update maximum GPS speed
		end
		altitude = value.alt.current
  	end

	if value.state == 2 then									-- if state is "launch climb"
		value.alt.launch = value.alt.current					-- update launch altitude with current alt
	end

	if value.alt.launch < 100 then xLaunch = 112 end			-- shift altitude value right 

	if value.rxBt < 5 then
		rxBtBlink = MIDSIZE+BLINK
	end

	lcd.drawNumber(xLaunch, 26, math.modf(value.alt.launch), MIDSIZE)
	lcd.drawNumber(112, 0, value.lnchnr, MIDSIZE+INVERS)
	lcd.drawText(15, 0, decimalZero(altitude).."m", MIDSIZE)
	lcd.drawText(112, 18, "LnA", SMLSIZE)
	lcd.drawText(112, 44, "RxB", SMLSIZE)
	lcd.drawText(110, 52, decimalZero(value.rxBt), rxBtBlink)	-- get voltage from the Tx
  	lcd.drawText(15, 57, decimalZero(value.time.duration).."s", SMLSIZE)
	lcd.drawText(15, 18, decimalZero(value.time.lap).."s", MIDSIZE)

	if value.state == 0 then
		lcd.drawText(18, 38, "[ ENTER long ] setup", SMLSIZE+INVERS)
	end
end

local rescaleX = function()
	if display.index > display.gWidth  then		-- if graph is full,

		local j = 1						-- temporary index number for compacted array
		for i = 1, display.gWidth do					-- compact the array, skipping every 4th point
			if i % 4 ~= 0 then				-- if not every 4th point
				display.alts[j] = display.alts[i]			-- copy to compacted array
				j = j + 1					-- increment j
			end
		end

		for i= j, display.gWidth do					-- reset the "empty" data at the end so it doesn't plot
			display.alts[i] = -10
		end

		display.index = j						-- set index to first "empty" location
		display.xMax = display.xMax * 4/3					-- new graph max time (sec)
		display.xSpeed = display.gWidth/display.xMax					-- new graph speed (pixels/sec)

		-- check the scale marker count, and adjust if needed
		display.xScale = 10						-- start with marker interval = 10 seconds
		while display.xMax/display.xScale > 7 do				-- as long as there would be more than 7 of them
			display.xScale = display.xScale + 10				-- increase the marker interval by 10 seconds
		end
	end
end

local rescaleY = function()
	if value.state > 1 and value.alt.current > display.yMax then	--  if "in flight" and altitude reaches top of graph
		display.yMax = display.yMax+10							-- add 10 m to top of graph

		-- check the scale marker count, and adjust if needed
		display.yScale = 10						-- start with marker interval = 10 m
		while display.yMax/display.yScale > 6 do				-- as long as there would be more than 6 of them
			display.yScale = display.yScale*2				-- double the marker interval
		end
	end
end

local displayAltitudeData = function()
	value.time.current = getTime()/100							-- get current time (seconds since radio started)

	if value.state > 1 and value.time.current > (value.time.start + display.index/display.xSpeed) then 			-- if "in flight" AND enough time has elapsed,
		display.alts[display.index] = value.alt.current						-- add current altitude to array
		display.index = display.index + 1							-- increment the index
	end
end

local drawGraph = function()
	for i = 1, display.gWidth do
		if display.alts[i] > -10 then
			local y = 64*(display.alts[i]-display.yMax)/(0-display.yMax)					-- calculate Y coordinate for graph point
			if y < 63 then								-- don't draw if below graph, because grey point overwrites bottom line.
				lcd.drawLine(display.gLeft+i, y, display.gLeft+i, 62, SOLID, 0)	--  draw grey line down from altitude
			end
		end
	end
end

local drawStaticElements = function()
	for i = display.yScale, display.yMax, display.yScale do						-- create Y-axis scale
		local y = 64*(i-display.yMax)/(0-display.yMax)				-- calculate y coordinates
		if y-3 > 2 then							-- if number will fit on screen
			lcd.drawNumber(0, y-3, i, SMLSIZE)			-- draw graph scale number
		end
		if y > 2 then							-- if horizonal line is below top of graph
			lcd.drawLine(display.gLeft+1, y, display.gRight, y, DOTTED, 0)	-- draw horizontal line
		end
	end
end

--  ================================
--	  switch detection & config
--  ================================
local switches = {}
for _, name in ipairs({"sa","sb","sc","sd","se","sf","sg","sh"}) do
	local info = getFieldInfo(name)
	if info then
		switches[#switches+1] = { name = name, id = info.id }
	end
end

local setupMode = false
local setupStep = 1					-- 1=switch, 2=position, 3=stop mode
local switchIndex = 1
local positions = {"up", "down"}
local positionIndex = 1					-- 1=up, 2=down
local launchPosition = "up"				-- which switch position activates launch ("up"=swSR>0, "down"=swSR<0)
local stopModes = {"alt", "sw"}
local stopModeIndex = 1					-- 1=alt, 2=sw
local stopMode = "alt"					-- "alt"=altimeter landing detection, "sw"=manual switch stop
local CONFIG_PATH = "/SCRIPTS/TELEMETRY/DLGF3K.cfg"

local function findSwitchIndex(name)
	for i, sw in ipairs(switches) do
		if sw.name == name then return i end
	end
	return nil
end

local function findOptionIndex(list, val)
	for i, v in ipairs(list) do
		if v == val then return i end
	end
	return 1
end

local function loadConfig()
	local file = io.open(CONFIG_PATH, "r")
	if file then
		local data = io.read(file, 128)
		io.close(file)
		if data then
			local name, pos, smode = string.match(data, "(%S+)%s+(%S+)%s*(%S*)")
			if not name then
				name = string.gsub(data, "%s+", "")
			end
			if name then
				local idx = findSwitchIndex(name)
				if idx then
					switchIndex = idx
					hardware.launchSwitch = name
					field.launchSwitchId = safeGetFieldId(name)
				end
			end
			if pos and (pos == "up" or pos == "down") then
				launchPosition = pos
				positionIndex = findOptionIndex(positions, pos)
			end
			if smode and (smode == "alt" or smode == "sw") then
				stopMode = smode
				stopModeIndex = findOptionIndex(stopModes, smode)
			end
			return
		end
	end
	local idx = findSwitchIndex(hardware.launchSwitch)
	if idx then
		switchIndex = idx
	elseif #switches > 0 then
		switchIndex = 1
		hardware.launchSwitch = switches[1].name
		field.launchSwitchId = switches[1].id
	end
end

local function saveConfig()
	local file = io.open(CONFIG_PATH, "w")
	if file then
		io.write(file, hardware.launchSwitch.."\n"..launchPosition.."\n"..stopMode)
		io.close(file)
	end
end

local function drawSetup()
	lcd.clear()
	lcd.drawText(14, 0, "DLG SETUP", DBLSIZE)

	local swStyle = setupStep == 1 and INVERS or 0
	local posStyle = setupStep == 2 and INVERS or 0
	local stopStyle = setupStep == 3 and INVERS or 0

	lcd.drawText(4, 18, "Switch:", SMLSIZE)
	local name = string.upper(switches[switchIndex].name)
	lcd.drawText(50, 17, name, MIDSIZE+swStyle)

	lcd.drawText(4, 32, "Launch:", SMLSIZE)
	local posLabel = string.upper(positions[positionIndex])
	lcd.drawText(50, 31, posLabel, MIDSIZE+posStyle)

	lcd.drawText(4, 46, "Stop:", SMLSIZE)
	local stopLabel = string.upper(stopModes[stopModeIndex])
	lcd.drawText(50, 45, stopLabel, MIDSIZE+stopStyle)

	lcd.drawText(4, 57, "[+/-] change", SMLSIZE)
	lcd.drawText(76, 57, "[ENT] next", SMLSIZE)
end

loadConfig()

--  ==============
--	  initialize
--  ==============
local function init()			-- intialize values
	for i = 1, display.gWidth do
		display.alts[i] = -10			-- set altitude array values to be below the visible graph range
	end
	display.xMax = settings.xMaxInit				-- set X-axis max value (sec)
	display.xSpeed = display.gWidth/display.xMax		-- set X-axis speed (pixels/second)
	display.xScale = 5					-- set X-axis marker interval (s)
	display.yMax = settings.yMaxInit				-- set Y-axis max value (m)
	display.yScale = 10					-- set Y-axis marker interval (sec)
	display.index = 1					-- set initial array position
	value.alt.launch = 0					-- reset flight launch altitude
	value.alt.max = 0					-- reset flight max altitude
	value.time.duration = 0					-- reset flight duration
	value.time.lap = 0					-- reset lap time
	value.gSpdMax = 0					-- reset max GPS speed
  	resetBaro()					-- reset barometric sensor
end

--  =======
--	  run
--  =======
local function run(event)				-- this function will run until it is stopped

	-- setup mode handling
	if setupMode then
		if event == EVT_VIRTUAL_INC or event == EVT_VIRTUAL_INC_REPT
				or event == EVT_PLUS_BREAK or event == EVT_PLUS_REPT then
			if setupStep == 1 then
				switchIndex = switchIndex < #switches and switchIndex + 1 or 1
			elseif setupStep == 2 then
				positionIndex = positionIndex < #positions and positionIndex + 1 or 1
			else
				stopModeIndex = stopModeIndex < #stopModes and stopModeIndex + 1 or 1
			end
		elseif event == EVT_VIRTUAL_DEC or event == EVT_VIRTUAL_DEC_REPT
				or event == EVT_MINUS_BREAK or event == EVT_MINUS_REPT then
			if setupStep == 1 then
				switchIndex = switchIndex > 1 and switchIndex - 1 or #switches
			elseif setupStep == 2 then
				positionIndex = positionIndex > 1 and positionIndex - 1 or #positions
			else
				stopModeIndex = stopModeIndex > 1 and stopModeIndex - 1 or #stopModes
			end
		elseif event == EVT_VIRTUAL_ENTER or event == EVT_ENTER_BREAK then
			if setupStep < 3 then
				setupStep = setupStep + 1
			else
				hardware.launchSwitch = switches[switchIndex].name
				field.launchSwitchId = switches[switchIndex].id
				launchPosition = positions[positionIndex]
				stopMode = stopModes[stopModeIndex]
				saveConfig()
				beep(200)
				setupStep = 1
				setupMode = false
			end
		elseif event == EVT_VIRTUAL_EXIT or event == EVT_EXIT_BREAK then
			switchIndex = findSwitchIndex(hardware.launchSwitch)
			positionIndex = findOptionIndex(positions, launchPosition)
			stopModeIndex = findOptionIndex(stopModes, stopMode)
			setupStep = 1
			setupMode = false
		end
		drawSetup()
		return 0
	end

	-- long-press ENTER to open setup (only in idle state)
	if (event == EVT_VIRTUAL_ENTER_LONG or event == EVT_ENTER_LONG) and value.state == 0 then
		setupMode = true
		killEvents(EVT_ENTER_BREAK)
		drawSetup()
		return 0
	end

	lcd.clear()						-- clear the display
	
	value.swSR = getValue(field.launchSwitchId)				-- get value of launch switch (Tx launch mode)
	value.alt.current = getValue(field.altId)				-- get current altitude from vario (m)
	local vspd = getValue(field.vspdId)						-- get current vertical speed (m/s)
	value.rxBt = getValue(field.rxBtId)						-- get current RxBt voltage
	if hasGps then
		value.gSpd = getValue(field.gspdId)					-- get current GPS speed (km/h)
	end

--  ----------------------------------
--	  change program state
--  ----------------------------------

	local launchOn = (launchPosition == "up" and value.swSR > 0) or (launchPosition == "down" and value.swSR < 0)
	local launchOff = (launchPosition == "up" and value.swSR < 0) or (launchPosition == "down" and value.swSR > 0)

	if value.state == 0 and launchOn then					-- if launch switch was moved to launch mode from "init/stop" state
		init()								-- reset graph data & scale
		beep(250)
		value.state = 1						-- change state to "ready"
		elseif value.state == 1 and launchOff then				-- if launch mode is ended without a flight
			value.state = 0						-- change state to "stop"
		elseif value.state == 1 and value.alt.current > settings.tresholdAlt then			-- if launch detected in "ready" state
			value.time.start = getTime()/100				-- set flight start time (seconds)
			value.time.takeOff = getDateTime()
			display.alts[1] = value.alt.current					-- set first altitude point
			display.index = 2						-- set index for 2nd alt point
			value.state = 2						-- change state to "launch climb"
			value.lnchnr = value.lnchnr + 1					-- increment the launch number
			model.setTimer(0,{mode=1})			-- unlock lap timer
		elseif value.state == 2 and value.alt.current < value.alt.max and value.alt.current > 2*settings.tresholdAlt then			-- if in "launch climb" and altitude decreases
			value.time.hook = value.time.current - value.time.start				-- set release hook time
			value.alt.launch = value.alt.max					-- set launch altitude
			value.state = 3						-- set state = "gliding"
			beep(1000)
		elseif value.state > 1 and ((stopMode == "alt" and value.alt.current < settings.tresholdAlt-1 and launchOff) or (stopMode == "sw" and launchOff)) then	-- landing detection
			value.state = 0						-- change state to "stop"
			beep(500)
			if settings.saveLog then
				value.time.landing = getDateTime()
				writeLog() -- landing, write to SD
			end
			logBook[value.lnchnr] = value.time.lap
			quickSort(logBook, 1, #logBook)
	end

	rescaleY()
	drawStaticElements()
	displayAltitudeData()
	drawGraph()
	rescaleX()
	displayValues()
end

return { init=init, run=run }
