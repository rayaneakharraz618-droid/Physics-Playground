function love.load()
    WINDOW_W, WINDOW_H = 1000, 700
    DT = 0

    love.window.setMode(WINDOW_W, WINDOW_H, {
        resizable = true,
        vsync = false,
        minwidth = 800,
        minheight = 600
    })


    love.window.setTitle("Physics Playground")

    mouseJoint = nil

    selecting = false
    selectStartX = 0
    selectStartY = 0
    selectEndX = 0
    selectEndY = 0

    selectedObjects = {}

    -- Tools
    TOOL_SELECT = 1
    TOOL_MOVE   = 2
    TOOL_BALL   = 3
    TOOL_BOX    = 4
    TOOL_DRAG   = 5
    TOOL_FREEZE = 6
    TOOL_MAGNET = 7

    currentTool = TOOL_SELECT

    dragForce = 10000

    magnetStrength = 1500
    magnetRadius = 150
    magnetMode = "attract" -- or "repel"

    rotateSpeed = 15 * 10000
    originalRS = rotateSpeed
    qDown = false
    eDown = false

    -- Properties panel
    PROPS_W = 200
    PROPS_H = 300
    PROPS_X = WINDOW_W - PROPS_W - 10
    PROPS_Y = WINDOW_H - PROPS_H - 10

    propsScroll = 0
    PROPERTY_PANEL_W = 280
    PROPERTY_ROW_H = 28
    PROPS_SCROLL_SPEED = 30

    hexColorInput = ""
    hexColorActive = false
    hexBoxX, hexBoxY, hexBoxW, hexBoxH = 0,0,0,0

    draggingGroup = false
    dragOffset = {}

    -- Shape Tools
    dragging = false
    dragStartX, dragStartY = 0, 0
    dragEndX, dragEndY = 0, 0

    -- Camera
    camX, camY = 0, 0
    panning = false
    panStartX, panStartY = 0, 0
    camStartX, camStartY = 0, 0

    -- Camera Zoom
    camScale = 1
    ZOOM_MIN = 0.25
    ZOOM_MAX = 3
    ZOOM_SPEED = 0.1

    timeScale = 1
    paused = false

    inSlowMotion = false
    slowMotionIcon = love.graphics.newImage("textures/Slow motion icon.png")

    outLimits = false

    -- Game States
    STATE_MENU = "menu"
    STATE_WORLD = "world"
    STATE_LOAD = "load"

    gameState = STATE_MENU
    
    SAVE_DIR = "saves/"
    love.filesystem.createDirectory(SAVE_DIR)

    currentWorldName = nil   -- like "my_world_1.lua"
    isNamingWorld = false
    worldNameInput = ""
    hoveredSaveIndex = nil

    AUTO_SAVE_INTERVAL = 60 -- seconds
    autoSaveTimer = 0

    -- Load Menu stuff
    loadMenuScroll = 0
    LOAD_ROW_HEIGHT = 34

    lastClickTime = 0
    DOUBLE_CLICK_TIME = 0.35
    lastClickedFile = nil

    loadSearch = ""

    saveCache = {} -- { filename, meta }

    buttonAnim = buttonAnim or {}

    uiConsumedClick = false

    love.physics.setMeter(64)
    world = love.physics.newWorld(0, 9.81 * 64, true)

    bodies = {}

    -- Ground
    ground = {}
    ground.body = love.physics.newBody(world, 400, 2550, "static")
    ground.shape = love.physics.newRectangleShape(80000, 4000)
    ground.fixture = love.physics.newFixture(ground.body, ground.shape)
end

function love.update(dt)
    local scaledDt = dt * timeScale
    DT = scaledDt
    world:update(scaledDt)

    -- Rotation Logic/Tool
    if #selectedObjects > 0 then
        if qDown then
            rotateSpeed = rotateSpeed + math.rad(1)
            for _, obj in ipairs(selectedObjects) do
                local body = obj.body
                body:applyTorque(rotateSpeed)
                if currentTool == TOOL_MOVE then
                    body:setAngle(body:getAngle() + rotateSpeed * 0.00002 * scaledDt)
                end
            end
        end

        if eDown then
            rotateSpeed = rotateSpeed + math.rad(1)
            for _, obj in ipairs(selectedObjects) do
                local body = obj.body
                body:applyTorque(-rotateSpeed)
                if currentTool == TOOL_MOVE then
                    body:setAngle(body:getAngle() - rotateSpeed * 0.00002 * scaledDt)
                end
            end
        end
    end

    -- Auto save timer
    if gameState == STATE_WORLD and currentWorldName then
        autoSaveTimer = autoSaveTimer + dt

        if autoSaveTimer >= AUTO_SAVE_INTERVAL then
            autoSaveTimer = 0
            saveWorld("saves/" .. currentWorldName)
            print("Auto-saved:", currentWorldName)
        end
    end

    -- Magnet Tool
    if currentTool == TOOL_MAGNET and love.mouse.isDown(1) then
        local sx, sy = love.mouse.getPosition()
        local mx, my = screenToWorld(sx, sy)

        for _, obj in ipairs(bodies) do
            local ox, oy = obj.body:getPosition()

            local dx = mx - ox
            local dy = my - oy
            local dist = math.sqrt(dx*dx + dy*dy)

            if dist > 1 and dist < magnetRadius then
                local nx = dx / dist
                local ny = dy / dist

                local falloff = 1 - (dist / magnetRadius)

                local force = magnetStrength * falloff

                -- REPEL = flip direction
                if magnetMode == "repel" then
                    force = -force
                end

                obj.body:applyForce(nx * force, ny * force)
            end
        end
    end

end

function love.resize(w, h)
    WINDOW_W = w
    WINDOW_H = h
    PROPS_X = WINDOW_W - PROPS_W - 10
    PROPS_Y = WINDOW_H - PROPS_H - 10
end

