-- krist.lua
-- Library used to interface with the Krist network
-- By hugeblank, Jan 2021

if not fs.exists("/lib/sha.lua") then
    local stream = http.get("https://raw.githubusercontent.com/hugeblank/pure_lua_SHA/e4143b10d831659379c196c5b70f3fa206c93c18/sha2.lua")
    if not stream then error("Could not download SHA library. Check your connection and try again.") end
    local file = fs.open("/lib/sha.lua", "w")
    if not file then error("Could not open file") end
    file.write(stream.readAll())
    file.close() stream.close()
end

local sha = require("lib.sha")

local persistent = "/.kprivkeys"

local function copy(t)
    local out = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            out[k] = copy(v)
        else
            out[k] = v
        end
    end
    return out
end

local wallets = {}
local function getWallets()
    if fs.exists(persistent) then
        local stream = fs.open(persistent, "r")
        if stream then
            local e = stream:readAll()
            stream:close()
            if e then
                local out = textutils.unserialize(e)
                for k, v in pairs(out) do
                    wallets[k] = v
                end
            end
        end
    end
    return wallets
end

local function cacheWallet(address, privkey)
    local out = getWallets()
    if not out[address] then
        out[address] = privkey
    end
    local stream = fs.open(persistent, "w")
    stream.write(textutils.serialize(out))
    stream.close()
end

local reqs = {}
local function request(url, body, forceNew)
    http.request(url, body)
    local e = {}
    while true do
        if e[1] == "http_success" then
            if e[2] == url then
                if reqs[url] and not body and not forceNew then -- Get from buffer since this URL has already been hit
                    return copy(reqs[url])
                end
                local out = textutils.unserializeJSON(e[3].readAll())
                e[3].close()
                reqs[url] = copy(out)
                return out
            end
        elseif e[1] == "http_failure" then
            return false
        end
        e = {os.pullEvent()}
    end
end

local out = {}

local cache

local function loadCache()
    if not cache then
        local file = fs.open(".kcache", "r")
        if not file then
            cache = {}
            return
        end
        cache = textutils.unserialise(file.readAll())
        file.close()
    end
end

local addToCache = function(tx)
    loadCache()
    tx.id = tonumber(tx.id)
    if not cache[tx.id] then
        tx = copy(tx)
        cache[tx.id] = tx
        local file = fs.open(".kcache", "w")
        file.write(textutils.serialize(cache))
        file.close()
    end
end

local getFromCache = function(id)
    loadCache()
    id = tonumber(id)
    if not cache[id] then return false end
    return copy(cache[id])
end

out.getTransactions = function(address, lim, off)
    lim = lim or 50; off = off or 0
    local res = request("https://krist.ceriat.net/addresses/"..address.."/transactions?limit="..lim.."&offset="..off, nil, true)
    if res and res.ok then
        local tx = res.transactions
        for i = 1, #tx do
            addToCache(tx[i])
        end
        return tx
    else
        return false
    end
end

out.getTransaction = function(tid)
    tid = tonumber(tid)
    if not tid then return false end

    local out = getFromCache(tid)
    if out then
        return out
    else
        local res = request("https://krist.ceriat.net/transactions/"..tid)
        if res and res.ok then
            local tx = res.transaction
            addToCache(tx)
            return tx
        end
    end
    return false
end

out.importWallet = function(password, remember, basic)
    local privkey, address
    if basic then -- Get the private key from the password, format for kristwallet as well
        privkey = sha.sha256(password)
    else
        privkey = sha.sha256("KRISTWALLET"..password).."-000"
    end
    local wallets = getWallets() -- Check if the key exists in the cache
    if wallets then
        for k, v in pairs(wallets) do
            if v == privkey then
                address = k
            end
        end
    end
    if not address then
        local res = request("https://krist.ceriat.net/login", "privatekey="..privkey)
        if res.ok and res.authed then
            address = res.address
        else
            return false
        end
    end
    if address and remember then
        cacheWallet(address, privkey)
    elseif address then
        wallets[address] = privkey
    end
    return address
end

-- TODD IS A SIMP

out.resolveName = function(name) -- Get the address attached to a name
    local res = request("https://krist.ceriat.net/names/"..name:gsub(".kst", ""))
    if res and res.ok then
        return res.name.owner
    end
    return false
end

out.startWS = function()
    local res = request("https://krist.ceriat.net/ws/start/", "privatekey=")
    if res and res.ok then
        local ws = http.websocket(res.url)
        if ws then
            local oldsend = ws.send
            local id = 0
            ws.send = function(msg)
                id = id+1
                msg.id = id
                oldsend(textutils.serialiseJSON(msg))
                return id
            end
            ws.receive = function(mid)
                local e = {}
                while not (e[1] == "websocket_closed" and e[2] == res.url) do
                    e = {os.pullEvent()}
                    if e[1] == "websocket_message" and e[2] == res.url then
                        local msg = textutils.unserializeJSON(e[3])
                        if msg.id == mid or not mid then
                            return msg
                        end
                    end
                end
                return false
            end
            ws.upgrade = function(privkey)
                local i = ws.send {
                    type= "login",
                    privatekey = privkey
                }
                local auth = ws.receive(i)
                if auth.ok then
                    return auth.address.address
                end
                return false
            end
            ws.upgradeImported = function(address)
                local wals = getWallets()
                if wals[address] then
                    return ws.upgrade(wals[address])
                end
                return false
            end
            ws.makeTransaction = function(toA, amt, meta)
                local smeta = ""
                for k, v in pairs(meta) do
                    if #smeta == 0 then
                        smeta = smeta..k..'='..v
                    else
                        smeta = smeta..';'..k..'='..v
                    end
                end
                local i = ws.send({
                    type="make_transaction",
                    to=toA,
                    amount=amt,
                    metadata=smeta
                })
                return ws.receive(i)
            end
            ws.subscribe = function(events)
                if type(events) == "table" then
                    for i = 1, #events do
                        ws.send({type="subscribe",event=events[i]})
                    end
                else
                    ws.send({type="subscribe",event=events})
                end
                local i = ws.send{
                    type="get_subscription_level"
                }
                return ws.receive(i)
            end
            ws.unsubscribe = function(events)
                if type(events) == "table" then
                    for i = 1, #events do
                        ws.send({type="unsubscribe",event=events[i]})
                    end
                else
                    ws.send({type="unsubscribe",event=events})
                end
                local i = ws.send{
                    type="get_subscription_level"
                }
                return ws.receive(i)
            end
            ws.cache = function()

            end
            return ws
        end
    end
    error("Could not connect to Krist, please check your connection and try again later")
end

return out