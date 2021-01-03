-- KristChat Client
-- A social media platform built on top of the Krist blockchain
-- hugeblank, Jan 2021
-- Some sections made live on Twitch, check out my channel here - https://twitch.tv/hugeblank
-- Random comments in code are due to a redeem that viewers of my channel can claim

--[[TODO
- Context menu when right clicking on posts
- nicknames for addresses because fuck remembering kasdfasdfa
- Settings menu???
- Color customization, "fancy" palette thingy???????
- remove debug test posts
- Allow tipping
]]
-- GG
--[[
    fatmanchummy
    fatmanchummy
    fatmanchummy
    fatmanchummy
    fatmanchummy
    fatmanchummy
    fatmanchummy
    fatmanchummy
    fatmanchummy
]]

if not fs.exists("/lib/raisin.lua") then
    local stream = http.get("https://raw.githubusercontent.com/hugeblank/raisin/v4.1/raisin.lua")
    if not stream then error("Could not download Raisin. Check your connection and try again.") end
    local file = fs.open("/lib/raisin.lua", "w")
    if not file then error("Could not open file") end
    file.write(stream.readAll())
    file.close() stream.close()
end

-- Hahah rrricohu stinky boy haha nerd lol - Love Hugeblank
local BASE, exit = term.current(), false
local eFilter = {
    "timer",
    "terminate",
    "http_success",
    "http_failure",
    "http_check",
    "websocket_success",
    "websocket_failure",
    "websocket_message",
    "login_success"
}
local gsw, gsh = term.getSize() -- Global width and height
local accounts = {} -- Wallets logged in

local ocolors = {}
for i = 0, 15 do
    ocolors[2^i] = {term.getPaletteColor(2^i)}
end
local function cls()
    for c, p in pairs(ocolors) do
        term.setPaletteColor(c, unpack(p))
    end
    term.redirect(term.native())
    if exit then
        term.setBackgroundColor(colors.black)
    else
        term.setBackgroundColor(colors.white)
    end
    term.clear()
    term.setCursorPos(1, 1)
end

-- Config setup
local config = {
    dark = false,
    timezone = "auto",
    censor = {},
    defaultLogin = "none",
    iUseMac = false
}
do
    local types = {
        dark = "boolean",
        timezone = "number",
        censor = "table",
        defaultLogin = "string",
        iUseMac = "boolean"
    }

    local function newConfig()
        local file = fs.open(".kconfig", "w")
        if file then
            file.write(textutils.serialise(config))
            file.close()
        end
    end

    if fs.exists(".kconfig") then
        local file = fs.open(".kconfig", "r")
        if file then
            local out = textutils.unserialise(file.readAll())
            if out then
                for k in pairs(config) do
                    if type(out[k]) == types[k] then
                        config[k] = out[k]
                    end
                end
            else
                newConfig()
            end
            file.close()
        end
    else
        newConfig()
    end

    if config.dark then
        term.setPaletteColor(colors.red, 0x44110A)
        term.setPaletteColor(colors.orange, 0x462206)
        term.setPaletteColor(colors.yellow, 0x453A02)
        term.setPaletteColor(colors.lime, 0x072818)
        term.setPaletteColor(colors.lightBlue, 0x101E33)
        term.setPaletteColor(colors.purple, 0x1A0E2D)
        term.setPaletteColor(colors.black, 0x9F9F9F)
        term.setPaletteColor(colors.white, 0x202122)
        term.setPaletteColor(colors.lightGray, 0x3B3B3B)
        term.setPaletteColor(colors.gray, 0x4B4B4B)
    end

    if config.timezone == "auto" then
        config.timezone = (os.time(os.date("*t"))-os.time(os.date("!*t")))/60/60
    end
end

_G.output = function(...)
    local args = {...}
    for i = 1, #args do
        args[i] = tostring(args[i])
    end
    local file = fs.open(".kcdbg", "a")
    file.writeLine(math.floor(os.epoch()).." | "..table.concat(args, ", "))
    file.close()
end

local raisin, kcontent = require("lib.raisin").manager(os.pullEventRaw), require("lib.kccontent")

local function quit()
    exit = true
    local run = {cls, kcontent.logout}
    for i = 1, #run do
        run[i]()
    end
end

local sidebar -- Windows used in app

