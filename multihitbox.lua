local aimbotKey = MOUSE_5
local requirePriority = false
local allowHeadHitbox = false
local useMultiPoints = false
local multiPointsScale = 0.5
local multiPointsNumber = 8
--local multiPointsBones = { 0, 1, 2, 3, 4, 5 }
local aimbotFovInPixels = 200
local enableDebug = true
local hitboxes = {}
local lastShot = nil
local lastShotTime = 0
local font = draw.CreateFont("Tahoma", 12, 400)

local function randomFloat(lower, greater)
    return lower + math.random()  * (greater - lower);
end

local function randomPointsInBoundingBox(min, max, count)
    local points = {}

    local multiPointsMin = 0.5 - (multiPointsScale / 2)
    local multiPointsMax = 0.5 + (multiPointsScale / 2)
    
    for i = 1, count do
        local point = Vector3(
            randomFloat(multiPointsMin, multiPointsMax) * (max.x - min.x) + min.x,
            randomFloat(multiPointsMin, multiPointsMax) * (max.y - min.y) + min.y,
            randomFloat(multiPointsMin, multiPointsMax) * (max.z - min.z) + min.z
        )
        table.insert(points, point)
    end
    
    return points
end

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

    local localPlayerWeapon = localPlayer:GetPropEntity("m_hActiveWeapon")
    if not localPlayerWeapon then
        return
    end

    local localPlayerWeaponNextPrimaryAttack = localPlayerWeapon:GetPropFloat("m_flNextPrimaryAttack")
    if not localPlayerWeaponNextPrimaryAttack then
        return
    end

    if localPlayerWeaponNextPrimaryAttack > globals.CurTime() then
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
            goto continue
        end

        if player:GetClass() ~= "CTFPlayer" then
            goto continue
        end

        if player:GetTeamNumber() == localPlayer:GetTeamNumber() then
            goto continue
        end

        if not player:IsAlive() then
            goto continue
        end

        if player:IsDormant() then
            goto continue
        end
        
        if player:InCond(E_TFCOND.TFCond_Cloaked) then
            goto continue
        end
        
        if requirePriority and playerlist.GetPriority(player) < 10 then
            goto continue
        end

        local origin = player:GetAbsOrigin()
        local mins = player:GetMins()
        local maxs = player:GetMaxs()
        local bboxCenter = origin + (mins + maxs) * 0.5

        local screenPos = client.WorldToScreen(bboxCenter)
        if not (screenPos ~= nil and screenPos[1] > 0 and screenPos[2] > 0 and screenPos[1] < screenSizeX and screenPos[2] < screenSizeY) then
            goto continue
        end

        local dx, dy = screenPos[1] - centerX, screenPos[2] - centerY
        local distSq = dx * dx + dy * dy

        if distSq >= bestDistSq then
            goto continue
        end

        closestPlayer, bestDistSq = player, distSq

        ::continue::
    end

    if not closestPlayer then
        return
    end

    local localViewOffset = localPlayer:GetPropFloat("m_vecViewOffset[2]")
    local localView = localPlayer:GetAbsOrigin() + Vector3(0, 0, localViewOffset)

    for hitboxId, hitboxData in ipairs(closestPlayer:GetHitboxes()) do
        -- i think 1 is always head?
        if hitboxId == 1 and not allowHeadHitbox then
            goto skipHitbox
        end

        local shouldEnableMultiPointsForBone = false
        if useMultiPoints then
            shouldEnableMultiPointsForBone = true
            --[[for _, multiPointBone in ipairs(multiPointsBones) do
                if hitboxId == multiPointBone + 1 then -- correction for indexes to bones
                    shouldEnableMultiPointsForBone = true
                    break
                end
            end]]
        end

        if shouldEnableMultiPointsForBone then
            local multiPointPoints = randomPointsInBoundingBox(hitboxData[1], hitboxData[2], multiPointsNumber)
            for _, multiPointPoint in ipairs(multiPointPoints) do
                table.insert(hitboxes, multiPointPoint)
            end
        else
            local hitboxCenter = (hitboxData[1] + hitboxData[2]) * 0.5
            table.insert(hitboxes, hitboxCenter)
        end

        ::skipHitbox::
    end

    for _, hitboxPoint in ipairs(hitboxes) do
        local screenPos = client.WorldToScreen(hitboxPoint)
        if not (screenPos ~= nil and screenPos[1] > ((screenSizeX / 2) - aimbotFovInPixels) and screenPos[2] > ((screenSizeY / 2) - aimbotFovInPixels) and screenPos[1] < ((screenSizeX / 2) + aimbotFovInPixels) and screenPos[2] < ((screenSizeY / 2) + aimbotFovInPixels)) then
            goto skipTrace
        end

        local traceResult = engine.TraceLine(localView, hitboxPoint, MASK_SHOT)
        if traceResult.hitbox == nil then
            goto skipTrace
        end

        lastShot = hitboxPoint
        lastShotTime = globals.RealTime()

        local angles = (localView - hitboxPoint):Angles()
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

        ::skipTrace::
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
