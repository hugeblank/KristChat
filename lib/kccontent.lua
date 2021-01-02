-- kcccontent.lua
-- An intermediary library between krist and KristChat - handles transaction evaluation
-- By hugeblank, Jan 2021
local krist = require("lib.krist")

local node
local offset, nodes = 0, {}

local out = {}

local parseMeta = function(content)
    local parts = {}
    for p in string.gmatch(content, "[^;]+") do
        local split, sem = p:find("="), p:sub(-1)
        if split == nil then
            parts[#parts+1] = p
        else
            local res
            if sem == ";" then
                res = p:sub(split+1, -2)
            else
                res = p:sub(split+1)
            end
            parts[p:sub(1, split-1)] = res:gsub("&semi", ";")
        end
    end
    return parts
end

local checkTX = function(tx)
    if tx and tx.to == nodes[node] and tx.metadata then -- Check it's for the node and has metadata
        tx.metadata = parseMeta(tx.metadata)
        if tx.metadata.type == "post" and tx.metadata.content then
            -- Check that the meta is a compliant KChat message
            if node:find(".kst") and tx.metadata[1] == node then
                -- If this is in the channel we want
                return tx
            elseif not node:find(".kst") then
                -- If this is a self post
                return tx
            end
        end
    end
    return false
end

out.providePosts = function()
    local tx, p = krist.getTransactions(nodes[node], 150, offset), {}
    if tx then
        for i = 1, #tx do
            local temp = checkTX(tx[i])
            if temp then p[#p+1] = temp end
        end
        return p
    end
    return false
end

out.getPost = function(tid)
    return checkTX(krist.getTransaction(tid))
end

local ws

out.receivePost = function()
    if not ws then return false end
    while ws do
        local msg = ws.receive()
        if msg.type == "event" and msg.event == "transaction" then -- Get a transaction
            local tx = checkTX(msg.transaction)
            if tx then return tx end
        end
    end
end

out.makePost = function(content, tid)
    if not (node and ws) then return false end
    content:gsub(";", "&semi")
    return ws.makeTransaction(node, 1, {type="post", content=content, ref=tid}) -- RESET THIS BACK TO POST
end

out.setChannel = function(n)
    if n:find(".kst") then
        local addr = krist.resolveName(n)
        if not addr then
            return false
        end
        nodes[n] = addr
    else
        nodes[n] = n
    end
    node = n
end

out.login = function(address)
    if not ws then
        ws = krist.startWS()
        if not ws then return false end
        address = ws.upgradeImported(address)
        if not address then return false end
        ws.subscribe("transactions")
        ws.unsubscribe("blocks")
        return true
    else
        return false
    end
end

out.logout = function()
    if ws then
        ws.close()
        ws = nil
        return true
    else
        return false
    end
end

out.importWallet = krist.importWallet
out.resolveChannel = krist.resolveName

return out