function love.draw()
    uiButtons = {}
    love.graphics.setBackgroundColor(0.1, 0.1, 0.1) -- dark gray

    -- =====================
    -- MENU (SCREEN SPACE)
    -- =====================
    if gameState == STATE_MENU then
        drawMainMenu()
        return
    end

    if gameState == STATE_LOAD then
        drawLoadMenu()
        return
    end


    -- =====================
    -- WORLD (WORLD SPACE)
    -- =====================
    love.graphics.push()
    love.graphics.translate(camX, camY)
    love.graphics.scale(camScale)


    love.graphics.setColor(0.05, 0.05, 0.05)
    drawBody(ground)

    for _, obj in ipairs(bodies) do
        -- Always draw real color
        love.graphics.setColor(obj.color)
        drawBody(obj)

        -- Draw outline if selected
        if obj.selected then
            drawSelectionOutline(obj)
        end
    end

    -- Magnet Tool
    if currentTool == TOOL_MAGNET then
        local sx, sy = love.mouse.getPosition()
        local mx, my = screenToWorld(sx, sy)

        love.graphics.setColor(0, 1, 1, 0.25)
        love.graphics.circle("fill", mx, my, magnetRadius)

        love.graphics.setColor(0, 1, 1, 0.8)
        love.graphics.circle("line", mx, my, magnetRadius)

        love.graphics.setColor(1,1,1,1)
    end

    -- Selection box
    if selecting then
        local x = selectStartX
        local y = selectStartY
        local w = selectEndX - selectStartX
        local h = selectEndY - selectStartY

        love.graphics.setColor(0, 1, 1, 0.3)
        love.graphics.rectangle("fill", x, y, w, h)
        love.graphics.setColor(0, 1, 1)
        love.graphics.rectangle("line", x, y, w, h)
    end

    if dragging then
        local x = math.min(dragStartX, dragEndX)
        local y = math.min(dragStartY, dragEndY)
        local w = math.abs(dragEndX - dragStartX)
        local h = math.abs(dragEndY - dragStartY)


        local cx = (dragStartX + dragEndX) / 2
        local cy = (dragStartY + dragEndY) / 2
                
        if currentTool == TOOL_BOX then
            love.graphics.setColor(0, 0.5, 1, 0.3)
            love.graphics.rectangle("fill", x, y, w, h)
            love.graphics.setColor(0, 0.5, 1)
            love.graphics.rectangle("line", x, y, w, h)

        elseif currentTool == TOOL_BALL then
            local radius = math.sqrt(w*w + h*h) / 2
            love.graphics.setColor(0, 0.5, 1, 0.3)
            love.graphics.circle("fill", cx, cy, radius)
            love.graphics.setColor(0, 0.5, 1)
            love.graphics.circle("line", cx, cy, radius)
        end
    end

    love.graphics.pop()

    -- =====================
    -- UI (SCREEN SPACE)
    -- =====================
    drawUI()

    -- Saving World UI
    if isNamingWorld then
        -- Dark overlay
        love.graphics.setColor(0,0,0,0.6)
        love.graphics.rectangle("fill", 0,0, WINDOW_W, WINDOW_H)

        local w, h = 400, 120
        local x = (WINDOW_W - w)/2
        local y = (WINDOW_H - h)/2

        love.graphics.setColor(0.15,0.15,0.15)
        love.graphics.rectangle("fill", x, y, w, h)
        love.graphics.setColor(1,1,1)
        love.graphics.rectangle("line", x, y, w, h)

        love.graphics.printf("Enter World Name:", x, y + 15, w, "center")

        -- Textbox
        love.graphics.rectangle("line", x+40, y+60, w-80, 30)
        love.graphics.print(worldNameInput .. "_", x+50, y+65)
    end

end

function love.mousepressed(x, y, button)
    uiConsumedClick = false
    -- Middle mouse = pan camera
    if button == 3 then
        panning = true
        panStartX, panStartY = x, y
        camStartX, camStartY = camX, camY
        return
    end

    if button ~= 1 then return end

    -- UI click FIRST (screen space)
    for _, btn in ipairs(uiButtons) do
        if x >= btn.x and x <= btn.x + btn.w and
           y >= btn.y and y <= btn.y + btn.h then
            btn.onClick()
            uiConsumedClick = true
            return
        end
    end

    -- =====================
    -- Load Menu Double Click
    -- =====================
    if gameState == STATE_LOAD and button == 1 then
        local panelW = math.floor(WINDOW_W * 0.6)
        local panelH = math.floor(WINDOW_H * 0.7)
        local panelX = math.floor((WINDOW_W - panelW) / 2)
        local panelY = math.floor((WINDOW_H - panelH) / 2)

        local listX = panelX + 20
        local listY = panelY + 60
        local listW = panelW - 40
        local rowH = 30
        local viewH = panelH - 120

        local files = {}

        for _, entry in ipairs(saveCache) do
            local name = entry.file:lower()
            if loadSearch == "" or name:find(loadSearch:lower(), 1, true) then
                table.insert(files, entry.file)
            end
        end


        for i, file in ipairs(files) do
            local rx = listX
            local ry = listY + (i-1) * LOAD_ROW_HEIGHT + loadMenuScroll
            local rw = listW
            local rh = rowH

            if x >= rx and x <= rx+rw and y >= ry and y <= ry+rh then
                local now = love.timer.getTime()

                if lastClickedFile == file and (now - lastClickTime) <= DOUBLE_CLICK_TIME then
                    -- DOUBLE CLICK → LOAD
                    local worldDir = getWorldDir(file)
                    loadWorld(worldDir .. "world.lua")

                    currentWorldName = file
                    autoSaveTimer = 0
                    gameState = STATE_WORLD

                    lastClickedFile = nil
                    lastClickTime = 0
                    uiConsumedClick = true
                    return
                else
                    -- SINGLE CLICK (select row)
                    lastClickedFile = file
                    lastClickTime = now
                    uiConsumedClick = true
                    return
                end
            end
        end

        -- Clicked empty space → clear selection
        lastClickedFile = nil
        lastClickTime = 0
    end

    -- Hex color focus (SCREEN SPACE)
    if x >= hexBoxX and x <= hexBoxX + hexBoxW and
    y >= hexBoxY and y <= hexBoxY + hexBoxH then
        hexColorActive = true
        uiConsumedClick = true
        return
    else
        hexColorActive = false
    end

    -- ⛔ UI CONSUMED = NO WORLD INPUT
    if uiConsumedClick then
        return
    end

    local wx, wy = screenToWorld(x, y)

    if currentTool == TOOL_SELECT then
        local obj = getObjectAtPoint(wx, wy)
        local ctrl = love.keyboard.isDown("lctrl", "rctrl")

        if obj then
            -- Click select object
            selectObject(obj, ctrl)
        else
            -- Box select
            selecting = true
            selectStartX, selectStartY = wx, wy
            selectEndX, selectEndY = wx, wy

            if uiConsumedClick then
                return
            end
            if not ctrl then
                clearAllSelection()
            end
        end

    elseif currentTool == TOOL_MOVE then
        if #selectedObjects > 0 then
            draggingGroup = true
            dragOffset = {}
            for _, obj in ipairs(selectedObjects) do
                local bx, by = obj.body:getPosition()
                dragOffset[obj] = { x = bx - wx, y = by - wy }
                obj.body:setType("kinematic")
            end
        end

    elseif currentTool == TOOL_DRAG then
        local obj = getObjectAtPoint(wx, wy)
        if obj then
            mouseJoint = love.physics.newMouseJoint(obj.body, wx, wy)
            mouseJoint:setMaxForce(dragForce)
        end
    
    elseif currentTool == TOOL_FREEZE then
        local obj = getObjectAtPoint(wx, wy)
        if obj then
            toggleFreeze(obj)
        end
    end

    if currentTool == TOOL_BOX or currentTool == TOOL_BALL then
        dragging = true
        dragStartX, dragStartY = wx, wy
        dragEndX, dragEndY = wx, wy
    end
end

function love.mousemoved(x, y)
    -- Camera pan
    if panning then
        camX = camStartX + (x - panStartX)
        camY = camStartY + (y - panStartY)
        return
    end

    local wx, wy = screenToWorld(x, y)

    if selecting then
        selectEndX, selectEndY = wx, wy
    end

    if draggingGroup then
        for _, obj in ipairs(selectedObjects) do
            local off = dragOffset[obj]
            obj.body:setPosition(wx + off.x, wy + off.y)
            obj.body:setLinearVelocity(0, 0)
            obj.body:setAngularVelocity(0)
        end
    end

    if mouseJoint then
        mouseJoint:setTarget(wx, wy)
    end

    if dragging then
        dragEndX, dragEndY = wx, wy
    end
end

