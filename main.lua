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

    currentTool = TOOL_SELECT

    dragForce = 10000

    rotateSpeed = 15 * 10000
    originalRS = rotateSpeed
    qDown = false
    eDown = false

    -- Properties panel
    PROPS_W = 200
    PROPS_H = 300
    PROPS_X = WINDOW_W - PROPS_W - 10
    PROPS_Y = WINDOW_H - PROPS_W - 10

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

    outLimits = false

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

    if #selectedObjects then
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
end

function love.resize(w, h)
    WINDOW_W = w
    WINDOW_H = h
    PROPS_X = WINDOW_W - PROPS_W - 10
    PROPS_Y = WINDOW_H - PROPS_H - 10
end

function love.draw()
    love.graphics.push()
    love.graphics.translate(camX, camY)
    love.graphics.scale(camScale)

    uiButtons = {}

    -- World
    love.graphics.setBackgroundColor(0.1, 0.1, 0.1) -- dark gray
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

    -- Tool UI
    local toolName = {
        [TOOL_SELECT] = "Select",
        [TOOL_MOVE] = "Move",
        [TOOL_BALL] = "Spawn Ball",
        [TOOL_BOX] = "Spawn Box",
        [TOOL_DRAG] = "Drag"
    }

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Tool: " .. toolName[currentTool], 10, 40)
    love.graphics.print("1-Select        2-Move        3-Ball        4-Box        5-Drag", 10, WINDOW_H - 60)
    
    love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 10)

    love.graphics.print("Drag Force: " .. dragForce, 10, WINDOW_H - 80)

    -- Controls Panel
    love.graphics.print("Controls", WINDOW_W - 170, 10)
    love.graphics.print("P to Pause Time", WINDOW_W - 190, 30)
    love.graphics.print("N and M to Increase And Decrease Drag Force", WINDOW_W - 280, 50)
    love.graphics.print("Middle Click to pan the Camera", WINDOW_W - 240, 70)
    love.graphics.print("Scroll Wheel to zoom in and out", WINDOW_W - 240, 90)
    love.graphics.print("Q and E to rotate an object", WINDOW_W - 230, 110)

    -- Properties Panel
    drawPropertiesPanel()
    drawToolsPanel()

end

function love.mousepressed(x, y, button)
    -- Middle mouse = pan camera
    if button == 3 then
        panning = true
        panStartX, panStartY = x, y
        camStartX, camStartY = camX, camY
        return
    end

    if button ~= 1 then return end

    local wx, wy = screenToWorld(x, y)

    -- UI click FIRST (screen space)
    for _, btn in ipairs(uiButtons) do
        if x >= btn.x and x <= btn.x + btn.w and
           y >= btn.y and y <= btn.y + btn.h then
            btn.onClick()
            return
        end
    end

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

    local mx, my = love.mouse.getPosition()
    local wx, wy = screenToWorld(mx, my)

    local oldScale = camScale
    camScale = math.max(ZOOM_MIN,
               math.min(ZOOM_MAX, camScale + dy * ZOOM_SPEED))

    local scaleFactor = camScale / oldScale

    -- Keep world point under cursor stable
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
        bg = {0.25, 0.25, 0.25},
        hover = {0.35, 0.35, 0.35},
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

    table.insert(uiButtons, {
        x=x,y=y,w=w,h=h,
        onClick = (isDisabled and nil or onClick)
    })

    -- Background
    if hovered then
        love.graphics.setColor(hover)
    else
        love.graphics.setColor(bg)
    end
    love.graphics.rectangle("fill", x, y, w, h)

    -- Border
    love.graphics.setColor(border)
    love.graphics.rectangle("line", x, y, w, h)

    -- Text
    love.graphics.setColor(textCol)
    love.graphics.print(text, x+6, y+2)
end



