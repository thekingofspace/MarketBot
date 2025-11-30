local Logger = require("./Logger")
local Discord = require("./libs/Nactari"); require("./libs/NactariInteractions");

local fs, serde = require("@lune/fs"), require("@lune/serde")
local task = require("@lune/task")
local BotInfo:{token:string} = serde.decode("json", fs.readFile("./BotInfo.json"))

local Intent = {
	GUILDS = bit32.lshift(1, 0),
	DIRECT_MESSAGES = bit32.lshift(1, 12),
}

local FinalIntent = 0
for _, v in pairs(Intent) do FinalIntent += v end

local Client = Discord.New(FinalIntent, BotInfo.token, 0, 1)

local AllowedParents = {
    ["1444445784199139458"] = { 
        Identifer = "LF Investors",
        LogChannel = "1444623240222740530",
        RecordChannel = "1444445891409875116";
        MinChars = 100;
        CreationMessage = `Thank you for creating a post! Refer to rules for rules on how posts work!`
    };

    ["1444621799261212755"] = { 
        Identifer = "Help Forums",
        LogChannel = "1444623240222740530",
        RecordChannel = "1444445891409875116";
        MinChars = 30;
        CreationMessage = `Please describe in depth what the issue you are having is.`
    }
}


local QuickRejectReasons = {
    ["AI Generated"] = 
        "Post appears AI-generated\n\nThe writing style, structure, or phrasing strongly resembles common AI-generated patterns, including repetitive wording, overly formal tone, or lack of personal context.",
    ["Low Effort"] = 
        "Low effort / lacks detail\n\nThe message is missing essential information, context, or effort. It may be too short, vague, or provide insufficient detail for others to engage meaningfully.",
    ["Off-Topic"] = 
        "Post is off-topic\n\nThe content does not match the purpose of this section or does not relate to the topic being discussed, creating noise for those seeking relevant posts.",
    ["Spam"] = 
        "Spam / promotional content\n\nThe post contains unsolicited advertising, repeated messages, irrelevant links, or promotional content not permitted in this section.",
    ["Violates Rules"] = 
        "Did not follow section rules\n\nThe post violates one or more of the section's posting requirements, such as missing templates, ignoring formatting guidelines, or breaking behavioral expectations.",
    ["[NA] Contact staff"] = "Contact staff in a ticket for this."
}
local PENDING_FILE = "./pending.json"

local function LoadPending()
    if not fs.isFile(PENDING_FILE) then return {} end
    local ok, data = pcall(serde.decode, "json"::any, fs.readFile(PENDING_FILE))
    return ok and type(data) == "table" and data or {}
end

local function SavePending(tbl)
    fs.writeFile(PENDING_FILE, serde.encode("json", tbl))
end

local PendingRemovals = LoadPending()

local function SetPending(ThreadID, data)
    PendingRemovals[ThreadID] = data
    SavePending(PendingRemovals)
    Logger:Info("Pending added: " .. ThreadID)
end

local function ClearPending(ThreadID)
    PendingRemovals[ThreadID] = nil
    SavePending(PendingRemovals)
    Logger:Info("Pending cleared: " .. ThreadID)
end

local function SendMultipart(Client, Method, Path, PayloadTable, FileName, FileContents)
    local boundary = "--------------------------" .. tostring(math.random(10000000,99999999))
    local payloadJson = serde.encode("json", PayloadTable)
    local body =
        "--" .. boundary .. "\r\n" ..
        'Content-Disposition: form-data; name="payload_json"' .. "\r\n" ..
        "Content-Type: application/json\r\n\r\n" ..
        payloadJson .. "\r\n" ..
        "--" .. boundary .. "\r\n" ..
        'Content-Disposition: form-data; name="files[0]"; filename="' .. FileName .. '"' .. "\r\n" ..
        "Content-Type: text/plain\r\n\r\n" ..
        FileContents .. "\r\n" ..
        "--" .. boundary .. "--\r\n"
    local headers = {
        ["Content-Type"] = "multipart/form-data; boundary=" .. boundary
    }
    return Client:SendContext(Method, Path, body, headers)
end

