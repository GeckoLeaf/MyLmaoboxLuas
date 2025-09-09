local aimbotKey = MOUSE_5
local requirePriority = false
local allowHeadHitbox = true
local aimbotFovInPixels = 200
local enableDebug = true
local hitboxes = {}
local lastShot = nil
local lastShotTime = 0
local font = draw.CreateFont("Tahoma", 12, 400)

---@param userCmd UserCmd
callbacks.Register("CreateMove", function(userCmd)
    hitboxes = {}

    if not input.IsButtonDown(aimbotKey) then
        return
    end

    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer or not (localPlayer:IsValid() and localPlayer:IsAlive()) then
        return
    end

    local screenSizeX, screenSizeY = draw.GetScreenSize()

    local centerX, centerY = screenSizeX * 0.5, screenSizeY * 0.5

    -- THIS IS BROKEN?
    --local players = entities.FindByClass("CTFPlayer")
    local closestPlayer, bestDistSq = nil, tonumber(math.huge)

    --for _, player in ipairs(players) do
    for i = 1, entities.GetHighestEntityIndex() do
        local player = entities.GetByIndex(i)

        if not player or not player:IsValid() then
            --print('player not valid')
            goto continue
        end

        if player:GetClass() ~= "CTFPlayer" then
            --print('player not a player')
            goto continue
        end

        if player:GetTeamNumber() == localPlayer:GetTeamNumber() then
            --print('player ' .. player:GetName() .. ' on same team')
            goto continue
        end

        if not player:IsAlive() then
            --print('player ' .. player:GetName() .. ' not alive')
            goto continue
        end

        if player:IsDormant() then
            --print('player ' .. player:GetName() .. ' dormant')
            goto continue
        end
        
        if player:InCond(E_TFCOND.TFCond_Cloaked) then
            --print('player ' .. player:GetName() .. ' cloaked')
            goto continue
        end
        
        if requirePriority and playerlist.GetPriority(player) < 10 then
            --print('player ' .. player:GetName() .. ' requires priority')
            goto continue
        end

        local origin = player:GetAbsOrigin()
        local mins = player:GetMins()
        local maxs = player:GetMaxs()
        local bboxCenter = origin + (mins + maxs) * 0.5

        local screenPos = client.WorldToScreen(bboxCenter)
        if not (screenPos ~= nil and screenPos[1] > 0 and screenPos[2] > 0 and screenPos[1] < screenSizeX and screenPos[2] < screenSizeY) then
            --print('player ' .. player:GetName() .. ' not on screen')
            goto continue
        end

        local dx, dy = screenPos[1] - centerX, screenPos[2] - centerY
        local distSq = dx * dx + dy * dy

        if distSq >= bestDistSq then
            --print('player '  .. player:GetName() .. ' not best')
            goto continue
        end

        closestPlayer, bestDistSq = player, distSq

        ::continue::
    end

    if not closestPlayer then
        --print('closest player invalid')
        return
    end

    local localViewOffset = localPlayer:GetPropFloat("m_vecViewOffset[2]")
    local localView = localPlayer:GetAbsOrigin() + Vector3(0, 0, localViewOffset)

    for hitboxId, hitboxData in ipairs(closestPlayer:GetHitboxes()) do
        -- i think 1 is always head?
        if hitboxId == 1 and not allowHeadHitbox then
            --print('skipping head hitbox')
            goto skipHitbox
        end

        local hitboxCenter = (hitboxData[1] + hitboxData[2]) * 0.5

        table.insert(hitboxes, hitboxCenter)

        local screenPos = client.WorldToScreen(hitboxCenter)
        if not (screenPos ~= nil and screenPos[1] > ((screenSizeX / 2) - aimbotFovInPixels) and screenPos[2] > ((screenSizeY / 2) - aimbotFovInPixels) and screenPos[1] < ((screenSizeX / 2) + aimbotFovInPixels) and screenPos[2] < ((screenSizeY / 2) + aimbotFovInPixels)) then
            --print('hitbox outside fov')
            goto skipHitbox
        end

        local traceResult = engine.TraceLine(localView, hitboxCenter, MASK_SHOT)
        if traceResult.entity ~= closestPlayer or traceResult.hitbox == nil then
            --print('hitbox cant hit')
            goto skipHitbox
        end

        lastShot = hitboxCenter
        lastShotTime = globals.RealTime()

        local angles = (localView - hitboxCenter):Angles()
        angles.x = -angles.x
        angles.y = angles.y + 180

        while angles.x > 90 do
            angles.x = angles.x - 180
        end

        while angles.x < -90 do
            angles.x = angles.x + 180
        end

        while angles.y > 180 do
            angles.y = angles.y - 360
        end

        while angles.y < -180 do
            angles.y = angles.y + 360
        end

        angles.z = 0

        userCmd:SetViewAngles(angles.x, angles.y, 0)
        userCmd:SetButtons(userCmd:GetButtons() | IN_ATTACK)
        break

        ::skipHitbox::
    end
end)

callbacks.Register("Draw", function()
    if not enableDebug then
        goto skipDraw
    end

    draw.SetFont(font)

    local screenSizeX, screenSizeY = draw.GetScreenSize()

    for _, hitbox in ipairs(hitboxes) do
        local worldToScreen = client.WorldToScreen(hitbox)
        if (worldToScreen ~= nil and worldToScreen[1] > 0 and worldToScreen[2] > 0 and worldToScreen[1] < screenSizeX and worldToScreen[2] < screenSizeY) then
            draw.Color(0, 255, 0, 255)
            draw.Text(worldToScreen[1], worldToScreen[2], "*")
        end
    end

    if lastShot and lastShotTime + 15 > globals.RealTime()then
        local worldToScreen = client.WorldToScreen(lastShot)
        if (worldToScreen ~= nil and worldToScreen[1] > 0 and worldToScreen[2] > 0 and worldToScreen[1] < screenSizeX and worldToScreen[2] < screenSizeY) then
            draw.Color(255, 0, 0, 255)
            draw.Text(worldToScreen[1], worldToScreen[2], "X")
        end
    end

    draw.ColoredCircle(screenSizeX / 2, screenSizeY / 2, aimbotFovInPixels, 255, 0, 0, 255)

    ::skipDraw::
end)
