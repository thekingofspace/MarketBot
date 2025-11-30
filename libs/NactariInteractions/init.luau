exposedbots =  exposedbots or {}
CreationBoot = CreationBoot or {}
ExposedMethods = ExposedMethods or {}
export type BotOverload = {
    Test:boolean
}

ExposedMethods.RegisterCommand = function(self, name, handler)
    if not self.__Commands then
        self.__Commands = {}
    end
    self.__Commands[name] = handler
end

ExposedMethods.HandleCommand = function(self, message)
    if not self.__Commands then return false end
    
    local prefix = self.__CommandPrefix or "!"
    if message.content:sub(1, #prefix) ~= prefix then
        return false
    end
    
    local args = message.content:sub(#prefix + 1):split(" ")
    local commandName = table.remove(args, 1)
    
    if self.__Commands[commandName] then
        self.__Commands[commandName](message, args)
        return true
    end
    
    return false
end

table.insert(CreationBoot, function(bot)
    bot.__Commands = {}
    bot.__CommandPrefix = "!"
    
    bot:On("message_create", function(message)
        if not message.author.bot then
            bot:HandleCommand(message)
        end
    end)
end)

ExposedMethods.GetStats = function(self)
    return {
        reconnects = self.__ReconnectCount or 0,
        events = self.__EventCount or 0,
        commands = self.__CommandCount or 0,
        uptime = os.time() - (self.__StartTime or os.time())
    }
end

table.insert(CreationBoot, function(bot)
    bot.__ReconnectCount = 0
    bot.__EventCount = 0
    bot.__CommandCount = 0
    bot.__StartTime = os.time()
    
    bot:On("resume", function()
        bot.__ReconnectCount += 1
    end)
    
    bot:On("signal_step", function()
        bot.__EventCount += 1
    end)
    
    local originalRegister = ExposedMethods.RegisterCommand
    ExposedMethods.RegisterCommand = function(self, name, handler)
        return originalRegister(self, name, function(...)
            self.__CommandCount += 1
            return handler(...)
        end)
    end
end)

local module = {}

return module