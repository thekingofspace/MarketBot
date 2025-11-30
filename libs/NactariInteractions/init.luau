exposedbots =  exposedbots or {}
CreationBoot = CreationBoot or {}
export type BotOverload = {
    
}

table.insert(CreationBoot, function(self)
    self.Test = true
end)

local Module = {}

return Module