function love.mousereleased(x, y, button)
    if button == 3 then
        panning = false
        return
    end

    if button ~= 1 then return end

    local wx, wy = screenToWorld(x, y)

    if draggingGroup then
        for _, obj in ipairs(selectedObjects) do
            obj.body:setType(obj.originalType)
        end
        draggingGroup = false
    end

    if selecting then
        selecting = false
        selectEndX, selectEndY = wx, wy
        doSelection()
    end

    if mouseJoint then
        mouseJoint:destroy()
        mouseJoint = nil
    end

    if dragging then
        dragging = false
        dragEndX, dragEndY = wx, wy

        local cx = (dragStartX + dragEndX) / 2
        local cy = (dragStartY + dragEndY) / 2

        local w = math.abs(dragEndX - dragStartX)
        local h = math.abs(dragEndY - dragStartY)

        if currentTool == TOOL_BOX then
            if w > 5 and h > 5 then
                spawnBox(cx, cy, w, h)
            end
        elseif currentTool == TOOL_BALL then
            local radius = math.sqrt(w*w + h*h) / 2
            if radius > 5 then
                spawnBall(cx, cy, radius)
            end
        end
    end
end

function love.wheelmoved(dx, dy)
    if dy == 0 then return end

    -- LOAD MENU SCROLL ONLY
    if gameState == STATE_LOAD then
        loadMenuScroll = loadMenuScroll + dy * 20
        return
    end

    local mx, my = love.mouse.getPosition()
    local wx, wy = screenToWorld(mx, my)

    local ctrl  = love.keyboard.isDown("lctrl", "rctrl")
    local shift = love.keyboard.isDown("lshift", "rshift")
    local alt   = love.keyboard.isDown("lalt", "ralt")

    -- =========================
    -- MAGNET TOOL MODIFIERS
    -- =========================
    if currentTool == TOOL_MAGNET then
        local radiusStep   = 15
        local strengthStep = 1000
        local modeStep     = 1

        if ctrl then
            magnetRadius = magnetRadius + dy * radiusStep
            magnetRadius = math.max(20, math.min(600, magnetRadius))
            return
        end

        if shift then
            magnetStrength = magnetStrength + dy * strengthStep
            magnetStrength = math.max(0, math.min(80000, magnetStrength))
            return
        end

        -- ALT scroll = toggle attract / repel
        if alt then
            if dy > 0 then
                magnetMode = "attract"
            else
                magnetMode = "repel"
            end
            return
        end
    end

    -- Properties panel scroll
    local mx, my = love.mouse.getPosition()
    if mx >= PROPS_X and mx <= PROPS_X + PROPS_W and
    my >= PROPS_Y and my <= PROPS_Y + PROPS_H then
        propsScroll = propsScroll + dy * PROPS_SCROLL_SPEED
        return
    end

    -- =========================
    -- WORLD ZOOM (DEFAULT)
    -- =========================
    local oldScale = camScale
    camScale = math.max(ZOOM_MIN,
            math.min(ZOOM_MAX, camScale + dy * ZOOM_SPEED))

    camX = mx - wx * camScale
    camY = my - wy * camScale
end

function love.keypressed(key)
    -- Reset Zoom
    if key == "0" then
        camScale = 1
        camX, camY = 0, 0
    end

    -- Tools
    if key == "1" then currentTool = TOOL_SELECT end
    if key == "2" then currentTool = TOOL_MOVE end
    if key == "3" then currentTool = TOOL_BALL end
    if key == "4" then currentTool = TOOL_BOX end
    if key == "5" then currentTool = TOOL_DRAG end
    if key == "6" then currentTool = TOOL_FREEZE end
    if key == "7" then currentTool = TOOL_MAGNET end

    -- Remove Selected Objects
    if key == "delete" then
        deleteSelectedObjects()
    end

    -- Pauses the time
    if key == "p" then
        if not paused then
            timeScale = 0.0
            paused = true
        else
            timeScale = 1.0
            paused = false
        end
    end

    -- Increase and decrease drag force
    if key == "n" then
        dragForce = dragForce + 1000
        if mouseJoint then
            mouseJoint:setMaxForce(dragForce)
        end
    end

    if key == "m" then
        dragForce = dragForce - 1000
        if mouseJoint then
            mouseJoint:setMaxForce(dragForce)
        end
    end

    -- Rotate selected objects with Q / E
    if #selectedObjects > 0 then
        if key == "q" then
            qDown = true
        end

        if key == "e" then
            eDown = true
        end
    end

    if key == "space" then
        if not inSlowMotion then
            timeScale = 0.4
            inSlowMotion = true
        else
            timeScale = 1.0
            inSlowMotion = false
        end
    end

    -- Save a world
    if key == "f5" then
        if not currentWorldName then
            -- First save ever → ask for name
            isNamingWorld = true
            worldNameInput = ""
        else
            -- Normal save → overwrite
            saveWorld(SAVE_DIR .. currentWorldName)
            autoSaveTimer = 0
        end
    end

    -- Pause the game
    if key == "escape" then
        gameState = STATE_MENU
    end

    -- Saving Name Input
    if isNamingWorld then
        if key == "backspace" then
            worldNameInput = worldNameInput:sub(1, -2)
            return
        end

        if key == "return" or key == "kpenter" then
            if worldNameInput ~= "" then
                currentWorldName = worldNameInput
                saveWorld(SAVE_DIR .. currentWorldName)
                isNamingWorld = false
            end
            return
        end

        if key == "escape" then
            isNamingWorld = false
            return
        end
    end

    if gameState == STATE_LOAD then
        if key == "backspace" then
            loadSearch = loadSearch:sub(1, -2)
            return
        end
    end

    if hexColorActive then
        if key == "backspace" then
            hexColorInput = hexColorInput:sub(1, -2)
        end
    end

end

function love.keyreleased(key)
    if key == "q" then
        rotateSpeed = originalRS
        qDown = false
    end

    if key == "e" then
        rotateSpeed = originalRS
        eDown = false
    end
end

function love.textinput(t)
    if isNamingWorld then
        worldNameInput = worldNameInput .. t
    end

    if gameState == STATE_LOAD then
        loadSearch = loadSearch .. t
    end

    if hexColorActive then
        if #hexColorInput < 7 then
            hexColorInput = hexColorInput .. t
        end
    end

end

-- =========================
-- Helpers
-- =========================

function spawnBall(x, y, radius)
    local obj = {}
    obj.body = love.physics.newBody(world, x, y, "dynamic")
    obj.shape = love.physics.newCircleShape(radius)
    obj.fixture = love.physics.newFixture(obj.body, obj.shape, 1)
    obj.fixture:setRestitution(0.6)
    obj.fixture:setFriction(0.4)
    obj.originalType = "dynamic"
    obj.fixture:setDensity(1.0)
    obj.body:resetMassData()

    obj.color = {1, 1, 1}
    table.insert(bodies, obj)
end

function spawnBox(x, y, w, h)
    local obj = {}
    obj.body = love.physics.newBody(world, x, y, "dynamic")
    obj.shape = love.physics.newRectangleShape(w, h)
    obj.fixture = love.physics.newFixture(obj.body, obj.shape, 1)
    obj.fixture:setRestitution(0.2)
    obj.fixture:setFriction(0.8)
    obj.originalType = "dynamic"
    obj.fixture:setDensity(1.0)
    obj.body:resetMassData()

    obj.color = {1, 1, 1}
    table.insert(bodies, obj)
end

function getObjectAtPoint(x, y)
    for _, obj in ipairs(bodies) do
        if obj.fixture:testPoint(x, y) then
            return obj
        end
    end
    return nil
end