local function SendDM(UserID, Title, Description, Color, FileName, FileContents)
    local DM = Client:SendContext("Post", "users/@me/channels", { recipient_id = tostring(UserID) })
    if not DM or not DM.id then return end
    local EmbedDescription
    if FileContents and #FileContents <= 1000 then
        EmbedDescription = Description .. "\n\n**Message Content:**\n```" .. FileContents .. "```"
        FileName = nil
        FileContents = nil
    else
        EmbedDescription = Description
    end
    Client:SendContext("Post", `channels/{DM.id}/messages`, {
        embeds = {{
            title = Title,
            description = EmbedDescription,
            color = Color or 0x00AEEF
        }}
    })
    if FileName and FileContents then
        task.spawn(function()
            SendMultipart(
                Client,
                "Post",
                `channels/{DM.id}/messages`,
                { content = "" },
                FileName,
                FileContents
            )
        end)
    end
end

local function RespondEphemeral(Packet, Text)
    return Client:SendContext("Post", `interactions/{Packet.id}/{Packet.token}/callback`, {
        type = 4,
        data = { content = Text, flags = 64 }
    })
end

local function DeletePendingRemoval(ThreadID)
    local Pending = PendingRemovals[ThreadID]
    if not Pending then return end
    Client:SendContext("Delete", `channels/{Pending.channel_id}/messages/{Pending.message_id}`)
    ClearPending(ThreadID)
end

local function OpenRemovalModal(Packet, ThreadID, Prefill)
    return Client:SendContext("Post", `interactions/{Packet.id}/{Packet.token}/callback`, {
        type = 9,
        data = {
            custom_id = "remove_modal_" .. ThreadID,
            title = "Removal Reason",
            components = {{
                type = 1,
                components = {{
                    type = 4,
                    style = 2,
                    custom_id = "remove_reason",
                    label = "Why are you removing this thread?",
                    min_length = 1,
                    max_length = 500,
                    required = true,
                    value = Prefill or nil
                }}
            }}
        }
    })
end

local function HasManageMessages(Packet)
    if not Packet.member or not Packet.member.permissions then
        return false
    end
    local MANAGE_MESSAGES = bit32.lshift(1, 13)
    return bit32.band(Packet.member.permissions, MANAGE_MESSAGES) ~= 0
end

local function RequirePerms(Packet)
    if HasManageMessages(Packet) then
        return true
    end
    Client:SendContext("Post", `interactions/{Packet.id}/{Packet.token}/callback`, {
        type = 4,
        data = {
            content = "You must have **Manage Messages** to use this.",
            flags = 64
        }
    })
    return false
end

local function LogApproval(ThreadID, Approver, RecordChannel)
    Client:SendContext("Post", `channels/{RecordChannel}/messages`, {
        embeds = {{
            title = "Thread Approved",
            description = `Thread <#{ThreadID}> marked as OK.`,
            color = 0x00FF00,
            fields = {{
                name = "Approved By",
                value = Approver and (Approver.username .. " `" .. Approver.id .. "`)") or "Unknown"
            }}
        }}
    })
end

local function HandleApproval(Packet, ThreadID)
    local Pending = PendingRemovals[ThreadID]
    if not Pending then
        return RespondEphemeral(Packet, "Thread data not found.")
    end
    
    DeletePendingRemoval(ThreadID)
    local Approver = Packet.member and Packet.member.user
    LogApproval(ThreadID, Approver, Pending.record_channel)
    return RespondEphemeral(Packet, "Thread approved.")
end

local function HandleRemovalButton(Packet, ThreadID)
    return OpenRemovalModal(Packet, ThreadID)
end

