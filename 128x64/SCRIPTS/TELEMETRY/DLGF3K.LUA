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

local field = {
	altId = getFieldInfo("Alt").id,
	vspdId = getFieldInfo("VSpd").id,
	rxBtId = getFieldInfo("RxBt").id,
	launchSwitchId = getFieldInfo(hardware.launchSwitch).id
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
	state = 0					-- program state : 0=init/stop, 1=ready, 2=launch climb, 3=gliding
}

logBook = {}					-- share flight results with logbook script

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

    if name == "alt" then
      model.resetSensor(i)
      break
    end
  end
end

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

    quickSort(array, 1, left-1)
    quickSort(array, left +1, ri)

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
  
	if newFile then io.write(file, "Date,TakeOff,Land,FlightNo,LaunchAltitude,MaxAltitude,Duration,Lap,AltGraph\r\n") end
	
	local date = takeOff.year.."-"..leadZero(takeOff.mon).."-"..leadZero(takeOff.day)
	local takeOff = leadZero(takeOff.hour)..":"..leadZero(takeOff.min)..":"..leadZero(takeOff.sec)
	local land = leadZero(landing.hour)..":"..leadZero(landing.min)..":"..leadZero(landing.sec)
	local flightNumber = value.lnchnr
	local launchAltitude = decimalZero(value.alt.launch)
	local maxAltitude = decimalZero(value.alt.max)
	local duration = decimalZero(value.time.duration)
	local lap = decimalZero(value.time.lap)
	local altGraph = ""
	for k,v in pairs(display.alts) do altGraph = altGraph..round(v,2).."_" end
	
	io.write(file, date..","..takeOff..","..land..","..flightNumber..","..launchAltitude..","..maxAltitude..","..duration..","..lap..","..altGraph.."\r\n")
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
	lcd.drawText(112, 52, decimalZero(value.rxBt), rxBtBlink)	-- get voltage from the Tx
  	lcd.drawText(15, 57, decimalZero(value.time.duration).."s", SMLSIZE)
	lcd.drawText(15, 18, decimalZero(value.time.lap).."s", MIDSIZE)
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
		display.yMax = display.yMax+10							-- add 5 m to top of graph

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
		y = 64*(display.alts[i]-display.yMax)/(0-display.yMax)						-- calculate Y coordinate for graph point
		if y < 63 then								-- don't draw if below graph, because grey point overwrites bottom line.
			lcd.drawLine(display.gLeft+i, y, display.gLeft+i, 62, SOLID, 0)	--  draw grey line down from altitude
		end
	end
end

local drawStaticElements = function()
	for i = display.yScale, display.yMax, display.yScale do						-- create Y-axis scale
		y = 64*(i-display.yMax)/(0-display.yMax)					-- calculate y coordinates
		if y-3 > 2 then							-- if number will fit on screen
			lcd.drawNumber(0, y-3, i, SMLSIZE)			-- draw graph scale number
		end
		if y > 2 then							-- if horizonal line is below top of graph
			lcd.drawLine(display.gLeft+1, y, display.gRight, y, DOTTED, 0)	-- draw horizontal line
		end
	end
end

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
  	resetBaro()					-- reset barometric sensor
end

--  =======
--	  run
--  =======
local function run(event)				-- this function will run until it is stopped
	lcd.clear()						-- clear the display
	
	value.swSR = getValue(field.launchSwitchId)				-- get value of launch switch (Tx launch mode)
	value.alt.current = getValue(field.altId)				-- get current altitude from vario (m)
	local vspd = getValue(field.vspdId)						-- get current vertical speed (m/s)					
	value.rxBt = getValue(field.rxBtId)						-- get current RxBt voltage

--  ----------------------------------
--	  change program if needed
--  ----------------------------------
	if value.state == 0 and value.swSR > 0 then					-- if launch switch was moved to launch mode from "init/stop" state
		init()								-- reset graph data & scale
		beep(250)							
		value.state = 1						-- change state to "ready"
		elseif value.state == 1 and value.swSR < 0 then				-- if launch mode is ended without a flight
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
		elseif value.state > 1 and value.alt.current < settings.tresholdAlt-1 and value.swSR < 0 then	-- if "in flight" and altitude drops below X
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