function doSelection()
    local ctrl = love.keyboard.isDown("lctrl", "rctrl")

    local minX = math.min(selectStartX, selectEndX)
    local maxX = math.max(selectStartX, selectEndX)
    local minY = math.min(selectStartY, selectEndY)
    local maxY = math.max(selectStartY, selectEndY)

    for _, obj in ipairs(bodies) do
        local bx, by = obj.body:getPosition()

        if bx >= minX and bx <= maxX and
           by >= minY and by <= maxY then

            if not isSelected(obj) then
                obj.selected = true
                table.insert(selectedObjects, obj)
            end
        end
    end
end


function isSelected(obj)
    for i, o in ipairs(selectedObjects) do
        if o == obj then
            return true, i
        end
    end
    return false, nil
end

function clearAllSelection()
    for _, obj in ipairs(bodies) do
        obj.selected = false
    end
    selectedObjects = {}
end

function selectObject(obj, additive)
    local isSel, index = isSelected(obj)

    if additive then
        -- TOGGLE
        if isSel then
            obj.selected = false
            table.remove(selectedObjects, index)
        else
            obj.selected = true
            table.insert(selectedObjects, obj)
        end
    else
        -- REPLACE
        clearAllSelection()
        obj.selected = true
        selectedObjects = { obj }
    end
end

-- =========================
-- Button Theme System
-- =========================

BUTTON_THEME = {
    normal = {
        bg = {0.12,0.12,0.16},
        hover = {0.22,0.22,0.26},
        border = {1,1,1},
        text = {1,1,1}
    },
    active = {
        bg = {0.2, 0.4, 0.8},
        hover = {0.3, 0.5, 1.0},
        border = {1,1,1},
        text = {1,1,1}
    },
    danger = {
        bg = {0.6, 0.15, 0.15},
        hover = {0.8, 0.2, 0.2},
        border = {1,1,1},
        text = {1,1,1}
    },
    disabled = {
        bg = {0.15, 0.15, 0.15},
        hover = {0.15, 0.15, 0.15},
        border = {0.5,0.5,0.5},
        text = {0.6,0.6,0.6}
    }
}

function drawButton(text, x, y, w, h, onClick, style)
    style = style or {}

    local theme = BUTTON_THEME[style.theme or "normal"]

    local mx, my = love.mouse.getPosition()
    local hovered = mx >= x and mx <= x + w and
                    my >= y and my <= y + h

    local isDisabled = style.disabled
    local isActive   = style.active

    local bg     = theme.bg
    local hover  = theme.hover
    local border = theme.border
    local textCol= theme.text

    if isActive then
        bg    = BUTTON_THEME.active.bg
        hover = BUTTON_THEME.active.hover
    end

    if isDisabled then
        bg     = BUTTON_THEME.disabled.bg
        hover  = BUTTON_THEME.disabled.hover
        border = BUTTON_THEME.disabled.border
        textCol= BUTTON_THEME.disabled.text
    end

    -- Button ID for animation
    local id = tostring(x) .. ":" .. tostring(y) .. ":" .. text
    buttonAnim[id] = buttonAnim[id] or 0

    -- Smooth hover animation (lerp)
    local target = hovered and 1 or 0
    buttonAnim[id] = buttonAnim[id] + (target - buttonAnim[id]) * 0.2
    local a = buttonAnim[id] -- 0..1

    -- Slight grow on hover
    local grow = 2 * a
    local bx = x - grow
    local by = y - grow
    local bw = w + grow*2
    local bh = h + grow*2

    table.insert(uiButtons, {
        x=bx,y=by,w=bw,h=bh,
        onClick = (isDisabled and nil or onClick)
    })

    -- Glow (behind button)
    if hovered and not isDisabled then
        love.graphics.setColor(hover[1], hover[2], hover[3], 0.25 * a)
        love.graphics.rectangle("fill", bx-3, by-3, bw+6, bh+6, 6, 6)
    end

    -- Background
    local mix = function(a,b,t) return a + (b-a)*t end
    local col = {
        mix(bg[1], hover[1], a),
        mix(bg[2], hover[2], a),
        mix(bg[3], hover[3], a)
    }

    love.graphics.setColor(col)
    love.graphics.rectangle("fill", bx, by, bw, bh, 4, 4)

    -- Border
    love.graphics.setColor(border)
    love.graphics.rectangle("line", bx, by, bw, bh, 4, 4)

    -- Text
    love.graphics.setColor(textCol)
    local font = love.graphics.getFont()
    local textW = font:getWidth(text)
    local textH = font:getHeight()

    local textX = math.floor(bx + (bw - textW) / 2)
    local textY = math.floor(by + (bh - textH) / 2)

    love.graphics.print(text, textX, textY)
end

function drawPanel(x, y, w, h)
    -- Panel bg
    love.graphics.setColor(0.08, 0.08, 0.11)
    love.graphics.rectangle("fill", x, y, w, h, 6, 6)

    -- Subtle border
    love.graphics.setColor(1,1,1,0.1)
    love.graphics.rectangle("line", x, y, w, h, 6, 6)
end

function drawSectionHeader(text, x, y, w)
    love.graphics.setColor(1,1,1,0.9)
    love.graphics.print(text, x, y)

    love.graphics.setColor(1,1,1,0.15)
    love.graphics.line(x, y + 18, x + w, y + 18)
end

function drawDividerSoft(x, y, w)
    love.graphics.setColor(1,1,1,0.08)
    love.graphics.line(x, y, x + w, y)
end

function getPrimarySelected()
    if #selectedObjects > 0 then
        return selectedObjects[1]
    end
    return nil
end

function drawPropertyRow(label, value, min, max, x, y, w)
    local mx, my = love.mouse.getPosition()
    local hovered = mx >= x and mx <= x + w and
                    my >= y and my <= y + PROPERTY_ROW_H

    -- Background
    if hovered then
        love.graphics.setColor(0.18, 0.18, 0.22)
    else
        love.graphics.setColor(0.12, 0.12, 0.16)
    end
    love.graphics.rectangle("fill", x, y, w, PROPERTY_ROW_H)

    -- Value bar
    local t = 0
    if max > min then
        t = (value - min) / (max - min)
        t = math.max(0, math.min(1, t))
    end

    love.graphics.setColor(0.25, 0.45, 0.9, 0.6)
    love.graphics.rectangle("fill", x, y + PROPERTY_ROW_H - 6, w * t, 6)

    -- Text
    love.graphics.setColor(1,1,1)
    love.graphics.print(label, x + 8, y + 6)

    local valueText = string.format("%.2f", value)
    local tw = love.graphics.getFont():getWidth(valueText)
    love.graphics.print(valueText, x + w - tw - 8, y + 6)
end

function isMultiSelected()
    return #selectedObjects > 1
end