local function RejectThread(ThreadID, Reason, Remover, CategoryName, RecordChannel)
    DeletePendingRemoval(ThreadID)
    local Msgs = Client:SendContext("Get", `channels/{ThreadID}/messages?after=0&limit=1`)
    local First = Msgs[1]
    local FullText = First and First.content or "*Message unavailable*"
    local UseFile = #FullText >= 1000
    
    local CategoryInfo = CategoryName and ("\n\n**Category:** " .. CategoryName) or ""
    
    if First and First.author and First.author.id then
        if UseFile then
            SendDM(
                First.author.id,
                "Post Removed",
                "Your post was removed by a moderator." .. CategoryInfo .. "\n\nReason:\n```" .. Reason .. "```",
                0xFF0000,
                "thread_message_" .. ThreadID .. ".txt",
                FullText
            )
        else
            SendDM(
                First.author.id,
                "Post Removed",
                "Your post was removed by a moderator." .. CategoryInfo .. "\n\nReason:\n```" .. Reason .. "```\n\nMessage Content:\n```" .. FullText .. "```",
                0xFF0000
            )
        end
    end
    
    local RecordEmbed = {
        title = "Thread Removed",
        color = 0xFF0000,
        fields = {
            { name = "Thread", value = `<#{ThreadID}>` },
            { name = "Reason", value = "```\n" .. Reason .. "\n```" },
            { name = "Author", value = First and (First.author.username .. " `" .. First.author.id .. "`)") or "Unknown" },
            { name = "Removed By", value = Remover and (Remover.username .. " `" .. Remover.id .. "`)") or "Unknown" }
        }
    }
    
    if CategoryName then
        table.insert(RecordEmbed.fields, { name = "Category", value = CategoryName })
    end
    
    if UseFile then
        Client:SendContext("Post", `channels/{RecordChannel}/messages`, { embeds = { RecordEmbed } })
        SendMultipart(Client, "Post", `channels/{RecordChannel}/messages`,
            { content = "" },
            "thread_message_" .. ThreadID .. ".txt",
            FullText
        )
    else
        RecordEmbed.fields[#RecordEmbed.fields + 1] = {
            name = "Message Content",
            value = "```\n" .. FullText .. "\n```"
        }
        Client:SendContext("Post", `channels/{RecordChannel}/messages`, { embeds = { RecordEmbed } })
    end
    
    Client:SendContext("Delete", `channels/{ThreadID}`)
end

local function HandleQuickReject(Packet, ThreadID, Key)
    local Reason = QuickRejectReasons[Key] or "No reason provided"
    local Remover = Packet.member and Packet.member.user
    
    local Pending = PendingRemovals[ThreadID]
    if not Pending then
        return RespondEphemeral(Packet, "Thread data not found.")
    end
    
    local CategoryName = Pending.category_name
    local RecordChannel = Pending.record_channel
    
    RespondEphemeral(Packet, "Post removed using quick reject.")
    RejectThread(ThreadID, Reason, Remover, CategoryName, RecordChannel)
    return
end

local function HandleRemovalModal(Packet, ThreadID)
    local Reason = Packet.data.components[1].components[1].value
    local Remover = Packet.member and Packet.member.user
    
    local Pending = PendingRemovals[ThreadID]
    if not Pending then
        return RespondEphemeral(Packet, "Thread data not found.")
    end
    
    local CategoryName = Pending.category_name
    local RecordChannel = Pending.record_channel
    
    RespondEphemeral(Packet, "Processing removal...")
    RejectThread(ThreadID, Reason, Remover, CategoryName, RecordChannel)
    return
end

