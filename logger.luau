local Logger = {}
Logger.Levels = {
    INFO = 1,
    WARN = 2,
    ERROR = 3,
    DEBUG = 4
}

local Colors = {
    INFO = "\27[1m\27[32m",
    WARN = "\27[1m\27[33m",
    ERROR = "\27[1m\27[31m",
    DEBUG = "\27[1m\27[34m",
    RESET = "\27[0m",
}

Logger.CurrentLevel = Logger.Levels.INFO

local function now()
    return os.date("%H:%M:%S")
end

function Logger:Log(level, ...)
    if self.Levels[level] < self.CurrentLevel then return end

    local Color = Colors[level]
    local Reset = Colors.RESET

    local Tag = ("[%s%s%s] -"):format(Color, level, Reset)

    print(("[%s] %s"):format(now(), Tag), ...)
end

function Logger:Info(...)
    self:Log("INFO", ...)
end

function Logger:Warn(...)
    self:Log("WARN", ...)
end

function Logger:Error(...)
    self:Log("ERROR", ...)
end

function Logger:Debug(...)
    self:Log("DEBUG", ...)
end

return Logger