function drawPropertiesPanel()
    love.graphics.setColor(0.15,0.15,0.15)
    love.graphics.rectangle("fill", PROPS_X, PROPS_Y, PROPS_W, PROPS_H)
    love.graphics.setColor(1,1,1)
    love.graphics.rectangle("line", PROPS_X, PROPS_Y, PROPS_W, PROPS_H)

    love.graphics.print("Properties", PROPS_X+10, PROPS_Y+5)

    -- Out of Limits Toggle
    drawToggleButton("Out of Limits", PROPS_X+10, PROPS_Y-30, 180, 20, outLimits, function(v)
        outLimits = v
    end)

    if #selectedObjects == 0 then
        love.graphics.print("No selection", PROPS_X+10, PROPS_Y+30)
        return
    end

    -- MULTI
    if #selectedObjects > 1 then
        love.graphics.print("Selected: " .. #selectedObjects, PROPS_X+10, PROPS_Y+30)

        local y = PROPS_Y + 60

        drawButton("Freeze All", PROPS_X+10, y, 140, 20, function()
            for _, obj in ipairs(selectedObjects) do
                obj.frozen = true
                obj.body:setType("static")
                obj.originalType = "static"
                obj.body:setLinearVelocity(0,0)
                obj.body:setAngularVelocity(0)
            end
        end)

        y = y + 30

        drawButton("Unfreeze All", PROPS_X+10, y, 140, 20, function()
            for _, obj in ipairs(selectedObjects) do
                obj.frozen = false
                obj.body:setType("dynamic")
                obj.originalType = "dynamic"
            end
        end)

        y = y + 40

        drawButton("Bounce +", PROPS_X+10, y, 65, 20, function()
            for _, obj in ipairs(selectedObjects) do
                local r = obj.fixture:getRestitution()
                local new = r + 0.1
                if not outLimits then new = math.min(1, new) end
                obj.fixture:setRestitution(new)
            end
        end)

        drawButton("Bounce -", PROPS_X+85, y, 65, 20, function()
            for _, obj in ipairs(selectedObjects) do
                local r = obj.fixture:getRestitution()
                local new = r - 0.1
                if not outLimits then new = math.max(0, new) end
                obj.fixture:setRestitution(new)
            end
        end)

        y = y + 30

        drawButton("Fric +", PROPS_X+10, y, 65, 20, function()
            for _, obj in ipairs(selectedObjects) do
                local f = obj.fixture:getFriction()
                local new = f + 0.1
                if not outLimits then new = math.min(1, new) end
                obj.fixture:setFriction(new)
            end
        end)

        drawButton("Fric -", PROPS_X+85, y, 65, 20, function()
            for _, obj in ipairs(selectedObjects) do
                local f = obj.fixture:getFriction()
                local new = f - 0.1
                if not outLimits then new = math.max(0, new) end
                obj.fixture:setFriction(new)
            end
        end)

        y = y + 30

        drawButton("Mass +", PROPS_X + 10, y, 65, 20, function ()
            for _, obj in ipairs(selectedObjects) do
                local d = obj.fixture:getDensity()
                local new = d + 0.2
                if not outLimits then new = math.max(0.1, new) end
                setObjectDensity(obj, new)
            end
        end)

        drawButton("Mass -", PROPS_X + 85, y, 65, 20, function ()
            for _, obj in ipairs(selectedObjects) do
                local d = obj.fixture:getDensity()
                local new = d - 0.2
                if not outLimits then new = math.max(0.1, new) end
                setObjectDensity(obj, new)
            end
        end)

        y = y + 30

        drawButton("Delete ALL", PROPS_X + 10, y, 140, 20, function ()
            deleteSelectedObjects()
        end, { theme = "danger" })

        return
    end

    -- SINGLE
    local obj = selectedObjects[1]
    local fixture = obj.fixture
    local y = PROPS_Y + 30

    love.graphics.print("Frozen: " .. tostring(obj.frozen == true), PROPS_X+10, y)
    drawButton("Toggle", PROPS_X+110, y, 80, 20, function()
        toggleFreeze(obj)
    end)

    y = y + 30

    local rest = fixture:getRestitution()
    love.graphics.print(string.format("Bounce: %.2f", rest), PROPS_X+10, y)

    drawButton("-", PROPS_X+130, y, 20, 20, function()
        local new = rest - 0.1
        new = math.max(0, new)
        fixture:setRestitution(new)
    end)

    drawButton("+", PROPS_X+160, y, 20, 20, function()
        local new = rest + 0.1
        if not outLimits then new = math.min(1, new) end
        fixture:setRestitution(new)
    end)

    y = y + 30

    local fric = fixture:getFriction()
    love.graphics.print(string.format("Friction: %.2f", fric), PROPS_X+10, y)

    drawButton("-", PROPS_X+130, y, 20, 20, function()
        local new = fric - 0.1
        new = math.max(0, new)
        fixture:setFriction(new)
    end)

    drawButton("+", PROPS_X+160, y, 20, 20, function()
        local new = fric + 0.1
        if not outLimits then new = math.min(1, new) end
        fixture:setFriction(new)
    end)

    y = y + 30

    local density = fixture:getDensity()
    love.graphics.print(string.format("Density: %.2f", density), PROPS_X + 10, y)

    drawButton("-", PROPS_X + 130, y, 20, 20, function ()
        local new = density - 0.2
        new = math.max(0.1, new)
        setObjectDensity(obj, new)
    end)

    drawButton("+", PROPS_X + 160, y, 20, 20, function ()
        local new = density + 0.2
        if not outLimits then new = math.max(0.1, new) end
        setObjectDensity(obj, new)
    end)

    y = y + 30

    -- ---------------------
    -- Colors
    -- ---------------------
    love.graphics.print("Color: ", PROPS_X + 10, y)
    -- Color preview box
    love.graphics.setColor(obj.color)
    love.graphics.rectangle("fill", PROPS_X + 60, y - 5, 20, 20)
    love.graphics.setColor(1,1,1)
    love.graphics.rectangle("line", PROPS_X + 60, y - 5, 20, 20)
    y = y + 25
    -- Red
    love.graphics.print("R", PROPS_X + 60, y)
    love.graphics.print(fmtColor(obj.color[1]), PROPS_X + 10, y)
    drawButton("+", PROPS_X + 130, y, 20, 20, function ()
        obj.color[1] = math.min(1, obj.color[1] + 0.1)
    end)
    drawButton("-", PROPS_X + 160, y, 20, 20, function ()
        obj.color[1] = math.max(0, obj.color[1] - 0.1)
    end)
    y = y + 25

    -- Green
    love.graphics.print("G", PROPS_X + 60, y)
    love.graphics.print(fmtColor(obj.color[2]), PROPS_X + 10, y)
    drawButton("+", PROPS_X + 130, y, 20, 20, function ()
        obj.color[2] = math.min(1, obj.color[2] + 0.1)
    end)
    drawButton("-", PROPS_X + 160, y, 20, 20, function ()
        obj.color[2] = math.max(0, obj.color[2] - 0.1)
    end)
    y = y + 25

    -- Blue
    love.graphics.print("B", PROPS_X + 60, y)
    love.graphics.print(fmtColor(obj.color[3]), PROPS_X + 10, y)
    drawButton("+", PROPS_X + 130, y, 20, 20, function ()
        obj.color[3] = math.min(1, obj.color[3] + 0.1)
    end)
    drawButton("-", PROPS_X + 160, y, 20, 20, function ()
        obj.color[3] = math.max(0, obj.color[3] - 0.1)
    end)
    y = y + 30


    drawButton("Delete", PROPS_X + 80, y, 100, 20, function ()
        if obj then
            deleteObject(obj)
            removeObjectFromList(obj)
            clearSelectionOf(obj)
            obj = nil
        end
    end, { theme = "danger" })
end

function fmtColor(v)
    return string.format("%.2f", v)
end

function drawToolsPanel()
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