local function openChannel(node) -- Opens a kristchat channel
    kcontent.setChannel(node)
    local halt = false
    local raisin = raisin.group(function() return halt end, 0, eFilter)
    local by, bw, offx, offy = 1, gsw+1, 2, 4 -- Border x, y, width
    local pgroup = raisin.group(function() return halt end, 0, eFilter) -- Thread group for rendering posts - often idle
    local board, banner, input, targeted -- Window housing all posts, Window for new post notifications, Post targeted for repost
    do -- Post board and Notif banner setup
        local bannerH = 3
        local temp = window.create(BASE, offx, offy, bw, gsh, true)
        temp.setBackgroundColor(colors.white)
        temp.clear()
        board, banner = window.create(temp, 1, by, bw, 1, true), window.create(BASE, offx, 4, bw, bannerH, false)
        board.setBackgroundColor(colors.white)
        banner.setBackgroundColor(colors.lightGray)
        banner.setTextColor(colors.black)
        banner.clear()
        board.clear()
        local brd, bsv = board.redraw, banner.setVisible
        board.redraw = function()
            brd()
            temp.redraw()
        end
        local vis = false
        banner.setVisible = function(b)
            if vis ~= b then
                if b then
                    offy = offy+bannerH
                    temp.reposition(offx, offy)
                else
                    offy = offy-bannerH
                    temp.reposition(offx, offy)
                end
                bsv(b)
                vis = b
            end
        end
        local prevY = 1
        board.shiftForInput = function(y)
            if y ~= prevY then
                prevY = y
                offy = offy+(y-prevY)
                temp.reposition(offx, offy)
            end
        end
    end
    -- Wrap the board window in another to keep it from overwriting the input bar
    local rendered, selectors, slim = {}, {}, 0 -- Current posts rendered, selection handlers for each message, scroll distance for post board
    local depths = {colors.red, colors.orange, colors.yellow, colors.lime, colors.lightBlue, colors.purple}

    local function parseWrapping(str, lim) -- Function for line wrapping, returns the text in a table of rows
        local row, rowind = {""}, 1
        for word in str:gmatch("%S*") do
            while #word >= lim-#row[rowind] do
                row[rowind] = row[rowind]..word:sub(1, lim-1)
                rowind = rowind+1
                row[rowind] = ""
                word = word:sub(lim, -1)
            end
            if #row[rowind]+#word >= lim then
                rowind = rowind+1
                row[rowind] = ""
            end
            if #word == 0 then
                row[rowind] = row[rowind]..word.." "
            else
                row[rowind] = row[rowind]..word
            end
        end
        return row
    end

    local function parseTime(timestr) -- Convert message time string to relative time
        local msg = {}
        local date = timestr:sub(1, timestr:find("T")-1)
        local time = timestr:sub(#date+2, timestr:find("Z")-1)

        msg.year = date:sub(1, 4)
        msg.month = date:sub(6, 7)
        msg.day = date:sub(9, 11)

        msg.hour = time:sub(1, 2)
        msg.min = time:sub(4, 5)
        msg.sec = time:sub(7, 8)

        for k, v in pairs(msg) do
            msg[k] = tonumber(v)
        end
        local out
        local daycheck = os.time(os.date("!*t"))-os.time(msg)
        msg.hour = msg.hour+config.timezone
        if daycheck < 86400 then
            out = "Today at "
        elseif daycheck > 86400 and daycheck < 86400*2 then
            out = "Yesterday at "
        else
            local months = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
            if msg.year%4 == 0 then months[2] = 29 end
            if msg.hour > 24 then
                msg.hour = msg.hour-24
                msg.day = msg.day+1
                if msg.day > months[msg.month] then
                    msg.month = msg.month+1
                    if msg.month > 12 then
                        msg.year = msg.year+1
                    end
                end
            elseif msg.hour < 0 then
                msg.hour = msg.hour+24
                msg.day = msg.day-1
                if msg.day < 1 then
                    msg.month = msg.month-1
                    if msg.month < 1 then
                        msg.year = msg.year-1
                    end
                end
            end
            return msg.month.."/"..msg.day.."/"..msg.year
        end
        msg.hour = msg.hour%24
        local twelvehour = msg.hour%12
        if twelvehour == 0 then twelvehour = 12 end
        out = out..twelvehour..":"..string.rep("0", #tostring(msg.min)%2)..msg.min
        if msg.hour/12 >= 1 then
            out = out.." PM"
        else
            out = out.." AM"
        end
        return out
    end

    local function postDisplay(base, post, depth, yinit) -- Display post, recursively renders
        local sx, sy = base.getSize() -- parent window width and height
        local selected = false -- Is this post selected
        local can = window.create(base, 1, yinit, sx-1, 1, depth ~= 1) -- Canvas for post embedding, first layer hidden, set visible when position is finalized
        sx, sy = can.getSize() -- post window width and height now
        local pcontent = window.create(can, 2, yinit+1, sx-1, 1) -- Canvas for post text block
        local subpost -- Variable allocated for context post canvas to embed into
        local pcrep = pcontent.reposition -- Redirect old function

        local function redrawText() -- Writes the text block
            local cx, cy = pcontent.getPosition()
            local rows = parseWrapping(post.metadata.content, sx-1)
            pcrep(cx, cy, sx-1, #rows)
            local c
            c = {colors.white, colors.black}
            if selected then
                c = {colors.gray, colors.white}
            end
            pcontent.setBackgroundColor(c[1])
            pcontent.setTextColor(c[2])
            pcontent.clear()
            for i = 1, #rows do
                pcontent.setCursorPos(1, i)
                pcontent.write(rows[i])
            end
            return #rows
        end
        pcontent.reposition = function(x, y, w) -- Reposition post content and redraw the content wrapping
            local _, rety = pcontent.getSize()
            if w then
                rety = redrawText()
                pcrep(x, y, w, rety)
            else
                pcrep(x, y)
            end
            return rety
        end

        local pcy = redrawText() -- Recurse into next post if there's a reference
        if post.metadata.ref and depth < 6 then
            local sp = kcontent.getPost(post.metadata.ref)
            if sp then
                post.metadata.ref = sp
                subpost = postDisplay(can, sp, depth+1, pcy)
            end
        end

        do -- Base canvas movement API
            local canrep, canrd = can.reposition, can.redraw
            can.reposition = function(x, y, w) -- Reposition canvas and all relevant components below this
                local pcony = pcontent.reposition(2, 2, sx)
                local _, py = pcontent.getSize()
                if subpost then
                    pcony = pcony+subpost.reposition(2, py+2, sx)
                end
                canrep(x, y, w, pcony+1)
                return pcony+1
            end

            can.redraw = function() --- Redraw canvas, and all relevant components below this
                if subpost then
                    subpost.redraw()
                end
                pcontent.redraw()
                canrd()
            end

            can.select = function(sel) -- Select this post with true, deselect with false
                selected = sel
                redrawText()
            end

            can.selector = function(x, y) -- Determine whether this post is targeted
                local cx, cy = can.getPosition()
                local cw, ch = can.getSize()
                cw, ch = cx+cw, cy+ch-1
                if cy <= y and y <= ch and cx <= x and x <= cw then
                    if subpost then
                        local i, s = subpost.selector(x-cx+1, y-cy+pcy)
                        if i then return i, s end
                    end
                    return post.id, can.select
                end
            end
        end

        -- Drawing borders, addresses, and timestamps
        sy = can.reposition(1, yinit, sx-1)
        local function drawHorizontal(y)
            can.setCursorPos(1, y)
            can.setBackgroundColor(depths[depth])
            can.write((' '):rep(sx))
        end

        drawHorizontal(1)
        drawHorizontal(sy)
        for i = 2, sy-1 do
            can.setCursorPos(1, i)
            can.write(' ')
        end

        local str = post.from
        can.setTextColor(colors.lightGray)
        can.setCursorPos(3, 1)
        can.write(str)
        local str = parseTime(post.time)
        can.setCursorPos(sx-#str-1, 1)
        can.write(str)

        return can, sy
    end

    local function postThread(msg, front) -- Event driven post renderer
        local pos
        if front then
            pos = 1
            for i = 1, #rendered do
                -- Adjust position of each rendered item so final position adjustment is correct
                rendered[i].pos = i+1
            end
        else
            pos = #rendered+1
        end
        table.insert(rendered, pos, {})
        pgroup.thread(function()
            local this = rendered[pos]
            if not this.pos then -- Position to be adjusted when inserting into the queue
                this.pos = pos
            end
            this.can, this.bottom = postDisplay(board, msg, 1, gsh+1)
            local _, bh = board.getSize()
            board.reposition(1, by, bw, bh+this.bottom)
            table.insert(selectors, pos, this.can.selector)

            this.finalizePosition = function(topY)
                local x = this.can.getPosition()
                local w = this.can.getSize()
                local height = this.can.reposition(x, topY, w)
                this.can.setVisible(true)
                if rendered[this.pos+1] then
                    while not rendered[this.pos+1].finalizePosition do
                        sleep(.05)
                    end
                    rendered[this.pos+1].finalizePosition(topY+height)
                end
                this.can.redraw()
            end
        end, pos, eFilter)
    end

    -- **God knows what the hell this line does. I really wish I knew how that one function works. I am a terrible programmer.**

    -- Load posts on startup, handle scrolling
    raisin.thread(function()
        local msgs = kcontent.providePosts()
        if not msgs then
            error("Failed to get posts")
        end
        if #msgs > 0 then
            for i = 1, #msgs do
                postThread(msgs[i], false)
            end
            raisin.thread(function() -- Thread for finalizing the positions of the posts
                while not rendered[1].finalizePosition do
                    sleep(.05)
                end
                rendered[1].finalizePosition(1)
            end)
        else
            board.setCursorPos(2, 1)
            board.setBackgroundColor(colors.white)
            board.setTextColor(colors.black)
            board.write("No messages to display. Be the first to post!")
        end
        while true do -- Handle scrolling
            local e = {os.pullEventRaw("mouse_scroll")} -- e[2] is +/- 1
            local _, bh = board.getSize()
            slim = slim+e[2]
            if slim >= 0 and slim+gsh-offy+1 < bh then
                by = by-e[2]
                board.reposition(1, by, bw, bh)
            else
                slim = slim-e[2]
            end
        end
    end, 1, eFilter)

    -- Posts received while app is running
    raisin.thread(function()
        local msgs = {}

        raisin.thread(function() -- Thread to do the injecty
            local e = {}
            while true do
                local banX, banY = banner.getPosition()
                local banW, banH = banner.getSize()
                if e[2] == 1 and e[3] >= banX and e[4] >= banY and e[3] < banX+banW and e[4] < banY+banH then
                    banner.setVisible(false)
                    while #msgs > 0 do
                        postThread(table.remove(msgs, 1), true)
                        while not rendered[1].finalizePosition do
                            sleep(.05)
                        end
                        rendered[1].finalizePosition(1)
                    end
                end
                e = {os.pullEventRaw("mouse_click")}
            end
        end)
        while true do
            local msg = kcontent.receivePost()
            if not msg then
                sleep(.05)
                -- Wait for websocket
            else
                msgs[#msgs+1] = msg
                banner.clear()
                local banw = banner.getSize()
                banner.setVisible(true)
                banner.clear()
                local str = "Click to view "..#msgs.." new post"
                if #msgs > 1 then str = str.."s" end
                banner.setCursorPos((banw/2)-(#str/2), 2)
                banner.write(str)
            end
        end
    end, 0, eFilter)

    -- Message selection handler
    raisin.thread(function()
        local e = {}
        while true do
            if e[2] == 2 then -- Select/deselect the post
                local oldid
                if targeted then
                    oldid = targeted.id
                    targeted.select(false)
                    targeted = nil
                end
                for _, v in pairs(selectors) do
                    local _, sy = board.getPosition()
                    local x, y = e[3]-offx+1, e[4]-offy-sy+2
                    local id, select = v(x, y)
                    if oldid ~= id and id then
                        select(true)
                        targeted = {id=id,select=select}
                        break
                    end
                end
            end
            e = {os.pullEventRaw("mouse_click")}
        end
    end, 1, eFilter)

    -- Post text input
    raisin.thread(function()
        input = window.create(BASE, 2, 1, gsw, 3, true)
        local e, str, ind, bound = {}, {}, 1, gsw-3

        local function getCoords(rows, ind)
            -- Interpolate from cursor position in string to x/y coordinates
            local out = 0
            while rows[out+1] and ind > #rows[out+1] and out < #rows-1 do
                ind = ind-#rows[out+1]
                out = out+1
            end
            return ind, out
        end
        local function getIndex(rows, x, y)
            -- Get index from x/y coordinates
            local out = x
            for i = 1, y do
                if rows[i] then
                    out = out+#rows[i]
                end
            end
            return out
        end

        local redraw, ctrl = true, false

        local function getWordRev(str, ind)
            local iter = 1
            if ctrl then
                for i = ind-1, 1, -1 do
                    if str[i] == " " and i ~= ind-1 then
                        iter = iter-1
                        break
                    end
                    iter = iter+1
                end
            end
            return iter
        end

        local function getWordFor(str, ind)
            local iter = 1
            if ctrl then
                for i = ind, #str do
                    if str[i] == " " and i ~= ind then
                        iter = iter-1
                        break
                    end
                    iter = iter+1
                end
            end
            return iter
        end

        raisin.thread(function()
            local e
            while true do
                e = {os.pullEvent()}
                if e[1] == "key" then
                    if config.iUseMac and e[2] == keys.leftAlt or e[2] == keys.rightAlt then
                        ctrl = true
                    elseif not config.iUseMac and e[2] == keys.leftCtrl or e[2] == keys.rightCtrl then
                        ctrl = true
                    end
                elseif e[1] == "key_up" then
                    if config.iUseMac and e[2] == keys.leftAlt or e[2] == keys.rightAlt then
                        ctrl = false
                    elseif not config.iUseMac and e[2] == keys.leftCtrl or e[2] == keys.rightCtrl then
                        ctrl = false
                    end
                end
            end
        end)

        while true do
            input.restoreCursor()
            e = {os.pullEvent()}
            local event = table.remove(e, 1)
            if event == "char" then
                local char = table.remove(e, 1)
                table.insert(str, ind, char)
                ind = ind+1
                redraw = true
            end
            local rows = parseWrapping(table.concat(str, ""), bound)
            if event == "key" then
                local key = table.remove(e, 1)
                if key == keys.enter and #str > 0 then
                    if targeted then
                        kcontent.makePost(table.concat(str, ""), targeted.id)
                        targeted.select(false)
                        targeted = nil
                    else
                        kcontent.makePost(table.concat(str, ""))
                    end
                    redraw = true
                    str = {}
                    ind = 1
                elseif key == keys.backspace then
                    local iter = getWordRev(str, ind)
                    for i = 1, iter do
                        ind = ind-1
                        if ind < 1 then
                            ind = 1
                        else
                            table.remove(str, ind)
                        end
                    end
                    redraw = true
                elseif key == keys.left then
                    local iter = getWordRev(str, ind)
                    for i = 1, iter do
                        ind = ind-1
                    end
                    if ind < 1 then
                        ind = 1
                    end
                elseif key == keys.right then
                    local iter = getWordFor(str, ind)
                    for i = 1, iter do
                        ind = ind+1
                    end
                    if ind > #str+1 then
                        ind = #str+1
                    end
                elseif key == keys.delete then
                    local iter = getWordFor(str, ind)
                    for i = 1, iter do
                        table.remove(str, ind)
                    end
                    redraw = true
                elseif key == keys.down then
                    local x, y = getCoords(rows, ind)
                    ind = getIndex(rows, x, y+1)
                    if ind > #str+1 then
                        ind = #str+1
                    end
                elseif key == keys.up then
                    local x, y = getCoords(rows, ind)
                    ind = getIndex(rows, x, y-1)
                    if y-1 == -1 then
                        ind = 1
                    end
                elseif key == keys.pageDown then
                    ind = #str+1
                elseif key == keys.pageUp then
                    ind = 1
                elseif key == keys.home then
                    local _, y = getCoords(rows, ind)
                    ind = getIndex(rows, 1, y)
                elseif key == keys["end"] then
                    local _, y = getCoords(rows, ind)
                    ind = getIndex(rows, #rows[y+1], y)
                end
            end
            if event == "paste" then
                for i = 1, #e[1] do
                    table.insert(str, ind, e[1]:sub(i,i))
                    ind = ind+1
                end
                redraw = true
            end
            if event == "mouse_click" then
                if e[1] == 1 and e[2] > 1 and e[3] > 1 and e[2] < gsw and e[3] < 2+#rows then
                    e[2], e[3] = e[2]-1, e[3]-2
                    if e[2] > #rows[(e[3]+1)]+1 then
                        e[2] = #rows[(e[3]+1)]+1
                    end
                    ind = getIndex(rows, e[2], e[3])-1
                else
                    redraw = true
                end
            end
            if redraw then
                -- local total = 18 -- when we're not on test_posts
                local total = 23
                if targeted then
                    total = total+#tostring(targeted.id)+5
                end
                while 255-total < #str do
                    table.remove(str, #str)
                end
                if ind > #str+1 then
                    ind = #str+1
                end
                rows = parseWrapping(table.concat(str, ""), bound)
                local rowind = #rows
                input.reposition(2, 1, gsw-1, 2+rowind)
                board.shiftForInput(rowind)
                input.setBackgroundColor(colors.lightBlue)
                input.clear()
                local amtstr = tostring(#str).."/"..tostring(255-total)
                if #str == 255-total then
                    input.setTextColor(colors.red)
                    amtstr = "Character Limit Reached: "..amtstr
                else
                    input.setTextColor(colors.black)
                end
                input.setCursorPos(gsw-#amtstr-1, 2+rowind)
                input.write(amtstr)
                if targeted then -- Make user aware that they are reposting
                    input.setCursorPos(2, 1)
                    input.setTextColor(colors.black)
                    input.write("[Repost]")
                    input.setTextColor(colors.white)
                    input.setBackgroundColor(colors.gray)
                else -- Default Post indicator
                    input.setCursorPos(2, 1)
                    input.setTextColor(colors.black)
                    input.write("[Post]")
                    input.setBackgroundColor(colors.white)
                end
                for i = 1, rowind do
                    input.setCursorPos(2, 1+i)
                    input.write(string.rep(" ", bound))
                end
                input.setCursorBlink(true)
                for i = 1, rowind do
                    input.setCursorPos(2, i+1)
                    input.write(rows[i])
                end
                redraw = false
            end
            local ix, iy = getCoords(rows, ind)
            input.setCursorPos(ix+1, iy+2)
        end
    end, 1, eFilter)

    -- Gracefully close
    local function close()
        raisin.thread(function() end)
        -- A nothing thread to force close
        halt = true
    end
    local function redraw()
        if board and input then
            board.redraw()
            input.redraw()
        end
    end

    return {close = close, toggle = raisin.toggle, redraw = redraw}
end

do -- Border/Menu
    local raisin = raisin.group(function() return exit end, 0, eFilter)
    local amtLoggedIn = 0 -- #accounts, basically
    local channel -- Channel currently being looked at
    local slots = {} -- Slots that buttons can occupy
    local width = math.floor(gsw/4)
    if width < 16 then -- The minimum space needed for sidebar (10 characters in button)
        width = 16
    end
    local function wcreate(...)
        local win = window.create(...)
        win.drawLine = function(x, y, w, color)
            win.setCursorPos(x, y)
            win.setBackgroundColor(color)
            win.write(string.rep(" ", w))
        end
        win.button = function(x, y, w, bcolor, tcolor, text)
            win.drawLine(x, y, w, bcolor)
            win.setCursorPos(x+(w/2)-(#text/2), y)
            win.setTextColor(tcolor)
            win.write(text)
        end
        return win
    end
    sidebar = wcreate(BASE, 1, 1, width, gsh, true)

    do -- Aesthetics
        sidebar.setBackgroundColor(colors.lightBlue)
        sidebar.clear()
        local str = "KristChat"
        sidebar.setTextColor(colors.gray)
        local spoint = ((gsh/2)-(#str/2))
        for i = spoint, #str+spoint do -- Write along right edge
            sidebar.setCursorPos(width, i)
            sidebar.write(str:sub(i-spoint+1, i-spoint+1))
        end
        sidebar.setCursorPos((width/2)-(#str/2), 1) -- Write on top of menu
        sidebar.write(str)
        for i = 2, gsh-1 do -- Clear the inside space
            sidebar.setCursorPos(2, i)
            sidebar.drawLine(2, i, width-2, colors.white)
        end
    end

    -- Default buttons
    local function sbutton(y, bc, tc, txt, onPress)
        local element
        element = {
            draw = function() sidebar.button(3, y, width-4, bc, tc, txt) end,
            press = function() raisin.thread(function()
                onPress()
                if slots[y] == element then
                    -- If the element still exists - a lot of elements get overwritten
                    element.draw()
                end
            end, 0, eFilter) end
        }
        element.draw()
        slots[y] = element
    end

    local function sbuttonRemove(y)
        slots[y] = nil
        sidebar.drawLine(2, y, width-2, colors.white)
    end

    local function storeButtons(y, h) -- store buttons starting at y and ending at y+h
        local storage = {}
        for i = y, y+h do
            storage[i] = slots[i]
            slots[i] = nil
        end
        return function() -- return function that restores the buttons when called
            for i = y, y+h do
                sidebar.drawLine(2, i, width-2, colors.white)
            end
            for i, v in pairs(storage) do
                slots[i] = v
                v.draw()
            end
        end
    end

    local function sdropdown(y, list, start, label, func)
        local this = {}
        local element
        element = {
            draw = function() -- Closed state
                sidebar.setBackgroundColor(colors.white)
                sidebar.setTextColor(colors.black)
                sidebar.setCursorPos(3, y-1)
                sidebar.write(label..":")
                sidebar.drawLine(3, y, width-5, colors.gray)
                sidebar.setCursorPos(3, y)
                -- Render the right element in the main bar
                for k, v in pairs(list) do
                    if v.current then
                        start = k
                    end
                end
                sidebar.write(" "..start)
                sidebar.setCursorPos(width-2, y)
                sidebar.setBackgroundColor(colors.lightGray)
                sidebar.write("^")
            end,
            press = function() raisin.thread(function()
                local menu = wcreate(sidebar, 3, y-1, width-4, 0)
                menu.setTextColor(colors.black)
                menu.setBackgroundColor(colors.gray)
                menu.clear()
                -- Render each list element except for the one selected
                local amt = 1
                local selectors = {}
                for k in pairs(list) do
                    if k ~= start then -- If the value isn't already displayed
                        menu.reposition(3, y-amt, width-4, amt)
                        menu.setCursorPos(1, amt)
                        menu.write(" "..k)
                        selectors[amt] = k
                        amt = amt+1
                    end
                end
                if amt > 1 then -- Open state
                    local restore = storeButtons(y-amt-1, amt+1)
                    sidebar.setCursorPos(width-2, y)
                    sidebar.setBackgroundColor(colors.lightGray)
                    sidebar.setTextColor(colors.black)
                    sidebar.write("v")

                    local e = {}
                    while true do
                        if e[2] == 1 and e[3] > 2 and e[3] < width-1 then
                            local pos = e[4]-y+amt
                            if e[4] == y then
                                -- Close, same value
                                restore()
                                element.draw()
                                return
                            elseif selectors[pos] then
                                -- Close, new value
                                restore()
                                list[start].current = false
                                local temp = selectors[pos]
                                selectors[pos] = start
                                start = temp
                                list[start].current = true
                                element.draw()
                                func(list, start)
                                return
                            end
                        end
                        e = {os.pullEvent("mouse_up")}
                    end
                end end, 0, eFilter)
            end
        }
        slots[y] = element
        element.draw()

        this.setCurrent = function(key)
            for _, v in pairs(list) do
                v.current = false
            end
            list[key].current = true
            func(list, key)
            element.draw()
        end

        return this
    end

    local function addChannel(y, channels, cdrop)
        local restore = storeButtons(y, 2)
        sidebar.drawLine(3, y, width-4, colors.black)
        sidebar.setTextColor(colors.white)
        sidebar.setCursorPos(width-5, y)
        sidebar.write(".kst")
        local temp = window.create(sidebar, 3, y, width-8, 1, true)
        local name
        while not name do
            temp.setBackgroundColor(colors.black)
            temp.setTextColor(colors.white)
            temp.clear()
            local ot = term.redirect(temp)
            term.setCursorPos(1, 1)
            name = read()
            term.redirect(ot)
            if #name == 0 then
                restore()
                return
            end
            if kcontent.resolveChannel(name) then -- tf is going on 'ere???
                channels[name] = {
                    address = name..".kst"
                }
                cdrop.setCurrent(name)
                restore()
                return
            else
                name = nil
                sidebar.setTextColor(colors.red)
                sidebar.setBackgroundColor(colors.white)
                local str = "Invalid Channel"
                for i = 1, 2 do
                    sidebar.setCursorPos(3, y+1)
                    sidebar.write(string.rep(" ", #str))
                    sleep(.05)
                    sidebar.setCursorPos(3, y+1)
                    sidebar.write(str)
                    sleep(.05)
                end
            end
        end

    end

    local login, accdrop, cdrop
    -- scope login up here for this function,
    -- account dropdown for updating when accounts are added,
    -- channel drop down for updating when channels are added
    local function addAccount(y, addr, remember)
        local aSlots = {2, 4, 6, 8}
        if not accounts[addr] then
            accounts[addr] = {
                channels = { -- The channels this address has joined
                    self = {
                        address = addr,
                        current = true,
                    },
                    allchat = {
                        address = "allchat.kst"
                    }
                },
                current = true, -- Current address being used to make posts
                remember = remember -- Remember this account when exiting app
            }
        end

        sbutton(y, colors.lime, colors.gray, "Add Account", function() login(y) end)
        sbutton(y-aSlots[3], colors.lightBlue, colors.gray, "Add Channel", function() addChannel(y-aSlots[3], accounts[addr].channels, cdrop) end)
        local function changeChannel(list, index)
            if channel then channel.close() end
            channel = openChannel(list[index].address)
            sidebar.redraw()
        end
        local function changeAccount(list, index)
            if channel then channel.close() end
            kcontent.logout()
            for k, v in pairs(list[index].channels) do -- Iterate over accounts
                if v.current then
                    sbuttonRemove(y-aSlots[4])
                    sbuttonRemove(y-aSlots[4]-1)
                    sidebar.drawLine(3, y-aSlots[4], width-4, colors.lightGray)
                    sidebar.setCursorPos(4, y-aSlots[4])
                    sidebar.write(" Switching")
                    kcontent.login(index)
                    cdrop = sdropdown(y-aSlots[4], list[index].channels, k, "Channels", changeChannel)
                    cdrop.setCurrent(k)
                end
            end
        end
        local function logout()
            local nstart
            for k, v in pairs(accounts) do
                if v.current then
                    accounts[k] = nil
                    if close then close() end
                end
            end
            for k, v in pairs(accounts) do
                nstart = k
                v.current = true
                break
            end
            amtLoggedIn = amtLoggedIn-1
            if amtLoggedIn == 0 then
                for i = 1, #aSlots do
                    sbuttonRemove(y-aSlots[i])
                    sidebar.drawLine(2, y-aSlots[i]-1, width-2, colors.white)
                end
                sbutton(y, colors.yellow, colors.lightGray, "Log in", function() login(y) end)
            else
                changeAccount(accounts, nstart)
                sdropdown(y-aSlots[2], accounts, nstart, "Accounts", changeAccount)
            end
        end
        -- If this is a first time setup
        accdrop = sdropdown(y-aSlots[2], accounts, addr, "Accounts", changeAccount)
        accdrop.setCurrent(addr)
        for k, v in pairs(accounts[addr].channels) do
            if v.current then
                cdrop = sdropdown(y-aSlots[4], accounts[addr].channels, k, "Channels", changeChannel)
                cdrop.setCurrent(k)
            end
        end
        sbutton(y-aSlots[1], colors.red, colors.lightGray, "Log out", logout)
        amtLoggedIn = amtLoggedIn+1
    end

    function login(bottomY)
        local menu = wcreate(sidebar, 2, bottomY-8+1, width-2, 8, true)
        local width, height = menu.getSize()
        local restoreButtons = storeButtons(bottomY-8+1, 8)
        local bht, cht, rht, pht = height, height-2, height-4, height-6 -- Height of: Log in button | Cancel button | Remember credentials button | Password input
        menu.setBackgroundColor(colors.white)
        menu.clear()
        local function redrawPassText(str)
            menu.setTextColor(colors.black)
            menu.drawLine(2, pht-1, width-2, colors.white)
            menu.setCursorPos(2, pht-1)
            menu.write(str..":")
            menu.drawLine(2, pht, width-2, colors.black)
        end
        redrawPassText("Password")
        local pwin = window.create(menu, 2, pht, width-2, 1, true)
        pwin.setBackgroundColor(colors.black)
        pwin.setTextColor(colors.white)

        local function redrawOptions(b)
            if b then
                -- Draw Log in button
                menu.button(2, bht, width-2, colors.lime, colors.gray, "Log in")
                -- Draw Cancel button
                menu.button(2, cht, width-2, colors.red, colors.lightGray, "Not me")
                -- Draw Remember credentials
                menu.setCursorPos(2, rht)
                menu.setBackgroundColor(colors.black)
                menu.write(" ")
                menu.setBackgroundColor(colors.white)
                menu.setTextColor(colors.black)
                menu.write(" Remember me")
            else
                for i = pht+1, bht do
                    menu.drawLine(2, i, width-2, colors.white)
                end
            end
        end

        local remember, password = false, ""
        local e = {}
        local offx, offy = menu.getPosition()
        while true do -- Get password input, Verify with user the address is correct, allow user to cache credentials, then log in            if #password > 0 then
            if #password == 0 then
                local ot = term.redirect(pwin)
                term.clear()
                term.setTextColor(colors.lightGray)
                password = read("*")
                term.redirect(ot)
                if #password ~= 0 then
                    local addr = kcontent.importWallet(password, false, false)
                    -- Write confirm check over password box
                    redrawPassText("Address")
                    menu.drawLine(2, pht, width-2, colors.black)
                    menu.setCursorPos(2, pht)
                    menu.setTextColor(colors.lightGray)
                    menu.write(addr)
                    menu.setCursorPos(2, pht+1)
                    menu.setTextColor(colors.black)
                    menu.setBackgroundColor(colors.white)
                    menu.write("Is this you?")
                    redrawOptions(true)
                else
                    restoreButtons()
                    slots[bottomY].draw()
                    return
                end
            end
            e = {os.pullEvent("mouse_up")}
            if e[2] == 1 and e[3]-offx+1 >= 2 and e[3]-offx+1 <= width-1 then
                e[4] = e[4]-offy+1
                if e[4] == cht then
                    -- If the cancel button was clicked
                    password = ""
                    redrawOptions(false)
                elseif e[4] == bht then
                    -- If the log in button was clicked
                    local addr = kcontent.importWallet(password, remember, false)
                    restoreButtons()
                    slots[bottomY].draw()
                    addAccount(bottomY, addr, remember)
                    return
                elseif e[4] == rht and e[3]-offx+1 == 2 then
                    -- If the remember check was clicked
                    remember = not remember
                    menu.setCursorPos(2, rht)
                    menu.setBackgroundColor(colors.black)
                    menu.setTextColor(colors.lime)
                    if remember then
                        menu.write("X")
                    else
                        menu.write(" ")
                    end
                end
            end
        end
    end

    raisin.thread(function()
        sbutton(gsh-2, colors.red, colors.lightGray, "Exit", function() exit = true end)
        if fs.exists(".kclogins") then -- First run
            local file = fs.open(".kclogins", "r")
            if file then
                accounts = textutils.unserialise(file.readAll())
                local startOn, alternate
                for k, v in pairs(accounts) do
                    if v.current then
                        startOn = k
                    end
                    alternate = k
                    amtLoggedIn = amtLoggedIn+1
                end
                if startOn then
                    addAccount(gsh-4, startOn)
                elseif alternate then
                    accounts[alternate].current = true
                    addAccount(gsh-4, alternate)
                else
                    error("No channels to open, delete .kclogins")
                end
                file.close()
            end
        end
        if amtLoggedIn == 0 then
            sbutton(gsh-4, colors.yellow, colors.lightGray, "Log in", function() login(gsh-4) end)
        end

        for _, v in pairs(slots) do
            v.draw()
        end
        local e = {}
        while not exit do
            if e[2] == 1 and e[3] > 2 and e[3] < width-1 and slots[(e[4])] then
                slots[(e[4])].press()
                sidebar.setCursorBlink(false)
                sleep()
            end
            e = {os.pullEvent("mouse_up")}
        end
    end, 0, eFilter)

    sidebar.setVisible = function(b)
        local p = -width+2
        if b then p = 1 end
        sidebar.reposition(p, 1, width, gsh)
        if channel then
            channel.toggle(not b)
            if not b then
                channel.redraw()
            end
        end
    end

    raisin.thread(function()
        local expanded = true
        local e = {}
        while not exit do
            if e[2] == 1 then
                if e[3] == math.floor(width) then
                    expanded = false
                elseif e[3] == 1 then
                    expanded = not expanded
                end
            end
            sidebar.setVisible(expanded)
            if board and not expanded then
                board.redraw()
            end
            e = {os.pullEvent("mouse_up")}
        end
    end, 0, eFilter)

    raisin.thread(function() -- Safely exit on termination
        while not exit do
            os.pullEvent("terminate")
            exit = true
        end
    end, 0, eFilter)
end

local bOk, sErr = pcall(function() raisin.run(function() return exit end) end)
if not bOk then
    exit = true
    cls()
    local file = fs.open(".error", "w")
    file.writeLine(sErr)
    file.close()
end
-- Save session
local file = fs.open(".kclogins", "w")
local save = {}
for k, v in pairs(accounts) do
    if v.remember then
        save[k] = v
    end
end
file.write(textutils.serialise(save))
file.close()
quit()