Client:On("thread_create", function(Packet)
    if Packet.message_count ~= 0 or Packet.last_message_id ~= nil or Packet.newly_created == false then
        return
    end

    local Messages = Client:SendContext("Get", `channels/{Packet.id}/messages?after=0&limit=1`)
    local First = Messages[1]
    local Info = AllowedParents[tostring(Packet.parent_id)]
    if not Info then return end

    local msg = First and First.content or "*No starting message*"
    local author = First.author
    local ThreadID = tostring(Packet.id)
    local ThreadTitle = Packet.name or "Untitled Thread"
    local UseFile = #msg >= 1000
    local LogChannel = Info.LogChannel
    local RecordChannel = Info.RecordChannel

    if #msg < Info.MinChars then
        if author and author.id then
            if UseFile then
                SendDM(
                    author.id,
                    "Post Removed",
                    "Your post was removed by auto moderation.\n\n**Thread Title:** " .. ThreadTitle .. "\n**Category:** " .. Info.Identifer .. "\n\nReason:\n```Post was under " .. Info.MinChars .. " characters```",
                    0xFF0000,
                    "thread_message_" .. ThreadID .. ".txt",
                    msg
                )
            else
                SendDM(
                    author.id,
                    "Post Removed",
                    "Your post was removed by auto moderation.\n\n**Thread Title:** " .. ThreadTitle .. "\n**Category:** " .. Info.Identifer .. "\n\nReason:\n```Post was under " .. Info.MinChars .. " characters```\n\nMessage Content:\n```" .. msg .. "```",
                    0xFF0000
                )
            end
        end

        local RecordEmbed = {
            title = "Thread Auto-Removed",
            color = 0xFF0000,
            fields = {
                { name = "Thread", value = `<#{ThreadID}>` },
                { name = "Thread Title", value = ThreadTitle },
                { name = "Reason", value = "```\nPost was under " .. Info.MinChars .. " characters\n```"},
                { name = "Author", value = author and (author.username .. " `" .. author.id .. "`)") or "Unknown" },
                { name = "Category", value = Info.Identifer }
            }
        }

        if UseFile then
            Client:SendContext("Post", `channels/{RecordChannel}/messages`, {
                embeds = { RecordEmbed }
            })

            SendMultipart(
                Client, "Post",
                `channels/{RecordChannel}/messages`,
                { content = "" },
                "thread_message_" .. ThreadID .. ".txt",
                msg
            )
        else
            RecordEmbed.fields[#RecordEmbed.fields + 1] = {
                name = "Message Content",
                value = "```\n" .. msg .. "\n```"
            }

            Client:SendContext("Post", `channels/{RecordChannel}/messages`, {
                embeds = { RecordEmbed }
            })
        end

        Client:SendContext("Delete", `channels/{ThreadID}`)
        ClearPending(ThreadID)
        return
    end

    local Short = (#msg > 1000) and (msg:sub(1,997) .. "...") or msg

    if Info.CreationMessage then
        Client:SendContext("Post", `channels/{Packet.id}/messages`, {
            content = Info.CreationMessage
        })
    end
    local Embed = {
        title = `New {Info.Identifer} thread created!`,
        description = "**Thread Title:** " .. ThreadTitle .. "\n\n**Message Text:**\n\n" .. Short .. `\n\n<#{First.id}>`,
        color = 0x00AEEF,
        footer = { text = "Thread started by " .. author.username }
    }

    local Options = {}
    for key in pairs(QuickRejectReasons) do
        table.insert(Options, { label = key, value = key })
    end

    local Components = {
        {
            type = 1,
            components = {
                { type = 2, style = 3, label = "Allow",  custom_id = "thread_allow_" .. Packet.id },
                { type = 2, style = 4, label = "Remove", custom_id = "thread_remove_" .. Packet.id }
            }
        },
        {
            type = 1,
            components = {{
                type = 3,
                custom_id = "quick_reject_" .. Packet.id,
                options = Options,
                min_values = 1,
                max_values = 1,
                placeholder = "Quick Reject Reason"
            }}
        }
    }

    local Sent = Client:SendContext("Post", `channels/{LogChannel}/messages`, {
        embeds = {Embed},
        components = Components
    })

    if Sent and Sent.id then
        SetPending(ThreadID, {
            message_id = Sent.id,
            channel_id = LogChannel,
            category_name = Info.Identifer,
            thread_title = ThreadTitle,
            record_channel = RecordChannel
        })
    end
end)

Client:On("thread_delete", function(Packet)
    local ThreadID = tostring(Packet.id)
    local Pending = PendingRemovals[ThreadID]
    if not Pending then return end
    Client:SendContext("Delete", `channels/{Pending.channel_id}/messages/{Pending.message_id}`)
    ClearPending(ThreadID)
end)

Client:On("interaction_create", function(Packet)
    if not Packet.data then return end
    if Packet.type == 3 or Packet.type == 5 then
        if not RequirePerms(Packet) then
            return
        end
    end
    local ID = Packet.data.custom_id
    if Packet.type == 3 and ID:find("thread_allow_") then
        return HandleApproval(Packet, ID:gsub("thread_allow_", ""))
    end
    if Packet.type == 3 and ID:find("thread_remove_") then
        return HandleRemovalButton(Packet, ID:gsub("thread_remove_", ""))
    end
    if Packet.type == 3 and ID:find("quick_reject_") then
        local ThreadID = ID:gsub("quick_reject_", "")
        local Key = Packet.data.values[1]
        return HandleQuickReject(Packet, ThreadID, Key)
    end
    if Packet.type == 5 and ID:find("remove_modal_") then
        return HandleRemovalModal(Packet, ID:gsub("remove_modal_", ""))
    end
    return
end)

Logger:Info("Client started.")
Client:Start()