function drawPropertiesPanel()
    local x = PROPS_X
    local y = PROPS_Y
    local w = PROPS_W
    local h = PROPS_H

    -- Panel BG
    love.graphics.setColor(0.10,0.10,0.14)
    love.graphics.rectangle("fill", x, y, w, h, 6, 6)

    -- Soft border
    love.graphics.setColor(1,1,1,0.12)
    love.graphics.rectangle("line", x, y, w, h, 6, 6)

    -- Title
    love.graphics.setColor(1,1,1)
    love.graphics.print("Properties", x+12, y+8)

    -- Subtle title underline
    love.graphics.setColor(1,1,1,0.08)
    love.graphics.line(x+10, y+26, x+w-10, y+26)
    love.graphics.setColor(1,1,1,1)


    -- Out of Limits Toggle (NOT SCROLLING)
    drawToggleButton("Out of Limits", x+10, y-30, 180, 22, outLimits, function(v)
        outLimits = v
    end)

    if #selectedObjects == 0 then
        love.graphics.setColor(1,1,1,0.7)
        love.graphics.print("No selection", x+10, y+40)
        love.graphics.setColor(1,1,1,1)
        return
    end

    -- =====================
    -- SCROLL CLIP AREA
    -- =====================
    local clipY = y + 30
    local clipH = h - 40

    love.graphics.setScissor(x, clipY, w, clipH)

    local cy = clipY + 10 + propsScroll

    -- Helpers
    local function drawSection(title)
        love.graphics.setColor(1,1,1,0.9)
        love.graphics.print(title, x+10, cy)
        love.graphics.setColor(1,1,1,0.15)
        love.graphics.line(x+10, cy+18, x+w-10, cy+18)
        love.graphics.setColor(1,1,1,1)
        cy = cy + 26
    end

    local function drawDivider()
        love.graphics.setColor(1,1,1,0.08)
        love.graphics.rectangle("fill", x+10, cy, w-20, 1)
        love.graphics.setColor(1,1,1,1)
        cy = cy + 12
    end

    local function forAllSelected(fn)
        for _, obj in ipairs(selectedObjects) do
            fn(obj)
        end
    end

    -- MULTI INFO
    if #selectedObjects > 1 then
        love.graphics.setColor(1,1,1,0.75)
        love.graphics.print("Selected: "..#selectedObjects, x+10, cy)
        love.graphics.setColor(1,1,1,1)
        cy = cy + 20
    end

    -- =====================
    -- STATE
    -- =====================
    drawSection("State")

    local anyFrozen = selectedObjects[1].frozen == true

    drawToggleButton("Frozen", x+15, cy, w-30, 22, anyFrozen, function(v)
        forAllSelected(function(obj)
            obj.frozen = v
            if v then
                obj.body:setType("static")
                obj.originalType = "static"
                obj.body:setLinearVelocity(0,0)
                obj.body:setAngularVelocity(0)
            else
                obj.body:setType("dynamic")
                obj.originalType = "dynamic"
            end
        end)
    end)

    cy = cy + 32
    drawDivider()

    -- =====================
    -- PHYSICS
    -- =====================
    drawSection("Physics")

    local function drawStepper(label, getter, setter, step, minVal, maxVal)
        -- Row background
        love.graphics.setColor(0.11, 0.11, 0.15)
        love.graphics.rectangle("fill", x+10, cy-2, w-20, 26, 4, 4)
        love.graphics.setColor(1,1,1)

        -- LIVE VALUE (from first selected)
        local liveValue = getter(selectedObjects[1])
        local valueText = string.format("%.2f", liveValue)

        -- Label
        love.graphics.setColor(1,1,1)
        love.graphics.print(label, x+15, cy)

        -- Live number (right side)
        local vw = love.graphics.getFont():getWidth(valueText)
        love.graphics.setColor(0.8, 0.9, 1)
        love.graphics.print(valueText, x+w-100-vw, cy)

        love.graphics.setColor(1,1,1)

        -- Minus
        drawButton("-", x+w-90, cy, 22, 22, function()
            forAllSelected(function(obj)
                local v = getter(obj) - step
                if not outLimits and minVal then v = math.max(minVal, v) end
                setter(obj, v)
            end)
        end)

        -- Plus
        drawButton("+", x+w-60, cy, 22, 22, function()
            forAllSelected(function(obj)
                local v = getter(obj) + step
                if not outLimits and maxVal then v = math.min(maxVal, v) end
                setter(obj, v)
            end)
        end)

        cy = cy + 28
    end


    drawStepper("Bounce",
        function(o) return o.fixture:getRestitution() end,
        function(o,v) o.fixture:setRestitution(v) end,
        0.1, 0, 1)

    drawStepper("Friction",
        function(o) return o.fixture:getFriction() end,
        function(o,v) o.fixture:setFriction(v) end,
        0.1, 0, 1)

    drawStepper("Density",
        function(o) return o.fixture:getDensity() end,
        function(o,v) setObjectDensity(o,v) end,
        0.2, 0.1, nil)

    cy = cy + 10
    drawDivider()

    -- =====================
    -- COLOR
    -- =====================
    drawSection("Color")

    local ref = selectedObjects[1]

    if not hexColorActive then
        hexColorInput = rgb01ToHex(ref.color[1], ref.color[2], ref.color[3])
    end

    love.graphics.setColor(ref.color)
    love.graphics.rectangle("fill", x+15, cy, 26, 26)
    love.graphics.setColor(1,1,1)
    love.graphics.rectangle("line", x+15, cy, 26, 26)

    cy = cy + 36

    local function adjustColor(i, delta)
        forAllSelected(function(obj)
            obj.color[i] = math.max(0, math.min(1, obj.color[i] + delta))
        end)
    end

    local labels = {"R","G","B"}
    for i=1,3 do
        love.graphics.print(labels[i], x+15, cy)
        love.graphics.print(fmtColor(ref.color[i]), x+50, cy)

        drawButton("-", x+w-120, cy, 22, 22, function()
            adjustColor(i, -0.05)
        end)

        drawButton("+", x+w-90, cy, 22, 22, function()
            adjustColor(i, 0.05)
        end)

        cy = cy + 28
    end

    cy = cy + 10
    drawDivider()
    cy = cy + 6

    -- =====================
    -- HEX COLOR INPUT
    -- =====================
    love.graphics.setColor(1,1,1,0.8)
    love.graphics.print("Hex Color", x+15, cy)

    local boxX = x + 15
    local boxY = cy + 20
    local boxW = w - 30
    local boxH = 26
    hexBoxX = boxX
    hexBoxY = boxY
    hexBoxW = boxW
    hexBoxH = boxH


    local mx, my = love.mouse.getPosition()
    local hovered = mx >= boxX and mx <= boxX + boxW and
                    my >= boxY and my <= boxY + boxH

    -- Box bg
    if hovered or hexColorActive then
        love.graphics.setColor(0.18,0.18,0.25)
    else
        love.graphics.setColor(0.12,0.12,0.16)
    end
    love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 4, 4)

    -- Border
    love.graphics.setColor(1,1,1,0.15)
    love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 4, 4)

    -- Text
    love.graphics.setColor(1,1,1)
    local displayText = hexColorInput
    if hexColorActive then
        displayText = displayText .. "_"
    end
    love.graphics.print(displayText, boxX + 8, boxY + 6)

    -- Apply button
    drawButton("Apply", boxX + boxW - 70, boxY, 60, boxH, function()
        local r,g,b = hexToRGB01(hexColorInput)
        if r then
            for _, obj in ipairs(selectedObjects) do
                obj.color[1] = r
                obj.color[2] = g
                obj.color[3] = b
            end
        end
    end)

    cy = cy + 60


    -- =====================
    -- DANGER
    -- =====================
    drawSection("Danger Zone")

    drawButton("Delete Selected", x+15, cy, w-30, 28, function()
        deleteSelectedObjects()
    end, { theme = "danger" })

    cy = cy + 40

    -- =====================
    -- END SCROLL CONTENT
    -- =====================
    love.graphics.setScissor()

    -- =====================
    -- SCROLL LIMITS + BAR
    -- =====================
    local contentHeight = cy - (clipY + propsScroll)
    local maxScroll = math.max(0, contentHeight - clipH)

    propsScroll = math.min(0, math.max(-maxScroll, propsScroll))

    -- Scrollbar
    if contentHeight > clipH then
        local barH = clipH * (clipH / contentHeight)
        local t = -propsScroll / maxScroll
        local barY = clipY + t * (clipH - barH)

        love.graphics.setColor(1,1,1,0.2)
        love.graphics.rectangle("fill", x+w-6, barY, 4, barH)
        love.graphics.setColor(1,1,1,1)
    end
