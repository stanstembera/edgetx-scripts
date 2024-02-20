local function init()
end

local function run(event)
    lcd.clear()
    local i = 0
    for _,v in pairs(logBook) do
        lcd.drawText(1, i*13, decimalZero(v).."s", MIDSIZE)
        i = i + 1
        if i == 5 then
            break
        end
    end
    if i == 0 then
        lcd.drawText(12,32, "No flights recorded yet", SMLSIZE)
    end
end

return {init=init, run=run}