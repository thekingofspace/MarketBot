local UsedLibraries = {
    { "Nactari", "1.0.0" },
    { "NactariDependants", "1.0.0" },
}

table.insert(CreationBoot, function(self)
    if not self.UsedLibraries then
        error("MISSING NACTARI DEPENDANTS")
    end

    self:On("Start", function()
        for _, dep in ipairs(UsedLibraries) do
            self:HasLibrary(dep)
        end
    end)
    
    :Catch(function(err)
        warn(err)
    end)
end)

return true