end

function fmtColor(v)
    return string.format("%.2f", v)
end

function rgb01ToHex(r,g,b)
    return string.format("#%02X%02X%02X",
        math.floor(r*255),
        math.floor(g*255),
        math.floor(b*255)
    )
end

function hexToRGB01(hex)
    hex = hex:gsub("#","")
    if #hex ~= 6 then return nil end

    local r = tonumber(hex:sub(1,2), 16)
    local g = tonumber(hex:sub(3,4), 16)
    local b = tonumber(hex:sub(5,6), 16)

    if not r or not g or not b then return nil end

    return r/255, g/255, b/255
end

function drawToolsPanel()
    -- Tools
    ToolButtonY = WINDOW_H - 30

    addToolButton("Select", 10, ToolButtonY, TOOL_SELECT, function ()
        currentTool = TOOL_SELECT
    end)

    addToolButton("Move", 80, ToolButtonY, TOOL_MOVE, function ()
        currentTool = TOOL_MOVE
    end)

    addToolButton("Ball", 150, ToolButtonY, TOOL_BALL, function ()
        currentTool = TOOL_BALL
    end)

    addToolButton("Box", 220, ToolButtonY, TOOL_BOX, function ()
        currentTool = TOOL_BOX
    end)

    addToolButton("Drag", 290, ToolButtonY, TOOL_DRAG, function ()
        currentTool = TOOL_DRAG
    end)

    addToolButton("Freeze", 360, ToolButtonY, TOOL_FREEZE, function ()
        currentTool = TOOL_FREEZE
    end)

    addToolButton("Magnet", 430, ToolButtonY, TOOL_MAGNET, function ()
        currentTool = TOOL_MAGNET
    end)

    -- Tool Properties
    ToolPropY = ToolButtonY - 30

    if currentTool == TOOL_MAGNET then
        love.graphics.print("Strength: " .. string.format("%.2f", magnetStrength), 10, ToolPropY - 20)
        love.graphics.print("Radius: " .. string.format("%.2f", magnetRadius), 10, ToolPropY)
        love.graphics.print("Mode: " .. magnetMode, 10, ToolPropY - 40)
    end

    if currentTool == TOOL_DRAG then
        love.graphics.print("Drag: " .. dragForce, 10, ToolPropY)
    end
end

function addToolButton(text, x, y, toolId, onClick)
    local w = 60
    local h = 30

    drawButton("", x, y, w, h, onClick, {
        active = (currentTool == toolId)
    })

    local font = love.graphics.getFont()
    local textW = font:getWidth(text)
    local textH = font:getHeight()

    local textX = math.floor(x + (w - textW) / 2 + 0.5)
    local textY = math.floor(y + (h - textH) / 2 + 0.5)

    love.graphics.setColor(1,1,1)
    love.graphics.print(text, textX, textY)
end

function drawToggleButton(label, x, y, w, h, value, onToggle)
    local text = label .. ": " .. (value and "ON" or "OFF")

    drawButton(text, x, y, w, h, function()
        onToggle(not value)
    end, {
        active = value
    })
end

function setObjectDensity(obj, density)
    obj.fixture:setDensity(density)
    obj.body:resetMassData() -- IMPORTANT: recalculates mass + inertia
end

function deleteObject(obj)
    if obj.body and not obj.body:isDestroyed() then
        obj.body:destroy()
    end
end

function removeObjectFromList(obj)
    for i = #bodies, 1, -1 do
        if bodies[i] == obj then
            table.remove(bodies, i)
            break
        end
    end
end

function deleteSelectedObjects()
    for _, obj in ipairs(selectedObjects) do
        deleteObject(obj)
        removeObjectFromList(obj)
    end
    selectedObjects = {}
end

function clearSelectionOf(obj)
    -- Remove from selectedObjects
    for i = #selectedObjects, 1, -1 do
        if selectedObjects[i] == obj then
            table.remove(selectedObjects, i)
        end
    end
end

function screenToWorld(x, y)
    return (x - camX) / camScale,
           (y - camY) / camScale
end

function drawSelectionOutline(obj)
    local r, g, b = obj.color[1], obj.color[2], obj.color[3]

    -- Perceived brightness for auto contrast
    local brightness = 0.2126*r + 0.7152*g + 0.0722*b

    local outlineColor
    if brightness > 0.6 then
        outlineColor = {0, 0, 0}   -- black glow for bright objects
    else
        outlineColor = {1, 1, 1}   -- white glow for dark objects
    end

    local body = obj.body
    local shape = obj.shape

    -- Glow passes (soft outer)
    for i = 3, 1, -1 do
        local alpha = 0.15 * i
        love.graphics.setColor(outlineColor[1], outlineColor[2], outlineColor[3], alpha)
        love.graphics.setLineWidth(4 + i * 2)

        if shape:typeOf("CircleShape") then
            local x, y = body:getPosition()
            love.graphics.circle("line", x, y, shape:getRadius() + 2 + i*2)
        else
            love.graphics.polygon(
                "line",
                body:getWorldPoints(shape:getPoints())
            )
        end
    end

    -- Sharp inner outline
    love.graphics.setColor(outlineColor)
    love.graphics.setLineWidth(2)

    if shape:typeOf("CircleShape") then
        local x, y = body:getPosition()
        love.graphics.circle("line", x, y, shape:getRadius() + 1)
    else
        love.graphics.polygon(
            "line",
            body:getWorldPoints(shape:getPoints())
        )
    end

    -- Reset
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1,1,1)
end

function drawUI()
    -- Tool UI
    local toolName = {
        [TOOL_SELECT] = "Select",
        [TOOL_MOVE] = "Move",
        [TOOL_BALL] = "Spawn Ball",
        [TOOL_BOX] = "Spawn Box",
        [TOOL_DRAG] = "Drag",
        [TOOL_FREEZE] = "Freeze",
        [TOOL_MAGNET] = "Magnet"
    }

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Tool: " .. toolName[currentTool], 10, 40)
    love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 10)

    -- Controls, slow motion, tools, properties
    drawPropertiesPanel()
    drawToolsPanel()

    drawButton("", WINDOW_W / 2, 10, 30, 30, function ()
        if not inSlowMotion then
            timeScale = 0.4
            inSlowMotion = true
        else
            timeScale = 1.0
            inSlowMotion = false
        end
    end)

    love.graphics.draw(slowMotionIcon, (WINDOW_W / 2) - 3, 10, 0, 0.03, 0.03)

    -- Current world Name
    if currentWorldName then
        love.graphics.print("World: " .. currentWorldName, 10, 60)
    else
        love.graphics.print("World: (unsaved)", 10, 60)
    end

    if currentWorldName then
        local t = math.floor(AUTO_SAVE_INTERVAL - autoSaveTimer)
        love.graphics.print("Auto-save in: " .. t .. "s", 10, 80)
    end

end

function drawMainMenu()
    love.graphics.setBackgroundColor(0.05, 0.05, 0.08)

    local cx = WINDOW_W / 2
    local cy = WINDOW_H / 2

    -- ===== Main Card Panel =====
    local panelW = 420
    local panelH = 420
    local panelX = cx - panelW / 2
    local panelY = cy - panelH / 2

    love.graphics.setColor(0.12, 0.12, 0.16)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 8, 8)

    love.graphics.setColor(1,1,1)
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 8, 8)

    -- ===== Title =====
    love.graphics.setColor(1,1,1)
    love.graphics.printf("PHYSICS PLAYGROUND", panelX, panelY + 40, panelW, "center")

    -- Subtitle
    love.graphics.setColor(0.7, 0.7, 0.9)
    love.graphics.printf("Sandbox Physics Simulator", panelX, panelY + 70, panelW, "center")

    -- Divider
    love.graphics.setColor(1,1,1,0.2)
    love.graphics.line(panelX + 40, panelY + 110, panelX + panelW - 40, panelY + 110)

    -- ===== Buttons =====
    local btnW = 240
    local btnH = 44
    local btnX = cx - btnW / 2
    local y = panelY + 150

    drawButton("New World", btnX, y, btnW, btnH, function()
        resetWorld()
        currentWorldName = nil
        autoSaveTimer = 0
        gameState = STATE_WORLD
    end)

    y = y + 65

    drawButton("Load World", btnX, y, btnW, btnH, function()
        refreshSaveCache()
        loadSearch = ""
        loadMenuScroll = 0
        gameState = STATE_LOAD
    end)

    y = y + 65

    drawButton("Quit", btnX, y, btnW, btnH, function()
        love.event.quit()
    end, { theme = "danger" })

    -- ===== Footer / Credits =====
    love.graphics.setColor(0.6, 0.6, 0.6)
    love.graphics.printf("Owner: Galaxy", panelX, panelY + panelH - 60, panelW, "center")

    love.graphics.setColor(0.5, 0.5, 0.5)
    love.graphics.printf("Thanks to Rick for the ideas!", panelX, panelY + panelH - 40, panelW, "center")

    -- Version / Build tag (feels pro)
    love.graphics.setColor(0.4, 0.4, 0.4)
    love.graphics.print("v0.8", panelX + 10, panelY + panelH - 20)
end

function drawLoadMenu()
    local panelW = math.floor(WINDOW_W * 0.65)
    local panelH = math.floor(WINDOW_H * 0.75)
    local panelX = math.floor((WINDOW_W - panelW) / 2)
    local panelY = math.floor((WINDOW_H - panelH) / 2)

    -- ===== Background Dim =====
    love.graphics.setColor(0,0,0,0.4)
    love.graphics.rectangle("fill", 0,0, WINDOW_W, WINDOW_H)

    -- ===== Main Panel =====
    love.graphics.setColor(0.12, 0.12, 0.16)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 8, 8)
    love.graphics.setColor(1,1,1)
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 8, 8)

    -- ===== Title =====
    love.graphics.setColor(1,1,1)
    love.graphics.printf("Load World", panelX, panelY + 20, panelW, "center")

    love.graphics.setColor(0.7,0.7,0.9)
    love.graphics.printf("Double-click a world to load", panelX, panelY + 45, panelW, "center")

    -- Divider
    love.graphics.setColor(1,1,1,0.2)
    love.graphics.line(panelX + 30, panelY + 75, panelX + panelW - 30, panelY + 75)

    -- ===== Back Button =====
    drawButton("Back", panelX + 20, panelY + 20, 80, 28, function()
        gameState = STATE_MENU
    end)

    -- ===== Search Bar =====
    local searchY = panelY + 90
    love.graphics.setColor(1,1,1)
    love.graphics.print("Search:", panelX + 30, searchY)

    local searchX = panelX + 100
    local searchW = 260
    love.graphics.rectangle("line", searchX, searchY - 4, searchW, 26)
    love.graphics.print(loadSearch .. "_", searchX + 6, searchY)

    -- ===== Filter Saves =====
    local filtered = {}
    for _, entry in ipairs(saveCache) do
        local name = entry.file:lower()
        if loadSearch == "" or name:find(loadSearch:lower(), 1, true) then
            table.insert(filtered, entry)
        end
    end

    -- ===== Scrolling =====
    local listX = panelX + 30
    local listY = panelY + 140
    local listW = panelW - 60
    local rowH  = LOAD_ROW_HEIGHT
    local viewH = panelH - 180
    local totalH = #filtered * rowH

    if totalH < viewH then
        loadMenuScroll = 0
    else
        loadMenuScroll = math.max(viewH - totalH, math.min(0, loadMenuScroll))
    end

    -- ===== List Background =====
    love.graphics.setColor(0.08, 0.08, 0.11)
    love.graphics.rectangle("fill", listX, listY, listW, viewH, 6, 6)
    love.graphics.setColor(1,1,1,0.15)
    love.graphics.rectangle("line", listX, listY, listW, viewH, 6, 6)

    -- ===== Draw Rows =====
    for i, entry in ipairs(filtered) do
        local file = entry.file
        local meta = entry.meta

        local x = listX
        local y = listY + (i-1) * rowH + loadMenuScroll
        local w = listW
        local h = rowH

        local clicked = false
        
        drawButton("", x, y, w, h, function()
            -- DOUBLE CLICK LOGIC
            if lastClickWorld == file and (love.timer.getTime() - lastClickTime) < 0.4 then
                local worldDir = getWorldDir(file)
                loadWorld(worldDir .. "world.lua")
                currentWorldName = file
                autoSaveTimer = 0
                gameState = STATE_WORLD
            end
            
            lastClickWorld = file
            lastClickTime = love.timer.getTime()
        end)
        
        local mx, my = love.mouse.getPosition()
        local hovered = mx >= x and mx <= x+w and my >= y and my <= y+h

        if y + h >= listY and y <= listY + viewH then
            -- Row BG
            if hovered then
                love.graphics.setColor(0.22, 0.22, 0.28)
            else
                love.graphics.setColor(0.16, 0.16, 0.20)
            end
            love.graphics.rectangle("fill", x, y, w, h)

            -- Border
            love.graphics.setColor(1,1,1,0.08)
            love.graphics.rectangle("line", x, y, w, h)

            -- Name
            love.graphics.setColor(1,1,1)
            love.graphics.print(meta.name or file, x + 10, y + 4)

            -- Meta Info
            local info = string.format(
                "Objects: %d   Modified: %s",
                meta.objectCount or 0,
                meta.modified and os.date("%Y-%m-%d %H:%M", meta.modified) or "?"
            )

            love.graphics.setColor(0.7,0.7,0.7)
            love.graphics.print(info, x + 10, y + 18)

            -- Delete Button (on hover)
            if hovered then
                drawButton("Delete", x + w - 80, y + 4, 70, h - 8, function()
                    deleteWorld(file)
                end, { theme = "danger" })
            end
        end
    end

    -- ===== Empty State =====
    if #filtered == 0 then
        love.graphics.setColor(0.7,0.7,0.7)
        love.graphics.printf("No saves found.", listX, listY + viewH/2 - 10, listW, "center")
    end
end


function saveWorld(worldName)
    if not worldName then
        print("saveWorld called with nil worldName")
        return
    end

    worldName = sanitizeWorldName(worldName)
    currentWorldName = worldName

    local worldDir = getWorldDir(worldName)
    love.filesystem.createDirectory(worldDir)

    local worldPath = worldDir .. "world.lua"
    local metaPath  = worldDir .. "meta.lua"

    local objects = {}

    for _, obj in ipairs(bodies) do
        local vx, vy = obj.body:getLinearVelocity()

        local entry = {
            type = obj.shape:typeOf("CircleShape") and "ball" or "box",
            x = obj.body:getX(),
            y = obj.body:getY(),
            angle = obj.body:getAngle(),
            vx = vx,
            vy = vy,
            av = obj.body:getAngularVelocity(),

            color = { obj.color[1], obj.color[2], obj.color[3] },

            restitution = obj.fixture:getRestitution(),
            friction    = obj.fixture:getFriction(),
            density     = obj.fixture:getDensity(),

            frozen = obj.frozen == true
        }

        if entry.type == "ball" then
            entry.radius = obj.shape:getRadius()
        else
            local pts = { obj.shape:getPoints() }
            entry.w = math.abs(pts[3] - pts[1])
            entry.h = math.abs(pts[6] - pts[2])
        end

        table.insert(objects, entry)
    end

    -- Write world.lua
    local worldChunk = "return { objects = " .. tableToString(objects) .. " }"
    love.filesystem.write(worldPath, worldChunk)

    -- Load old meta if exists (to preserve created time)
    local createdTime = os.time()
    if love.filesystem.getInfo(metaPath) then
        local ok, oldChunk = pcall(love.filesystem.load, metaPath)
        if ok and oldChunk then
            local old = oldChunk()
            if old and old.created then
                createdTime = old.created
            end
        end
    end

    -- Write meta.lua
    local meta = {
        name = worldName,
        created = createdTime,
        modified = os.time(),
        objectCount = #bodies,
        playtime = 0
    }

    local metaChunk = "return " .. tableToString(meta)
    love.filesystem.write(metaPath, metaChunk)

    print("World saved:", worldDir)
end

function loadWorld(worldPath)
    if not love.filesystem.getInfo(worldPath) then
        print("No save file:", worldPath)
        return
    end

    clearWorld()

    local ok, chunk = pcall(love.filesystem.load, worldPath)
    if not ok or not chunk then
        print("Failed to load world chunk:", worldPath)
        return
    end

    local ok2, data = pcall(chunk)
    if not ok2 or not data or not data.objects then
        print("Invalid world data:", worldPath)
        return
    end

    for _, entry in ipairs(data.objects) do
        local obj

        if entry.type == "ball" then
            spawnBall(entry.x, entry.y, entry.radius)
            obj = bodies[#bodies]
        else
            spawnBox(entry.x, entry.y, entry.w, entry.h)
            obj = bodies[#bodies]
        end

        obj.body:setAngle(entry.angle or 0)
        obj.body:setLinearVelocity(entry.vx or 0, entry.vy or 0)
        obj.body:setAngularVelocity(entry.av or 0)

        obj.color = entry.color or {1,1,1}

        obj.fixture:setRestitution(entry.restitution or 0.2)
        obj.fixture:setFriction(entry.friction or 0.8)
        setObjectDensity(obj, entry.density or 1.0)

        if entry.frozen then
            obj.frozen = true
            obj.body:setType("static")
            obj.originalType = "static"
        end
    end

    clearAllSelection()

    print("World loaded:", worldPath)
end

function clearWorld()
    for _, obj in ipairs(bodies) do
        if obj.body then
            obj.body:destroy()
        end
    end
    bodies = {}
    selectedObjects = {}
end

function resetWorld()
    -- Clear old physics + objects
    clearWorld()

    -- Recreate physics world
    love.physics.setMeter(64)
    world = love.physics.newWorld(0, 9.81 * 64, true)

    -- Reset lists
    bodies = {}
    selectedObjects = {}

    -- Reset save name
    currentWorldName = nil
    autoSaveTimer = 0

    -- Reset tools/state
    currentTool = TOOL_SELECT
    mouseJoint = nil
    dragging = false
    selecting = false

    -- Reset camera
    camX, camY = 0, 0
    camScale = 1

    -- Recreate ground
    ground = {}
    ground.body = love.physics.newBody(world, 400, 2550, "static")
    ground.shape = love.physics.newRectangleShape(80000, 4000)
    ground.fixture = love.physics.newFixture(ground.body, ground.shape)
end

function getWorldDir(worldName)
    worldName = sanitizeWorldName(worldName)
    return SAVE_DIR .. worldName .. "/"
end

function deleteWorld(worldName)
    worldName = sanitizeWorldName(worldName)
    local dir = getWorldDir(worldName)

    if not love.filesystem.getInfo(dir) then
        print("World folder not found:", dir)
        return
    end

    -- delete files inside
    love.filesystem.remove(dir .. "world.lua")
    love.filesystem.remove(dir .. "meta.lua")

    -- remove folder
    love.filesystem.remove(dir)

    print("Deleted world:", worldName)

    refreshSaveCache()
end

function tableToString(t, indent)
    indent = indent or 0
    local s = "{\n"

    for k, v in pairs(t) do
        local key
        if type(k) == "number" then
            key = ""
        else
            key = tostring(k) .. " = "
        end

        s = s .. string.rep(" ", indent + 2) .. key

        if type(v) == "table" then
            s = s .. tableToString(v, indent + 2)
        elseif type(v) == "string" then
            s = s .. string.format("%q", v)
        else
            s = s .. tostring(v)
        end

        s = s .. ",\n"
    end

    s = s .. string.rep(" ", indent) .. "}"
    return s
end

function getSaveFiles()
    local files = love.filesystem.getDirectoryItems(SAVE_DIR)
    local saves = {}

    for _, file in ipairs(files) do
        if file:match("%.lua$") then
            table.insert(saves, file)
        end
    end

    return saves
end

function refreshSaveCache()
    saveCache = {}

    local folders = love.filesystem.getDirectoryItems(SAVE_DIR)

    for _, folder in ipairs(folders) do
        local worldPath = SAVE_DIR .. folder .. "/world.lua"
        local metaPath  = SAVE_DIR .. folder .. "/meta.lua"

        if love.filesystem.getInfo(worldPath) then
            local meta = {
                name = folder,
                modified = 0,
                objectCount = 0
            }

            if love.filesystem.getInfo(metaPath) then
                local ok, chunk = pcall(love.filesystem.load, metaPath)
                if ok and chunk then
                    local ok2, data = pcall(chunk)
                    if ok2 and type(data) == "table" then
                        meta = data
                    end
                end
            end

            table.insert(saveCache, {
                file = folder,   -- folder name
                meta = meta
            })
        end
    end

    table.sort(saveCache, function(a,b)
        return (a.meta.modified or 0) > (b.meta.modified or 0)
    end)
end

function sanitizeWorldName(name)
    if not name then return "World" end

    -- remove any slashes or folders
    name = name:gsub("[/\\]", "")
    name = name:gsub("^saves", "")
    name = name:gsub("^SAVE", "")

    if name == "" then
        name = "World"
    end

    return name
end

function toggleFreeze(obj)
    if obj.frozen then
        obj.frozen = false
        obj.body:setType("dynamic")
        obj.originalType = "dynamic"
    else
        obj.frozen = true
        obj.body:setType("static")
        obj.originalType = "static"
        obj.body:setLinearVelocity(0,0)
        obj.body:setAngularVelocity(0)
    end
end

function drawBody(obj)
    local body = obj.body
    local shape = obj.shape

    if shape:typeOf("CircleShape") then
        local x,y = body:getPosition()
        love.graphics.circle("fill", x, y, shape:getRadius())
    else
        love.graphics.polygon("fill", body:getWorldPoints(shape:getPoints()))
    end
end
